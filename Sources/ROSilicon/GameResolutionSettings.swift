import Foundation

/// Controls whether ROSilicon's Wine advertises one extra windowed mode sized
/// to the primary Mac display's usable content area. Ragnarok still owns and
/// saves the actual selection through Setup; the launcher never edits the
/// game's generated settings files.
struct GameResolutionSettings: Equatable, Sendable {
    var advertiseUsableScreenResolution = false

    static let preferenceKey = "advertiseUsableScreenResolution"
    static let registryKey = #"HKCU\Software\Wine\Mac Driver"#
    static let registryValue = "ROSiliconFitUsableScreenMode"

    static func load(from defaults: UserDefaults) -> Self {
        Self(advertiseUsableScreenResolution:
            defaults.object(forKey: preferenceKey) as? Bool ?? false)
    }

    func save(to defaults: UserDefaults) {
        defaults.set(advertiseUsableScreenResolution, forKey: Self.preferenceKey)
    }

    /// Both Boolean states are explicit and idempotent. The Mac driver reads this
    /// prefix-local value while enumerating display modes in Setup and the
    /// game. Saving the launcher preference alone never invokes Wine.
    var registryArguments: [String] {
        ["reg", "add", Self.registryKey, "/v", Self.registryValue, "/t", "REG_SZ",
         "/d", advertiseUsableScreenResolution ? "y" : "n", "/f"]
    }

    typealias Run = @Sendable (URL, [String], [String: String]) async throws -> Void

    func apply(
        wine: URL,
        environment: [String: String],
        reporter: Reporter,
        run: Run = { wine, arguments, environment in
            try await Shell.check(wine, arguments, environment: environment)
        }
    ) async throws {
        try Task.checkCancellation()
        var registryEnvironment = environment
        registryEnvironment["WINEDEBUG"] = "-all"
        try await run(wine, registryArguments, registryEnvironment)
        try Task.checkCancellation()
        await reporter.log(advertiseUsableScreenResolution
            ? Strings.logResolutionAdvertised : Strings.logResolutionNotAdvertised)
    }
}
