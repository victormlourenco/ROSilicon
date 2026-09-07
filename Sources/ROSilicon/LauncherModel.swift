import AppKit
import Foundation
import SwiftUI

@MainActor
final class LauncherModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case working
        case running

        var isBusy: Bool { self != .idle }
    }

    @Published private(set) var paths: Paths
    @Published private(set) var status = Status()
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var step = ""
    @Published private(set) var progress: DownloadProgress?
    @Published private(set) var log: [LogLine] = []
    @Published var failure: String?
    @Published var clientURLText = Paths.defaultClientURL.absoluteString
    /// Metal's frame-rate overlay, remembered between launches so someone
    /// chasing a stutter does not have to switch it on every time.
    @Published var metalHUD = UserDefaults.standard.bool(forKey: LauncherModel.metalHUDKey) {
        didSet { UserDefaults.standard.set(metalHUD, forKey: Self.metalHUDKey) }
    }
    /// Wine's debug channels, as typed. Remembered between launches like the
    /// overlay is: someone chasing a crash keeps their channels across
    /// restarts of the launcher.
    @Published var wineDebugText = UserDefaults.standard.string(
        forKey: LauncherModel.wineDebugKey) ?? LaunchOptions.defaultWineDebug {
        didSet { UserDefaults.standard.set(wineDebugText, forKey: Self.wineDebugKey) }
    }
    /// Extra `NAME=value` pairs separated by `;`, applied on top of everything
    /// the launcher sets itself.
    @Published var extraEnvironmentText = UserDefaults.standard.string(
        forKey: LauncherModel.extraEnvironmentKey) ?? "" {
        didSet { UserDefaults.standard.set(extraEnvironmentText, forKey: Self.extraEnvironmentKey) }
    }

    private var job: Task<Void, Never>?
    private static let logLimit = 5_000
    private static let metalHUDKey = "metalHUD"
    private static let wineDebugKey = "wineDebug"
    private static let extraEnvironmentKey = "extraEnvironment"

    struct LogLine: Identifiable, Sendable {
        /// What the line is, so the view can colour it without matching on
        /// text that changes with the reader's language.
        enum Kind: Sendable { case plain, step, failure }

        let id = UUID()
        let text: String
        var kind: Kind = .plain
    }

    init() {
        paths = Paths.locateRoot()
        refresh()
    }

    var installFolder: URL { paths.root }

    // MARK: - State

    func refresh() {
        guard !phase.isBusy else { return }
        let paths = self.paths
        Task {
            let fresh = await Task.detached { Status.inspect(paths) }.value
            self.status = fresh
        }
    }

    var canPlay: Bool { status.canPlay && !phase.isBusy }
    var needsInstall: Bool { !status.canPlay }

    /// What the ⌥ menu's environment settings come to, read at the moment a
    /// process is started so an edit made mid-session lands on the next one.
    var launchOptions: LaunchOptions {
        LaunchOptions(wineDebug: wineDebugText, extraEnvironment: extraEnvironmentText)
    }

    var statusLine: String {
        switch phase {
        case .working, .running: step
        case .idle:
            if let failure { failure }
            else if status.canPlay { Strings.readyToPlay }
            else { Strings.notInstalledYet }
        }
    }

    // MARK: - Reporting

    private var reporter: Reporter {
        Reporter(
            log: { [weak self] line in await self?.append(line) },
            step: { [weak self] step in await self?.setStep(step) },
            progress: { [weak self] progress in
                Task { @MainActor in self?.setProgress(progress) }
            })
    }

    private func append(_ line: String, kind: LogLine.Kind = .plain) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !log.isEmpty else { return }
        log.append(LogLine(text: trimmed, kind: kind))
        if log.count > Self.logLimit { log.removeFirst(log.count - Self.logLimit) }
    }

    private func setStep(_ text: String) {
        step = text
        append("==> " + text, kind: .step)
    }

    private func setProgress(_ value: DownloadProgress?) {
        // Updates arrive from a background queue, so a stale one can land last.
        if let value, let current = progress, value.total == current.total,
           value.completed < current.completed { return }
        progress = value
    }

    // MARK: - Actions

    func install(reinstallClient: Bool = false) {
        guard !phase.isBusy else { return }
        let paths = self.paths
        let url = URL(string: clientURLText.trimmingCharacters(in: .whitespaces))
            ?? Paths.defaultClientURL
        start(.working) { [reporter] in
            try await Installer(paths: paths, reporter: reporter)
                .installEverything(clientURL: url, reinstallClient: reinstallClient)
        }
    }

    func play() {
        guard canPlay else { return }
        let paths = self.paths
        let hud = metalHUD
        let options = launchOptions
        start(.running) { [reporter] in
            try await GameRunner(
                paths: paths, reporter: reporter, metalHUD: hud, options: options
            ).play()
        }
    }

    /// Opens winecfg or a cmd.exe window against the prefix.
    ///
    /// These run beside the launcher instead of through `start`: they are
    /// windows of their own that stay open until someone closes them, so
    /// taking the launcher busy for the whole time would be wrong. Two can be
    /// open at once, which is exactly what someone comparing settings wants.
    func openWineTool(_ tool: WineTool) {
        guard canOpenWineTools else { return }
        let paths = self.paths
        let reporter = self.reporter
        let options = launchOptions
        Task {
            do {
                try await GameRunner(paths: paths, reporter: reporter, options: options)
                    .open(tool)
            } catch {
                append(Strings.errorPrefix + error.localizedDescription, kind: .failure)
            }
        }
    }

    /// Wine has to be there, and an install must not be replacing the build
    /// underneath them. A running game is fine — that is when looking at the
    /// prefix is most useful.
    var canOpenWineTools: Bool { status.wineReady && phase != .working }

    /// Moves the install folder to the Trash. Only offered behind a
    /// confirmation, and refused while Wine is running.
    func clearInstallation() {
        guard !phase.isBusy else { return }
        let paths = self.paths
        start(.working) { [reporter] in
            try await Installer(paths: paths, reporter: reporter).clearInstallation()
        }
    }

    /// What the install takes up on disk, for the confirmation dialog.
    var installedSizeText: String? {
        guard let bytes = status.installedSize, bytes > 0 else { return nil }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    var hasSomethingInstalled: Bool {
        status.wineReady || status.prefixReady || status.clientReady
            || (status.installedSize ?? 0) > 0
    }

    func cancel() {
        job?.cancel()
    }

    /// Stops a running game: wineserver -k takes the whole prefix down, so a
    /// client that stopped responding does not linger.
    func quitGame() {
        guard phase == .running else { return }
        let paths = self.paths
        Task {
            await GameRunner(paths: paths, reporter: reporter).quit()
            job?.cancel()
        }
    }

    private func start(_ phase: Phase, _ work: @escaping @Sendable () async throws -> Void) {
        failure = nil
        self.phase = phase
        job = Task { [weak self] in
            do {
                try await work()
            } catch is CancellationError {
                self?.finish(with: Strings.cancelled)
                return
            } catch let error as URLError where error.code == .cancelled {
                self?.finish(with: Strings.cancelled)
                return
            } catch {
                self?.finish(with: error.localizedDescription)
                return
            }
            self?.finish(with: nil)
        }
    }

    private func finish(with failure: String?) {
        job = nil
        phase = .idle
        progress = nil
        self.failure = failure
        if let failure {
            append(Strings.errorPrefix + failure, kind: .failure)
            step = failure
        }
        refresh()
    }

    // MARK: - Folders

    /// Reveals the install folder, creating it first so Finder always has
    /// something to open.
    func revealInstallFolder() {
        let url = (try? paths.createRoot()) ?? paths.root
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.path)
    }

    /// Reveals the game folder itself, several levels down inside the prefix.
    func revealGameFolder() {
        guard FileManager.default.fileExists(atPath: paths.gameDir.path) else {
            revealInstallFolder()
            return
        }
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: paths.gameDir.path)
    }

    func copyLog() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(
            log.map(\.text).joined(separator: "\n"), forType: .string)
    }
}
