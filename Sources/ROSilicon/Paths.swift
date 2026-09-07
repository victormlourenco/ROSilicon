import Foundation

enum BundledToolsError: LocalizedError {
    case missing(String, URL)

    var errorDescription: String? {
        switch self {
        case .missing(let name, let folder):
            Strings.errorBundledToolMissing(name, folder.path)
        }
    }
}

/// Every path and pinned version the launcher needs, mirroring tools/wine-env.sh.
///
/// `root` is where the launcher installs: the Wine build, the prefix, the game
/// and copies of the two bundled Windows binaries, under
/// ~/Library/Application Support/ROSilicon. The app itself carries DXVK and the
/// Steam stub, so it needs nothing beside it and can live anywhere,
/// /Applications included.
struct Paths: Sendable {
    static let wowSiliconVersion = "3.1.0"
    static let defaultClientURL = URL(string:
        "https://ro1patch.gnjoylatam.com/LIVE/client/LATAM_RO1_Live_20260601_091136.tar")!

    static var wowSiliconDMGURL: URL {
        URL(string: "https://github.com/WoWSilicon/WoWSilicon/releases/download/"
            + "v\(wowSiliconVersion)/WoWSilicon-\(wowSiliconVersion).dmg")!
    }

    let root: URL

    init(root: URL) { self.root = root }

    var wsApp: URL { root.appending(path: "WoWSilicon.app") }
    var wsResources: URL { wsApp.appending(path: "Contents/Resources") }
    var wineRoot: URL { wsResources.appending(path: "Wine") }
    var wine: URL { wineRoot.appending(path: "bin/wine") }
    var wineserver: URL { wineRoot.appending(path: "bin/wineserver") }
    var wineExternalLibs: URL { wineRoot.appending(path: "lib/external") }

    var prefix: URL { root.appending(path: "wine") }
    var driveC: URL { prefix.appending(path: "drive_c") }
    var gameDir: URL { driveC.appending(path: "Gravity/Ragnarok") }
    var ragexe: URL { gameDir.appending(path: "Ragexe.exe") }

