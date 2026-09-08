import Foundation
@testable import ROSilicon

/// A one-connection-at-a-time HTTP server on the loopback interface, primed
/// with the replies a test wants and remembering what was asked for.
///
/// The downloader builds its own `URLSession` with its own configuration, so a
/// `URLProtocol` stub registered with the loading system never sees its
/// requests. A real socket does, and it exercises the same path the client
/// download takes — `Range` headers, resumes and all.
final class LocalHTTPServer: @unchecked Sendable {

    struct Reply: Sendable {
        var status = 200
        var headers: [String: String] = [:]
        var body = Data()
        /// Hangs up without answering, the way an unreachable host does.
        var dropsConnection = false

        /// A 206 handing back `file` from the offset that was asked for.
        static func partial(of file: Data, from offset: Int) -> Reply {
            let tail = Data(file[offset...])
            return Reply(
                status: 206,
                headers: [
                    "Content-Range": "bytes \(offset)-\(file.count - 1)/\(file.count)",
                ],
                body: tail)
        }

        /// A 200 handing back the whole file, which is what a server that
        /// ignores `Range` does.
        static func whole(_ file: Data) -> Reply {
            Reply(status: 200, body: file)
        }
    }

    /// One request, as far as these tests care about it.
    struct Request: Sendable {
        var method = ""
        var path = ""
        var range: String?
    }

    let url: URL

    private let listener: Int32
    private let lock = NSLock()
    private var pending: [Reply]
    private var log: [Request] = []
    private var stopped = false

    init(replies: [Reply], path: String = "/LATAM_RO1_Live.tar") throws {
        pending = replies

        // A local binding throughout: the closures below may not touch `self`
        // until every stored property has a value.
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw ServerError.cannotListen }
        listener = descriptor

        var reuse: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_REUSEADDR, &reuse,
                   socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0                                      // any free port
        address.sin_addr.s_addr = UInt32(0x7F00_0001).bigEndian   // 127.0.0.1

        let size = socklen_t(MemoryLayout<sockaddr_in>.size)
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(descriptor, $0, size) }
        }
        guard bound == 0, listen(descriptor, 16) == 0 else {
            close(descriptor)
            throw ServerError.cannotListen
        }

        var actual = sockaddr_in()
        var length = size
        _ = withUnsafeMutablePointer(to: &actual) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(descriptor, $0, &length)
            }
        }
        url = URL(string: "http://127.0.0.1:\(UInt16(bigEndian: actual.sin_port))\(path)")!

        let thread = Thread { [weak self] in self?.serve() }
        thread.name = "LocalHTTPServer"
        thread.start()
    }

    deinit { stop() }

    func stop() {
        lock.lock()
        let alreadyStopped = stopped
        stopped = true
        lock.unlock()
        if !alreadyStopped { close(listener) }   // makes the accept loop return
    }

    /// Every request that arrived, in order.
    var received: [Request] {
        lock.lock(); defer { lock.unlock() }
        return log
    }

    enum ServerError: Error { case cannotListen }

    // MARK: - Serving

    private func serve() {
        while true {
            let connection = accept(listener, nil, nil)
            guard connection >= 0 else { return }             // the socket closed
            handle(connection)
            close(connection)
        }
    }

    private func handle(_ connection: Int32) {
        guard let head = readRequestHead(connection) else { return }
        let request = parse(head)

        lock.lock()
        log.append(request)
        let reply = pending.isEmpty ? nil : pending.removeFirst()
        lock.unlock()

        guard let reply, !reply.dropsConnection else { return }

        // A HEAD carries the headers of the response it describes, but never
        // the body itself.
        let body = request.method == "HEAD" ? Data() : reply.body
        let declared = reply.headers["Content-Length"]
            ?? "\(request.method == "HEAD" ? reply.body.count : body.count)"

        var response = "HTTP/1.1 \(reply.status) \(Self.reason(reply.status))\r\n"
        response += "Content-Length: \(declared)\r\n"
        response += "Connection: close\r\n"
        for (name, value) in reply.headers where name.lowercased() != "content-length" {
            response += "\(name): \(value)\r\n"
        }
        response += "\r\n"

        send(connection, Data(response.utf8))
        if !body.isEmpty { send(connection, body) }
    }

    private func readRequestHead(_ connection: Int32) -> String? {
        var received = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while received.range(of: Data("\r\n\r\n".utf8)) == nil {
            let count = recv(connection, &buffer, buffer.count, 0)
            guard count > 0 else { return nil }
            received.append(contentsOf: buffer[0..<count])
        }
        return String(decoding: received, as: UTF8.self)
    }

    private func parse(_ head: String) -> Request {
        var request = Request()
        for (index, line) in head.components(separatedBy: "\r\n").enumerated() {
            if index == 0 {
                let parts = line.split(separator: " ")
                request.method = parts.first.map(String.init) ?? ""
                request.path = parts.count > 1 ? String(parts[1]) : ""
            } else if line.lowercased().hasPrefix("range:") {
                request.range = String(line.dropFirst("range:".count))
                    .trimmingCharacters(in: .whitespaces)
            }
        }
        return request
    }

    private func send(_ connection: Int32, _ data: Data) {
        data.withUnsafeBytes { raw in
            guard var pointer = raw.baseAddress else { return }
            var left = raw.count
            while left > 0 {
                let written = Foundation.send(connection, pointer, left, 0)
                guard written > 0 else { return }
                pointer += written
                left -= written
            }
        }
    }

    private static func reason(_ status: Int) -> String {
        switch status {
        case 200: "OK"
        case 206: "Partial Content"
        case 404: "Not Found"
        case 416: "Requested Range Not Satisfiable"
        case 429: "Too Many Requests"
        case 500: "Internal Server Error"
        case 503: "Service Unavailable"
        default: "Status"
        }
    }
}
