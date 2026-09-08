import Foundation
import Testing
@testable import ROSilicon

struct StatusTests {

    /// `Status.State` is not Equatable, and does not need to be for the app's
    /// sake; naming the cases here keeps the assertions readable.
    private func name(_ state: Status.State) -> String {
        switch state {
        case .ok: "ok"
        case .warning: "warning"
        case .missing: "missing"
        }
    }

    private func item(_ id: String, in status: Status) throws -> Status.Item {
        try #require(status.items.first { $0.id == id }, "no \(id) item in the checklist")
    }

    // MARK: - The checklist

    @Test func showsTheFourThingsInTheOrderTheyAreNeeded() throws {
        let temp = try TemporaryDirectory()
        let status = Status.inspect(Paths(root: temp.url))
        #expect(status.items.map(\.id) == ["rosetta", "wine", "prefix", "client"])
        #expect(status.items.allSatisfy { !$0.title.isEmpty })
        #expect(status.items.allSatisfy { !$0.detail.isEmpty })
    }

    @Test func anEmptyInstallFolderHasNeitherPrefixNorClient() throws {
        let temp = try TemporaryDirectory()
        let status = Status.inspect(Paths(root: temp.url))
        #expect(!status.prefixReady)
        #expect(!status.clientReady)
        #expect(!status.canPlay)
        #expect(name(try item("prefix", in: status).state) == "missing")
        #expect(name(try item("client", in: status).state) == "missing")
        #expect(try item("prefix", in: status).detail == Strings.notCreated)
        #expect(try item("client", in: status).detail == Strings.notInstalled)
    }

    // MARK: - The prefix

    @Test func aBootedPrefixReadsAsReady() throws {
        let temp = try TemporaryDirectory()
        try temp.write(to: "wine/system.reg")
        try temp.makeDirectory("wine/drive_c/windows/system32")

        let status = Status.inspect(Paths(root: temp.url))
        #expect(status.prefixReady)
        #expect(name(try item("prefix", in: status).state) == "ok")
        #expect(try item("prefix", in: status).detail == "wine/")
    }

    /// A folder that exists but was never finished is a different problem from
    /// one that was never made, and says so.
    @Test func aHalfMadePrefixSaysItIsIncompleteRatherThanMissing() throws {
        let temp = try TemporaryDirectory()
        try temp.makeDirectory("wine/drive_c")

        let status = Status.inspect(Paths(root: temp.url))
        #expect(!status.prefixReady)
        #expect(try item("prefix", in: status).detail == Strings.incomplete)
        #expect(name(try item("prefix", in: status).state) == "missing")
    }

    // MARK: - The client

    @Test func theClientIsFoundByItsExecutable() throws {
        let temp = try TemporaryDirectory()
        try temp.write(Data("MZ".utf8), to: "wine/drive_c/Gravity/Ragnarok/Ragexe.exe")

        let status = Status.inspect(Paths(root: temp.url))
        #expect(status.clientReady)
        #expect(name(try item("client", in: status).state) == "ok")
        // Dated from the file, so the checklist says which build is installed.
        #expect(try item("client", in: status).detail != Strings.notInstalled)
    }

    @Test func aGameFolderWithoutRagexeIsNotAClient() throws {
        let temp = try TemporaryDirectory()
        try temp.write(Data("data".utf8), to: "wine/drive_c/Gravity/Ragnarok/data.grf")

        #expect(!Status.inspect(Paths(root: temp.url)).clientReady)
    }

    // MARK: - Playable

    @Test func playingNeedsWineThePrefixAndTheClientTogether() {
        var status = Status()
        #expect(!status.canPlay)
        status.wineReady = true
        #expect(!status.canPlay)
        status.prefixReady = true
        #expect(!status.canPlay)
        status.clientReady = true
        #expect(status.canPlay)

        status.wineReady = false
        #expect(!status.canPlay)
    }

    // MARK: - Size on disk

    @Test func addsUpWhatIsUnderTheInstallFolder() throws {
        let temp = try TemporaryDirectory()
        try temp.write(Data(repeating: 0x41, count: 200_000), to: "downloads/client.tar")
        try temp.write(Data(repeating: 0x42, count: 100_000), to: "wine/drive_c/data.grf")

        let size = try #require(Status.inspect(Paths(root: temp.url)).installedSize)
        // Allocated size, so it rounds up to whole blocks rather than matching
        // the byte count exactly.
        #expect(size >= 300_000)
    }

    @Test func anEmptyInstallFolderTakesUpNothing() throws {
        let temp = try TemporaryDirectory()
        #expect(Status.inspect(Paths(root: temp.url)).installedSize == 0)
    }

    // MARK: - Rosetta

