import Foundation
import Testing
@testable import ROSilicon

struct DownloaderProbeTests {

    private func httpStatus(of error: any Error) -> Int? {
        guard case .httpStatus(let code)? = error as? DownloadError else { return nil }
        return code
    }

    private func isUnreachable(_ error: any Error) -> Bool {
        guard case .unreachable? = error as? DownloadError else { return false }
        return true
    }

    // MARK: - Reading the answer

    @Test func readsTheSizeFromContentLength() async throws {
        let server = try LocalHTTPServer(replies: [
            .init(headers: ["Content-Length": "5000000000"])
        ])
        defer { server.stop() }

        let info = try await Downloader.probe(server.url)
        #expect(info.size == 5_000_000_000)
        #expect(server.received.count == 1)
        #expect(server.received.first?.method == "HEAD", "a probe must not fetch the body")
    }

    @Test func anEmptyFileProbesAsZeroBytes() async throws {
        let server = try LocalHTTPServer(replies: [.init(headers: ["Content-Length": "0"])])
        defer { server.stop() }

        let info = try await Downloader.probe(server.url)
        #expect(info.size == 0)
        #expect(info.md5 == nil)
    }

    // MARK: - ETags

    @Test func takesAPlainMD5ETagAsTheChecksum() async throws {
        let digest = "d41d8cd98f00b204e9800998ecf8427e"
        let server = try LocalHTTPServer(replies: [
            .init(headers: ["ETag": "\"\(digest)\""])
        ])
        defer { server.stop() }

        #expect(try await Downloader.probe(server.url).md5 == digest)
    }

    @Test func acceptsAnUnquotedETag() async throws {
        let digest = "900150983cd24fb0d6963f7d28e17f72"
        let server = try LocalHTTPServer(replies: [.init(headers: ["ETag": digest])])
        defer { server.stop() }

        #expect(try await Downloader.probe(server.url).md5 == digest)
    }

    /// An S3-style multipart ETag is a hash of hashes, not of the file. Taking
    /// it for a checksum would fail every verification and delete a download
    /// that was perfectly good.
    @Test(arguments: [
        "\"d41d8cd98f00b204e9800998ecf8427e-3\"",        // multipart
        "\"D41D8CD98F00B204E9800998ECF8427E\"",          // uppercase
        "\"d41d8cd98f00b204e9800998ecf842\"",            // too short
        "\"d41d8cd98f00b204e9800998ecf8427e00\"",        // too long
        "\"zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz\"",          // not hex
        "W/\"d41d8cd98f00b204e9800998ecf8427e\"",        // weak validator
    ])
    func ignoresAnETagThatIsNotAFileChecksum(etag: String) async throws {
        let server = try LocalHTTPServer(replies: [.init(headers: ["ETag": etag])])
        defer { server.stop() }

        #expect(try await Downloader.probe(server.url).md5 == nil)
    }

    // MARK: - When the server says no

    /// A CDN answering 429 to the very first request should not sink an
    /// install that would work a moment later.
    @Test func retriesAServerAskingUsToSlowDown() async throws {
        let server = try LocalHTTPServer(replies: [
            .init(status: 429),
            .init(status: 200, headers: ["Content-Length": "1024"]),
        ])
        defer { server.stop() }

        let info = try await Downloader.probe(server.url)
        #expect(info.size == 1024)
        #expect(server.received.count == 2)
    }

    @Test func retriesAServerThatIsHavingAMoment() async throws {
        let server = try LocalHTTPServer(replies: [
            .init(status: 503),
            .init(status: 200, headers: ["Content-Length": "7"]),
        ])
        defer { server.stop() }

        #expect(try await Downloader.probe(server.url).size == 7)
        #expect(server.received.count == 2)
    }

    /// A refusal that will not go away on its own is not worth asking twice.
    @Test(arguments: [404, 403, 410])
    func doesNotRetryARefusalThatWillNotChange(status: Int) async throws {
        let server = try LocalHTTPServer(replies: [
            .init(status: status), .init(status: 200),
        ])
        defer { server.stop() }

        do {
            _ = try await Downloader.probe(server.url)
            Issue.record("A \(status) should be reported, not retried into a success")
        } catch {
            #expect(httpStatus(of: error) == status)
        }
        #expect(server.received.count == 1)
    }

    @Test func givesUpAfterTheLastAttempt() async throws {
        let server = try LocalHTTPServer(replies: [
            .init(status: 500), .init(status: 500), .init(status: 500),
        ])
        defer { server.stop() }

        do {
            _ = try await Downloader.probe(server.url, attempts: 2)
            Issue.record("Two failed attempts should be reported as a failure")
        } catch {
            #expect(httpStatus(of: error) == 500)
        }
        #expect(server.received.count == 2, "it should stop at the number of attempts asked for")
    }

    @Test func aHostThatCannotBeReachedIsReportedAsSuch() async throws {
        let server = try LocalHTTPServer(replies: [.init(dropsConnection: true)])
        defer { server.stop() }

        do {
            _ = try await Downloader.probe(server.url, attempts: 1)
            Issue.record("An unreachable host should throw")
        } catch {
            #expect(isUnreachable(error))
        }
        // How many times URLSession itself tried before giving up is its
        // business; what matters is that the failure came back as unreachable.
    }
}
