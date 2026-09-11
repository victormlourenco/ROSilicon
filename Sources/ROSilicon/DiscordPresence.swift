import Foundation

/// Tells the Discord app the game is being played, so it shows as "Playing
/// Ragnarok Online" with the time since the first client started.
///
/// Discord cannot see it for itself: it recognizes games by their executable,
/// and to macOS the client is a process called wine. So the launcher says so,
/// over the socket the Discord app listens on for programs on the same Mac —
/// the one every game with Rich Presence talks to. Nothing goes over the
/// network from here, and with Discord not open there is nobody to tell.
@MainActor
final class DiscordPresence {
    /// Discord's own application for the game, the one it detects Ragexe.exe
    /// as on Windows: its name and icon are what Discord shows.
    nonisolated static let applicationID = "498990766643740692"

    private let directories: [URL]
    private let retryInterval: Duration
    /// The connection kept up while the game runs. Still set after Discord
    /// refused the activity, so the same session does not ask again.
    private(set) var session: Task<Void, Never>?

    nonisolated init(
        directories: [URL] = DiscordIPC.socketDirectories(),
        retryInterval: Duration = .seconds(15)
    ) {
        self.directories = directories
        self.retryInterval = retryInterval
    }

    /// Shows the game, played since `start`, and keeps it shown: a Discord
    /// that is not open yet, or is quit and opened again, is looked for again
    /// every little while.
    func show(since start: Date, reporter: Reporter) {
        guard session == nil else { return }
        session = Task.detached { [directories, retryInterval] in
            await Self.run(
                since: start, directories: directories, retryInterval: retryInterval,
                reporter: reporter)
        }
    }

    /// Closing the connection is what takes the activity down: Discord clears
    /// whatever a program set the moment it disconnects.
    func clear() {
        session?.cancel()
        session = nil
    }

    /// Only a refusal is logged. Discord not being open is the ordinary case
    /// for someone who does not use it, and not worth a line every retry.
    private nonisolated static func run(
        since start: Date, directories: [URL], retryInterval: Duration, reporter: Reporter
    ) async {
        while !Task.isCancelled {
            do {
                let connection = try await offThread {
                    try DiscordIPC.connect(in: directories, clientID: applicationID)
                }
                try await withTaskCancellationHandler {
                    try await offThread { try connection.setActivity(since: start) }
                    guard !Task.isCancelled else { return }
                    await reporter.log(Strings.logDiscordPresence)
                    await offThread { connection.waitUntilClosed() }
                } onCancel: {
                    connection.shutdown()
                }
            } catch DiscordIPCError.refused(let message) {
                await reporter.log(Strings.logDiscordPresenceRefused(message))
                return
            } catch {
                // Discord is not open, or has just been quit: look again later.
            }
            try? await Task.sleep(for: retryInterval)
        }
    }
}

enum DiscordIPCError: Error, Equatable {
    /// No Discord app to talk to: no socket, or nobody listening on it.
    case notRunning
    /// The connection went away, or stopped answering.
    case disconnected
    /// Discord answered, and said no.
    case refused(String)
}

/// Discord's local protocol: frames of a little-endian opcode and length,
/// then that many bytes of JSON, over a Unix socket named discord-ipc-N.
enum DiscordIPC {
    enum Opcode: UInt32, Sendable {
        case handshake = 0, frame, close, ping, pong
    }

    struct Frame: Sendable {
        /// Nil for an opcode this does not know, which it skips.
        let opcode: Opcode?
        let payload: Data

        var json: [String: Any] {
            (try? JSONSerialization.jsonObject(with: payload)) as? [String: Any] ?? [:]
        }
    }

    static let version = 1
    /// Discord numbers its sockets from 0, one per Discord app running —
    /// Stable, PTB and Canary side by side — and takes the first free one.
    static let instances = 0..<10
    /// A frame is a handshake reply or an answer to one command: kilobytes.
    /// A length far past that is a stream out of step, not a frame.
    static let maximumPayload: UInt32 = 1 << 20

