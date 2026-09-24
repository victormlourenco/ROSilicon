import Foundation

/// The Vulkan driver DXVK renders through, both of them on Metal.
///
/// Wine loads the Khronos loader as libvulkan.1.dylib, and the loader loads
/// whichever driver's manifest `VK_DRIVER_FILES` names; the runtime carries
/// both. KosmicKrisp, Mesa's conformant Vulkan-on-Metal driver, is the one the
/// game uses. It needs a Metal 4 GPU, which macOS only offers from 26 on, so
/// an older Mac gets MoltenVK, the driver the launcher shipped before it.
enum VulkanDriver: String, CaseIterable, Sendable {
    // The raw values are what RO_VULKAN_DRIVER takes.
    case kosmicKrisp = "kosmickrisp"
    case moltenVK = "moltenvk"

    /// The first macOS KosmicKrisp runs on.
    static let firstKosmicKrispMacOS = 26

    /// Names a driver outright, for comparing the two on a Mac that runs both.
    static let overrideKey = "RO_VULKAN_DRIVER"

    /// The driver for `version`, honoring `requested` where that Mac can run
    /// it. Pure, so a test can ask about a Mac it is not running on.
    static func chosen(onMacOS version: OperatingSystemVersion,
                       requested: VulkanDriver? = nil) -> VulkanDriver {
        guard version.majorVersion >= firstKosmicKrispMacOS else { return .moltenVK }
        return requested ?? .kosmicKrisp
    }

    /// The driver this launcher uses. Read once: neither the Mac nor the
    /// launcher's environment changes under it.
    static let onThisMac = chosen(
        onMacOS: ProcessInfo.processInfo.operatingSystemVersion,
        requested: ProcessInfo.processInfo.environment[overrideKey]
            .flatMap { VulkanDriver(rawValue: $0.lowercased()) })

    /// Its manifest, relative to the Wine runtime; assemble.sh writes both.
    var manifest: String { "share/vulkan/icd.d/\(rawValue)_icd.json" }

    /// How the log names it.
    var label: String {
        switch self {
        case .kosmicKrisp: "KosmicKrisp"
        case .moltenVK: "MoltenVK"
        }
    }

    /// Variables the loader would also read drivers from, cleared so one
    /// inherited from whoever started the launcher cannot add a second.
    static let inheritedKeys = ["VK_ICD_FILENAMES", "VK_ADD_DRIVER_FILES"]
}
