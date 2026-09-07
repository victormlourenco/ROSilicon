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

    private var job: Task<Void, Never>?
    private static let logLimit = 5_000

    struct LogLine: Identifiable, Sendable {
        let id = UUID()
        let text: String
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
    var needsInstall: Bool { !status.fullyInstalled }

    var statusLine: String {
        switch phase {
        case .working, .running: step
        case .idle:
            if let failure { failure }
            else if status.fullyInstalled { "Ready to play" }
            else if status.canPlay { "Playable — the GameGuard workaround still needs applying" }
            else { "Not installed yet" }
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

    private func append(_ line: String) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !log.isEmpty else { return }
        log.append(LogLine(text: trimmed))
        if log.count > Self.logLimit { log.removeFirst(log.count - Self.logLimit) }
    }

    private func setStep(_ text: String) {
        step = text
        append("==> " + text)
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
        start(.running) { [reporter] in
            try await GameRunner(paths: paths, reporter: reporter).play()
        }
    }

    func reapplyWintrustPatch() {
        guard !phase.isBusy else { return }
        let paths = self.paths
        start(.working) { [reporter] in
            try await Installer(paths: paths, reporter: reporter).patchWintrust()
        }
    }

    func restoreWintrust() {
        guard !phase.isBusy else { return }
        let paths = self.paths
        start(.working) { [reporter] in
            try await Installer(paths: paths, reporter: reporter).restoreWintrust()
        }
    }

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
                self?.finish(with: "Cancelled.")
                return
            } catch let error as URLError where error.code == .cancelled {
                self?.finish(with: "Cancelled.")
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
            append("error: " + failure)
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
