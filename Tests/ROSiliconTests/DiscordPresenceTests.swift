import Foundation
import Testing
@testable import ROSilicon

struct DiscordIPCTests {
    @Test func aFrameIsOpcodeThenLengthLittleEndianThenPayload() {
        let frame = DiscordIPC.encode(.frame, Data("{}".utf8))
        #expect(Array(frame) == [1, 0, 0, 0, 2, 0, 0, 0, 0x7B, 0x7D])
    }

    /// Discord puts its sockets in TMPDIR; /tmp is where it goes without one,
    /// so it is the last place to look.
    @Test func socketsAreLookedForInTheTemporaryFolderThenTmp() {
        let directories = DiscordIPC.socketDirectories(environment: ["TMPDIR": "/test/T/"])
        #expect(directories.first?.path == "/test/T")
        #expect(directories.last?.path == "/tmp")
        #expect(Set(directories.map(\.path)).count == directories.count)
    }

    @Test func everyDiscordInstanceIsTriedInOrder() {
        let paths = DiscordIPC.socketPaths(in: [URL(filePath: "/a"), URL(filePath: "/b")])
        #expect(paths.count == 20)
        #expect(paths.first == "/a/discord-ipc-0")
        #expect(paths[9] == "/a/discord-ipc-9")
        #expect(paths.last == "/b/discord-ipc-9")
    }

    @Test func aPathTooLongForASocketHasNoAddress() {
        #expect(DiscordIPC.address("/tmp/discord-ipc-0") != nil)
        #expect(DiscordIPC.address("/" + String(repeating: "x", count: 200)) == nil)
    }

    /// The game and the time played, and nothing else: no profile name, which
    /// may well be a character's or an account's.
    @Test func theActivitySaysOnlyWhenPlayStarted() throws {
        let start = Date(timeIntervalSince1970: 1_789_160_557)
        let command = DiscordIPC.activity(since: start, nonce: "n")
        #expect(JSONSerialization.isValidJSONObject(command))
        #expect(command["cmd"] as? String == "SET_ACTIVITY")
        #expect(command["nonce"] as? String == "n")
        let arguments = try #require(command["args"] as? [String: Any])
        #expect(arguments["pid"] as? Int == Int(ProcessInfo.processInfo.processIdentifier))
        let activity = try #require(arguments["activity"] as? [String: Any])
        #expect(activity.keys.sorted() == ["timestamps"])
        #expect((activity["timestamps"] as? [String: Any])?["start"] as? Int == 1_789_160_557)
    }

    @Test(.timeLimit(.minutes(1)))
    func aRefusedHandshakeSaysWhy() async throws {
        let folder = try SocketFolder()
        let discord = try FakeDiscord(in: folder.url)
        let attempt = Task.detached {
            try DiscordIPC.connect(in: [folder.url], clientID: "123")
        }
        let connection = try await discord.accept()
        _ = try await connection.next()
        try connection.send(.close, ["code": 4000, "message": "Invalid Client ID"])
        await #expect(throws: DiscordIPCError.refused("Invalid Client ID (4000)")) {
            try await attempt.value
        }
    }

    @Test func noSocketMeansDiscordIsNotRunning() throws {
        let folder = try SocketFolder()
        #expect(throws: DiscordIPCError.notRunning) {
            try DiscordIPC.connect(in: [folder.url], clientID: DiscordPresence.applicationID)
        }
    }
}

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct DiscordPresenceTests {
    @Test func showsTheGameUntilCleared() async throws {
        let folder = try SocketFolder()
        let discord = try FakeDiscord(in: folder.url)
        let recorder = RecordingReporter()
        let presence = DiscordPresence(directories: [folder.url], retryInterval: .milliseconds(50))
        presence.show(since: Date(timeIntervalSince1970: 1_789_160_557), reporter: recorder.reporter)

        let connection = try await discord.accept()
        let (handshake, command) = try await connection.actAsDiscord()
        #expect(handshake.json["client_id"] as? String == DiscordPresence.applicationID)
        #expect(handshake.json["v"] as? Int == 1)
        #expect(command.json["cmd"] as? String == "SET_ACTIVITY")
        let activity = (command.json["args"] as? [String: Any])?["activity"] as? [String: Any]
        #expect((activity?["timestamps"] as? [String: Any])?["start"] as? Int == 1_789_160_557)
        try await eventually { await recorder.logs.items == [Strings.logDiscordPresence] }

        // Showing it again, as another client starting does, changes nothing.
        let session = try #require(presence.session)
        presence.show(since: .now, reporter: recorder.reporter)
        #expect(presence.session == session)

        // The activity comes down with the connection.
        presence.clear()
        await session.value
        #expect(presence.session == nil)
        await #expect(throws: DiscordIPCError.disconnected) { try await connection.next() }
    }

    /// Asking again would be refused again, and say so in the log every time.
    @Test func aRefusalIsLoggedOnceAndNotAskedAgain() async throws {
        let folder = try SocketFolder()
        let discord = try FakeDiscord(in: folder.url)
        let recorder = RecordingReporter()
        let presence = DiscordPresence(directories: [folder.url], retryInterval: .milliseconds(50))
        presence.show(since: .now, reporter: recorder.reporter)

        let connection = try await discord.accept()
        _ = try await connection.next()
        try connection.send(.close, ["code": 4000, "message": "Invalid Client ID"])

        let session = try #require(presence.session)
        await session.value
        #expect(await recorder.logs.items == [Strings.logDiscordPresenceRefused("Invalid Client ID (4000)")])
    }

    /// Discord opened after the game started, then quit and opened again: the
    /// game shows each time, and nothing is logged while Discord is away.
    @Test func findsDiscordWheneverItIsOpen() async throws {
        let folder = try SocketFolder()
        let recorder = RecordingReporter()
        let presence = DiscordPresence(directories: [folder.url], retryInterval: .milliseconds(50))
        presence.show(since: .now, reporter: recorder.reporter)
        defer { presence.clear() }

        try await Task.sleep(for: .milliseconds(200))
        #expect(await recorder.logs.items.isEmpty)

        var discord: FakeDiscord? = try FakeDiscord(in: folder.url)
        var connection: DiscordConnection? = try await discord?.accept()
        _ = try await connection?.actAsDiscord()
        connection?.shutdown()
        connection = nil
        discord = nil

        let reopened = try FakeDiscord(in: folder.url)
        let again = try await reopened.accept()
        _ = try await again.actAsDiscord()
        try await eventually { await recorder.logs.items.count == 2 }
    }
}