    /// The Rosetta line gates installing, never playing: a wrong answer about
    /// a path Apple owns must not lock anyone out of a working game.
    @Test func rosettaIsReportedButNeverBlocksPlaying() throws {
        let temp = try TemporaryDirectory()
        try temp.write(to: "wine/system.reg")
        try temp.makeDirectory("wine/drive_c/windows/system32")
        try temp.write(Data("MZ".utf8), to: "wine/drive_c/Gravity/Ragnarok/Ragexe.exe")

        var status = Status.inspect(Paths(root: temp.url))
        status.wineReady = true
        #expect(status.canPlay)
        #expect(["ok", "warning", "missing"].contains(name(try item("rosetta", in: status).state)))
    }

    @Test func rosettaStateMatchesTheHardwareThisIsRunningOn() {
        if Rosetta.isAppleSilicon {
            #expect(Rosetta.state != .notAppleSilicon)
        } else {
            #expect(Rosetta.state == .notAppleSilicon)
        }
    }

    @Test func theRosettaInstallCommandIsTheOneApplePublishes() {
        #expect(Rosetta.installCommand == "softwareupdate --install-rosetta --agree-to-license")
    }

    /// The expensive check only disagrees with the cheap one by finding Rosetta
    /// where the known paths did not; it never takes it away.
    @Test func verifyOnlyEverUpgradesTheCheapAnswer() async {
        let cheap = Rosetta.state
        let verified = await Rosetta.verify()
        switch cheap {
        case .ready, .notAppleSilicon: #expect(verified == cheap)
        case .missing: #expect(verified == .ready || verified == .missing)
        }
    }
}

struct WineToolTests {

    /// cmd.exe goes through wineconsole because a launcher started from Finder
    /// has no terminal for it to inherit.
    @Test func eachToolNamesTheLoaderThatStartsIt() {
        #expect(WineTool.winecfg.executable == "winecfg")
        #expect(WineTool.winecfg.arguments == [])
        #expect(WineTool.winecfg.label == "winecfg")

        #expect(WineTool.commandPrompt.executable == "wineconsole")
        #expect(WineTool.commandPrompt.arguments == ["cmd"])
        #expect(WineTool.commandPrompt.label == "cmd.exe")
    }

    @Test func toolsAreLookedUpInWinesOwnBinFolder() {
        let paths = Paths(root: URL(filePath: "/test/root"))
        for tool in [WineTool.winecfg, .commandPrompt] {
            let url = paths.wineTool(tool.executable)
            #expect(url.deletingLastPathComponent().lastPathComponent == "bin")
            #expect(url.lastPathComponent == tool.executable)
        }
    }
}

struct GameRunnerTests {

    /// Without a Wine to run there is nothing to prepare, and it says so
    /// before touching the prefix. Everything past this guard needs the
    /// bundled runtime, which a `swift test` run does not have.
    @Test func prepareStopsWhenTheBundleCarriesNoWine() throws {
        let temp = try TemporaryDirectory()
        let paths = Paths(root: temp.url)
        try #require(
            !FileManager.default.isExecutableFile(atPath: paths.wine.path),
            "this test only makes sense outside an assembled app bundle")

        let runner = GameRunner(paths: paths, reporter: .silent)
        #expect(throws: RunError.self) { try runner.prepare() }
    }

    @Test func everyRunFailureDescribesItself() throws {
        let failures: [RunError] = [
            .missingWine(URL(filePath: "/test/wine")),
            .missingFile("d3d9.dll", URL(filePath: "/test/d3d9.dll")),
            .gameNotInstalled(URL(filePath: "/test/game")),
            .exited(139),
        ]
        for failure in failures {
            #expect(!(try #require(failure.errorDescription)).isEmpty)
        }
    }

    @Test func everyInstallFailureDescribesItself() throws {
        let failures: [InstallError] = [
            .rootNotWritable(URL(filePath: "/test/root")),
            .wineRunning,
            .wineRuntimeMissing(URL(filePath: "/test/Wine")),
            .sidecarMissing(URL(filePath: "/test/Resources")),
            .rosettaMissing,
            .notAppleSilicon,
        ]
        for failure in failures {
            #expect(!(try #require(failure.errorDescription)).isEmpty)
        }
    }

    @Test func everyDownloadFailureDescribesItself() throws {
        let failures: [DownloadError] = [
            .unreachable(URL(string: "https://example.com/client.tar")!),
            .httpStatus(503),
            .incomplete(expected: 1000, got: 400),
            .checksumMismatch(expected: "abc", got: "def"),
        ]
        for failure in failures {
            #expect(!(try #require(failure.errorDescription)).isEmpty)
        }
    }
}
