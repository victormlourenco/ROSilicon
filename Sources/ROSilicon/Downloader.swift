import CryptoKit
import Foundation

struct DownloadProgress: Sendable, Equatable {
    var completed: Int64
    var total: Int64?
    var bytesPerSecond: Double

    var fraction: Double? {
        guard let total, total > 0 else { return nil }
        return min(1, Double(completed) / Double(total))
    }
}

/// Size and, when the server offers one, MD5 of a remote file.
struct RemoteInfo: Sendable {
    var size: Int64?
    /// An ETag that is a plain 32-hex-digit MD5; nil for anything else, since
    /// S3-style multipart ETags ("<md5>-<parts>") are not file checksums.
    var md5: String?
}

enum DownloadError: LocalizedError {
    case unreachable(URL)
    case httpStatus(Int)
    case incomplete(expected: Int64, got: Int64)
    case checksumMismatch(expected: String, got: String)

    var errorDescription: String? {
        switch self {
        case .unreachable(let url):
            Strings.errorUnreachable(url.host() ?? url.absoluteString)
        case .httpStatus(let code): Strings.errorHTTPStatus(code)
        case .incomplete(let expected, let got):
            Strings.errorIncomplete(
                ByteCountFormatter.string(fromByteCount: got, countStyle: .file),
                ByteCountFormatter.string(fromByteCount: expected, countStyle: .file))
        case .checksumMismatch(let expected, let got):
            Strings.errorChecksum(expected, got)
        }
    }
}

enum Downloader {
    /// Asks the server how big a file is, so a complete one is not re-fetched
    /// and a truncated one still resumes. Retried a couple of times: a CDN
    /// answering 429 to the very first request should not sink an install.
    static func probe(_ url: URL, attempts: Int = 3) async throws -> RemoteInfo {
        for attempt in 1...max(1, attempts) {
            do {
                return try await probeOnce(url)
            } catch let error as DownloadError {
                let retryable: Bool
                switch error {
                case .httpStatus(let code): retryable = code == 429 || code >= 500
                case .unreachable: retryable = true
                default: retryable = false
                }
                guard retryable, attempt < attempts else { throw error }
                try await Task.sleep(for: .seconds(2 * attempt))
            }
        }
        throw DownloadError.unreachable(url)
    }

    private static func probeOnce(_ url: URL) async throws -> RemoteInfo {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (_, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse
        else { throw DownloadError.unreachable(url) }
        guard (200..<300).contains(http.statusCode) else {
            throw DownloadError.httpStatus(http.statusCode)
        }

        var info = RemoteInfo()
        if let length = http.value(forHTTPHeaderField: "Content-Length"), let size = Int64(length) {
            info.size = size
        } else if http.expectedContentLength > 0 {
            info.size = http.expectedContentLength
        }
        if let etag = http.value(forHTTPHeaderField: "ETag")?
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"")),
           etag.count == 32,
           etag.allSatisfy({ $0.isHexDigit && !$0.isUppercase }) {
            info.md5 = etag
        }
        return info
    }

    /// Downloads `url` to `destination`, resuming a partial file left by an
    /// earlier run or by a connection that dropped. Returns without touching
    /// the network when the file is already the expected size.
    ///
    /// A dropped connection is retried a few times, each attempt picking up
    /// from what is already on disk — the same job `curl --retry -C -` did in
    /// the shell scripts, and what makes a 4.8 GB download survive a flaky
    /// network.
    static func download(
        _ url: URL,
        to destination: URL,
        expectedSize: Int64?,
        attempts: Int = 6,
        onProgress: @escaping @Sendable (DownloadProgress) -> Void,
        onRetry: (@Sendable (Int, Error) -> Void)? = nil
    ) async throws {
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)

        for attempt in 1...max(1, attempts) {
            do {
                if try await attemptDownload(
                    url, to: destination, expectedSize: expectedSize, onProgress: onProgress) {
                    return
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as URLError where error.code == .cancelled {
                throw CancellationError()
            } catch let error as DownloadError {
                // A refusal from the server is worth retrying only when it is
                // the kind that goes away on its own.
                guard case .httpStatus(let code) = error, code == 429 || code >= 500,
                      attempt < attempts else { throw error }
                onRetry?(attempt, error)
            } catch {
                guard attempt < attempts else { throw error }
                onRetry?(attempt, error)
            }
            if attempt < attempts {
                try await Task.sleep(for: .seconds(min(30, 2 << min(attempt, 4))))
            }
        }
        throw DownloadError.incomplete(
            expected: expectedSize ?? 0, got: fileSize(destination))
    }

    /// One pass over the wire. Returns true when the file is complete.
    private static func attemptDownload(
        _ url: URL,
        to destination: URL,
        expectedSize: Int64?,
        onProgress: @escaping @Sendable (DownloadProgress) -> Void
    ) async throws -> Bool {
        let fm = FileManager.default
        var existing = fileSize(destination)
        if let expectedSize {
            if existing == expectedSize { return true }
            if existing > expectedSize {
                try? fm.removeItem(at: destination)
                existing = 0
            }
        }
        if !fm.fileExists(atPath: destination.path) {
            fm.createFile(atPath: destination.path, contents: nil)
            existing = 0
        }

        let sink = try DownloadSink(
            destination: destination, alreadyHave: existing,
            expectedTotal: expectedSize, onProgress: onProgress)

        var request = URLRequest(url: url)
        request.timeoutInterval = 60
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if existing > 0 { request.setValue("bytes=\(existing)-", forHTTPHeaderField: "Range") }

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForResource = 24 * 60 * 60
        configuration.waitsForConnectivity = true
        let session = URLSession(configuration: configuration, delegate: sink, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        let task = session.dataTask(with: request)
        do {
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    sink.resume(continuation)
                    task.resume()
                }
            } onCancel: {
                task.cancel()
            }
        } catch {
            try? sink.close()
            throw error
        }
        try sink.close()

        guard let expectedSize else { return true }
        return fileSize(destination) == expectedSize
    }

    /// Streams the file through MD5 without loading it into memory.
    static func md5(of url: URL, onProgress: (@Sendable (Int64) -> Void)? = nil) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = Insecure.MD5()
        var read: Int64 = 0
        while let chunk = try handle.read(upToCount: 4 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
            read += Int64(chunk.count)
            onProgress?(read)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Size of a file on disk, or 0 when it is not there.
    ///
    /// Deliberately not `URL.resourceValues`: the bridged NSURL caches what it
    /// reads, so a file being appended to would keep reporting its old size and
    /// a resumed download would never look finished.
    static func fileSize(_ url: URL) -> Int64 {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.size] as? NSNumber)?.int64Value ?? 0
    }
}

