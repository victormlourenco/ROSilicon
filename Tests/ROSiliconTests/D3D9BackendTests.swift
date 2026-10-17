import Foundation
import Testing
@testable import ROSilicon

@Suite(.timeLimit(.minutes(1)))
struct D3D9BackendTests {

    /// Nobody gets d9mt without asking for it. It is the experimental half of
    /// the picker, and the client is only known to run on DXVK.
    @Test func dxvkIsTheDefault() {
        #expect(D3D9Backend.default == .dxvk)
    }

    /// The raw values are a stored preference and the value `RO_D3D9_BACKEND`
    /// takes, so they are not free to be renamed with the cases.
    @Test func rawValuesAreWhatThePreferenceAndTheOverrideHold() {
        #expect(D3D9Backend.dxvk.rawValue == "dxvk")
        #expect(D3D9Backend.d9mt.rawValue == "d9mt")
        #expect(D3D9Backend(rawValue: "d9mt") == .d9mt)
        #expect(D3D9Backend(rawValue: "vulkan") == nil)
    }

    /// Asking for d9mt in an app that was built without it gets DXVK, rather
    /// than a run that fails on a missing d3d9.dll. Which way this goes is the
    /// build's to decide, so the test asks the same question the code does.
    @Test(.enabled(if: D3D9Backend.override == nil, "RO_D3D9_BACKEND already named one"))
    func d9mtIsOnlyEverTheAnswerWhereItWasBuiltIn() {
        #expect(D3D9Backend.d9mt.asShipped
            == (D3D9Backend.isD9MTBundled ? .d9mt : .default))
        #expect(D3D9Backend.dxvk.asShipped == .dxvk)
    }

    /// Both halves have to be in the bundle for d9mt to count as built in: the
    /// PE d3d9.dll the prefix links, and the winemetal unixlib in the Wine
    /// tree it calls Metal through. Outside a bundle neither is there, which
    /// is the case the suite itself runs in.
    @Test func bundledMeansBothHalves() {
        let fm = FileManager.default
        let both = fm.fileExists(atPath: Paths.d9mtDLL.path)
            && fm.fileExists(atPath: Paths.bundledWineMetal.path)
        #expect(D3D9Backend.isD9MTBundled == both)
    }

    /// Where the two staged halves lie, which is the layout `build.sh` writes
    /// and `tools/d9mt/stage.sh` stages.
    @Test func theStagedHalvesAreWhereBuildShPutsThem() {
        #expect(Paths.d9mtDLL.path.hasSuffix("/d9mt/d3d9.dll"))
        #expect(Paths.bundledWineMetal.path
            .hasSuffix("/Wine/lib/wine/x86_64-unix/winemetal.so"))
    }

    /// Only DXVK goes through Vulkan, which is what makes the Vulkan driver
    /// picker meaningless under d9mt — and the MoltenVK variable with it.
    @Test func onlyDXVKUsesVulkan() {
        #expect(D3D9Backend.dxvk.usesVulkan)
        #expect(!D3D9Backend.d9mt.usesVulkan)
    }

    /// Both backends need the native-first d3d9 override, or Wine loads its
    /// own D3D9 and the choice decided nothing. d9mt needs its two builtins
    /// named as well, since a d3d9.dll whose bridge did not load dies on its
    /// first draw.
    @Test func everyBackendOverridesD3D9AndD9MTAlsoNamesItsBridge() {
        for backend in D3D9Backend.allCases {
            #expect(backend.dllOverrides.contains("d3d9=n,b"), "\(backend) does not load")
        }
        for builtin in ["winemetal=b", "d9mtair=b"] {
            #expect(D3D9Backend.d9mt.dllOverrides.contains(builtin))
            #expect(!D3D9Backend.dxvk.dllOverrides.contains(builtin),
                    "DXVK has no bridge to load")
        }
    }

    /// `prepare()` links one of these, so each case has to name a file the
    /// build actually stages — the DXVK built for the run's driver, or d9mt's.
    @Test func eachBackendNamesItsOwnD3D9() {
        for driver in VulkanDriver.allCases {
            #expect(Paths.d3d9DLL(for: .dxvk, vulkan: driver) == Paths.dxvkDLL(for: driver))
            #expect(Paths.d3d9DLL(for: .d9mt, vulkan: driver) == Paths.d9mtDLL)
        }
    }
}
