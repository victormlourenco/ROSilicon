import Foundation
import Testing
@testable import ROSilicon

struct GameKeyboardSettingsTests {
    @Test func enabledByDefault() throws {
        let suite = "ROSiliconTests.keyboard.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(GameKeyboardSettings().commandShortcuts)
        #expect(GameKeyboardSettings.load(from: defaults).commandShortcuts)
        #expect(defaults.object(forKey: GameKeyboardSettings.preferenceKey) == nil)
    }

    @Test(arguments: [true, false])
    func savedChoiceSurvivesReload(enabled: Bool) throws {
        let suite = "ROSiliconTests.keyboard.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        GameKeyboardSettings(commandShortcuts: enabled).save(to: defaults)
        let reopened = try #require(UserDefaults(suiteName: suite))
        #expect(GameKeyboardSettings.load(from: reopened).commandShortcuts == enabled)
        #expect(reopened.object(forKey: GameKeyboardSettings.preferenceKey) as? Bool == enabled)
    }

    @Test(arguments: [true, false])
    func onlyChangesTheGameEditMenu(enabled: Bool) {
        let settings = GameKeyboardSettings(commandShortcuts: enabled)
        #expect(settings.registryArguments == [
            "reg", "add", #"HKCU\Software\Wine\AppDefaults\Ragexe.exe\Mac Driver"#,
            "/v", "EditMenu", "/t", "REG_SZ", "/d", enabled ? "disabled" : "key", "/f"
        ])
    }

    @Test(arguments: [true, false])
    func appliesUsingTheEffectiveGameEnvironment(enabled: Bool) async throws {
        let settings = GameKeyboardSettings(commandShortcuts: enabled)
        let wine = URL(filePath: "/test/ROSilicon.app/Contents/Resources/Wine/bin/wine")
        let environment = [
            "WINEPREFIX": "/test/An overridden prefix with spaces",
            "WINELOADER": wine.path,
            "WINESERVER": "/test/wineserver",
            "DYLD_LIBRARY_PATH": "/test/external",
            "X87_SIDECAR_PATH": "/test/x87sidecar",
            "WINEDLLOVERRIDES": "d3d9=n,b",
            "WINEDEBUG": "+seh"
        ]
        let calls = Calls()
        try await settings.apply(wine: wine, environment: environment, reporter: .silent) {
            executable, arguments, actualEnvironment in
            #expect(executable == wine)
            #expect(arguments == settings.registryArguments)
            var expected = environment
            expected["WINEDEBUG"] = "-all"
            #expect(actualEnvironment == expected)
            await calls.record()
        }
        #expect(await calls.count == 1)
        #expect(environment["WINEDEBUG"] == "+seh")
    }

    @Test func repeatedApplicationsAndSwitchingOffAreIdempotent() async throws {
        let values = Values()
        let run: GameKeyboardSettings.Run = { _, arguments, _ in
            let index = try #require(arguments.firstIndex(of: "/d"))
            await values.record(arguments[index + 1])
        }
        for enabled in [true, true, false, false, true] {
            try await GameKeyboardSettings(commandShortcuts: enabled).apply(
                wine: URL(filePath: "/test/wine"),
                environment: ["WINEPREFIX": "/test/prefix"],
                reporter: .silent, run: run)
        }
        #expect(await values.items == ["disabled", "disabled", "key", "key", "disabled"])
    }

    @Test func registryFailureIsPropagatedWithoutSuccessLog() async {
        let logs = Calls()
        let reporter = Reporter(log: { _ in await logs.record() }, step: { _ in }, progress: { _ in })
        do {
            try await GameKeyboardSettings().apply(
                wine: URL(filePath: "/test/wine"), environment: [:], reporter: reporter
            ) { _, _, _ in
                throw ProcessFailure(command: "wine", status: 5, output: "Access denied")
            }
            Issue.record("Registry failure should stop installation/game launch")
        } catch let failure as ProcessFailure {
            #expect(failure.status == 5)
            #expect(failure.output == "Access denied")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        #expect(await logs.count == 0)
    }

    @Test func cancellationBeforeApplyDoesNotLaunchWine() async {
        let calls = Calls()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await GameKeyboardSettings().apply(
                wine: URL(filePath: "/test/wine"), environment: [:], reporter: .silent
            ) { _, _, _ in await calls.record() }
        }
        do {
            try await task.value
            Issue.record("A cancelled task should not apply settings")
        } catch is CancellationError {
            // Expected.
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        #expect(await calls.count == 0)
    }

    @Test func cancellationAfterWriteDoesNotReportSuccess() async {
        let logs = Calls()
        let reporter = Reporter(log: { _ in await logs.record() }, step: { _ in }, progress: { _ in })
        let task = Task {
            try await GameKeyboardSettings().apply(
                wine: URL(filePath: "/test/wine"), environment: [:], reporter: reporter
            ) { _, _, _ in
                withUnsafeCurrentTask { $0?.cancel() }
            }
        }
        do {
            try await task.value
            Issue.record("Cancellation after a registry write should still stop launch")
        } catch is CancellationError {
            // Expected, even though the preference may already be applied.
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        #expect(await logs.count == 0)
    }

    @Test(arguments: ["en", "pt-BR", "es"])
    func shortcutStringsAreLocalized(language: String) throws {
        let root = URL(filePath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let url = root.appending(path: "Resources/Localizations/\(language).lproj/Localizable.strings")
        let strings = try #require(PropertyListSerialization.propertyList(
            from: Data(contentsOf: url), format: nil) as? [String: String])
        for key in ["menu.command_shortcuts", "help.command_shortcuts",
                    "log.command_shortcuts_on", "log.command_shortcuts_off"] {
            let value = try #require(strings[key])
            #expect(!value.isEmpty)
            #expect(value != key)
        }
    }
}

private actor Calls {
    private(set) var count = 0
    func record() { count += 1 }
}

private actor Values {
    private(set) var items: [String] = []
    func record(_ value: String) { items.append(value) }
}
