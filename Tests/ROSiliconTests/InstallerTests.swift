import Foundation
import Testing
@testable import ROSilicon

/// Serialized: the "is Wine running?" guard shells out to `pgrep -f <path>`,
/// and two of these running at once match each other's command line — every
/// test here would then be told Wine is running.
@Suite(.serialized)
struct InstallerTests {

    private func installer(_ paths: Paths, _ recorder: RecordingReporter) -> Installer {
        Installer(paths: paths, reporter: recorder.reporter)
    }

    // MARK: - The prefix

    /// Installing twice must not rebuild a prefix that is already there — that
    /// is what makes Repair cheap and safe to press.
    @Test func anInitializedPrefixIsLeftAloneAndNoWineIsStarted() async throws {
        let temp = try TemporaryDirectory()
        try temp.write(to: "wine/system.reg")
        try temp.makeDirectory("wine/drive_c/windows/system32")
        let paths = Paths(root: temp.url)
        let recorder = RecordingReporter()

        try await installer(paths, recorder).createPrefix()

        #expect(await recorder.logs.items == [Strings.logPrefixExists(paths.prefix.path)])
        #expect(await recorder.steps.items.isEmpty, "nothing was done, so nothing to announce")
    }

    /// Without the bundled runtime there is no wine to boot the prefix with,
    /// and the failure has to come out rather than leave a half-made prefix
    /// looking finished.
    @Test func makingAPrefixFailsWhenThereIsNoWineToBootIt() async throws {
        let temp = try TemporaryDirectory()
        let paths = Paths(root: temp.url)
        try #require(!FileManager.default.isExecutableFile(atPath: paths.wine.path),
                     "this test only makes sense outside an assembled app bundle")
        let recorder = RecordingReporter()

        await #expect(throws: (any Error).self) {
            try await installer(paths, recorder).createPrefix()
        }
        #expect(!paths.prefixInitialized)
        #expect(await recorder.steps.items == [Strings.stepCreatingPrefix])
    }

    // MARK: - What the app carries

    @Test func aBuildWithoutAWineRuntimeSaysSoBeforeAnythingElse() async throws {
        let temp = try TemporaryDirectory()
        let paths = Paths(root: temp.url)
        try #require(!FileManager.default.isExecutableFile(atPath: paths.wine.path))
        let recorder = RecordingReporter()

        await #expect(throws: InstallError.self) {
            try await installer(paths, recorder).checkBundle()
        }
        #expect(await recorder.steps.items.isEmpty, "it never got as far as a step")
    }

    // MARK: - The client

    /// An install that already has the client skips the download entirely —
    /// this test would need the network if it did not.
    @Test func anInstalledClientIsNotDownloadedAgain() async throws {
        let temp = try TemporaryDirectory()
        try temp.write(Data("MZ".utf8), to: "wine/drive_c/Gravity/Ragnarok/Ragexe.exe")
        let paths = Paths(root: temp.url)
        let recorder = RecordingReporter()

        try await installer(paths, recorder).installClient(
            from: Paths.defaultClientURL, force: false)

        #expect(await recorder.logs.items == [Strings.logClientInstalled(paths.gameDir.path)])
        #expect(await recorder.steps.items.isEmpty)
    }

    // MARK: - Clearing it out

    @Test func clearingAnEmptyInstallRemovesNothingAndSaysSo() async throws {
        let temp = try TemporaryDirectory()
        let paths = Paths(root: temp.url.appending(path: "never-installed"))
        let recorder = RecordingReporter()

        let destination = try await installer(paths, recorder).clearInstallation()

        #expect(destination == nil)
        #expect(await recorder.logs.items == [Strings.logNothingToRemove(paths.root.path)])
        #expect(await recorder.steps.items == [Strings.stepNothingToRemove])
    }

    /// The install goes to the Trash rather than being deleted outright, so a
    /// mis-click is recoverable until the Trash is emptied.
    @Test func clearingAnInstallMovesItToTheTrash() async throws {
        let temp = try TemporaryDirectory()
        let paths = Paths(root: temp.url.appending(path: "ROSilicon"))
        try paths.createRoot()
        try temp.write(Data(repeating: 0x41, count: 32), to: "ROSilicon/wine/system.reg")
        let recorder = RecordingReporter()

        let destination = try await installer(paths, recorder).clearInstallation()

        let trashed = try #require(destination, "the folder should have landed somewhere")
        // Put the test's own rubbish out again rather than leaving it in the
        // Trash for someone to find.
        defer { try? FileManager.default.removeItem(at: trashed) }

        #expect(!FileManager.default.fileExists(atPath: paths.root.path))
        #expect(FileManager.default.fileExists(atPath: trashed.path))
        #expect(await recorder.steps.items == [Strings.stepRemoving, Strings.stepRemoved])
    }

    // MARK: - Where it installs

    /// A folder that cannot be written to is caught before Rosetta, the
    /// runtime check or a single byte of download.
    @Test func anUnwritableInstallFolderIsRefusedUpFront() async throws {
        try #require(getuid() != 0, "root can write anywhere, so this proves nothing")
        let temp = try TemporaryDirectory()
        let root = try temp.makeDirectory("read-only")
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o555)], ofItemAtPath: root.path)
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: NSNumber(value: 0o755)], ofItemAtPath: root.path)
        }
        let recorder = RecordingReporter()

        await #expect(throws: InstallError.self) {
            try await installer(Paths(root: root), recorder)
                .installEverything(clientURL: Paths.defaultClientURL, reinstallClient: false)
        }
        #expect(await recorder.logs.items.isEmpty, "it refused before saying where it installs")
    }
}
