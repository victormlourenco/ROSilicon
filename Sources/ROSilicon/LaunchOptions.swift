import Foundation

/// The bits of the launch environment someone can bend by hand from the ⌥
/// menu: Wine's debug channels, and any other variables they want the game
/// started with.
///
/// Both are carried as the text that was typed, so the sheet hands back
/// exactly what went in; the parsing happens here, on the way to the process.
struct LaunchOptions: Sendable {
    /// What `WINEDEBUG` is set to. Empty means the launcher's own default.
    var wineDebug = ""
    /// `NAME=value` pairs separated by `;`, as typed.
    var extraEnvironment = ""

    /// Wine says nothing unless asked to: the client is chatty enough that its
    /// fixme lines would drown everything else in the log.
    static let defaultWineDebug = "-all"

    var wineDebugValue: String {
        let trimmed = wineDebug.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? Self.defaultWineDebug : trimmed
    }

    /// The extra variables, parsed. An entry with nothing before its first `=`
    /// is dropped rather than guessed at, and only that first `=` splits, so a
    /// value may contain more of them.
    var extraVariables: [String: String] {
        var variables: [String: String] = [:]
        for entry in extraEnvironment.split(separator: ";") {
            let parts = entry.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let name = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            variables[name] = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return variables
    }

    /// Applies both to an environment on its way to a process, and returns the
    /// extra variables as `NAME=value` for the log.
    ///
    /// The extras go on last so they win: someone overriding `WINEDLLOVERRIDES`
    /// or `WINEDEBUG` from the sheet means it.
    @discardableResult
    func apply(to environment: inout [String: String]) -> [String] {
        environment["WINEDEBUG"] = wineDebugValue
        let extras = extraVariables
        for (name, value) in extras { environment[name] = value }
        return extras.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }
    }
}
