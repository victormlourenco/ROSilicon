import Foundation

/// The Vulkan driver DXVK renders through, both of them on Metal, chosen
/// behind ⌥.
///
/// Wine loads the Khronos loader as libvulkan.1.dylib, and the loader loads
/// whichever driver's manifest `VK_DRIVER_FILES` names; the runtime carries
/// both. KosmicKrisp, Mesa's conformant Vulkan-on-Metal driver, is the one the
/// game uses. It needs a Metal 4 GPU, which macOS only offers from 26 on, so
/// an older Mac gets MoltenVK, the driver the launcher shipped before it.
enum VulkanDriver: String, CaseIterable, Identifiable, Sendable {
    // The raw values are what RO_VULKAN_DRIVER takes, and what the launcher's
    // preferences remember.
    case kosmicKrisp = "kosmickrisp"
    case moltenVK = "moltenvk"

    static let `default` = VulkanDriver.kosmicKrisp

    /// The first macOS KosmicKrisp runs on.
    static let firstKosmicKrispMacOS = 26

    /// Names a driver outright, ahead of the menu's choice, for comparing the
    /// two from a terminal.
    static let overrideKey = "RO_VULKAN_DRIVER"

    /// What `RO_VULKAN_DRIVER` asks for, nil when it is unset or names
    /// neither driver. Read once: the launcher's environment does not change
    /// under it.
    static let override = ProcessInfo.processInfo.environment[overrideKey]
        .flatMap { VulkanDriver(rawValue: $0.lowercased()) }

    /// Whether KosmicKrisp can run on `version` at all. Pure, so a test can
    /// ask about a Mac it is not running on.
    static func supportsKosmicKrisp(onMacOS version: OperatingSystemVersion) -> Bool {
        version.majorVersion >= firstKosmicKrispMacOS
    }

    /// Whether this Mac can run KosmicKrisp. Read once: it cannot change
    /// under a running launcher.
    static let isKosmicKrispSupportedHere = supportsKosmicKrisp(
        onMacOS: ProcessInfo.processInfo.operatingSystemVersion)

    /// The driver for `version`, honoring `requested` where that Mac can run
    /// it. Pure, so a test can ask about a Mac it is not running on.
    static func chosen(onMacOS version: OperatingSystemVersion,
                       requested: VulkanDriver? = nil) -> VulkanDriver {
        guard supportsKosmicKrisp(onMacOS: version) else { return .moltenVK }
        return requested ?? .default
    }

    /// What the choice amounts to on this Mac — MoltenVK before macOS 26
    /// whatever the preferences remember, and `RO_VULKAN_DRIVER` ahead of
    /// both. Every wine the launcher starts is given its driver through
    /// `wineEnvironment`, which resolves it here, so this is the one place
    /// that has to hold for no Mac to be handed a driver it cannot load.
    var onThisMac: VulkanDriver {
        Self.chosen(onMacOS: ProcessInfo.processInfo.operatingSystemVersion,
                    requested: Self.override ?? self)
    }

    var id: String { rawValue }

    /// Its manifest, relative to the Wine runtime; assemble.sh writes both.
    var manifest: String { "share/vulkan/icd.d/\(rawValue)_icd.json" }

    /// How the log names it.
    var label: String {
        switch self {
        case .kosmicKrisp: "KosmicKrisp"
        case .moltenVK: "MoltenVK"
        }
    }

    var menuLabel: String {
        switch self {
        case .kosmicKrisp: Strings.menuVulkanKosmicKrisp
        case .moltenVK: Strings.menuVulkanMoltenVK
        }
    }

    /// Variables the loader would also read drivers from, cleared so one
    /// inherited from whoever started the launcher cannot add a second.
    static let inheritedKeys = ["VK_ICD_FILENAMES", "VK_ADD_DRIVER_FILES"]
}