// MARK: - A stand-in for Discord

/// A folder short enough to hold a socket: its path must fit in 104 bytes,
/// and TemporaryDirectory's, with a UUID in it, takes most of that already.
final class SocketFolder: @unchecked Sendable {
    let url: URL

    init() throws {
        var template = Array((NSTemporaryDirectory() + "rp.XXXXXX").utf8CString)
        guard let made = mkdtemp(&template) else { throw POSIXError(.EIO) }
        url = URL(filePath: String(cString: made))
    }

    deinit { try? FileManager.default.removeItem(at: url) }
}

/// Listens where the Discord app would, and hands each connection over to be
/// answered. Quits, taking its socket with it, when released.
final class FakeDiscord: @unchecked Sendable {
    private let listener: Int32
    private let path: String

    init(in folder: URL) throws {
        path = folder.appending(path: "discord-ipc-0").path
        guard var address = DiscordIPC.address(path) else { throw POSIXError(.ENAMETOOLONG) }
        listener = socket(AF_UNIX, SOCK_STREAM, 0)
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(listener, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard listener >= 0, bound == 0, listen(listener, 4) == 0 else {
            close(listener)
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        // A launcher that never connects fails the test rather than hanging it.
        var timeout = timeval(tv_sec: 10, tv_usec: 0)
        setsockopt(listener, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    }

    deinit {
        close(listener)
        unlink(path)
    }

    func accept() async throws -> DiscordConnection {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async { [listener] in
                let descriptor = Darwin.accept(listener, nil, nil)
                if descriptor >= 0 {
                    continuation.resume(returning: DiscordConnection(descriptor: descriptor))
                } else {
                    continuation.resume(throwing: POSIXError(.ETIMEDOUT))
                }
            }
        }
    }
}

extension DiscordConnection {
    /// The next frame, read off the test's thread.
    func next() async throws -> DiscordIPC.Frame {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async {
                continuation.resume(with: Result { try self.receive() })
            }
        }
    }

    /// Answers the way Discord does when all is well: READY to the handshake,
    /// then the activity taken. Returns what was asked of it.
    @discardableResult
    func actAsDiscord() async throws -> (handshake: DiscordIPC.Frame, command: DiscordIPC.Frame) {
        let handshake = try await next()
        #expect(handshake.opcode == .handshake)
        try send(.frame, ["cmd": "DISPATCH", "evt": "READY", "data": ["v": 1]])
        let command = try await next()
        #expect(command.opcode == .frame)
        try send(.frame, [
            "cmd": "SET_ACTIVITY", "evt": NSNull(), "data": [String: Any](),
            "nonce": command.json["nonce"] ?? NSNull(),
        ])
        return (handshake, command)
    }
}

/// Waits for something another thread is doing. The suite's time limit is
/// what fails a test whose condition never comes true.
private func eventually(_ condition: @Sendable () async -> Bool) async throws {
    while !(await condition()) {
        try await Task.sleep(for: .milliseconds(10))
    }
}
