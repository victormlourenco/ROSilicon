import Foundation

enum ProfileError: LocalizedError, Equatable {
    case nameEmpty
    case nameInvalid
    case nameTaken(String)
    case defaultNotDeletable

    var errorDescription: String? {
        switch self {
        case .nameEmpty: Strings.errorProfileNameEmpty
        case .nameInvalid: Strings.errorProfileNameInvalid
        case .nameTaken(let name): Strings.errorProfileNameTaken(name)
        case .defaultNotDeletable: Strings.errorDefaultProfileNotDeletable
        }
    }
}

/// A Wine prefix of its own, with its own game client, registry and settings.
///
/// The default profile is `wine/`, the prefix every install had before there
/// were profiles, so an existing install carries on untouched; it cannot be
/// deleted. The rest sit side by side under `profiles/`, each in a folder named
/// after it. That folder is all there is to one: no list is kept anywhere
/// else, so the folders on disk are the profiles.
enum Profile: Hashable, Sendable, Identifiable {
    case `default`
    case named(String)

    /// The folder the additional profiles live in, under the install folder.
    static let folderName = "profiles"

    /// What the preferences remember: empty for the default profile, which no
    /// name typed for a new one can ever be.
    init(rawValue: String) { self = rawValue.isEmpty ? .default : .named(rawValue) }

    var rawValue: String {
        switch self {
        case .default: ""
        case .named(let name): name
        }
    }

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .default: Strings.profileDefault
        case .named(let name): name
        }
    }

    /// Only the profiles someone made can be deleted.
    var isDeletable: Bool { self != .default }

    /// Where its prefix sits, relative to the install folder.
    var folder: String {
        switch self {
        case .default: "wine"
        case .named(let name): Self.folderName + "/" + name
        }
    }

    // MARK: - On disk

    /// Every profile in the install at `root`: the default first, then the
    /// folders under `profiles/` in Finder order. A folder is a profile from
    /// the moment it exists, prefix or not — creating one makes only the
    /// folder, and Install does the rest.
    static func all(in root: URL) -> [Profile] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: root.appending(path: folderName), includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles])) ?? []
        let names = contents
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .map(\.lastPathComponent)
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        return [.default] + names.map(Profile.named)
    }

    /// The name as it will be used, trimmed, or why it cannot be. It becomes a
    /// folder name, so it may not reach outside `profiles/` or hide itself, and
    /// it has to differ from every existing profile's in more than case — the
    /// file system usually does not tell the two apart, and neither would
    /// someone reading the menu.
    static func validatedName(_ name: String, existing: [Profile]) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ProfileError.nameEmpty }
        guard !trimmed.hasPrefix("."), !trimmed.contains("/"), !trimmed.contains(":")
        else { throw ProfileError.nameInvalid }
        if let clash = existing.first(where: {
            $0.displayName.caseInsensitiveCompare(trimmed) == .orderedSame
        }) {
            throw ProfileError.nameTaken(clash.displayName)
        }
        return trimmed
    }

    /// Makes a new profile's folder and hands the profile back. Its prefix is
    /// left for Install to boot, like the default one on a fresh install.
    static func create(named name: String, in root: URL) throws -> Profile {
        let profile = Profile.named(try validatedName(name, existing: all(in: root)))
        try FileManager.default.createDirectory(
            at: Paths(root: root, profile: profile).prefix, withIntermediateDirectories: true)
        return profile
    }
}
