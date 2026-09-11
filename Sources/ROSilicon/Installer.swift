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
    case wineRuntimeMissing(URL)
    case sidecarMissing(URL)
    case rosettaMissing
    case notAppleSilicon

    var errorDescription: String? {
        switch self {
        case .rootNotWritable(let url): Strings.errorRootNotWritable(url.path)
        case .wineRunning: Strings.errorWineRunning
        case .wineRuntimeMissing(let url): Strings.errorWineRuntimeMissing(url.path)
        case .sidecarMissing(let url): Strings.errorSidecarMissing(url.path)
        case .rosettaMissing: Strings.errorRosettaMissing(Rosetta.installCommand)
        case .notAppleSilicon: Strings.errorNotAppleSilicon
        }
    }
}

/// Everything needed to get from a fresh app to a playable game, in three
/// stages. The first only checks what the app already carries; the rest are
/// each skipped when they are already done, so installing is safe — and cheap
/// — to repeat.
struct Installer: Sendable {
    let paths: Paths
    let reporter: Reporter
    var keyboard = GameKeyboardSettings()

    func installEverything(clientURL: URL, reinstallClient: Bool) async throws {
        try paths.createRoot()
        guard FileManager.default.isWritableFile(atPath: paths.root.path) else {
            throw InstallError.rootNotWritable(paths.root)
        }
        await reporter.log(Strings.logInstallingInto(paths.root.path))
        // Nothing may be using the prefix while we patch the DLLs in it.
        if await Shell.isProcessRunning(matching: paths.wineRoot.path) {
            throw InstallError.wineRunning
        }

        try await verifyRosetta()
        try await checkBundle()
        try await probeSidecar()
        try await createPrefix()
        // Outside createPrefix's early return: repairs of existing prefixes
        // must apply the saved choice just like a new installation does.
        try await keyboard.apply(
            wine: paths.wine, environment: paths.wineEnvironment(), reporter: reporter)
        try await installClient(from: clientURL, force: reinstallClient)

        await reporter.step(Strings.readyToPlay)
        await reporter.log("")
        await reporter.log(Strings.logReady)
    }

    // MARK: - Prerequisites

    /// Checks Rosetta before a byte is downloaded, so a Mac without it hears
    /// about it in a second rather than after several gigabytes.
    func verifyRosetta() async throws {
        await reporter.step(Strings.stepCheckingRosetta)
        switch await Rosetta.verify() {
        case .ready: await reporter.log(Strings.logRosettaOK)
        case .missing: throw InstallError.rosettaMissing
        case .notAppleSilicon: throw InstallError.notAppleSilicon
        }
    }

    // MARK: - 1. What the app carries

    /// Nothing to install: Wine, DXVK, the Steam stub and x87sidecar all run
    /// from inside the app bundle, patched and signed by `build.sh`. This
    /// checks they are there and says which Wine it is.
    func checkBundle() async throws {
        guard let bundled = Paths.bundledWineVersion,
              FileManager.default.isExecutableFile(atPath: paths.wine.path)
        else { throw InstallError.wineRuntimeMissing(Paths.bundledWineRoot) }
        try Paths.verifyBundledTools()

        await reporter.step(Strings.stepCheckingWine(bundled))
        // The app may have arrived quarantined from a .dmg, and Gatekeeper
        // would then refuse the binaries inside it. Best effort: an app
        // installed somewhere unwritable cannot be cleared, and one the user
        // has already opened does not need it.
        _ = try? await Shell.tool(
            "xattr", ["-dr", "com.apple.quarantine", Paths.bundledTools.path])

        let version = try? await Shell.check(
            paths.wine, ["--version"], environment: paths.wineEnvironment())
        await reporter.log(Strings.logUsingWine(version ?? Strings.logUnknownWineVersion))

        // Older installs kept their own copies under the install folder: up to
        // 0.0.3 a whole WoWSilicon.app, downloaded on first run, and a tools/
        // folder beside it. Gigabytes of nothing now.
        for stale in ["WoWSilicon.app", "wine-runtime", "tools"] {
            let url = paths.root.appending(path: stale)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            await reporter.log(Strings.logRemovingOld(stale))
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Validates the x87 hook against the Rosetta build actually installed.
    func probeSidecar() async throws {
        guard let sidecar = Paths.x87Sidecar else {
            throw InstallError.sidecarMissing(Paths.bundledTools)
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

    // MARK: - 3. The game client

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

    /// Moves the whole install folder to the Trash: every profile's prefix and
    /// game, the downloads. Not Wine, DXVK or the stubs, which are part of the
    /// app. The Trash rather than an outright delete, so a mis-click is
    /// recoverable until it is emptied.
    ///
    /// Returns where it landed, or nil when there was nothing to remove.
    @discardableResult
    func clearInstallation() async throws -> URL? {
        if await Shell.isProcessRunning(matching: paths.wineRoot.path) {
            throw InstallError.wineRunning
        }
        return try await trash(
            paths.root, removing: Strings.stepRemoving, removed: Strings.stepRemoved)
    }

    /// Moves the profile's prefix to the Trash, its game and settings with it,
    /// and leaves every other profile alone. Never the default profile, which
    /// only goes with the whole install folder.
    ///
    /// Returns where it landed, or nil when there was nothing to remove.
    @discardableResult
    func deleteProfile() async throws -> URL? {
        guard paths.profile.isDeletable else { throw ProfileError.defaultNotDeletable }
        if await Shell.isProcessRunning(matching: paths.wineRoot.path) {
            throw InstallError.wineRunning
        }
        let name = paths.profile.displayName
        return try await trash(
            paths.prefix, removing: Strings.stepRemovingProfile(name),
            removed: Strings.stepProfileRemoved(name))
    }

    /// Moves `folder` to the Trash, announcing it with the two steps given.
    private func trash(_ folder: URL, removing: String, removed: String) async throws -> URL? {
        guard FileManager.default.fileExists(atPath: folder.path) else {
            await reporter.log(Strings.logNothingToRemove(folder.path))
            await reporter.step(Strings.stepNothingToRemove)
            return nil
        }

        await reporter.step(removing)
        await reporter.log(Strings.logMovingToTrash(folder.path))
        var trashed: NSURL?
        try FileManager.default.trashItem(at: folder, resultingItemURL: &trashed)
        let destination = trashed as URL?
        await reporter.log(Strings.logInTrash(destination?.path ?? Strings.logRemoved))
        await reporter.step(removed)
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
