import AppKit
import Foundation
import IOKit
import IOKit.hidsystem

/// Which way the top row of the keyboard reads — the setting System Settings
/// calls "Use F1, F2, etc. keys as standard function keys".
///
/// The raw values are the ones `IOHIDSystem` stores under `HIDFKeyMode`, so
/// they are the wire format as much as the launcher's own preference.
enum FunctionKeyMode: Int, Sendable {
    /// F1 dims the screen, fn+F1 is F1. What a Mac does out of the box.
    case media = 0
    /// F1 is F1, fn+F1 dims the screen. What the game's hotkey bars want.
    case standard = 1
}

/// The system-wide function key mode, read and written through IOKit.
///
/// This is `IOHIDSystem`'s `HIDFKeyMode` parameter, reached the way
/// [Fluor](https://github.com/Pyroh/Fluor) reaches it — its `FKeyManager`, in
/// turn derived from `fntoggle`. Neither the read nor the write needs any
/// privilege: the parameter connection is one macOS hands to whoever asks,
/// which is how System Settings' own checkbox gets there.
///
/// Every call returns rather than throws. The launcher treats the keyboard as
/// a convenience — a Mac that will not hand over its HID parameters must not
/// be a Mac that cannot start the game.
enum FunctionKeys {
    /// `IOHIDSystem` itself, or 0 when it is not there. Its path in the
    /// registry is fixed, so looking it up by path rather than by matching
    /// dictionary keeps this to a single call.
    ///
    /// Fluor asks `IOMainPort` for a port first; the default one does as well
    /// and is a constant, which keeps this clear of the global `bootstrap_port`
    /// that Swift 6 will not let a concurrent context read.
    private static func system() -> io_registry_entry_t {
        IORegistryEntryFromPath(kIOMainPortDefault, "IOService:/IOResources/IOHIDSystem")
    }

    /// The mode in force, or nil when it could not be read — an unknown value
    /// included, since a mode the launcher does not understand is not one it
    /// can promise to put back.
    static func current() -> FunctionKeyMode? {
        let entry = system()
        guard entry != 0 else { return nil }
        defer { IOObjectRelease(entry) }

        guard let parameters = IORegistryEntryCreateCFProperty(
            entry, kIOHIDParametersKey as CFString, kCFAllocatorDefault, 0
        )?.takeRetainedValue() as? [String: Any],
            let raw = parameters[kIOHIDFKeyModeKey] as? Int
        else { return nil }
        return FunctionKeyMode(rawValue: raw)
    }

    /// Sets the mode for the whole Mac, every keyboard attached to it
    /// included. Returns whether it took.
    ///
    /// The change is live and it outlives this process, which is why the
    /// override above is careful to put back what it found.
    @discardableResult
    static func set(_ mode: FunctionKeyMode) -> Bool {
        let entry = system()
        guard entry != 0 else { return false }
        defer { IOObjectRelease(entry) }

        var connection: io_connect_t = 0
        guard IOServiceOpen(
            entry, mach_task_self_, UInt32(kIOHIDParamConnectType), &connection
        ) == KERN_SUCCESS else { return false }
        defer { IOServiceClose(connection) }

        return IOHIDSetCFTypeParameter(
            connection, kIOHIDFKeyModeKey as CFString, mode.rawValue as CFNumber) == KERN_SUCCESS
    }
}

/// Holds the function keys in one mode while the game runs, and puts the Mac
/// back the way it was afterwards.
///
/// The client reads F1–F12 as its hotkey bars, so on a Mac left at the default
/// every skill key dims the screen or skips a track instead. Flipping the
/// setting by hand works, but it is a setting for the whole Mac and it stays
/// flipped — the brightness keys are then gone from every other app until it
/// is flipped back. So the launcher borrows it: it switches on the way into a
/// game and switches back when the last client closes.
///
/// What it borrows is remembered in `restoring`, not assumed: someone who
/// already keeps their Mac on standard function keys has nothing done to them
/// and nothing put back. A mode that could not be read is a mode that cannot
/// be restored, so nothing is touched at all.
///
/// One thing works in the launcher's favour: the write is live only. macOS
/// keeps the reader's own choice in `com.apple.keyboard.fnState`, and setting
/// the HID parameter does not touch it — so a launcher that is killed outright,
/// with no chance to put anything back, still loses to the next login. The
/// restore below is what makes it right within the session; that is the floor
/// under it.
///
/// The IOKit calls are injected so the tests can drive the whole state machine
/// without a Mac's keyboard changing under the person running them.
@MainActor
final class FunctionKeyOverride {
    typealias Read = @MainActor () -> FunctionKeyMode?
    typealias Write = @MainActor (FunctionKeyMode) -> Bool

    private let read: Read
    private let write: Write
    /// What was in force before the override went on, and what `release` puts
    /// back. Nil whenever there is nothing owed — never engaged, engaged onto
    /// a Mac already in the wanted mode, or already released.
    private(set) var restoring: FunctionKeyMode?

    private var terminationObserver: (any NSObjectProtocol)?

    init(read: @escaping Read = FunctionKeys.current,
         write: @escaping Write = FunctionKeys.set) {
        self.read = read
        self.write = write
    }

    /// Puts the keyboard in `mode`, remembering what it replaced.
    ///
    /// Engaging twice does nothing the second time: two clients running at
    /// once share one override, and the mode to put back is the one from
    /// before the first of them.
    func engage(_ mode: FunctionKeyMode, reporter: Reporter) {
        guard restoring == nil else { return }
        guard let previous = read() else {
            Task { await reporter.log(Strings.logFunctionKeysUnavailable) }
            return
        }
        // Already theirs to begin with: say nothing, owe nothing.
        guard previous != mode else { return }
        guard write(mode) else {
            Task { await reporter.log(Strings.logFunctionKeysUnavailable) }
            return
        }
        restoring = previous
        watchForTermination()
        Task { await reporter.log(Strings.logFunctionKeysStandard) }
    }

    /// Puts back whatever was in force before. A no-op when nothing is owed,
    /// so the last of several clients to close is the one that restores.
    func release(reporter: Reporter) {
        guard let previous = restoring else { return }
        restoring = nil
        stopWatchingForTermination()
        guard write(previous) else {
            Task { await reporter.log(Strings.logFunctionKeysNotRestored) }
            return
        }
        Task { await reporter.log(Strings.logFunctionKeysRestored) }
    }

    /// Quitting the launcher mid-game must not leave the Mac switched over:
    /// the game goes down with it, and the brightness keys have to come back.
    /// There is no window left to log to by then, so this one is silent.
    ///
    /// `willTerminate` is delivered on the main thread and the restore is a
    /// pair of synchronous IOKit calls, so it finishes before the process does
    /// — which a `Task` scheduled here would not.
    private func watchForTermination() {
        guard terminationObserver == nil else { return }
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let previous = self.restoring else { return }
                self.restoring = nil
                _ = self.write(previous)
            }
        }
    }

    private func stopWatchingForTermination() {
        guard let terminationObserver else { return }
        NotificationCenter.default.removeObserver(terminationObserver)
        self.terminationObserver = nil
    }
}
