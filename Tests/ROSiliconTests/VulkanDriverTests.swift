import Foundation
import Testing
@testable import ROSilicon

@Suite(.timeLimit(.minutes(1)))
struct VulkanDriverTests {

    private func macOS(_ major: Int) -> OperatingSystemVersion {
        OperatingSystemVersion(majorVersion: major, minorVersion: 0, patchVersion: 0)
    }

    @Test func kosmicKrispIsTheDriverFromMacOS26On() {
        #expect(VulkanDriver.chosen(onMacOS: macOS(26)) == .kosmicKrisp)
        #expect(VulkanDriver.chosen(onMacOS: macOS(27)) == .kosmicKrisp)
    }

    /// KosmicKrisp needs a Metal 4 GPU, which an older macOS never offers.
    @Test func anOlderMacGetsMoltenVK() {
        #expect(VulkanDriver.chosen(onMacOS: macOS(14)) == .moltenVK)
        #expect(VulkanDriver.chosen(onMacOS: macOS(15)) == .moltenVK)
    }

    @Test func moltenVKCanBeAskedForWhereBothRun() {
        #expect(VulkanDriver.chosen(onMacOS: macOS(26), requested: .moltenVK) == .moltenVK)
    }

    /// Asking for KosmicKrisp cannot make it run where it cannot.
    @Test func askingForKosmicKrispBeforeMacOS26StillGetsMoltenVK() {
        #expect(VulkanDriver.chosen(onMacOS: macOS(15), requested: .kosmicKrisp) == .moltenVK)
    }

    /// The one the menu starts on, and what `chosen` falls back to.
    @Test func kosmicKrispIsTheDefault() {
        #expect(VulkanDriver.default == .kosmicKrisp)
        #expect(VulkanDriver.chosen(onMacOS: macOS(26)) == VulkanDriver.default)
    }

    /// Where both run and nothing names one outright, the menu's choice is
    /// what the launcher hands the loader.
    @Test(.enabled(if: VulkanDriver.isKosmicKrispSupportedHere && VulkanDriver.override == nil,
                   "this Mac runs one driver, or RO_VULKAN_DRIVER already named one"))
    func theMenusChoiceIsWhatRunsWhereBothDo() {
        for driver in VulkanDriver.allCases {
            #expect(driver.onThisMac == driver)
        }
    }

    /// assemble.sh writes the manifests under these names.
    @Test func manifestsLieInTheRuntimesICDFolder() {
        #expect(VulkanDriver.kosmicKrisp.manifest == "share/vulkan/icd.d/kosmickrisp_icd.json")
        #expect(VulkanDriver.moltenVK.manifest == "share/vulkan/icd.d/moltenvk_icd.json")
    }
}
