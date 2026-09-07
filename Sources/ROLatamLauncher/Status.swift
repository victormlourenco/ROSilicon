import Foundation

/// What is installed right now — the checklist the window shows.
struct Status: Sendable {
    enum State: Sendable { case ok, warning, missing }

    struct Item: Identifiable, Sendable {
        let id: String
        let title: String
        let detail: String
        let state: State
    }

    var items: [Item] = []
    /// Bytes on disk under the install folder, nil when there is nothing there.
    var installedSize: Int64?
    var wineReady = false
    var prefixReady = false
    var wintrustPatched = false
    var clientReady = false

    var canPlay: Bool { wineReady && prefixReady && clientReady }
    var fullyInstalled: Bool { canPlay && wintrustPatched }

    /// Inspects the folder. Cheap enough to re-run whenever the window
    /// reappears; the wintrust check parses two DLL export tables.
    static func inspect(_ paths: Paths) -> Status {
        let fm = FileManager.default
        var status = Status()

        // 1. The Wine build
        let installedVersion = paths.installedWineVersion
        let wineUsable = fm.isExecutableFile(atPath: paths.wine.path) && paths.x87Sidecar != nil
        switch (installedVersion, wineUsable) {
        case (Paths.wowSiliconVersion, true):
            status.wineReady = true
            status.items.append(Item(
                id: "wine", title: "Wine build",
                detail: "WoWSilicon \(Paths.wowSiliconVersion)", state: .ok))
        case (let version?, true):
            status.wineReady = true
            status.items.append(Item(
                id: "wine", title: "Wine build",
                detail: "WoWSilicon \(version) — \(Paths.wowSiliconVersion) available",
                state: .warning))
        default:
            status.items.append(Item(
                id: "wine", title: "Wine build",
                detail: installedVersion == nil ? "not installed" : "incomplete — install again",
                state: .missing))
        }

        // 2. The Wine prefix
        status.prefixReady = paths.prefixInitialized
        status.items.append(Item(
            id: "prefix", title: "Wine prefix",
            detail: status.prefixReady
                ? paths.prefix.lastPathComponent + "/"
                : (fm.fileExists(atPath: paths.prefix.path) ? "incomplete" : "not created"),
            state: status.prefixReady ? .ok : .missing))

        // 3. The GameGuard workaround
        let targets = paths.wintrustTargets.filter { fm.fileExists(atPath: $0.path) }
        status.wintrustPatched = !targets.isEmpty && targets.allSatisfy(WintrustPatch.isPatched)
        status.items.append(Item(
            id: "wintrust", title: "GameGuard workaround",
            detail: targets.isEmpty
                ? "no wintrust.dll yet"
                : (status.wintrustPatched
                    ? "wintrust.dll patched (\(targets.count) copies)"
                    : "wintrust.dll not patched"),
            state: targets.isEmpty ? .missing : (status.wintrustPatched ? .ok : .warning)))

        // 4. The game client
        status.clientReady = fm.fileExists(atPath: paths.ragexe.path)
        var clientDetail = "not installed"
        if status.clientReady {
            let modified = (try? paths.ragexe.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate
            clientDetail = modified.map {
                "Ragexe.exe — " + $0.formatted(date: .abbreviated, time: .omitted)
            } ?? "Ragexe.exe"
        }
        status.items.append(Item(
            id: "client", title: "Game client", detail: clientDetail,
            state: status.clientReady ? .ok : .missing))

        status.installedSize = sizeOnDisk(paths.root)
        return status
    }

    /// Walks the install folder so the "clear" confirmation can say how much
    /// is about to go.
    private static func sizeOnDisk(_ url: URL) -> Int64? {
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        guard let walker = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles], errorHandler: { _, _ in true })
        else { return nil }

        var total: Int64 = 0
        for case let file as URL in walker {
            let values = try? file.resourceValues(forKeys: Set(keys))
            total += Int64(values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? 0)
        }
        return total
    }
}
