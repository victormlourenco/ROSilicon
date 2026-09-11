import Foundation
import Testing
@testable import ROSilicon

struct PathsTests {

    // MARK: - Layout

    @Test func everythingInstalledHangsOffTheRoot() {
        let paths = Paths(root: URL(filePath: "/test/root"))
        #expect(paths.prefix.path == "/test/root/wine")
        #expect(paths.driveC.path == "/test/root/wine/drive_c")
        #expect(paths.gameDir.path == "/test/root/wine/drive_c/Gravity/Ragnarok")
        #expect(paths.ragexe.path == "/test/root/wine/drive_c/Gravity/Ragnarok/Ragexe.exe")
        #expect(paths.downloads.path == "/test/root/downloads")
    }

    /// Wine runs from inside the app bundle, so the launcher can live anywhere
    /// and nothing under the install folder is Wine's.
    @Test func wineIsReadFromTheBundleNotTheInstallFolder() {
        let paths = Paths(root: URL(filePath: "/test/root"))
        let bundled = Paths.bundledWineRoot.path
        #expect(paths.wineRoot.path == bundled)
        #expect(paths.wine.path == bundled + "/bin/wine")
        #expect(paths.wineserver.path == bundled + "/bin/wineserver")
        #expect(paths.wineExternalLibs.path == bundled + "/lib/external")
        #expect(paths.wineTool("winecfg").path == bundled + "/bin/winecfg")
        #expect(paths.wineTool("wineconsole").path == bundled + "/bin/wineconsole")
        #expect(!paths.wine.path.hasPrefix(paths.root.path))
    }

    @Test func bundledWineRootSitsBesideTheOtherBundledTools() {
        #expect(Paths.bundledWineRoot.path == Paths.bundledTools.path + "/Wine")
        #expect(Paths.dxvkDLL.path == Paths.bundledTools.path + "/d3d9.dll")
        #expect(Paths.steamStub.path == Paths.bundledTools.path + "/steam_stub.exe")
        #expect(Paths.rosettaX87JITFolder.path == Paths.bundledTools.path + "/rosettax87_jit")
        #expect(X87Backend.rosettaX87JIT.bundledLocation == Paths.rosettaX87JITFolder)
    }

    @Test func theDefaultClientURLIsAnHTTPSTarball() {
        #expect(Paths.defaultClientURL.scheme == "https")
        #expect(Paths.defaultClientURL.pathExtension == "tar")
    }

    // MARK: - Prefix readiness

    /// The folder existing is not proof the prefix was booted: any wine call
    /// with WINEPREFIX set creates it, and only a finished bootstrap leaves
    /// both of these behind.
    @Test func prefixCountsAsInitializedOnlyOnceBootstrapFinished() throws {
        let temp = try TemporaryDirectory()
        let paths = Paths(root: temp.url)
        #expect(!paths.prefixInitialized)

        try temp.makeDirectory("wine")
        #expect(!paths.prefixInitialized)

        try temp.write(to: "wine/system.reg")
        #expect(!paths.prefixInitialized)

        try temp.makeDirectory("wine/drive_c/windows/system32")
        #expect(paths.prefixInitialized)
    }

    @Test func aPrefixWithSystem32ButNoRegistryIsIncomplete() throws {
        let temp = try TemporaryDirectory()
        try temp.makeDirectory("wine/drive_c/windows/system32")
        #expect(!Paths(root: temp.url).prefixInitialized)
    }

    // MARK: - The install folder

    @Test func createRootIsSafeToRepeatAndReturnsTheFolder() throws {
        let temp = try TemporaryDirectory()
        let root = temp.url.appending(path: "nested/install")
        let paths = Paths(root: root)

        #expect(try paths.createRoot() == root)
        #expect(FileManager.default.fileExists(atPath: root.path))
        try temp.write(Data("keep".utf8), to: "nested/install/marker")

        #expect(try paths.createRoot() == root)
        #expect(FileManager.default.fileExists(atPath: root.appending(path: "marker").path))
    }

    // MARK: - The Wine environment

    @Test func wineEnvironmentPointsEveryWineVariableAtThisInstall() {
        let paths = Paths(root: URL(filePath: "/test/root"))
        let environment = paths.wineEnvironment()
        #expect(environment["WINEPREFIX"] == paths.prefix.path)
        #expect(environment["WINELOADER"] == paths.wine.path)
        #expect(environment["WINESERVER"] == paths.wineserver.path)
    }

    /// The bundle's own libraries go first, and anything the process inherited
    /// is kept behind them rather than thrown away.
    @Test func wineEnvironmentPrependsTheBundledLibrariesToWhatWasInherited() {
        let paths = Paths(root: URL(filePath: "/test/root"))
        let inherited = ProcessInfo.processInfo.environment["DYLD_LIBRARY_PATH"]
        let expected = paths.wineExternalLibs.path + (inherited.map { ":\($0)" } ?? "")
        #expect(paths.wineEnvironment()["DYLD_LIBRARY_PATH"] == expected)
    }

