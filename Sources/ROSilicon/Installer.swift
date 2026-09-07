import Foundation

/// How the installer talks back to the UI. The model supplies closures that
/// hop to the main actor; awaiting them keeps log lines in order.
struct Reporter: Sendable {
    var log: @Sendable (String) async -> Void
    var step: @Sendable (String) async -> Void
    var progress: @Sendable (DownloadProgress?) -> Void

    static let silent = Reporter(log: { _ in }, step: { _ in }, progress: { _ in })
}

enum InstallError: LocalizedError {
    case rootNotWritable(URL)
    case wineRunning
    case missingInDMG(URL)
    case sidecarMissing(URL)

    var errorDescription: String? {
        switch self {
        case .rootNotWritable(let url): Strings.errorRootNotWritable(url.path)
        case .wineRunning: Strings.errorWineRunning
        case .missingInDMG(let url): Strings.errorMissingInDMG(url.lastPathComponent)
        case .sidecarMissing(let url): Strings.errorSidecarMissing(url.path)
        }
    }
}

/// Everything needed to get from a fresh checkout to a playable game, in four
/// stages. Each one is skipped when it is already done, so installing is safe
/// — and cheap — to repeat.
struct Installer: Sendable {
    let paths: Paths
    let reporter: Reporter

    func installEverything(clientURL: URL, reinstallClient: Bool) async throws {
        try paths.createRoot()
        guard FileManager.default.isWritableFile(atPath: paths.root.path) else {
            throw InstallError.rootNotWritable(paths.root)
        }
        await reporter.log(Strings.logInstallingInto(paths.root.path))
        // Nothing may be using the Wine build while we replace or patch it.
        if FileManager.default.fileExists(atPath: paths.wsApp.path),
           await Shell.isProcessRunning(matching: paths.wineRoot.path) {
            throw InstallError.wineRunning
        }

        try await installTools()
        try await installWine()
        try await probeSidecar()
        try await createPrefix()
        try await patchWintrust()
        try await installClient(from: clientURL, force: reinstallClient)

        await reporter.step(Strings.readyToPlay)
        await reporter.log("")
        await reporter.log(Strings.logReady)
    }

    // MARK: - 0. The bundled Windows binaries

    /// Puts DXVK and the Steam stub into the install folder. They ship inside
    /// the app, but the prefix links to these copies, so an install keeps
    /// working even while the app itself is being rebuilt.
    func installTools() async throws {
        await reporter.step(Strings.stepTools)
        let copied = try paths.copyBundledTools()
        if copied.isEmpty {
            await reporter.log(Strings.logToolsInPlace)
        } else {
            await reporter.log(Strings.logToolsCopied(
                copied.joined(separator: " \(Strings.logAnd) "),
                paths.toolsDir.lastPathComponent))
        }
    }

    // MARK: - 1. The Wine build

