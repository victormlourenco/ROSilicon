import Foundation

/// Thrown when a helper process exits non-zero.
struct ProcessFailure: LocalizedError {
    let command: String
    let status: Int32
    let output: String

    var errorDescription: String? {
        let tail = output.split(separator: "\n").suffix(3).joined(separator: "\n")
        return tail.isEmpty
            ? "\(command) failed (exit \(status))"
            : "\(command) failed (exit \(status)):\n\(tail)"
    }
}

enum Shell {
    /// Runs a process, streaming its combined stdout and stderr line by line.
    ///
    /// Returns the exit status; it never throws on a non-zero exit, so callers
    /// decide what counts as a failure.
    @discardableResult
    static func run(
        _ executable: URL,
        _ arguments: [String] = [],
        environment: [String: String]? = nil,
        currentDirectory: URL? = nil,
        onLine: (@Sendable (String) async -> Void)? = nil
    ) async throws -> Int32 {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        if let environment { process.environment = environment }
        if let currentDirectory { process.currentDirectoryURL = currentDirectory }

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice

        let (chunks, continuation) = AsyncStream<Data>.makeStream()
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                continuation.finish()
            } else {
                continuation.yield(data)
            }
        }

        try process.run()

        // Cancelling the surrounding task stops the child too, so Cancel
        // during an install — or Quit Game — actually stops what is running.
        await withTaskCancellationHandler {
            var pending = Data()
            for await chunk in chunks {
                pending.append(chunk)
                while let newline = pending.firstIndex(of: 0x0A) {
                    let line = String(decoding: pending[..<newline], as: UTF8.self)
                    pending = pending[pending.index(after: newline)...]
                    await onLine?(line)
                }
            }
            if !pending.isEmpty {
                await onLine?(String(decoding: pending, as: UTF8.self))
            }
        } onCancel: {
            process.terminate()
        }

        // The pipe is at EOF, so the process has finished or is about to;
        // waiting on a background thread avoids racing terminationHandler
        // against an already-exited process.
        return await withCheckedContinuation { resume in
            DispatchQueue.global(qos: .userInitiated).async {
                process.waitUntilExit()
                resume.resume(returning: process.terminationStatus)
            }
        }
    }

    /// Runs a process and returns its trimmed combined output, throwing on a
    /// non-zero exit.
    @discardableResult
    static func check(
        _ executable: URL,
        _ arguments: [String] = [],
        environment: [String: String]? = nil,
        currentDirectory: URL? = nil,
        onLine: (@Sendable (String) async -> Void)? = nil
    ) async throws -> String {
        let collected = OutputBox()
        let status = try await run(
            executable, arguments,
            environment: environment,
            currentDirectory: currentDirectory
        ) { line in
            collected.append(line)
            await onLine?(line)
        }
        let output = collected.text
        guard status == 0 else {
            throw ProcessFailure(
                command: executable.lastPathComponent, status: status, output: output)
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Runs a tool from PATH, e.g. `hdiutil`, `ditto`, `tar`.
    @discardableResult
    static func tool(
        _ name: String,
        _ arguments: [String] = [],
        environment: [String: String]? = nil,
        onLine: (@Sendable (String) async -> Void)? = nil
    ) async throws -> String {
        try await check(
            URL(filePath: "/usr/bin/env"), [name] + arguments,
            environment: environment, onLine: onLine)
    }

    /// True when any running process's command line mentions `pattern`.
    static func isProcessRunning(matching pattern: String) async -> Bool {
        let status = try? await run(
            URL(filePath: "/usr/bin/env"), ["pgrep", "-f", pattern])
        return status == 0
    }
}

/// Small lock-guarded string accumulator, so output can be collected from the
/// pipe's background queue.
private final class OutputBox: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []

    func append(_ line: String) {
        lock.lock(); defer { lock.unlock() }
        lines.append(line)
    }

    var text: String {
        lock.lock(); defer { lock.unlock() }
        return lines.joined(separator: "\n")
    }
}