    static func encode(_ opcode: Opcode, _ payload: Data) -> Data {
        var data = Data(capacity: 8 + payload.count)
        withUnsafeBytes(of: opcode.rawValue.littleEndian) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: UInt32(payload.count).littleEndian) { data.append(contentsOf: $0) }
        data.append(payload)
        return data
    }

    /// Where Discord puts its sockets: the first of these variables it finds
    /// set, else /tmp. On macOS that is TMPDIR, the per-user temporary folder,
    /// which a program started from the Finder may not have in its
    /// environment — so the folder itself is asked for as well.
    static func socketDirectories(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> [URL] {
        let candidates = ["XDG_RUNTIME_DIR", "TMPDIR", "TMP", "TEMP"].compactMap { environment[$0] }
            + [NSTemporaryDirectory(), "/tmp"]
        var seen = Set<String>()
        return candidates
            .filter { !$0.isEmpty }
            .map { URL(filePath: $0, directoryHint: .isDirectory).standardizedFileURL }
            .filter { seen.insert($0.path).inserted }
    }

    static func socketPaths(in directories: [URL]) -> [String] {
        directories.flatMap { directory in
            instances.map { directory.appending(path: "discord-ipc-\($0)").path }
        }
    }

    /// Connects to the first Discord that answers and introduces the
    /// application. A refusal ends the search: another Discord would refuse
    /// the same application too.
    static func connect(in directories: [URL], clientID: String) throws -> DiscordConnection {
        for path in socketPaths(in: directories) where FileManager.default.fileExists(atPath: path) {
            do {
                let connection = try DiscordConnection.open(path)
                try connection.handshake(clientID: clientID)
                return connection
            } catch DiscordIPCError.refused(let message) {
                throw DiscordIPCError.refused(message)
            } catch {
                continue
            }
        }
        throw DiscordIPCError.notRunning
    }

    /// The address of a socket at `path`, or nil when the path is too long
    /// for one — sun_path holds 104 bytes, its terminator included.
    static func address(_ path: String) -> sockaddr_un? {
        var address = sockaddr_un()
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard path.utf8.count < capacity else { return nil }
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: path.utf8) }
        return address
    }

    static func activity(since start: Date, nonce: String) -> [String: Any] {
        [
            "cmd": "SET_ACTIVITY",
            "nonce": nonce,
            "args": [
                "pid": Int(ProcessInfo.processInfo.processIdentifier),
                "activity": ["timestamps": ["start": Int(start.timeIntervalSince1970)]],
            ] as [String: Any],
        ]
    }
}

/// One connection to a Discord app. Every call blocks, so they are made off
/// Swift's cooperative threads; `shutdown` is the one meant for another
/// thread, to wake whichever is waiting on a read.
final class DiscordConnection: @unchecked Sendable {
    private let descriptor: Int32

    /// How long Discord gets to answer the handshake and the activity. Past
    /// that, it is treated as gone.
    private static let answerTimeout = 5

    init(descriptor: Int32) {
        self.descriptor = descriptor
        // A write to a connection Discord has closed must fail, not raise
        // SIGPIPE, which would take the launcher down with it.
        var on: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        setReceiveTimeout(Self.answerTimeout)
    }

    deinit { Darwin.close(descriptor) }