    func installWine() async throws {
        let installed = paths.installedWineVersion
        if installed == Paths.wowSiliconVersion {
            await reporter.log(Strings.logWineInstalled(Paths.wowSiliconVersion))
            return
        }
        if let installed {
            await reporter.log(Strings.logWineReplacing(installed, Paths.wowSiliconVersion))
        }

        await reporter.step(Strings.stepDownloadingWine(Paths.wowSiliconVersion))
        let url = Paths.wowSiliconDMGURL
        let dmg = paths.downloads.appending(path: "WoWSilicon-\(Paths.wowSiliconVersion).dmg")
        let info = try await Downloader.probe(url)
        await reporter.log(Strings.logDownloading(url.lastPathComponent, format(info.size)))
        try await Downloader.download(
            url, to: dmg, expectedSize: info.size,
            onProgress: reporter.progress, onRetry: retryLogger)
        reporter.progress(nil)

        let mountpoint = URL(filePath: NSTemporaryDirectory())
            .appending(path: "wowsilicon-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: mountpoint, withIntermediateDirectories: true)

        await reporter.step(Strings.stepInstallingWine(Paths.wowSiliconVersion))
        await reporter.log(Strings.logMounting(dmg.lastPathComponent))
        try await Shell.tool("hdiutil", [
            "attach", dmg.path, "-mountpoint", mountpoint.path,
            "-nobrowse", "-readonly", "-quiet",
        ])
        // Detach even when copying fails, so no stray mount is left behind.
        do {
            let source = mountpoint.appending(path: "WoWSilicon.app")
            guard FileManager.default.fileExists(atPath: source.path) else {
                throw InstallError.missingInDMG(dmg)
            }
            await reporter.log(Strings.logCopyingApp(paths.root.path))
            try? FileManager.default.removeItem(at: paths.wsApp)
            try await Shell.tool("ditto", [source.path, paths.wsApp.path])
        } catch {
            _ = try? await Shell.tool("hdiutil", ["detach", mountpoint.path, "-quiet"])
            try? FileManager.default.removeItem(at: mountpoint)
            throw error
        }
        _ = try? await Shell.tool("hdiutil", ["detach", mountpoint.path, "-quiet"])
        try? FileManager.default.removeItem(at: mountpoint)

        // URLSession does not set the quarantine flag, but a manually
        // downloaded .dmg does; clear it so Gatekeeper does not block the Wine
        // binaries.
        _ = try? await Shell.tool("xattr", ["-dr", "com.apple.quarantine", paths.wsApp.path])

        try? FileManager.default.removeItem(at: dmg)
        try? FileManager.default.removeItem(at: paths.downloads)

        let version = try? await Shell.check(
            paths.wine, ["--version"], environment: paths.wineEnvironment())
        await reporter.log(Strings.logUsingWine(version ?? Strings.logUnknownWineVersion))
    }

    /// Validates the x87 hook against the Rosetta build actually installed.
    func probeSidecar() async throws {
        guard let sidecar = paths.x87Sidecar else {
            throw InstallError.sidecarMissing(paths.wsResources)
        }
        await reporter.step(Strings.stepCheckingSidecar)
        let status = try? await Shell.run(sidecar, ["--probe"])
        await reporter.log(status == 0 ? Strings.logSidecarOK : Strings.logSidecarUnsupported)
    }

    // MARK: - 2. The Wine prefix

    func createPrefix() async throws {
        guard !paths.prefixInitialized else {
            await reporter.log(Strings.logPrefixExists(paths.prefix.path))
            return
        }
        await reporter.step(Strings.stepCreatingPrefix)
        await reporter.log(Strings.logCreatingPrefix(paths.prefix.path))
        try FileManager.default.createDirectory(at: paths.prefix, withIntermediateDirectories: true)

        var environment = paths.wineEnvironment()
        environment["WINEDEBUG"] = "-all"
        let status = try await Shell.run(
            paths.wine, ["wineboot", "--init"], environment: environment
        ) { line in await reporter.log(line) }
        guard status == 0 else {
            throw ProcessFailure(command: "wineboot", status: status, output: "")
        }
        _ = try? await Shell.run(paths.wineserver, ["-w"], environment: environment)
        await reporter.log(Strings.logPrefixReady)
    }

    // MARK: - 3. The signature-check workaround

    func patchWintrust() async throws {
        await reporter.step(Strings.stepPatching)
        await reporter.log(Strings.logPatching)
        for target in paths.wintrustTargets {
            guard FileManager.default.fileExists(atPath: target.path) else { continue }
            await reporter.log(try WintrustPatch.patch(target))
        }
    }

    func restoreWintrust() async throws {
        await reporter.step(Strings.stepRestoring)
        for target in paths.wintrustTargets {
            guard FileManager.default.fileExists(atPath: target.path) else { continue }
            await reporter.log(try WintrustPatch.restore(target))
        }
    }

    // MARK: - 4. The game client

    func installClient(from url: URL, force: Bool) async throws {
        if FileManager.default.fileExists(atPath: paths.ragexe.path) && !force {
            await reporter.log(Strings.logClientInstalled(paths.gameDir.path))
            return
        }

        await reporter.step(Strings.stepCheckingDownload)
        await reporter.log(Strings.logQuerying(url.absoluteString))
        let info = try await Downloader.probe(url)
        let tarball = paths.downloads.appending(path: url.lastPathComponent)

        await reporter.step(Strings.stepDownloadingClient)
        await reporter.log(Strings.logDownloadingClient(format(info.size)))
        try await Downloader.download(
            url, to: tarball, expectedSize: info.size,
            onProgress: reporter.progress, onRetry: retryLogger)
        reporter.progress(nil)

        if let expected = info.md5 {
            await reporter.step(Strings.stepVerifying)
            await reporter.log(Strings.logVerifying)
            let total = Downloader.fileSize(tarball)
            let report = reporter.progress
            let actual = try Downloader.md5(of: tarball) { read in
                report(DownloadProgress(completed: read, total: total, bytesPerSecond: 0))
            }
            reporter.progress(nil)
            if actual != expected {
                try? FileManager.default.removeItem(at: tarball)
                throw DownloadError.checksumMismatch(expected: expected, got: actual)
            }
            await reporter.log(Strings.logMD5OK)
        }

        await reporter.step(Strings.stepExtracting)
        await reporter.log(Strings.logExtractingTo(paths.gameDir.path))
        try FileManager.default.createDirectory(
            at: paths.gameDir, withIntermediateDirectories: true)
        // The tarball has no top-level wrapper directory, so its contents land
        // directly in the game folder.
        let counter = Counter()
        try await Shell.tool("tar", ["-xvf", tarball.path, "-C", paths.gameDir.path]) { line in
            let n = counter.increment()
            if n % 25 == 0 { await reporter.step(Strings.stepExtractingCount(n)) }
            _ = line
        }
        await reporter.log(Strings.logExtracted(counter.value))

        await reporter.log(Strings.logRemovingFolder(paths.downloads.lastPathComponent))
        try? FileManager.default.removeItem(at: paths.downloads)
    }

    // MARK: - Extras

    /// Moves the whole install folder to the Trash: the Wine build, the prefix,
    /// the game, the downloads. The Trash rather than an outright delete, so a
    /// mis-click is recoverable until it is emptied.
    ///
    /// Returns where it landed, or nil when there was nothing to remove.
    @discardableResult
    func clearInstallation() async throws -> URL? {
        if await Shell.isProcessRunning(matching: paths.wineRoot.path) {
            throw InstallError.wineRunning
        }
        guard FileManager.default.fileExists(atPath: paths.root.path) else {
            await reporter.log(Strings.logNothingToRemove(paths.root.path))
            await reporter.step(Strings.stepNothingToRemove)
            return nil
        }

        await reporter.step(Strings.stepRemoving)
        await reporter.log(Strings.logMovingToTrash(paths.root.path))
        var trashed: NSURL?
        try FileManager.default.trashItem(at: paths.root, resultingItemURL: &trashed)
        let destination = trashed as URL?
        await reporter.log(Strings.logInTrash(destination?.path ?? Strings.logRemoved))
        await reporter.step(Strings.stepRemoved)
        return destination
    }

    /// Notes a dropped connection in the log; the next attempt resumes.
    private var retryLogger: @Sendable (Int, Error) -> Void {
        { [reporter] attempt, error in
            Task {
                await reporter.log(
                    Strings.logRetrying(error.localizedDescription, attempt + 1))
            }
        }
    }

    private func format(_ bytes: Int64?) -> String {
        guard let bytes else { return Strings.unknownSize }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

/// Counts lines coming off a subprocess's pipe queue.
private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func increment() -> Int {
        lock.lock(); defer { lock.unlock() }
        count += 1
        return count
    }

    var value: Int {
        lock.lock(); defer { lock.unlock() }
        return count
    }
}
