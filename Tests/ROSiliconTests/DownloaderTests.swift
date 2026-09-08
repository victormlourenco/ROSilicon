import Foundation
import Testing
@testable import ROSilicon

struct DownloadProgressTests {

    @Test func fractionIsUnknownWithoutAUsableTotal() {
        #expect(DownloadProgress(completed: 100, total: nil, bytesPerSecond: 0).fraction == nil)
        #expect(DownloadProgress(completed: 100, total: 0, bytesPerSecond: 0).fraction == nil)
        #expect(DownloadProgress(completed: 100, total: -1, bytesPerSecond: 0).fraction == nil)
    }

    @Test func fractionIsTheShareDone() throws {
        let progress = DownloadProgress(completed: 250, total: 1000, bytesPerSecond: 0)
        #expect(try #require(progress.fraction) == 0.25)
        #expect(DownloadProgress(completed: 0, total: 1000, bytesPerSecond: 0).fraction == 0)
    }

    /// A server that sends more than it advertised must not push the bar past
    /// the end of its track.
    @Test func fractionIsClampedToOne() {
        let progress = DownloadProgress(completed: 2000, total: 1000, bytesPerSecond: 0)
        #expect(progress.fraction == 1)
    }

    @Test func fractionSurvivesSizesTooBigForDouble() throws {
        let big = Int64(1) << 42
        let progress = DownloadProgress(completed: big / 2, total: big, bytesPerSecond: 0)
        #expect(try #require(progress.fraction) == 0.5)
    }
}

struct DownloaderFileTests {

    // MARK: - Size on disk

    @Test func missingFileHasNoSize() throws {
        let temp = try TemporaryDirectory()
        #expect(Downloader.fileSize(temp.url.appending(path: "absent.tar")) == 0)
    }

    @Test func sizeIsTheBytesOnDisk() throws {
        let temp = try TemporaryDirectory()
        let file = try temp.write(Data(repeating: 0x41, count: 4096), to: "client.tar")
        #expect(Downloader.fileSize(file) == 4096)
    }

    @Test func emptyFileHasSizeZero() throws {
        let temp = try TemporaryDirectory()
        #expect(Downloader.fileSize(try temp.write(to: "empty.tar")) == 0)
    }

    /// The reason `fileSize` avoids `URL.resourceValues`: the bridged NSURL
    /// caches what it read, so a resumed download would keep seeing the size
    /// the file had when it started and would never look finished.
    @Test func sizeFollowsAFileThatIsStillBeingAppendedTo() throws {
        let temp = try TemporaryDirectory()
        let file = try temp.write(Data(repeating: 0, count: 10), to: "partial.tar")
        #expect(Downloader.fileSize(file) == 10)

        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(repeating: 1, count: 90))
        try handle.synchronize()

        #expect(Downloader.fileSize(file) == 100)
    }

    // MARK: - MD5

    @Test(arguments: [
        ("", "d41d8cd98f00b204e9800998ecf8427e"),
        ("abc", "900150983cd24fb0d6963f7d28e17f72"),
        ("The quick brown fox jumps over the lazy dog", "9e107d9d372bb6826bd81d3542a419d6"),
    ])
    func md5MatchesTheKnownVectors(contents: String, digest: String) throws {
        let temp = try TemporaryDirectory()
        let file = try temp.write(Data(contents.utf8), to: "vector")
        #expect(try Downloader.md5(of: file) == digest)
    }

    /// Lowercase, 32 digits — the same shape as the ETag `probe` accepts, so
    /// the two can be compared directly.
    @Test func md5IsThirtyTwoLowercaseHexDigits() throws {
        let temp = try TemporaryDirectory()
        let file = try temp.write(Data([0x00, 0x0f, 0xff]), to: "shape")
        let digest = try Downloader.md5(of: file)
        #expect(digest.count == 32)
        #expect(digest.allSatisfy { $0.isHexDigit && !$0.isUppercase })
    }

    /// The client is gigabytes: the hash is streamed in 4 MB chunks rather
    /// than read into memory, so it has to survive crossing a chunk boundary.
    @Test func md5StreamsAcrossChunkBoundaries() async throws {
        let temp = try TemporaryDirectory()
        var contents = Data(count: 9 << 20)
        for index in stride(from: 0, to: contents.count, by: 977) {
            contents[index] = UInt8(index % 251)
        }
        let file = try temp.write(contents, to: "large.tar")

        let reference = try await Shell.check(URL(filePath: "/sbin/md5"), ["-q", file.path])
        #expect(try Downloader.md5(of: file) == reference)
    }

    @Test func md5ReportsProgressUpToTheFileSize() throws {
        let temp = try TemporaryDirectory()
        let size = 9 << 20
        let file = try temp.write(Data(repeating: 0x7A, count: size), to: "large.tar")

        let reports = Reports()
        _ = try Downloader.md5(of: file) { reports.append($0) }
        let read = reports.values
        #expect(read.count > 1, "a 9 MB file should take more than one 4 MB chunk")
        #expect(read.last == Int64(size))
        #expect(read == read.sorted())
    }

    @Test func md5OfAMissingFileThrows() throws {
        let temp = try TemporaryDirectory()
        #expect(throws: (any Error).self) {
            try Downloader.md5(of: temp.url.appending(path: "absent.tar"))
        }
    }
}

/// `md5`'s progress callback is `@Sendable` and called from the calling
/// thread; this keeps the values without tripping the concurrency checker.
private final class Reports: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Int64] = []

    func append(_ value: Int64) {
        lock.lock(); defer { lock.unlock() }
        storage.append(value)
    }

    var values: [Int64] {
        lock.lock(); defer { lock.unlock() }
        return storage
    }
}
