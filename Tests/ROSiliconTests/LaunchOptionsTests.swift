import Foundation
import Testing
@testable import ROSilicon

struct LaunchOptionsTests {

    // MARK: - Wine's debug channels

    @Test func quietByDefault() {
        #expect(LaunchOptions().wineDebugValue == LaunchOptions.defaultWineDebug)
        #expect(LaunchOptions.defaultWineDebug == "-all")
    }

    @Test(arguments: ["", " ", "\t", "\n", "   \n  "])
    func blankChannelsFallBackToTheQuietDefault(typed: String) {
        #expect(LaunchOptions(wineDebug: typed).wineDebugValue == "-all")
    }

    @Test func channelsAreTrimmedButOtherwiseKeptAsTyped() {
        #expect(LaunchOptions(wineDebug: "  +seh,+relay  ").wineDebugValue == "+seh,+relay")
    }

    // MARK: - Extra variables

    @Test func noExtraVariablesByDefault() {
        #expect(LaunchOptions().extraVariables.isEmpty)
    }

    @Test func parsesSemicolonSeparatedPairs() {
        let options = LaunchOptions(extraEnvironment: "A=1;B=2;C=3")
        #expect(options.extraVariables == ["A": "1", "B": "2", "C": "3"])
    }

    @Test func trimsWhitespaceAroundNamesAndValues() {
        let options = LaunchOptions(extraEnvironment: " A = 1 ; B\t=\t2 ")
        #expect(options.extraVariables == ["A": "1", "B": "2"])
    }

    @Test func onlyTheFirstEqualsSplits() {
        let options = LaunchOptions(extraEnvironment: "WINEDLLOVERRIDES=d3d9=n,b")
        #expect(options.extraVariables == ["WINEDLLOVERRIDES": "d3d9=n,b"])
    }

    /// `NAME=` is dropped, not read as an empty value: splitting on `=` omits
    /// the empty subsequence, so the entry never reaches two parts. Pinned
    /// because setting a variable to the empty string is not currently a way
    /// to clear one from the sheet.
    @Test func anEmptyValueIsDroppedRatherThanSetToTheEmptyString() {
        #expect(LaunchOptions(extraEnvironment: "EMPTY=").extraVariables.isEmpty)
        #expect(LaunchOptions(extraEnvironment: "A=1;EMPTY=").extraVariables == ["A": "1"])
    }

    /// Anything the sheet cannot read as `NAME=value` is dropped rather than
    /// guessed at, so a typo cannot smuggle a nameless variable through.
    @Test(arguments: ["NOEQUALS", "=value", "  =value", ";;", "", "   "])
    func dropsEntriesThatAreNotNameValuePairs(typed: String) {
        #expect(LaunchOptions(extraEnvironment: typed).extraVariables.isEmpty)
    }

    @Test func keepsTheGoodPairsBesideABadOne() {
        let options = LaunchOptions(extraEnvironment: "A=1;garbage;=2;B=3;")
        #expect(options.extraVariables == ["A": "1", "B": "3"])
    }

    @Test func lastValueWinsForARepeatedName() {
        #expect(LaunchOptions(extraEnvironment: "A=1;A=2").extraVariables == ["A": "2"])
    }

    // MARK: - Applying them

    @Test func applySetsTheDebugChannelsAndLeavesTherestAlone() {
        var environment = ["WINEPREFIX": "/test/prefix", "PATH": "/usr/bin"]
        let extras = LaunchOptions(wineDebug: "+seh").apply(to: &environment)
        #expect(extras.isEmpty)
        #expect(environment == [
            "WINEPREFIX": "/test/prefix", "PATH": "/usr/bin", "WINEDEBUG": "+seh"])
    }

    @Test func applyWritesTheDefaultWhenNothingWasTyped() {
        var environment: [String: String] = [:]
        LaunchOptions().apply(to: &environment)
        #expect(environment == ["WINEDEBUG": "-all"])
    }

    @Test func extrasAreReturnedSortedForTheLog() {
        var environment: [String: String] = [:]
        let extras = LaunchOptions(extraEnvironment: "ZED=z;alpha=a;Beta=b")
            .apply(to: &environment)
        #expect(extras == ["Beta=b", "ZED=z", "alpha=a"])
    }

    /// Someone overriding what the launcher chose for itself means it: the
    /// extras go on last, so they win.
    @Test func extrasOverrideWhatTheLauncherSetItself() {
        var environment = ["WINEDLLOVERRIDES": "d3d9=n,b", "MTL_HUD_ENABLED": "1"]
        let options = LaunchOptions(
            wineDebug: "+relay", extraEnvironment: "WINEDLLOVERRIDES=d3d9=b;WINEDEBUG=+seh")
        let extras = options.apply(to: &environment)
        #expect(environment["WINEDLLOVERRIDES"] == "d3d9=b")
        #expect(environment["WINEDEBUG"] == "+seh")
        #expect(environment["MTL_HUD_ENABLED"] == "1")
        #expect(extras == ["WINEDEBUG=+seh", "WINEDLLOVERRIDES=d3d9=b"])
    }
}
