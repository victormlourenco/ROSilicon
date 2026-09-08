import Foundation
@testable import ROSilicon

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
