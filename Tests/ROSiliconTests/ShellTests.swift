import Foundation
import Testing
@testable import ROSilicon

struct ShellTests {

    // MARK: - run

    @Test func runReturnsTheExitStatusWithoutThrowing() async throws {
        #expect(try await Shell.run(URL(filePath: "/usr/bin/true")) == 0)
        #expect(try await Shell.run(URL(filePath: "/usr/bin/false")) == 1)
    }

    @Test func runReportsAnUnusualExitStatus() async throws {
        let status = try await Shell.run(
            URL(filePath: "/bin/sh"), ["-c", "exit 42"])
        #expect(status == 42)
    }

    @Test func runStreamsOutputOneLineAtATime() async throws {
        let lines = Collected<String>()
        let status = try await Shell.run(
            URL(filePath: "/bin/sh"), ["-c", "printf 'one\\ntwo\\nthree\\n'"]
        ) { await lines.record($0) }
        #expect(status == 0)
        #expect(await lines.items == ["one", "two", "three"])
    }

    /// Wine's last gasp before it dies often has no trailing newline; losing it
    /// would lose the one line that explains the failure.
    @Test func runDeliversATrailingLineWithoutItsNewline() async throws {
        let lines = Collected<String>()
        _ = try await Shell.run(
            URL(filePath: "/bin/sh"), ["-c", "printf 'first\\nno newline here'"]
        ) { await lines.record($0) }
        #expect(await lines.items == ["first", "no newline here"])
    }

    @Test func runKeepsEmptyLines() async throws {
        let lines = Collected<String>()
        _ = try await Shell.run(
            URL(filePath: "/bin/sh"), ["-c", "printf 'a\\n\\nb\\n'"]
        ) { await lines.record($0) }
        #expect(await lines.items == ["a", "", "b"])
    }

    /// stdout and stderr share one pipe, so the log reads in the order the
    /// child actually wrote things.
    @Test func runMergesStandardErrorIntoTheSameStream() async throws {
        let lines = Collected<String>()
        _ = try await Shell.run(
            URL(filePath: "/bin/sh"), ["-c", "echo out; echo err 1>&2"]
        ) { await lines.record($0) }
        #expect(await lines.items.sorted() == ["err", "out"])
    }

    @Test func runPassesTheEnvironmentItIsGivenAndNothingElse() async throws {
        let lines = Collected<String>()
        _ = try await Shell.run(
            URL(filePath: "/usr/bin/env"), [],
            environment: ["WINEPREFIX": "/test/prefix", "WINEDEBUG": "-all"]
        ) { await lines.record($0) }
        #expect(await lines.items.sorted() == ["WINEDEBUG=-all", "WINEPREFIX=/test/prefix"])
    }

    @Test func runHonoursTheWorkingDirectory() async throws {
        let temp = try TemporaryDirectory()
        let lines = Collected<String>()
        _ = try await Shell.run(
            URL(filePath: "/bin/pwd"), [], currentDirectory: temp.url
        ) { await lines.record($0) }
        #expect(await lines.items == [temp.url.path])
    }