    /// True when the prefix has actually been booted, not merely created.
    ///
    /// Any wine invocation with WINEPREFIX set bootstraps the prefix, so the
    /// folder existing is not proof it is complete; these two are written at
    /// the end of that bootstrap.
    var prefixInitialized: Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: prefix.appending(path: "system.reg").path)
            && fm.fileExists(atPath: driveC.appending(path: "windows/system32").path)
    }

    /// Where the app keeps the two Windows binaries it ships with.
    ///
    /// Normally the app's own Resources/. `RO_TOOLS` points somewhere else when
    /// the code runs outside a bundle, as it does under `swift run`.
    static let bundledTools: URL = {
        if let override = ProcessInfo.processInfo.environment["RO_TOOLS"] {
            return URL(filePath: override).standardizedFileURL
        }
        return Bundle.main.resourceURL ?? Bundle.main.bundleURL
    }()

    /// Their copies in the install folder. The prefix links to these rather
    /// than reaching into the app bundle, so the install stands on its own.
    var toolsDir: URL { root.appending(path: "tools") }
    var dxvkDLL: URL { toolsDir.appending(path: "d3d9.dll") }
    var steamStub: URL { toolsDir.appending(path: "steam_stub.exe") }

    /// Copies the bundled binaries into the install folder, replacing copies
    /// that differ from the ones the app now ships. Returns what it copied.
    @discardableResult
    func copyBundledTools() throws -> [String] {
        let fm = FileManager.default
        try fm.createDirectory(at: toolsDir, withIntermediateDirectories: true)

        var copied: [String] = []
        for name in ["d3d9.dll", "steam_stub.exe"] {
            let source = Self.bundledTools.appending(path: name)
            let destination = toolsDir.appending(path: name)
            guard fm.fileExists(atPath: source.path) else {
                throw BundledToolsError.missing(name, Self.bundledTools)
            }
            // Size is enough to notice a rebuilt app shipping a new DXVK.
            let sizeOf: (URL) -> Int64? = {
                (try? fm.attributesOfItem(atPath: $0.path)[.size] as? NSNumber)??.int64Value
            }
            if let have = sizeOf(destination), have == sizeOf(source) { continue }
            try? fm.removeItem(at: destination)
            try fm.copyItem(at: source, to: destination)
            copied.append(name)
        }
        return copied
    }

    var downloads: URL { root.appending(path: "downloads") }

    /// x87sidecar ships inside the SwiftPM resource bundle; some builds flatten
    /// it straight into Resources/ instead.
    var x87Sidecar: URL? {
        let candidates = [
            wsResources.appending(path: "WoWSilicon-swift_WoWSiliconSwift.bundle/Patching/x87sidecar/x87sidecar"),
            wsResources.appending(path: "Patching/x87sidecar/x87sidecar"),
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    /// Version of the installed WoWSilicon.app, nil when it is not there.
    var installedWineVersion: String? {
        let plist = wsApp.appending(path: "Contents/Info.plist")
        guard let data = try? Data(contentsOf: plist),
              let info = try? PropertyListSerialization.propertyList(
                  from: data, format: nil) as? [String: Any]
        else { return nil }
        return info["CFBundleShortVersionString"] as? String
    }

    /// Every wintrust.dll that needs patching. This Wine copies its DLLs into
    /// each prefix instead of symlinking them, so patching the build alone
    /// leaves an already-created prefix untouched.
    var wintrustTargets: [URL] {
        var targets = [
            wineRoot.appending(path: "lib/wine/i386-windows/wintrust.dll"),
            wineRoot.appending(path: "lib/wine/x86_64-windows/wintrust.dll"),
        ]
        for dll in ["windows/system32/wintrust.dll", "windows/syswow64/wintrust.dll"] {
            let url = driveC.appending(path: dll)
            if FileManager.default.fileExists(atPath: url.path) { targets.append(url) }
        }
        return targets
    }

    /// Environment shared by every Wine invocation — the Swift side of `wine_env`.
    func wineEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["WINEPREFIX"] = prefix.path
        env["WINELOADER"] = wine.path
        env["WINESERVER"] = wineserver.path
        // Wine's loader re-execs itself under `x87sidecar --cooperative` when
        // this is set. That is what makes the client's legacy x87 float code
        // fast on Apple Silicon, and unlike rosettax87 it needs no
        // task_for_pid privilege, so macOS never asks for a password.
        if let sidecar = x87Sidecar { env["X87_SIDECAR_PATH"] = sidecar.path }
        // Wine dlopen()s freetype, gnutls, MoltenVK and SDL2 by leaf name; the
        // bundle keeps them here rather than relying on a system copy.
        let dyld = env["DYLD_LIBRARY_PATH"].map { ":\($0)" } ?? ""
        env["DYLD_LIBRARY_PATH"] = wineExternalLibs.path + dyld
        env["PATH"] = wineRoot.appending(path: "bin").path + ":" + (env["PATH"] ?? "/usr/bin:/bin")
        return env
    }

    /// Where the launcher installs, by default
    /// ~/Library/Application Support/ROSilicon. `RO_ROOT` overrides it.
    static var installRoot: URL {
        if let override = ProcessInfo.processInfo.environment["RO_ROOT"] {
            return URL(filePath: override).standardizedFileURL
        }
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(filePath: NSHomeDirectory()).appending(path: "Library/Application Support")
        return base.appending(path: "ROSilicon")
    }

    static func locateRoot() -> Paths { Paths(root: installRoot) }

    /// Creates the install folder. Called before installing and before showing
    /// the folder in Finder, so neither ever faces a missing directory.
    @discardableResult
    func createRoot() throws -> URL {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

}
