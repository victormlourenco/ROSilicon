import Foundation
import Testing
@testable import ROSilicon

/// The strings files are read straight off disk rather than through `Strings`:
/// outside an app bundle there is no strings table to look a key up in, so
/// `Bundle.main.localizedString` hands back the key it was given.
struct LocalizationTests {
    static let developmentLanguage = "en"
    static let languages = ["en", "es", "pt-BR"]
    /// Every language but the one the keys were written in.
    static let translations = languages.filter { $0 != developmentLanguage }

    static func strings(_ language: String) throws -> [String: String] {
        let url = projectRoot.appending(
            path: "Resources/Localizations/\(language).lproj/Localizable.strings")
        let contents = try Data(contentsOf: url)
        return try #require(
            PropertyListSerialization.propertyList(from: contents, format: nil) as? [String: String],
            "\(language).lproj/Localizable.strings is not a strings file")
    }

    // MARK: - Every language says everything

    @Test(arguments: languages)
    func everyLanguageFileParses(language: String) throws {
        #expect(!(try Self.strings(language)).isEmpty)
    }

    /// macOS falls back to English for a missing key, so a gap would show as
    /// one English line in an otherwise translated window.
    @Test(arguments: translations)
    func aTranslationCoversEveryKeyAndInventsNone(language: String) throws {
        let english = Set(try Self.strings(Self.developmentLanguage).keys)
        let translated = Set(try Self.strings(language).keys)
        #expect(translated.subtracting(english).sorted() == [], "keys not in en.lproj")
        #expect(english.subtracting(translated).sorted() == [], "keys missing from \(language)")
    }

    @Test(arguments: languages)
    func noValueIsBlankOrLeftAsItsKey(language: String) throws {
        for (key, value) in try Self.strings(language) {
            #expect(!value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    "\(language): \(key) is empty")
            #expect(value != key, "\(language): \(key) was never given a translation")
        }
    }

    // MARK: - Placeholders

    /// `String(format:)` reads its arguments by the types the format asks for.
    /// A translation that says %d where English says %@ would read a pointer
    /// as a number, so this is a crash, not a typo.
    @Test(arguments: translations)
    func placeholdersMatchEnglishInKindAndNumber(language: String) throws {
        let english = try Self.strings(Self.developmentLanguage)
        for (key, translation) in try Self.strings(language) {
            guard let original = english[key] else { continue }
            #expect(argumentTypes(of: translation) == argumentTypes(of: original),
                    Comment(rawValue: "\(language): \(key) — \"\(translation)\" does not "
                        + "take the same arguments as \"\(original)\""))
        }
    }

    @Test func theFormatParserUnderstandsWhatTheStringsFilesUse() {
        #expect(argumentTypes(of: "no placeholders") == [])
        #expect(argumentTypes(of: "%@ and %@") == ["@", "@"])
        #expect(argumentTypes(of: "%d files") == ["d"])
        #expect(argumentTypes(of: "100%% of %@") == ["@"])
        #expect(argumentTypes(of: "%2$@ then %1$@") == ["@", "@"])
        #expect(argumentTypes(of: "%1$@ exited with %2$d") == ["@", "d"])
        #expect(argumentTypes(of: "%-10.3f") == ["f"])
        #expect(argumentTypes(of: "%ld") == ["d"])
    }

    // MARK: - Against the Swift that asks for them

    @Test func everyKeyStringsAsksForIsInTheEnglishFile() throws {
        let english = try Self.strings(Self.developmentLanguage)
        for call in try StringsCall.allInSource() {
            #expect(english[call.key] != nil,
                    "Strings.swift asks for \(call.key), which en.lproj does not define")
        }
    }

    @Test func theEnglishFileHasNoKeysNothingAsksFor() throws {
        let asked = Set(try StringsCall.allInSource().map(\.key))
        for key in try Self.strings(Self.developmentLanguage).keys {
            #expect(asked.contains(key), "en.lproj defines \(key), which nothing asks for")
        }
    }

    /// Too few arguments for the placeholders in a format is undefined
    /// behaviour, and the way a launcher crashes on a message about something
    /// else having gone wrong.
    @Test func everyCallPassesAsManyArgumentsAsItsFormatTakes() throws {
        let english = try Self.strings(Self.developmentLanguage)
        for call in try StringsCall.allInSource() {
            guard let format = english[call.key] else { continue }
            #expect(call.arguments == argumentTypes(of: format).count,
                    Comment(rawValue: "Strings.swift passes \(call.arguments) argument(s) "
                        + "for \(call.key), whose format takes "
                        + "\(argumentTypes(of: format).count)"))
        }
    }
}

// MARK: - Reading format strings

/// The conversions a format string takes, in argument order. Positional forms
/// (`%2$@`) are placed where they belong rather than where they appear.
func argumentTypes(of format: String) -> [Character] {
    let found = specifiers(in: format)
    guard found.contains(where: { $0.position != nil }) else { return found.map(\.conversion) }

    var byPosition: [Int: Character] = [:]
    for (index, specifier) in found.enumerated() {
        byPosition[specifier.position ?? index + 1] = specifier.conversion
    }
    guard let highest = byPosition.keys.max() else { return [] }
    return (1...highest).map { byPosition[$0] ?? "?" }
}

private struct Specifier {
    var position: Int?
    var conversion: Character
}

private func specifiers(in format: String) -> [Specifier] {
    let characters = Array(format)
    var found: [Specifier] = []
    var index = 0

    while index < characters.count {
        guard characters[index] == "%" else { index += 1; continue }
        index += 1
        guard index < characters.count else { break }
        if characters[index] == "%" { index += 1; continue }   // an escaped percent

        var position: Int?
        var cursor = index
        var digits = ""
        while cursor < characters.count, characters[cursor].isNumber {
            digits.append(characters[cursor])
            cursor += 1
        }
        if cursor < characters.count, characters[cursor] == "$", !digits.isEmpty {
            position = Int(digits)
            index = cursor + 1
        }

        while index < characters.count, "-+ #0'".contains(characters[index]) { index += 1 }
        while index < characters.count, characters[index].isNumber { index += 1 }
        if index < characters.count, characters[index] == "." {
            index += 1
            while index < characters.count, characters[index].isNumber { index += 1 }
        }
        while index < characters.count, "hlLqjzt".contains(characters[index]) { index += 1 }

        guard index < characters.count else { break }
        found.append(Specifier(position: position, conversion: characters[index]))
        index += 1
    }
    return found
}

// MARK: - Reading Strings.swift

/// One `t("key", …)` call in Strings.swift: the key it looks up and how many
/// arguments it hands to `String(format:)`.
struct StringsCall {
    let key: String
    let arguments: Int

    static func allInSource() throws -> [StringsCall] {
        let source = try String(
            contentsOf: projectRoot.appending(path: "Sources/ROSilicon/Strings.swift"),
            encoding: .utf8)
        // The calls are all simple: a literal key, then bare identifiers. None
        // of them contains a parenthesis, so the closing one ends the call.
        let pattern = try NSRegularExpression(pattern: #"\bt\("([^"]+)"([^)]*)\)"#)
        let range = NSRange(source.startIndex..., in: source)

        return pattern.matches(in: source, range: range).compactMap { match in
            guard let key = Range(match.range(at: 1), in: source),
                  let rest = Range(match.range(at: 2), in: source)
            else { return nil }
            let arguments = source[rest]
                .split(separator: ",")
                .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            return StringsCall(key: String(source[key]), arguments: arguments.count)
        }
    }
}
