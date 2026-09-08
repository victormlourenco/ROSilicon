import Foundation
import Testing
@testable import ROSilicon

struct DownloaderDownloadTests {

    /// 200 KB of nothing in particular, but not all the same byte: a resume
    /// that stitched the halves together in the wrong order would still look
    /// right if every byte matched.
    static let file: Data = {
        var data = Data(count: 200_000)
        for index in 0..<data.count { data[index] = UInt8((index * 7 + index / 251) % 256) }
        return data
    }()

    private func downloaded(_ url: URL, to destination: URL, expectedSize: Int64?) async throws {
        try await Downloader.download(
            url, to: destination, expectedSize: expectedSize, attempts: 3,
            onProgress: { _ in })
    }

    @Test func fetchesAWholeFileFromScratch() async throws {
        let temp = try TemporaryDirectory()
        let server = try LocalHTTPServer(replies: [.whole(Self.file)])
        defer { server.stop() }
        let destination = temp.url.appending(path: "downloads/client.tar")

        try await downloaded(server.url, to: destination, expectedSize: Int64(Self.file.count))

        #expect(try Data(contentsOf: destination) == Self.file)
        #expect(server.received.count == 1)
        #expect(server.received.first?.range == nil,
                "nothing on disk yet, so nothing to resume from")
    }

    @Test func makesTheFolderItDownloadsInto() async throws {
        let temp = try TemporaryDirectory()
        let server = try LocalHTTPServer(replies: [.whole(Self.file)])
        defer { server.stop() }
        let destination = temp.url.appending(path: "a/b/c/client.tar")

        try await downloaded(server.url, to: destination, expectedSize: Int64(Self.file.count))
        #expect(FileManager.default.fileExists(atPath: destination.path))
    }

    /// What makes a 4.8 GB download survive a connection that dropped: the
    /// bytes already on disk are kept and the rest is asked for.
    @Test func resumesFromWhatIsAlreadyOnDisk() async throws {
        let temp = try TemporaryDirectory()
        let alreadyHave = 120_000
        let destination = try temp.write(
            Self.file.prefix(alreadyHave), to: "downloads/client.tar")
        let server = try LocalHTTPServer(replies: [
            .partial(of: Self.file, from: alreadyHave)
        ])
        defer { server.stop() }

        try await downloaded(server.url, to: destination, expectedSize: Int64(Self.file.count))

        #expect(try Data(contentsOf: destination) == Self.file)
        #expect(server.received.first?.range == "bytes=\(alreadyHave)-")
    }

    /// Some servers ignore `Range` and send the lot. Appending that to what was
    /// already there would double the file, so it starts over instead.
    @Test func startsOverWhenTheServerIgnoresTheRangeRequest() async throws {
        let temp = try TemporaryDirectory()
        let destination = try temp.write(Self.file.prefix(90_000), to: "downloads/client.tar")
        let server = try LocalHTTPServer(replies: [.whole(Self.file)])
        defer { server.stop() }

        try await downloaded(server.url, to: destination, expectedSize: Int64(Self.file.count))

        #expect(try Data(contentsOf: destination) == Self.file)
        #expect(Downloader.fileSize(destination) == Int64(Self.file.count))
    }

    /// 416 means there was nothing left to ask for: the file is already whole.
    @Test func treatsRangeNotSatisfiableAsAFinishedFile() async throws {
        let temp = try TemporaryDirectory()
        // One byte short, so it asks — and is told there is nothing to send.
        let destination = try temp.write(Self.file.dropLast(), to: "downloads/client.tar")
        let server = try LocalHTTPServer(replies: [
            .init(status: 416),
            .partial(of: Self.file, from: Self.file.count - 1),
        ])
        defer { server.stop() }

        try await downloaded(server.url, to: destination, expectedSize: nil)
        #expect(server.received.count == 1)
    }

    @Test func doesNotAskForAFileItAlreadyHasWhole() async throws {
        let temp = try TemporaryDirectory()
        let destination = try temp.write(Self.file, to: "downloads/client.tar")
        let server = try LocalHTTPServer(replies: [.whole(Self.file)])
        defer { server.stop() }

        try await downloaded(server.url, to: destination, expectedSize: Int64(Self.file.count))

        #expect(server.received.count == 0, "a complete file needs no network at all")
        #expect(try Data(contentsOf: destination) == Self.file)
    }

    /// More on disk than the server says exists means the leftovers are from
    /// something else; they go, rather than being resumed from.
    @Test func throwsAwayAPartialFileBiggerThanTheOneBeingFetched() async throws {
        let temp = try TemporaryDirectory()
        let destination = try temp.write(
            Data(repeating: 0xFF, count: Self.file.count + 5_000), to: "downloads/client.tar")
        let server = try LocalHTTPServer(replies: [.whole(Self.file)])
        defer { server.stop() }

        try await downloaded(server.url, to: destination, expectedSize: Int64(Self.file.count))

        #expect(try Data(contentsOf: destination) == Self.file)
        #expect(server.received.first?.range == nil)
    }

    // MARK: - When it goes wrong

    @Test func retriesADroppedConnectionAndSaysSo() async throws {
        let temp = try TemporaryDirectory()
        let destination = temp.url.appending(path: "downloads/client.tar")
        let server = try LocalHTTPServer(replies: [
            .init(status: 503), .whole(Self.file),
        ])
        defer { server.stop() }

        let retries = Collected<Int>()
        try await Downloader.download(
            server.url, to: destination, expectedSize: Int64(Self.file.count), attempts: 3,
            onProgress: { _ in },
            onRetry: { attempt, _ in Task { await retries.record(attempt) } })

        #expect(try Data(contentsOf: destination) == Self.file)
        #expect(server.received.count == 2)
    }

    @Test func reportsARefusalThatRetryingWillNotFix() async throws {
        let temp = try TemporaryDirectory()
        let destination = temp.url.appending(path: "downloads/client.tar")
        let server = try LocalHTTPServer(replies: [
            .init(status: 404), .whole(Self.file),
        ])
        defer { server.stop() }

        await #expect(throws: DownloadError.self) {
            try await Downloader.download(
                server.url, to: destination, expectedSize: Int64(Self.file.count), attempts: 3,
                onProgress: { _ in })
        }
        #expect(server.received.count == 1, "a 404 is not worth asking twice")
    }

    // MARK: - Progress

    @Test func reportsProgressThatOnlyEverMovesForward() async throws {
        let temp = try TemporaryDirectory()
        let destination = temp.url.appending(path: "downloads/client.tar")
        let server = try LocalHTTPServer(replies: [.whole(Self.file)])
        defer { server.stop() }

        let reports = Reported()
        try await Downloader.download(
            server.url, to: destination, expectedSize: Int64(Self.file.count), attempts: 1,
            onProgress: { reports.append($0) })

        let seen = reports.values
        #expect(!seen.isEmpty)
        #expect(seen.map(\.completed) == seen.map(\.completed).sorted())
        #expect(seen.last?.completed == Int64(Self.file.count))
        #expect(seen.last?.total == Int64(Self.file.count))
        #expect(seen.last?.fraction == 1)
    }
}

/// Progress arrives on URLSession's queue; this keeps it without tripping the
/// concurrency checker.
private final class Reported: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [DownloadProgress] = []

    func append(_ value: DownloadProgress) {
        lock.lock(); defer { lock.unlock() }
        storage.append(value)
    }

    var values: [DownloadProgress] {
        lock.lock(); defer { lock.unlock() }
        return storage
    }
}
