import Foundation

/// Whether Rosetta 2 is on this machine.
///
/// Everything below the launcher is x86: the client, the Windows DLLs Wine
/// loads for it, and the x87 float code `x87sidecar` hooks. Rosetta is what
/// runs all of it, so a Mac without it gets no further than the first launch.
enum Rosetta {
    enum State: Sendable, Equatable {
        case ready
        case missing
        /// An Intel Mac, where Rosetta is neither present nor the problem.
        case notAppleSilicon
    }

    /// What `softwareupdate --install-rosetta` leaves behind. Looked at rather
    /// than run, so the checklist stays cheap enough to refresh every time the
    /// window comes back.
    private static let runtimeMarkers = [
        "/Library/Apple/usr/libexec/oah/libRosettaRuntime",
        "/Library/Apple/usr/share/rosetta/rosetta",
    ]

    /// The hardware question, not the process one: a translated process still
    /// answers yes, which is what we want.
    static var isAppleSilicon: Bool {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("hw.optional.arm64", &value, &size, nil, 0) == 0 else { return false }
        return value != 0
    }

    /// The cheap answer, for the checklist.
    static var state: State {
        guard isAppleSilicon else { return .notAppleSilicon }
        let fm = FileManager.default
        return runtimeMarkers.contains { fm.fileExists(atPath: $0) } ? .ready : .missing
    }

    /// The answer worth acting on, for the installer.
    ///
    /// Where the runtime keeps its files is Apple's business and has moved
    /// before, so a machine that looks bare is asked the only question that
    /// really matters: does an x86_64 binary run? Nothing is downloaded on the
    /// back of a stale path.
    static func verify() async -> State {
        let cheap = state
        guard cheap == .missing else { return cheap }
        // Rosetta absent, this exits non-zero with "Bad CPU type in
        // executable" — the child never reaches LaunchServices, so no install
        // dialog appears and nothing waits on one.
        let status = try? await Shell.run(
            URL(filePath: "/usr/bin/arch"), ["-x86_64", "/usr/bin/true"])
        return status == 0 ? .ready : .missing
    }

    /// What to tell someone to run. Rosetta installs itself from here without
    /// the launcher ever needing an admin password of its own.
    static let installCommand = "softwareupdate --install-rosetta --agree-to-license"
}