/// Appends a response body to a file on disk and reports progress.
///
/// URLSession's own resume data only survives inside one session, so the
/// launcher does its own ranged request and appends to the partial file — that
/// way a 4.8 GB download picks up where it left off even after a restart.
private final class DownloadSink: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private let handle: FileHandle
    private let onProgress: @Sendable (DownloadProgress) -> Void
    private let expectedTotal: Int64?

    private var completed: Int64
    private var continuation: CheckedContinuation<Void, Error>?
    private var finished = false

    private var lastReport = ContinuousClock.now
    private var lastReportedBytes: Int64
    private var speed: Double = 0

    init(
        destination: URL, alreadyHave: Int64, expectedTotal: Int64?,
        onProgress: @escaping @Sendable (DownloadProgress) -> Void
    ) throws {
        handle = try FileHandle(forWritingTo: destination)
        try handle.seekToEnd()
        self.completed = alreadyHave
        self.lastReportedBytes = alreadyHave
        self.expectedTotal = expectedTotal
        self.onProgress = onProgress
    }

    func resume(_ continuation: CheckedContinuation<Void, Error>) {
        lock.lock(); defer { lock.unlock() }
        self.continuation = continuation
    }

    func close() throws {
        try handle.close()
    }

    private func finish(_ result: Result<Void, Error>) {
        lock.lock()
        guard !finished, let continuation else { lock.unlock(); return }
        finished = true
        self.continuation = nil
        lock.unlock()
        continuation.resume(with: result)
    }

    func urlSession(
        _ session: URLSession, dataTask: URLSessionDataTask,
        didReceive response: URLResponse
    ) async -> URLSession.ResponseDisposition {
        guard let http = response as? HTTPURLResponse else { return .allow }
        switch http.statusCode {
        case 206:
            return .allow
        case 200:
            // The server ignored our Range header: start the file over.
            restartFile()
            return .allow
        case 416:
            // Range not satisfiable — we already have the whole file.
            finish(.success(()))
            return .cancel
        default:
            finish(.failure(DownloadError.httpStatus(http.statusCode)))
            return .cancel
        }
    }

    /// Rewinds to zero when the server answers a ranged request with the whole
    /// file. Kept separate because NSLock may not be taken in an async context.
    private func restartFile() {
        lock.lock(); defer { lock.unlock() }
        try? handle.truncate(atOffset: 0)
        completed = 0
        lastReportedBytes = 0
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        do {
            try handle.write(contentsOf: data)
        } catch {
            lock.unlock()
            finish(.failure(error))
            dataTask.cancel()
            return
        }
        completed += Int64(data.count)

        // Throttle to a few updates a second; SwiftUI does not need more.
        let now = ContinuousClock.now
        let elapsed = Double((now - lastReport).components.seconds)
            + Double((now - lastReport).components.attoseconds) / 1e18
        var report: DownloadProgress?
        if elapsed >= 0.25 {
            speed = Double(completed - lastReportedBytes) / elapsed
            lastReport = now
            lastReportedBytes = completed
            report = DownloadProgress(
                completed: completed, total: expectedTotal, bytesPerSecond: speed)
        }
        lock.unlock()
        if let report { onProgress(report) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled {
                finish(.failure(CancellationError()))
            } else {
                finish(.failure(error))
            }
        } else {
            lock.lock()
            let final = DownloadProgress(
                completed: completed, total: expectedTotal, bytesPerSecond: speed)
            lock.unlock()
            onProgress(final)
            finish(.success(()))
        }
    }
}
