import Foundation
import Testing
@testable import ROSilicon

/// Only the parts that can be reached without standing a model up: it reads
/// the real install folder and the user's own preferences, and a test has no
/// business writing to either.
@MainActor
struct LauncherModelTests {

    /// Every button in the window is disabled off the back of this, so an
    /// install that reads as idle would let someone start a second one.
    @Test func onlyIdleIsNotBusy() {
        #expect(!LauncherModel.Phase.idle.isBusy)
        #expect(LauncherModel.Phase.working.isBusy)
        #expect(LauncherModel.Phase.running.isBusy)
    }

    @Test func aLogLineIsOrdinaryUnlessItSaysOtherwise() {
        let line = LauncherModel.LogLine(text: "wine: created the prefix")
        #expect(line.text == "wine: created the prefix")
        if case .plain = line.kind {} else { Issue.record("a new line should be plain") }
    }

    /// The view colours lines by what they are, not by matching on text that
    /// changes with the reader's language.
    @Test func everyLineCarriesAnIdentityOfItsOwn() {
        let lines = (0..<100).map { LauncherModel.LogLine(text: "line \($0)") }
        #expect(Set(lines.map(\.id)).count == lines.count)
    }
}
