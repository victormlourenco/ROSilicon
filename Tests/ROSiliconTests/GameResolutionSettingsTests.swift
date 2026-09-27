import Foundation
import Testing
@testable import ROSilicon

@Suite(.timeLimit(.minutes(1)))
struct GameResolutionSettingsTests {
    @Test func extraResolutionIsNotAdvertisedByDefault() throws {
        let suite = "ROSiliconTests.resolution.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(!GameResolutionSettings().advertiseUsableScreenResolution)
        #expect(!GameResolutionSettings.load(from: defaults).advertiseUsableScreenResolution)
        #expect(defaults.object(forKey: GameResolutionSettings.preferenceKey) == nil)
    }

    @Test(arguments: [false, true])
    func savedChoiceSurvivesReload(enabled: Bool) throws {
        let suite = "ROSiliconTests.resolution.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        GameResolutionSettings(advertiseUsableScreenResolution: enabled).save(to: defaults)
        let reopened = try #require(UserDefaults(suiteName: suite))
        #expect(GameResolutionSettings.load(from: reopened).advertiseUsableScreenResolution
            == enabled)
        #expect(reopened.bool(forKey: GameResolutionSettings.preferenceKey) == enabled)
    }

    @Test func nonBooleanSavedChoiceFailsClosed() throws {
        let suite = "ROSiliconTests.resolution.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("future-mode", forKey: GameResolutionSettings.preferenceKey)

        #expect(!GameResolutionSettings.load(from: defaults).advertiseUsableScreenResolution)
    }

    @Test(arguments: [false, true])
    func onlyChangesItsOwnPrefixLocalValue(enabled: Bool) {
        #expect(GameResolutionSettings(
            advertiseUsableScreenResolution: enabled).registryArguments == [
            "reg", "add", #"HKCU\Software\Wine\Mac Driver"#,
            "/v", "ROSiliconFitUsableScreenMode", "/t", "REG_SZ",
            "/d", enabled ? "y" : "n", "/f"
        ])
    }

    @Test(arguments: [false, true])
    func appliesUsingTheEffectiveGameEnvironment(enabled: Bool) async throws {
        let settings = GameResolutionSettings(advertiseUsableScreenResolution: enabled)
        let wine = URL(filePath: "/test/ROSilicon.app/Contents/Resources/Wine/bin/wine")
        let environment = [
            "WINEPREFIX": "/test/An overridden prefix with spaces",
            "WINELOADER": wine.path,
            "WINESERVER": "/test/wineserver",
            "DYLD_LIBRARY_PATH": "/test/external",
            "WINEDEBUG": "+display"
        ]
        let calls = ResolutionCalls()
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
        #expect(environment["WINEDEBUG"] == "+display")
    }

    @Test func registryFailureIsPropagatedWithoutSuccessLog() async {
        let logs = ResolutionCalls()
        let reporter = Reporter(
            log: { _ in await logs.record() }, step: { _ in }, progress: { _ in })
        do {
            try await GameResolutionSettings(advertiseUsableScreenResolution: true).apply(
                wine: URL(filePath: "/test/wine"), environment: [:], reporter: reporter
            ) { _, _, _ in
                throw ProcessFailure(command: "wine", status: 5, output: "Access denied")
            }
            Issue.record("Registry failure should stop Setup or the game")
        } catch let failure as ProcessFailure {
            #expect(failure.status == 5)
            #expect(failure.output == "Access denied")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        #expect(await logs.count == 0)
    }

    @Test func cancellationBeforeApplyDoesNotLaunchWine() async {
        let calls = ResolutionCalls()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await GameResolutionSettings(advertiseUsableScreenResolution: true).apply(
                wine: URL(filePath: "/test/wine"), environment: [:], reporter: .silent
            ) { _, _, _ in await calls.record() }
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await calls.count == 0)
    }
}

private actor ResolutionCalls {
    private(set) var count = 0
    func record() { count += 1 }
}
