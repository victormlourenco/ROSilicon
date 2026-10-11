import Foundation

/// What turns the client's Direct3D 9 into Metal, chosen behind ⌥.
///
/// DXVK is the one the launcher has always shipped: D3D9 to Vulkan, and a
/// Vulkan driver — MoltenVK or KosmicKrisp, see ``VulkanDriver`` — from there
/// to Metal. [d9mt](https://github.com/neo773/d9mt-v2) is the alternative,
/// and it replaces that whole stack: DXVK 3.0's D3D9 state tracker with a
/// Metal backend bolted straight on, no Vulkan anywhere. It has no compiler
/// of its own for the Vulkan layer to lose, which is the point of trying it;
/// what it costs is maturity.
///
/// Where ``VulkanDriver`` only has to name a manifest, this one decides which
/// `d3d9.dll` the prefix links and which builtins Wine is told to load, so
/// the two pickers are not interchangeable — picking d9mt takes the Vulkan
/// driver out of the picture entirely.
enum D3D9Backend: String, CaseIterable, Identifiable, Sendable {
    // The raw values are what RO_D3D9_BACKEND takes, and what the launcher's
    // preferences remember.
    case dxvk
    case d9mt

    /// DXVK, and for a long while yet: it is the stack the client is known to
    /// run on, and d9mt's own notes still describe a driver whose d3d9.dll
    /// only recently started linking at all. The menu is how d9mt gets tried.
    static let `default` = D3D9Backend.dxvk

    /// Names a backend outright, ahead of the menu's choice, for comparing
    /// the two from a terminal.
    static let overrideKey = "RO_D3D9_BACKEND"

    /// What `RO_D3D9_BACKEND` asks for, nil when it is unset or names
    /// neither. Read once: the launcher's environment does not change under
    /// it.
    static let override = ProcessInfo.processInfo.environment[overrideKey]
        .flatMap { D3D9Backend(rawValue: $0.lowercased()) }

    /// Whether the app was built with d9mt at all.
    ///
    /// It is an optional build product, like x87sidecar: `build.sh` stages it
    /// only when `D9MT` points at a build, so most apps ship without it. Both
    /// halves have to be there — the PE `d3d9.dll` the prefix links, and the
    /// `winemetal` unixlib inside the bundled Wine tree that it calls Metal
    /// through — because a `d3d9.dll` whose bridge is missing loads and then
    /// fails on its first draw.
    static var isD9MTBundled: Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: Paths.d9mtDLL.path)
            && fm.fileExists(atPath: Paths.bundledWineMetal.path)
    }

    /// What the choice amounts to in this app — DXVK whatever the preferences
    /// remember when d9mt was not built in, and `RO_D3D9_BACKEND` ahead of
    /// both. Not `onThisMac` like the other two pickers': what rules d9mt out
    /// is the build, not the Mac.
    ///
    /// Every run resolves the backend here, so this is the one place that has
    /// to hold for no client to be handed a `d3d9.dll` that is not there.
    var asShipped: D3D9Backend {
        let requested = Self.override ?? self
        guard requested == .d9mt else { return requested }
        return Self.isD9MTBundled ? .d9mt : .default
    }

    var id: String { rawValue }

    /// How the log names it.
    var label: String {
        switch self {
        case .dxvk: "DXVK"
        case .d9mt: "d9mt"
        }
    }

    var menuLabel: String {
        switch self {
        case .dxvk: Strings.menuD3D9BackendDXVK
        case .d9mt: Strings.menuD3D9BackendD9MT
        }
    }

    /// Whether DXVK is in the picture, which is what decides whether naming a
    /// Vulkan driver means anything: d9mt never loads one.
    var usesVulkan: Bool { self == .dxvk }

    /// What `WINEDLLOVERRIDES` has to say for this backend.
    ///
    /// `d3d9=n,b` is the native-first override that gets the linked DLL
    /// loaded in place of Wine's own D3D9, and is all DXVK needs. d9mt
    /// additionally reaches Metal through two Wine builtins — `winemetal`,
    /// vendored from DXMT, and `d9mtair`, its shader compiler — which the
    /// tree carries as PE/unixlib pairs and which must be loaded builtin, not
    /// looked for in the prefix.
    var dllOverrides: String {
        switch self {
        case .dxvk: "d3d9=n,b"
        case .d9mt: "d3d9=n,b;winemetal=b;d9mtair=b"
        }
    }
}
