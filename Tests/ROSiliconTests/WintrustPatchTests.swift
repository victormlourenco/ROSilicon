import Foundation
import Testing
@testable import ROSilicon

struct WintrustPatchTests {

    // MARK: - What gets written

    @Test func patchesTheTwoExportsTheClientChecks() {
        #expect(WintrustPatch.exports == ["WinVerifyTrust", "WinVerifyTrustEx"])
    }

    /// stdcall with three arguments pops its own twelve bytes; the 64-bit ABI
    /// leaves that to the caller.
    @Test func returnZeroIsTheRightInstructionForEachArchitecture() {
        #expect(WintrustPatch.Machine.i386.returnZero == [0x31, 0xC0, 0xC2, 0x0C, 0x00])
        #expect(WintrustPatch.Machine.x86_64.returnZero == [0x31, 0xC0, 0xC3])
        #expect(WintrustPatch.Machine.i386.name == "i386")
        #expect(WintrustPatch.Machine.x86_64.name == "x86_64")
        #expect(WintrustPatch.Machine(rawValue: 0x014C) == .i386)
        #expect(WintrustPatch.Machine(rawValue: 0x8664) == .x86_64)
        #expect(WintrustPatch.Machine(rawValue: 0x01C0) == nil)   // ARM
    }

    @Test func backupSitsBesideTheFileItCameFrom() {
        let url = URL(filePath: "/test/Wine/wintrust.dll")
        #expect(WintrustPatch.backupURL(for: url).path == "/test/Wine/wintrust.dll.wine-orig")
    }

    @Test(arguments: [
        (WintrustPatch.Machine.i386, UInt16(0x10B)),      // PE32
        (WintrustPatch.Machine.x86_64, UInt16(0x20B)),    // PE32+
    ])
    func bothExportsAreRewrittenToReturnSuccess(
        machine: WintrustPatch.Machine, magic: UInt16
    ) throws {
        let temp = try TemporaryDirectory()
        var dll = SyntheticDLL()
        dll.machine = machine.rawValue
        dll.optionalMagic = magic
        let url = try temp.write(dll.data(), to: "wintrust.dll")

        #expect(try WintrustPatch.patch(url))

        let patched = try Data(contentsOf: url)
        let opcodes = machine.returnZero
        #expect(dll.body(0, in: patched, count: opcodes.count) == opcodes)
        #expect(dll.body(1, in: patched, count: opcodes.count) == opcodes)
    }

    /// Only the two entry points move: everything else in the DLL, headers and
    /// export table included, has to survive byte for byte.
    @Test func nothingButTheTwoEntryPointsIsTouched() throws {
        let temp = try TemporaryDirectory()
        let dll = SyntheticDLL()
        let original = dll.data()
        let url = try temp.write(original, to: "wintrust.dll")

        try WintrustPatch.patch(url)
        var patched = try Data(contentsOf: url)
        #expect(patched.count == original.count)

        // Put the original bytes back over the two patched spans; the file
        // should then be indistinguishable from the one that went in.
        let length = WintrustPatch.Machine.i386.returnZero.count
        for index in 0..<2 {
            let start = dll.bodyOffset(index)
            patched.replaceSubrange(start..<start + length, with: original[start..<start + length])
        }
        #expect(patched == original)
    }

    // MARK: - Doing it twice

    @Test func patchingAnAlreadyPatchedFileChangesNothing() throws {
        let temp = try TemporaryDirectory()
        let url = try temp.write(SyntheticDLL().data(), to: "wintrust.dll")

        #expect(try WintrustPatch.patch(url))
        let afterFirst = try Data(contentsOf: url)

        #expect(try WintrustPatch.patch(url) == false)
        #expect(try Data(contentsOf: url) == afterFirst)
    }

    // MARK: - The way back

    @Test func theOriginalIsKeptBesideThePatchedFile() throws {
        let temp = try TemporaryDirectory()
        let original = SyntheticDLL().data()
        let url = try temp.write(original, to: "wintrust.dll")

        try WintrustPatch.patch(url)

        let backup = WintrustPatch.backupURL(for: url)
        #expect(try Data(contentsOf: backup) == original)
        #expect(try Data(contentsOf: url) != original)
    }

    /// Running the patch again must not overwrite the way back with the
    /// patched bytes — that would make the backup worthless.
    @Test func aSecondPatchDoesNotClobberTheBackup() throws {
        let temp = try TemporaryDirectory()
        let original = SyntheticDLL().data()
        let url = try temp.write(original, to: "wintrust.dll")

        try WintrustPatch.patch(url)
        try WintrustPatch.patch(url)

        #expect(try Data(contentsOf: WintrustPatch.backupURL(for: url)) == original)
    }

