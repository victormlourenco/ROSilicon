import Foundation

/// Makes Wine's wintrust.dll report every file as trusted.
///
/// Why: the client's copy-protection component calls
///     WinVerifyTrust(WINTRUST_ACTION_GENERIC_VERIFY_V2,
///                    L"C:\\windows\\system32\\ntdll.dll")
/// Under Wine that file is Wine's own unsigned reimplementation, so the call
/// fails with TRUST_E_NOSIGNATURE (0x800b0100) and the client aborts with
/// "Verify C:\\windows\\system32\\ntdll.dll". Wine's system DLLs can never
/// carry a Microsoft signature, so this check is a false positive by
/// construction.
///
/// The fix rewrites the first bytes of the exported WinVerifyTrust and
/// WinVerifyTrustEx to `return 0` (ERROR_SUCCESS):
///
///   i386 (stdcall, 3 args):  31 C0 C2 0C 00   xor eax,eax; ret 0x0c
///   x86_64:                  31 C0 C3         xor eax,eax; ret
///
/// Originals are preserved next to each file as wintrust.dll.wine-orig.
///
/// This runs once, at build time: `build.sh` applies it to the Wine runtime it
/// bundles, through the launcher's own `--patch-wintrust` flag, so the app
/// ships patched. Wine copies its DLLs into each prefix, so a prefix made from
/// that runtime is born patched too, and the launcher never writes to either —
/// it only reads them back, for the checklist.
enum WintrustPatch {
    static let exports = ["WinVerifyTrust", "WinVerifyTrustEx"]

    enum Machine: UInt16 {
        case i386 = 0x014C
        case x86_64 = 0x8664

        var returnZero: [UInt8] {
            switch self {
            case .i386: [0x31, 0xC0, 0xC2, 0x0C, 0x00]
            case .x86_64: [0x31, 0xC0, 0xC3]
            }
        }

        var name: String {
            switch self {
            case .i386: "i386"
            case .x86_64: "x86_64"
            }
        }
    }

    /// A DLL that cannot be parsed. The reasons stay in English on purpose:
    /// they describe a malformed PE file and are diagnostics, not guidance.
    struct PEError: LocalizedError {
        let path: String
        let reason: String
        var errorDescription: String? { "\(path): \(reason)" }
    }

    // MARK: - Commands

    /// Patches one DLL in place, keeping the bytes it replaces beside it as
    /// wintrust.dll.wine-orig — the way back, and by hand. Returns false when
    /// the file was already patched and nothing was written.
    @discardableResult
    static func patch(_ url: URL) throws -> Bool {
        var data = try Data(contentsOf: url)
        let hits = try exports.map { try findExport(data, named: $0, path: url.path) }
        let backup = backupURL(for: url)

        if hits.allSatisfy({ Array(data[$0.offset..<$0.offset + $0.machine.returnZero.count]) == $0.machine.returnZero }) {
            return false
        }

        if let existing = try? Data(contentsOf: backup) {
            if existing != data {
                // Wine was updated in place: the old backup no longer matches
                // the installed DLL. Refresh it so `restore` can never roll
                // back to a stale upstream version.
                try data.write(to: backup)
            }
        } else {
            try data.write(to: backup)
        }

        for hit in hits {
            data.replaceSubrange(
                hit.offset..<hit.offset + hit.machine.returnZero.count,
                with: hit.machine.returnZero)
        }

        try makeWritable(url)
        try data.write(to: url)
        return true
    }

    static func backupURL(for url: URL) -> URL {
        URL(filePath: url.path + ".wine-orig")
    }

    private static func makeWritable(_ url: URL) throws {
        // These files ship read-only.
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        if let mode = attributes[.posixPermissions] as? NSNumber, mode.uint16Value & 0o200 == 0 {
            try FileManager.default.setAttributes(
                [.posixPermissions: NSNumber(value: mode.uint16Value | 0o200)],
                ofItemAtPath: url.path)
        }
    }

    // MARK: - PE parsing

