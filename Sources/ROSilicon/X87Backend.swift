import Foundation

/// The x87 hook Wine's loader re-execs 32-bit programs under, chosen behind ⌥.
///
/// Both make the client's legacy x87 float code fast on Apple Silicon by
/// patching Rosetta's translator; they differ in how they reach the process.
/// x87sidecar is handed the task port by Wine itself, so it needs no privilege
/// and macOS never asks for anything. rosettax87_jit takes the port with
/// task_for_pid, which macOS allows only once someone has typed their password
/// to authorize it — which is why it is the alternative and not the default.
enum X87Backend: String, CaseIterable, Identifiable, Sendable {
    // The raw values are what the launcher's preferences remember.
    case sidecar = "x87sidecar"
    case rosettaX87JIT = "rosettax87_jit"
    /// No hook at all: the client runs under stock Rosetta, its x87 code slow
    /// but translated exactly as Apple does it. For telling a hook's bug from
    /// the game's own.
    case disabled

    static let `default` = X87Backend.sidecar

    /// The first macOS whose Rosetta the hooks are built against. Both of them
    /// work by patching the translator from outside the process, so they are
    /// bound to the Rosetta they were written for rather than to anything the
    /// system promises to keep.
    static let firstSupportedMacOS = 26

    /// Whether a hook can run on `version` at all. Pure, so a test can ask
    /// about a Mac it is not running on.
    static func isSupported(onMacOS version: OperatingSystemVersion) -> Bool {
        version.majorVersion >= firstSupportedMacOS
    }

    /// Whether this Mac can run a hook. Read once: it cannot change under a
    /// running launcher.
    static let isSupportedHere = isSupported(
        onMacOS: ProcessInfo.processInfo.operatingSystemVersion)

    /// What the choice amounts to on this Mac — itself where the hooks run,
    /// and no hook at all before macOS 26, whatever the preferences remember.
    /// Every path that starts a 32-bit program goes through here, so an older
    /// Mac gets stock Rosetta even from a preference set on a newer one.
    var onThisMac: X87Backend { Self.isSupportedHere ? self : .disabled }

    /// Every variable Wine's loader reads a hook from.
    static let environmentKeys = allCases.compactMap(\.environmentKey)

    var id: String { rawValue }

    /// The variable Wine's loader reads the hook's path from, nil when there
    /// is no hook.
    var environmentKey: String? {
        switch self {
        case .sidecar: "X87_SIDECAR_PATH"
        case .rosettaX87JIT: "ROSETTA_X87_PATH"
        case .disabled: nil
        }
    }

    /// The hook inside the app, nil when the app was built without it or
    /// there is no hook.
    var executable: URL? {
        switch self {
        case .sidecar: Paths.x87Sidecar
        case .rosettaX87JIT: Paths.rosettaX87JIT
        case .disabled: nil
        }
    }

    /// Where the app keeps it, for saying so when it is not there. nil when
    /// there is nothing to keep.
    var bundledLocation: URL? {
        switch self {
        case .sidecar: Paths.bundledTools.appending(path: "x87sidecar")
        case .rosettaX87JIT: Paths.rosettaX87JITFolder
        case .disabled: nil
        }
    }

    var menuLabel: String {
        switch self {
        case .sidecar: Strings.menuX87Sidecar
        case .rosettaX87JIT: Strings.menuRosettaX87JIT
        case .disabled: Strings.menuX87Disabled
        }
    }
}
