import Foundation

/// Wine's Mac Edit menu consumes Command+A/C/V/X/Z before Ragnarok sees
/// them as Alt shortcuts. Disable it for Ragexe.exe, not the whole prefix.
struct GameKeyboardSettings: Sendable {
    var commandShortcuts = true

    static let preferenceKey = "commandShortcuts"
    static let registryKey = #"HKCU\Software\Wine\AppDefaults\Ragexe.exe\Mac Driver"#

    static func load(from defaults: UserDefaults) -> Self {
        Self(commandShortcuts: defaults.object(forKey: preferenceKey) as? Bool ?? true)
    }

    func save(to defaults: UserDefaults) {
        defaults.set(commandShortcuts, forKey: Self.preferenceKey)
    }

    /// Both choices are explicit and idempotent. "key" restores the bundled
    /// runtime's default Mac editing behavior without touching sibling values
    /// or another application's settings, even if the prefix has an override.
    var registryArguments: [String] {
        ["reg", "add", Self.registryKey, "/v", "EditMenu", "/t", "REG_SZ",
         "/d", commandShortcuts ? "disabled" : "key", "/f"]
    }

    typealias Run = @Sendable (URL, [String], [String: String]) async throws -> Void

    /// Use the same prefix/environment as the following game process, including
    /// a WINEPREFIX override from the advanced menu. This runs after prefix
    /// creation on Install/Repair and before every Play, so existing installs
    /// pick it up too. Tests inject a runner and never launch Wine.
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
        await reporter.log(commandShortcuts
            ? Strings.logCommandShortcutsOn : Strings.logCommandShortcutsOff)
    }
}