    @Test func runWithoutALineHandlerStillFinishes() async throws {
        #expect(try await Shell.run(
            URL(filePath: "/bin/sh"), ["-c", "echo ignored"]) == 0)
    }

    @Test func runThrowsWhenTheExecutableIsNotThere() async {
        await #expect(throws: (any Error).self) {
            try await Shell.run(URL(filePath: "/nonexistent/tool"))
        }
    }

    /// Cancel during an install, or Quit Game, has to take the child down with
    /// it rather than leave it running unattended.
    @Test func cancellingTheTaskTerminatesTheChild() async throws {
        let task = Task {
            try await Shell.run(URL(filePath: "/bin/sleep"), ["30"])
        }
        // Give the child a moment to actually be running before cancelling.
        try await Task.sleep(for: .milliseconds(200))
        let start = ContinuousClock.now
        task.cancel()
        _ = try? await task.value
        #expect(start.duration(to: .now) < .seconds(10))
    }

    // MARK: - check

    @Test func checkReturnsTheTrimmedOutput() async throws {
        let output = try await Shell.check(
            URL(filePath: "/bin/sh"), ["-c", "printf '  wine-11.13  \\n\\n'"])
        #expect(output == "wine-11.13")
    }

    @Test func checkJoinsMultipleLinesWithNewlines() async throws {
        let output = try await Shell.check(
            URL(filePath: "/bin/sh"), ["-c", "printf 'one\\ntwo\\n'"])
        #expect(output == "one\ntwo")
    }

    @Test func checkThrowsOnANonZeroExitCarryingWhatWasSaid() async throws {
        do {
            _ = try await Shell.check(
                URL(filePath: "/bin/sh"), ["-c", "echo something broke 1>&2; exit 7"])
            Issue.record("A non-zero exit should throw")
        } catch let failure as ProcessFailure {
            #expect(failure.command == "sh")
            #expect(failure.status == 7)
            #expect(failure.output == "something broke")
            #expect(failure.errorDescription?.isEmpty == false)
        }
    }

    @Test func checkStillReportsLinesWhileCollectingThem() async throws {
        let lines = Collected<String>()
        let output = try await Shell.check(
            URL(filePath: "/bin/sh"), ["-c", "printf 'a\\nb\\n'"]
        ) { await lines.record($0) }
        #expect(await lines.items == ["a", "b"])
        #expect(output == "a\nb")
    }

    // MARK: - tool

    @Test func toolRunsSomethingFromPath() async throws {
        #expect(try await Shell.tool("echo", ["hello"]) == "hello")
    }

    @Test func toolReportsAFailingToolAsTheToolItself() async throws {
        do {
            _ = try await Shell.tool("tar", ["-xf", "/nonexistent/client.tar"])
            Issue.record("tar should refuse a file that is not there")
        } catch let failure as ProcessFailure {
            #expect(failure.status != 0)
            // /usr/bin/env is what is launched, and what the message names.
            #expect(failure.command == "env")
        }
    }

    // MARK: - isProcessRunning

    /// This is how the installer refuses to patch DLLs out from under a
    /// running Wine, so it has to see a process that is actually up — and stop
    /// seeing it once that process is gone.
    ///
    /// The child is a symlink to `sleep` named after the marker, so the marker
    /// is in its command line and there is no shell between us and it: a shell
    /// would survive as an orphan holding the pipe open when the task is
    /// cancelled.
    @Test func seesAProcessWhileItRunsAndNotAfterwards() async throws {
        let temp = try TemporaryDirectory()
        let marker = "ROSiliconTests-wine-\(UUID().uuidString)"
        let executable = temp.url.appending(path: marker)
        try FileManager.default.createSymbolicLink(
            at: executable, withDestinationURL: URL(filePath: "/bin/sleep"))

        let child = Task { try await Shell.run(executable, ["30"]) }
        defer { child.cancel() }
        try await waitUntil("the child is visible by its command line") {
            await Shell.isProcessRunning(matching: marker)
        }

        child.cancel()
        _ = try? await child.value
        try await waitUntil("the child is gone once its task is cancelled") {
            await !Shell.isProcessRunning(matching: marker)
        }
    }

    /// Polls a condition for a few seconds. `pgrep` sees a process a moment
    /// after it starts and for a moment after it dies, so neither side of the
    /// check can be made the instant the task changes.
    private func waitUntil(
        _ what: Comment, timeout: Duration = .seconds(10),
        _ condition: () async -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        Issue.record("Timed out waiting until \(what)")
    }

    @Test func findsNothingForAPatternThatMatchesNoProcess() async {
        #expect(await !Shell.isProcessRunning(matching: "ROSilicon-\(UUID().uuidString)"))
    }
}