    static func open(_ path: String) throws -> DiscordConnection {
        guard var address = DiscordIPC.address(path) else { throw DiscordIPCError.notRunning }
        let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw DiscordIPCError.notRunning }
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        // A socket file with nobody listening is what a Discord that crashed
        // leaves behind.
        guard result == 0 else {
            Darwin.close(descriptor)
            throw DiscordIPCError.notRunning
        }
        return DiscordConnection(descriptor: descriptor)
    }

    /// Discord answers a handshake with READY, or with a close frame saying
    /// why not — an application ID it does not know, say.
    func handshake(clientID: String) throws {
        try send(.handshake, ["v": DiscordIPC.version, "client_id": clientID])
        let reply = try receive()
        switch reply.opcode {
        case .frame where reply.json["evt"] as? String == "READY": return
        case .close: throw DiscordIPCError.refused(Self.message(in: reply.json))
        default: throw DiscordIPCError.disconnected
        }
    }

    /// Sets the activity and waits for Discord to take it.
    func setActivity(since start: Date) throws {
        let nonce = UUID().uuidString
        try send(.frame, DiscordIPC.activity(since: start, nonce: nonce))
        while true {
            let reply = try receive()
            switch reply.opcode {
            case .ping: try send(.pong, reply.payload)
            case .close: throw DiscordIPCError.refused(Self.message(in: reply.json))
            case .frame:
                let json = reply.json
                guard json["nonce"] as? String == nonce else { continue }
                if json["evt"] as? String == "ERROR" {
                    throw DiscordIPCError.refused(
                        Self.message(in: json["data"] as? [String: Any] ?? [:]))
                }
                return
            default: continue
            }
        }
    }

    /// Returns once Discord closes the connection, or `shutdown` is called.
    /// Pings are answered meanwhile, so Discord does not take the silence for
    /// a program that has hung.
    func waitUntilClosed() {
        setReceiveTimeout(0)
        while let frame = try? receive() {
            switch frame.opcode {
            case .ping: guard (try? send(.pong, frame.payload)) != nil else { return }
            case .close: return
            default: continue
            }
        }
    }

    /// Ends the connection from any thread, and wakes a read waiting on it.
    func shutdown() {
        Darwin.shutdown(descriptor, SHUT_RDWR)
    }

    func send(_ opcode: DiscordIPC.Opcode, _ json: [String: Any]) throws {
        try send(opcode, JSONSerialization.data(withJSONObject: json))
    }

    func send(_ opcode: DiscordIPC.Opcode, _ payload: Data) throws {
        try DiscordIPC.encode(opcode, payload).withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            var sent = 0
            while sent < buffer.count {
                let count = Darwin.send(descriptor, base + sent, buffer.count - sent, 0)
                if count > 0 {
                    sent += count
                } else if count < 0, errno == EINTR {
                    continue
                } else {
                    throw DiscordIPCError.disconnected
                }
            }
        }
    }

    func receive() throws -> DiscordIPC.Frame {
        let header = try read(8)
        let opcode = header.withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(as: UInt32.self)) }
        let length = header.withUnsafeBytes {
            UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: 4, as: UInt32.self))
        }
        guard length <= DiscordIPC.maximumPayload else { throw DiscordIPCError.disconnected }
        return DiscordIPC.Frame(opcode: DiscordIPC.Opcode(rawValue: opcode), payload: try read(Int(length)))
    }

    private func read(_ count: Int) throws -> Data {
        var data = Data(count: count)
        var received = 0
        while received < count {
            let result = data.withUnsafeMutableBytes { buffer in
                Darwin.recv(descriptor, buffer.baseAddress! + received, count - received, 0)
            }
            if result > 0 {
                received += result
            } else if result < 0, errno == EINTR {
                continue
            } else {
                // The end of the stream, a timeout or a shutdown: all the same here.
                throw DiscordIPCError.disconnected
            }
        }
        return data
    }

    /// Zero waits for as long as it takes.
    private func setReceiveTimeout(_ seconds: Int) {
        var timeout = timeval(tv_sec: seconds, tv_usec: 0)
        setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    }

    private static func message(in json: [String: Any]) -> String {
        let message = json["message"] as? String ?? ""
        guard let code = json["code"] as? Int else { return message }
        return message.isEmpty ? "\(code)" : "\(message) (\(code))"
    }
}

/// Runs blocking work on a thread of Dispatch's rather than one of the few
/// Swift's tasks share, which a connection held open for a whole game would
/// otherwise keep to itself.
private func offThread<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
    try await withCheckedThrowingContinuation { continuation in
        DispatchQueue.global(qos: .utility).async {
            continuation.resume(with: Result { try work() })
        }
    }
}

private func offThread(_ work: @escaping @Sendable () -> Void) async {
    await withCheckedContinuation { continuation in
        DispatchQueue.global(qos: .utility).async {
            work()
            continuation.resume()
        }
    }
}
