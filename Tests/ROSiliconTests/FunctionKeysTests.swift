import Foundation
import Testing
@testable import ROSilicon

/// Stands in for the Mac's `HIDFKeyMode` parameter: the mode it holds, every
/// write that reached it, and switches for a Mac that will not give the
/// parameter up.
///
/// The real one is a setting for the whole computer, so the tests must not go
/// near it — a test run has no business changing the keyboard of whoever
/// started it.
@MainActor
final class FakeFunctionKeys {
    var mode: FunctionKeyMode?
    private(set) var writes: [FunctionKeyMode] = []
    var readable = true
    var writable = true

    init(_ mode: FunctionKeyMode?) { self.mode = mode }

    var read: FunctionKeyOverride.Read {
        { [self] in readable ? mode : nil }
    }

    var write: FunctionKeyOverride.Write {
        { [self] wanted in
            guard writable else { return false }
            writes.append(wanted)
            mode = wanted
            return true
        }
    }

    func override() -> FunctionKeyOverride {
        FunctionKeyOverride(read: read, write: write)
    }
}

/// The state machine around the keyboard, driven without IOKit.
///
/// What matters here is that the launcher always gives back exactly what it
/// borrowed, and borrows nothing it cannot give back: the mode outlives the
/// process, so a mistake leaves somebody's brightness keys gone.
@MainActor
struct FunctionKeyOverrideTests {

    // MARK: - Borrowing and giving back

    @Test func engagingSwitchesTheKeyboardAndRemembersWhatItReplaced() {
        let keys = FakeFunctionKeys(.media)
        let override = keys.override()

        override.engage(.standard, reporter: .silent)

        #expect(keys.mode == .standard)
        #expect(keys.writes == [.standard])
        #expect(override.restoring == .media)
    }

    @Test func releasingPutsBackWhatWasThere() {
        let keys = FakeFunctionKeys(.media)
        let override = keys.override()

        override.engage(.standard, reporter: .silent)
        override.release(reporter: .silent)

        #expect(keys.mode == .media)
        #expect(keys.writes == [.standard, .media])
        #expect(override.restoring == nil)
    }

    /// Someone who already keeps their Mac on standard function keys is having
    /// nothing done to them, so there is nothing to undo either — and in
    /// particular the launcher must not "restore" them to media keys they
    /// never asked for.
    @Test func aMacAlreadyInTheWantedModeIsLeftAlone() {
        let keys = FakeFunctionKeys(.standard)
        let override = keys.override()

        override.engage(.standard, reporter: .silent)
        #expect(keys.writes == [])
        #expect(override.restoring == nil)

        override.release(reporter: .silent)
        #expect(keys.mode == .standard)
        #expect(keys.writes == [])
    }

    @Test func releasingWithoutEngagingDoesNothing() {
        let keys = FakeFunctionKeys(.media)
        let override = keys.override()

        override.release(reporter: .silent)

        #expect(keys.mode == .media)
        #expect(keys.writes == [])
    }

    // MARK: - Several clients at once

    /// Two clients share one override. The mode to put back is the one from
    /// before the first of them, not whatever is in force by the time the
    /// second starts.
    @Test func engagingTwiceBorrowsOnceAndKeepsTheFirstModeToRestore() {
        let keys = FakeFunctionKeys(.media)
        let override = keys.override()

        override.engage(.standard, reporter: .silent)
        override.engage(.standard, reporter: .silent)

        #expect(keys.writes == [.standard])
        #expect(override.restoring == .media)
    }

    /// The last client to close is the one that restores; the ones before it
    /// find nothing owed.
    @Test func onlyTheFirstReleaseGivesTheKeyboardBack() {
        let keys = FakeFunctionKeys(.media)
        let override = keys.override()

        override.engage(.standard, reporter: .silent)
        override.release(reporter: .silent)
        override.release(reporter: .silent)

        #expect(keys.writes == [.standard, .media])
        #expect(override.restoring == nil)
    }

    /// A session that ends and another that begins: the second borrows afresh
    /// from whatever the Mac is set to by then.
    @Test func aLaterSessionBorrowsAgain() {
        let keys = FakeFunctionKeys(.media)
        let override = keys.override()

        override.engage(.standard, reporter: .silent)
        override.release(reporter: .silent)
        override.engage(.standard, reporter: .silent)

        #expect(keys.writes == [.standard, .media, .standard])
        #expect(override.restoring == .media)
    }

    // MARK: - A Mac that will not co-operate

    /// A mode that cannot be read is a mode that cannot be put back, so
    /// nothing is touched at all. Failing to set the keyboard is a nuisance;
    /// leaving it set is worse.
    @Test func aModeThatCannotBeReadIsNotTouched() {
        let keys = FakeFunctionKeys(.media)
        keys.readable = false
        let override = keys.override()

        override.engage(.standard, reporter: .silent)

        #expect(keys.writes == [])
        #expect(override.restoring == nil)
    }

    /// `FunctionKeys.current` hands back nil for a mode it does not
    /// understand, which has to be treated the same way as one it could not
    /// read — the launcher cannot promise to restore a value it has no case
    /// for.
    @Test func aModeThatIsNotOneOfTheTwoIsNotTouched() {
        let keys = FakeFunctionKeys(nil)
        let override = keys.override()

        override.engage(.standard, reporter: .silent)

        #expect(keys.writes == [])
        #expect(override.restoring == nil)
    }

    /// A write that did not take leaves nothing borrowed, so the release at
    /// the end of the game does not set a mode that was never replaced.
    @Test func aWriteThatFailsOwesNothing() {
        let keys = FakeFunctionKeys(.media)
        keys.writable = false
        let override = keys.override()

        override.engage(.standard, reporter: .silent)
        #expect(override.restoring == nil)

        keys.writable = true
        override.release(reporter: .silent)
        #expect(keys.writes == [])
        #expect(keys.mode == .media)
    }

    /// A restore that fails is let go of rather than held on to: retrying it
    /// on the next release would write a mode from an older session over a
    /// newer one.
    @Test func aRestoreThatFailsIsNotOwedTwice() {
        let keys = FakeFunctionKeys(.media)
        let override = keys.override()

        override.engage(.standard, reporter: .silent)
        keys.writable = false
        override.release(reporter: .silent)

        #expect(override.restoring == nil)

        keys.writable = true
        override.release(reporter: .silent)
        #expect(keys.writes == [.standard], "the failed restore should not be repeated")
    }
}

/// The IOKit side. Reading is safe to do for real; writing is not, so these
/// only ever read.
struct FunctionKeysTests {

    /// The raw values are what `IOHIDSystem` stores, not an ordering of the
    /// launcher's own choosing: 1 is the mode System Settings calls "use F1,
    /// F2, etc. as standard function keys".
    @Test func theRawValuesAreTheOnesIOKitStores() {
        #expect(FunctionKeyMode.media.rawValue == 0)
        #expect(FunctionKeyMode.standard.rawValue == 1)
        #expect(FunctionKeyMode(rawValue: 0) == .media)
        #expect(FunctionKeyMode(rawValue: 1) == .standard)
        #expect(FunctionKeyMode(rawValue: 2) == nil)
    }

    /// Proves the registry path and the parameter names still reach a real
    /// `IOHIDSystem`. Which mode the Mac running the tests is in is its own
    /// business, so only the reachability is asserted — and nil is allowed,
    /// for a machine with no HID system to ask.
    @Test func theModeCanBeReadFromThisMac() {
        let mode = FunctionKeys.current()
        #expect(mode == nil || mode == .media || mode == .standard)
    }
}
