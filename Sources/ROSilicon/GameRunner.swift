import Foundation

enum RunError: LocalizedError {
    case missingWine(URL)
    case missingFile(String, URL)
    case gameNotInstalled(URL)
    case exited(Int32)

    var errorDescription: String? {
        switch self {
        case .missingWine(let url): Strings.errorMissingWine(url.path)
        case .missingFile(let what, let url): Strings.errorMissingFile(what, url.path)
        case .gameNotInstalled(let url): Strings.errorGameNotInstalled(url.path)
        case .exited(let status): Strings.errorGameExited(status)
        }
    }
}

/// Wine's own tools, offered behind ⌥ for poking at the prefix by hand.
enum WineTool: Sendable {
    case winecfg
    case commandPrompt

    /// The loader in Wine's bin/ that starts it. cmd.exe goes through
    /// wineconsole because it needs a console window drawn for it, and a
    /// launcher started from Finder has no terminal to inherit.
    var executable: String {
        switch self {
        case .winecfg: "winecfg"
        case .commandPrompt: "wineconsole"
        }
    }

    var arguments: [String] {
        switch self {
        case .winecfg: []
        case .commandPrompt: ["cmd"]
        }
    }

    /// What the log calls it, untranslated: these are program names.
    var label: String {
        switch self {
        case .winecfg: "winecfg"
        case .commandPrompt: "cmd.exe"
        }
    }
}

/// Launches the client the way Run.command does.
struct GameRunner: Sendable {
    let paths: Paths
    let reporter: Reporter
    /// Draws Metal's frame-rate overlay on top of the client. Off unless
    /// someone turned it on in the menu; quitting never needs it.
    var metalHUD = false

    /// Shuts down everything in the prefix. Wine's own way of doing it, so a
    /// hung client goes down with it rather than being orphaned.
    func quit() async {
        var environment = paths.wineEnvironment()
        environment["WINEDEBUG"] = "-all"
        _ = try? await Shell.run(paths.wineserver, ["-k"], environment: environment)
    }

    /// Opens one of Wine's tools against the prefix, in a window of its own.
    ///
    /// Unlike playing, this needs neither the client nor the bundled DLLs, so
    /// it stays available on a half-finished install — which is when it is
    /// most useful. An uninitialized prefix gets bootstrapped on the way, the
    /// same as any other wine invocation would do.
    func open(_ tool: WineTool) async throws {
        guard FileManager.default.isExecutableFile(atPath: paths.wine.path) else {
            throw RunError.missingWine(paths.wine)
        }
        let executable = paths.wineTool(tool.executable)
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw RunError.missingFile(tool.executable, executable)
        }

        var environment = paths.wineEnvironment()
        environment["WINEDEBUG"] = "-all"
        await reporter.log(Strings.logOpeningTool(tool.label))
        // Nothing is logged on success: winecfg blocks until its window is
        // closed, while wineconsole returns the moment it has handed the
        // console off, so "closed" would be a lie for one of the two.
        let status = try await Shell.run(
            executable, tool.arguments, environment: environment
        ) { line in await reporter.log(line) }
        if status != 0 {
            await reporter.log(Strings.logToolExited(tool.label, status))
        }
    }

    func play() async throws {
        let steamExe = try prepare()

        var environment = paths.wineEnvironment()
        environment["WINEDLLOVERRIDES"] = "d3d9=n,b"        // DXVK instead of Wine's D3D9
        environment["MVK_CONFIG_SYNCHRONOUS_QUEUE_SUBMITS"] = "1"
        environment["DXVK_ASYNC"] = "1"
        environment["WINEDEBUG"] = "-all"
        // DXVK renders through MoltenVK, so the overlay Metal itself draws is
        // the one that shows the frame rate of the client.
        if metalHUD {
            environment["MTL_HUD_ENABLED"] = "1"
            await reporter.log(Strings.logMetalHUD)
        }

        await reporter.step(Strings.stepRunning)
        await reporter.log(Strings.logLaunching)
        // The client is started through steam.exe because it expects a Steam
        // process to be present.
        let status = try await Shell.run(
            paths.wine, [steamExe.path], environment: environment
        ) { line in await reporter.log(line) }

        if Task.isCancelled { throw CancellationError() }
        guard status == 0 else { throw RunError.exited(status) }
        await reporter.log(Strings.logExitedNormally)
    }

    /// Checks the pieces are in place and links DXVK and the Steam stub, both
    /// inside the app, into the prefix. The links are rewritten every launch,
    /// so one left pointing at an app that has since moved is replaced rather
    /// than followed. Returns the path of steam.exe inside drive_c.
    @discardableResult
    func prepare() throws -> URL {
        guard FileManager.default.isExecutableFile(atPath: paths.wine.path) else {
            throw RunError.missingWine(paths.wine)
        }
        guard FileManager.default.fileExists(atPath: Paths.dxvkDLL.path) else {
            throw RunError.missingFile("d3d9.dll", Paths.dxvkDLL)
        }
        guard FileManager.default.fileExists(atPath: Paths.steamStub.path) else {
            throw RunError.missingFile("steam_stub.exe", Paths.steamStub)
        }
        guard FileManager.default.fileExists(atPath: paths.gameDir.path) else {
            throw RunError.gameNotInstalled(paths.gameDir)
        }

        let steamExe = paths.driveC.appending(path: "steam.exe")
        try link(Paths.dxvkDLL, at: paths.gameDir.appending(path: "d3d9.dll"))
        try link(Paths.steamStub, at: steamExe)
        return steamExe
    }

    /// `ln -sfn`: replace whatever is there with a symlink.
    private func link(_ target: URL, at location: URL) throws {
        let fm = FileManager.default
        if (try? location.checkResourceIsReachable()) == true
            || (try? fm.attributesOfItem(atPath: location.path)) != nil {
            try fm.removeItem(at: location)
        }
        try fm.createSymbolicLink(at: location, withDestinationURL: target)
    }
}