    /// Wine updated in place leaves a backup of the version before it. Keeping
    /// it would let `restore` roll the tree back to a DLL that is no longer
    /// the one installed, so it is refreshed instead.
    @Test func aStaleBackupIsRefreshedFromTheFileOnDisk() throws {
        let temp = try TemporaryDirectory()
        let newer = SyntheticDLL().data()
        let url = try temp.write(newer, to: "wintrust.dll")
        let stale = Data(repeating: 0xEE, count: 64)
        try temp.write(stale, to: "wintrust.dll.wine-orig")

        try WintrustPatch.patch(url)

        let backup = try Data(contentsOf: WintrustPatch.backupURL(for: url))
        #expect(backup != stale)
        #expect(backup == newer)
    }

    // MARK: - Permissions

    @Test func aReadOnlyDLLIsMadeWritableToPatchIt() throws {
        let temp = try TemporaryDirectory()
        let url = try temp.write(SyntheticDLL().data(), to: "wintrust.dll")
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o444)], ofItemAtPath: url.path)

        #expect(try WintrustPatch.patch(url))

        let mode = try #require(
            FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions]
                as? NSNumber)
        #expect(mode.uint16Value & 0o200 != 0)
    }

    // MARK: - Files it refuses

    @Test func refusesSomethingThatIsNotAPEFile() throws {
        let temp = try TemporaryDirectory()
        let url = try temp.write(Data(repeating: 0x5A, count: 4096), to: "notadll.dll")
        #expect(throws: WintrustPatch.PEError.self) { try WintrustPatch.patch(url) }
    }

    @Test func refusesAFileTooShortToHoldAHeader() throws {
        let temp = try TemporaryDirectory()
        let url = try temp.write(Data([0x4D, 0x5A, 0x90, 0x00]), to: "tiny.dll")
        #expect(throws: WintrustPatch.PEError.self) { try WintrustPatch.patch(url) }
    }

    @Test func refusesAnMZFileWithNoPESignature() throws {
        let temp = try TemporaryDirectory()
        var data = SyntheticDLL().data()
        data[0x80] = 0x00       // blank the 'P' of "PE\0\0"
        let url = try temp.write(data, to: "wintrust.dll")
        #expect(throws: WintrustPatch.PEError.self) { try WintrustPatch.patch(url) }
    }

    /// Neither ARM nor anything else the client will never be: better to stop
    /// than to write i386 opcodes into a machine that is not one.
    @Test func refusesAnArchitectureItHasNoOpcodesFor() throws {
        let temp = try TemporaryDirectory()
        var dll = SyntheticDLL()
        dll.machine = 0x01C0    // ARM
        let url = try temp.write(dll.data(), to: "wintrust.dll")
        #expect(throws: WintrustPatch.PEError.self) { try WintrustPatch.patch(url) }
    }

    @Test func refusesAnUnknownOptionalHeaderMagic() throws {
        let temp = try TemporaryDirectory()
        var dll = SyntheticDLL()
        dll.optionalMagic = 0x107   // ROM image
        let url = try temp.write(dll.data(), to: "wintrust.dll")
        #expect(throws: WintrustPatch.PEError.self) { try WintrustPatch.patch(url) }
    }

    @Test func refusesADLLThatDoesNotExportBothFunctions() throws {
        let temp = try TemporaryDirectory()
        var dll = SyntheticDLL()
        dll.exportNames = ["WinVerifyTrust"]    // no WinVerifyTrustEx
        let url = try temp.write(dll.data(), to: "wintrust.dll")
        #expect(throws: WintrustPatch.PEError.self) { try WintrustPatch.patch(url) }
    }

    /// A forwarded export has no code in this file to rewrite; patching where
    /// it points would corrupt the export table.
    @Test func refusesAForwardedExport() throws {
        let temp = try TemporaryDirectory()
        var dll = SyntheticDLL()
        dll.forwarded = ["WinVerifyTrustEx"]
        let url = try temp.write(dll.data(), to: "wintrust.dll")
        #expect(throws: WintrustPatch.PEError.self) { try WintrustPatch.patch(url) }
    }

    @Test func refusesAFileThatIsNotThere() throws {
        let temp = try TemporaryDirectory()
        #expect(throws: (any Error).self) {
            try WintrustPatch.patch(temp.url.appending(path: "absent.dll"))
        }
    }

    /// A DLL it cannot make sense of is left exactly as it was: no half-patched
    /// file, and no backup implying one was made.
    @Test func aRefusedDLLIsLeftUntouchedWithNoBackup() throws {
        let temp = try TemporaryDirectory()
        var dll = SyntheticDLL()
        dll.exportNames = ["WinVerifyTrust"]
        let original = dll.data()
        let url = try temp.write(original, to: "wintrust.dll")

        #expect(throws: WintrustPatch.PEError.self) { try WintrustPatch.patch(url) }

        #expect(try Data(contentsOf: url) == original)
        #expect(!FileManager.default.fileExists(
            atPath: WintrustPatch.backupURL(for: url).path))
    }

    @Test func aRefusalNamesTheFileAndTheReason() {
        let error = WintrustPatch.PEError(path: "/test/wintrust.dll", reason: "not an MZ file")
        #expect(error.errorDescription == "/test/wintrust.dll: not an MZ file")
    }
}
