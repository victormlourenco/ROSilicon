import Foundation
import Testing
@testable import ROSilicon

struct ProfileTests {

    // MARK: - Where they live

    /// The default profile is the prefix every install had before profiles,
    /// so an existing install needs nothing moved to keep working.
    @Test func theDefaultProfileIsTheWineFolder() {
        let paths = Paths(root: URL(filePath: "/test/root"))
        #expect(paths.profile == .default)
        #expect(paths.prefix.path == "/test/root/wine")
    }

    @Test func anAdditionalProfileIsAPrefixOfItsOwnUnderProfiles() {
        let paths = Paths(root: URL(filePath: "/test/root"), profile: .named("Alt"))
        #expect(paths.prefix.path == "/test/root/profiles/Alt")
        #expect(paths.driveC.path == "/test/root/profiles/Alt/drive_c")
        #expect(paths.gameDir.path == "/test/root/profiles/Alt/drive_c/Gravity/Ragnarok")
        #expect(paths.wineEnvironment()["WINEPREFIX"] == "/test/root/profiles/Alt")
        // Shared: only one install runs at a time, whichever profile it is for.
        #expect(paths.downloads.path == "/test/root/downloads")
    }

    /// Each profile is booted on its own: one being ready says nothing of
    /// another.
    @Test func eachProfileIsInitializedOnItsOwn() throws {
        let temp = try TemporaryDirectory()
        try temp.write(to: "wine/system.reg")
        try temp.makeDirectory("wine/drive_c/windows/system32")
        try temp.makeDirectory("profiles/Alt")

        #expect(Paths(root: temp.url).prefixInitialized)
        #expect(!Paths(root: temp.url, profile: .named("Alt")).prefixInitialized)
    }

    /// The preferences keep the profile as a string; the default one, which no
    /// typed name can be, as an empty one.
    @Test func aProfileSurvivesTheTripThroughThePreferences() {
        for profile in [Profile.default, .named("Alt"), .named("Main account")] {
            #expect(Profile(rawValue: profile.rawValue) == profile)
        }
        #expect(Profile(rawValue: "") == .default)
    }

    @Test func onlyTheDefaultProfileCannotBeDeleted() {
        #expect(!Profile.default.isDeletable)
        #expect(Profile.named("Alt").isDeletable)
    }

    // MARK: - Listing

    @Test func aFreshInstallHasOnlyTheDefaultProfile() throws {
        let temp = try TemporaryDirectory()
        #expect(Profile.all(in: temp.url) == [.default])
        #expect(Profile.all(in: temp.url.appending(path: "never-installed")) == [.default])
    }

    /// The folders are the profiles: no list is kept anywhere else.
    @Test func everyFolderUnderProfilesIsOneDefaultFirst() throws {
        let temp = try TemporaryDirectory()
        try temp.makeDirectory("profiles/b")
        try temp.makeDirectory("profiles/Alt 10")
        try temp.makeDirectory("profiles/Alt 2")
        try temp.makeDirectory("profiles/.hidden")
        try temp.write(to: "profiles/notes.txt")

        #expect(Profile.all(in: temp.url)
                == [.default, .named("Alt 2"), .named("Alt 10"), .named("b")])
    }

    // MARK: - Naming

    @Test func aNameIsTrimmedAndOtherwiseKept() throws {
        #expect(try Profile.validatedName("  Main account ", existing: [.default])
                == "Main account")
    }

    @Test func aNameMustSaySomething() {
        #expect(throws: ProfileError.nameEmpty) { try Profile.validatedName("", existing: []) }
        #expect(throws: ProfileError.nameEmpty) { try Profile.validatedName("  ", existing: []) }
    }

    /// It becomes a folder name, so it may not leave profiles/ or hide.
    @Test(arguments: ["../wine", "a/b", "a:b", ".hidden", ".."])
    func aNameCannotReachOutsideItsFolderOrHide(name: String) {
        #expect(throws: ProfileError.nameInvalid) {
            try Profile.validatedName(name, existing: [.default])
        }
    }

    /// The file system does not usually tell "alt" from "Alt", so neither does
    /// this — and the default profile's own name is taken too.
    @Test func aNameAlreadyInUseIsRefusedWhateverItsCase() {
        let existing: [Profile] = [.default, .named("Alt")]
        #expect(throws: ProfileError.nameTaken("Alt")) {
            try Profile.validatedName("alt", existing: existing)
        }
        #expect(throws: ProfileError.nameTaken(Strings.profileDefault)) {
            try Profile.validatedName(Strings.profileDefault.uppercased(), existing: existing)
        }
    }

    // MARK: - Creating

    /// Only the folder: booting the prefix and fetching the client are what
    /// Install is for.
    @Test func creatingAProfileMakesItsFolderAndNothingElse() throws {
        let temp = try TemporaryDirectory()
        let profile = try Profile.create(named: " Alt ", in: temp.url)

        #expect(profile == .named("Alt"))
        #expect(FileManager.default.fileExists(
            atPath: temp.url.appending(path: "profiles/Alt").path))
        #expect(!Paths(root: temp.url, profile: profile).prefixInitialized)
        #expect(Profile.all(in: temp.url) == [.default, .named("Alt")])
    }

    @Test func creatingAProfileTwiceIsRefused() throws {
        let temp = try TemporaryDirectory()
        _ = try Profile.create(named: "Alt", in: temp.url)
        #expect(throws: ProfileError.nameTaken("Alt")) {
            try Profile.create(named: "ALT", in: temp.url)
        }
    }

    @Test func everyProfileFailureDescribesItself() throws {
        let failures: [ProfileError] = [
            .nameEmpty, .nameInvalid, .nameTaken("Alt"), .defaultNotDeletable,
        ]
        for failure in failures {
            #expect(!(try #require(failure.errorDescription)).isEmpty)
        }
    }
}
