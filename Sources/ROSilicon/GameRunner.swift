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

/// Launches the client the way Run.command does.
struct GameRunner: Sendable {
    let paths: Paths
    let reporter: Reporter

    /// Shuts down everything in the prefix. Wine's own way of doing it, so a
    /// hung client goes down with it rather than being orphaned.
    func quit() async {
        var environment = paths.wineEnvironment()
        environment["WINEDEBUG"] = "-all"
        _ = try? await Shell.run(paths.wineserver, ["-k"], environment: environment)
    }

    func play() async throws {
        let steamExe = try prepare()

        var environment = paths.wineEnvironment()
        environment["WINEDLLOVERRIDES"] = "d3d9=n,b"        // DXVK instead of Wine's D3D9
        environment["MVK_CONFIG_SYNCHRONOUS_QUEUE_SUBMITS"] = "1"
        environment["DXVK_ASYNC"] = "1"
        environment["WINEDEBUG"] = "-all"

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

    /// Checks the pieces are in place and links DXVK and the Steam stub into
    /// the prefix. Returns the path of steam.exe inside drive_c.
    @discardableResult
    func prepare() throws -> URL {
        guard FileManager.default.isExecutableFile(atPath: paths.wine.path) else {
            throw RunError.missingWine(paths.wine)
        }
        // Puts back a copy that was deleted, and picks up a newer one from a
        // rebuilt app.
        try paths.copyBundledTools()
        guard FileManager.default.fileExists(atPath: paths.dxvkDLL.path) else {
            throw RunError.missingFile("d3d9.dll", paths.dxvkDLL)
        }
        guard FileManager.default.fileExists(atPath: paths.steamStub.path) else {
            throw RunError.missingFile("steam_stub.exe", paths.steamStub)
        }
        guard FileManager.default.fileExists(atPath: paths.gameDir.path) else {
            throw RunError.gameNotInstalled(paths.gameDir)
        }

        let steamExe = paths.driveC.appending(path: "steam.exe")
        try link(paths.dxvkDLL, at: paths.gameDir.appending(path: "d3d9.dll"))
        try link(paths.steamStub, at: steamExe)
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
