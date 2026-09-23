import Foundation
@testable import ROSilicon

// A note on a hang, for whoever meets it next.
//
// The suite stalls now and then — once in two runs at worst, once in six at
// best, and it will not reproduce on demand. It is not one bad test: both
// times it was caught, fourteen tests were outstanding together — every
// Downloader test, the two Shell ones that watch a live process, and the
// Discord socket one.
//
// The Downloader suites are disabled, and that is a quarantine rather than a
// cure — they are not the cause, and turning them off does not stop the hang.
// Run alone, fifteen times, over runs as long as the whole suite takes, they
// never stalled once. They crowd the list above because they are the slowest
// thing here, so they are what is still in flight when the freeze lands.
// Whatever is wrong runs alongside them.
//
// Left under suspicion, as the rest of that list of fourteen: the two Shell
// tests that watch a live process, and the Discord socket one. `Shell.run`
// holds a thread in `waitUntilExit()` for as long as its child lives, and the
// cancellation test keeps `/bin/sleep 30` for up to thirty seconds. The next
// cut is the mirror of the one already done: keep the Downloader suites, put
// those three away, and see whether it still stalls.
//
// The suites all carry `.timeLimit` and it does not catch this. That was
// measured, not assumed: a stalled run sat for 150 seconds against a ceiling
// of 60 and never tripped it. A time limit races a sleeping task against the
// test, and both want the same cooperative threads — if what is stuck is the
// pool itself, the timeout cannot be scheduled either. The ceilings are worth
// keeping for an ordinary slow test; they are no help here.
//
// What would settle it is a sampler caught on a stalled run:
//     swift test & sleep 60; sample $(pgrep -x swiftpm-testing-helper) 5
// Match the executable, not the command line — `pgrep -f` also finds the
// shell you typed it into, and samples that instead.

/// The repository root, found from this file rather than the working
/// directory, so the resource-reading tests work under `swift test` and Xcode
/// alike.
let projectRoot = URL(filePath: #filePath)
    .deletingLastPathComponent()   // ROSiliconTests
    .deletingLastPathComponent()   // Tests
    .deletingLastPathComponent()   // repository root

/// A scratch directory that goes away with the test that made it.
///
/// The path is canonical: the system temp folder is /var, a link to
/// /private/var, and a subprocess asked where it is answers with the real one.
/// `resolvingSymlinksInPath` is no good here — it strips a leading /private
/// rather than following the link — so this asks realpath(3) instead.
final class TemporaryDirectory: @unchecked Sendable {
    let url: URL

    init(_ name: String = "ROSiliconTests") throws {
        let created = URL(filePath: NSTemporaryDirectory())
            .appending(path: "\(name).\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: created, withIntermediateDirectories: true)
        url = Self.canonical(created)
    }

    private static func canonical(_ url: URL) -> URL {
        guard let resolved = realpath(url.path, nil) else { return url }
        defer { free(resolved) }
        return URL(filePath: String(cString: resolved))
    }

    deinit { try? FileManager.default.removeItem(at: url) }

    /// Creates a directory under the scratch folder, parents included.
    @discardableResult
    func makeDirectory(_ path: String) throws -> URL {
        let directory = url.appending(path: path)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Lays out a prefix that looks like a finished `wineboot --init`: the
    /// registry, the 64-bit system folder, and the 32-bit kernel32 the client
    /// loads. All three, because a bootstrap cut short leaves the first two
    /// without the third and the launcher must not call that ready.
    @discardableResult
    func makeBootedPrefix(_ folder: String = "wine") throws -> URL {
        try write(to: "\(folder)/system.reg")
        try makeDirectory("\(folder)/drive_c/windows/system32")
        try write(to: "\(folder)/drive_c/windows/syswow64/kernel32.dll")
        return url.appending(path: folder)
    }

    /// Writes a file under the scratch folder, creating its parents.
    @discardableResult
    func write(_ contents: Data = Data(), to path: String) throws -> URL {
        let file = url.appending(path: path)
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: file)
        return file
    }
}

/// Counts calls made from concurrent contexts.
actor CallCounter {
    private(set) var count = 0
    func record() { count += 1 }
}

/// Collects values in order from concurrent contexts.
actor Collected<Value: Sendable> {
    private(set) var items: [Value] = []
    func record(_ value: Value) { items.append(value) }
}

/// A reporter that keeps everything it is told, so a test can assert on what
/// reached the UI and in which order.
struct RecordingReporter {
    let logs = Collected<String>()
    let steps = Collected<String>()
    let progress = Collected<DownloadProgress?>()

    var reporter: Reporter {
        Reporter(
            log: { [logs] line in await logs.record(line) },
            step: { [steps] step in await steps.record(step) },
            progress: { [progress] value in
                Task { await progress.record(value) }
            })
    }
}