    @Test func wineEnvironmentPutsWinesBinFirstOnPath() {
        let paths = Paths(root: URL(filePath: "/test/root"))
        let inherited = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin"
        let path = paths.wineEnvironment()["PATH"]
        #expect(path == paths.wineRoot.appending(path: "bin").path + ":" + inherited)
    }

    /// The launcher's own variables are added to the process environment, not
    /// substituted for it, so the child keeps HOME and the rest.
    @Test func wineEnvironmentInheritsTheRestOfTheProcessEnvironment() {
        let environment = Paths(root: URL(filePath: "/test/root")).wineEnvironment()
        for (name, value) in ProcessInfo.processInfo.environment
        where !["WINEPREFIX", "WINELOADER", "WINESERVER", "X87_SIDECAR_PATH",
                "ROSETTA_X87_PATH", "DYLD_LIBRARY_PATH", "PATH"].contains(name) {
            #expect(environment[name] == value)
        }
    }

    // MARK: - The x87 hook

    /// x87sidecar is the default, and it comes alone: Wine's loader would
    /// otherwise be left to pick between two.
    @Test func theDefaultX87HookIsTheSidecarAlone() {
        let environment = Paths(root: URL(filePath: "/test/root")).wineEnvironment()
        #expect(environment["X87_SIDECAR_PATH"] == Paths.x87Sidecar?.path)
        #expect(environment["ROSETTA_X87_PATH"] == nil)
    }

    /// The loader tries X87_SIDECAR_PATH first, so choosing rosettax87_jit has
    /// to clear it or the choice would do nothing.
    @Test func choosingRosettaX87JITClearsTheSidecar() {
        let environment = Paths(root: URL(filePath: "/test/root"))
            .wineEnvironment(x87: .rosettaX87JIT)
        #expect(environment["X87_SIDECAR_PATH"] == nil)
        #expect(environment["ROSETTA_X87_PATH"] == Paths.rosettaX87JIT?.path)
    }

    /// Disabled means neither variable, so Wine's loader execs the client
    /// under stock Rosetta.
    @Test func disablingTheX87HookSetsNeither() {
        let environment = Paths(root: URL(filePath: "/test/root"))
            .wineEnvironment(x87: .disabled)
        #expect(environment["X87_SIDECAR_PATH"] == nil)
        #expect(environment["ROSETTA_X87_PATH"] == nil)
        #expect(X87Backend.disabled.executable == nil)
        #expect(X87Backend.disabled.bundledLocation == nil)
    }

    /// The loader reads libRuntimeRosettax87 from its own folder, so on its
    /// own it is no hook.
    @Test func rosettaX87JITNeedsItsRuntimeBesideTheLoader() throws {
        let temp = try TemporaryDirectory()
        let loader = try temp.write(to: "runtime_loader")
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: loader.path)
        #expect(Paths.rosettaX87JIT(in: temp.url) == nil)

        try temp.write(to: "libRuntimeRosettax87")
        #expect(Paths.rosettaX87JIT(in: temp.url) == loader)
    }

    @Test func aRosettaX87JITLoaderThatCannotRunIsNoHook() throws {
        let temp = try TemporaryDirectory()
        try temp.write(to: "runtime_loader")
        try temp.write(to: "libRuntimeRosettax87")
        #expect(Paths.rosettaX87JIT(in: temp.url) == nil)
    }

    /// The raw values are what the preferences remember, so renaming a case
    /// would quietly send someone back to the default.
    @Test func x87HooksKeepTheNamesThePreferencesStore() {
        #expect(X87Backend.default == .sidecar)
        #expect(X87Backend.allCases.map(\.rawValue)
                == ["x87sidecar", "rosettax87_jit", "disabled"])
        #expect(X87Backend.sidecar.environmentKey == "X87_SIDECAR_PATH")
        #expect(X87Backend.rosettaX87JIT.environmentKey == "ROSETTA_X87_PATH")
        #expect(X87Backend.disabled.environmentKey == nil)
        #expect(X87Backend.environmentKeys == ["X87_SIDECAR_PATH", "ROSETTA_X87_PATH"])
    }

    // MARK: - Errors

    /// The message itself is checked against the shipped strings file in
    /// `LocalizationTests`; outside the app bundle there is no strings table
    /// to look one up in, so all this can say is that a description exists.
    @Test func aMissingBundledToolDescribesItself() throws {
        let error = BundledToolsError.missing("d3d9.dll", URL(filePath: "/test/Resources"))
        #expect(!(try #require(error.errorDescription)).isEmpty)
    }
}