    private struct Export {
        let name: String
        let machine: Machine
        let offset: Int
    }

    private struct Section {
        let virtualAddress: UInt32
        let virtualSize: UInt32
        let rawPointer: UInt32
        let rawSize: UInt32
    }

    /// Locates an exported function's code in the file.
    private static func findExport(_ data: Data, named name: String, path: String) throws -> Export {
        func fail(_ reason: String) -> PEError { PEError(path: path, reason: reason) }

        guard data.count > 0x40, data[0] == 0x4D, data[1] == 0x5A else {
            throw fail("not an MZ file")
        }
        let pe = Int(try data.u32(0x3C))
        guard data.count > pe + 24,
              data[pe] == 0x50, data[pe + 1] == 0x45,
              data[pe + 2] == 0, data[pe + 3] == 0
        else { throw fail("no PE signature") }

        let machineValue = try data.u16(pe + 4)
        guard let machine = Machine(rawValue: machineValue) else {
            throw fail(String(format: "unsupported machine 0x%x", machineValue))
        }
        let sectionCount = Int(try data.u16(pe + 6))
        let optionalSize = Int(try data.u16(pe + 20))
        let optional = pe + 24

        let dataDirectory: Int
        switch try data.u16(optional) {
        case 0x10B: dataDirectory = optional + 96    // PE32
        case 0x20B: dataDirectory = optional + 112   // PE32+
        case let magic: throw fail(String(format: "unknown optional header magic 0x%x", magic))
        }
        let exportRVA = try data.u32(dataDirectory)
        let exportSize = try data.u32(dataDirectory + 4)

        var sections: [Section] = []
        let sectionBase = optional + optionalSize
        for i in 0..<sectionCount {
            let offset = sectionBase + 40 * i
            sections.append(Section(
                virtualAddress: try data.u32(offset + 12),
                virtualSize: try data.u32(offset + 8),
                rawPointer: try data.u32(offset + 20),
                rawSize: try data.u32(offset + 16)))
        }

        func offset(ofRVA rva: UInt32) throws -> Int {
            for section in sections {
                let span = max(section.virtualSize, section.rawSize)
                if rva >= section.virtualAddress, rva < section.virtualAddress &+ span {
                    return Int(section.rawPointer) + Int(rva - section.virtualAddress)
                }
            }
            throw fail(String(format: "RVA 0x%x not covered by any section", rva))
        }

        let directory = try offset(ofRVA: exportRVA)
        let nameCount = Int(try data.u32(directory + 24))
        let functionsOffset = try offset(ofRVA: try data.u32(directory + 28))
        let namesOffset = try offset(ofRVA: try data.u32(directory + 32))
        let ordinalsOffset = try offset(ofRVA: try data.u32(directory + 36))
        let wanted = Array(name.utf8)

        for i in 0..<nameCount {
            let nameOffset = try offset(ofRVA: try data.u32(namesOffset + 4 * i))
            guard let end = data[nameOffset...].firstIndex(of: 0) else { continue }
            guard Array(data[nameOffset..<end]) == wanted else { continue }

            let ordinal = Int(try data.u16(ordinalsOffset + 2 * i))
            let functionRVA = try data.u32(functionsOffset + 4 * ordinal)
            guard !(functionRVA >= exportRVA && functionRVA < exportRVA &+ exportSize) else {
                throw fail("\(name) is a forwarded export; refusing to patch")
            }
            return Export(name: name, machine: machine, offset: try offset(ofRVA: functionRVA))
        }
        throw fail("export \(name) not found")
    }
}

private extension Data {
    func u16(_ offset: Int) throws -> UInt16 {
        guard offset >= 0, offset + 2 <= count else { throw ReadError.outOfBounds }
        return withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt16.self) }
    }

    func u32(_ offset: Int) throws -> UInt32 {
        guard offset >= 0, offset + 4 <= count else { throw ReadError.outOfBounds }
        return withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self) }
    }

    enum ReadError: LocalizedError {
        case outOfBounds
        var errorDescription: String? { "truncated PE file" }
    }
}
