import AppKit
import SwiftUI

/// Tracks whether ⌥ is held, so the menu can keep its rarely-used entries out
/// of the way until someone asks for them — the same gesture macOS itself uses
/// to reveal alternate menu items.
///
/// The flag is seeded from the current state and kept current by a local
/// flags-changed monitor, which makes SwiftUI rebuild the menu the moment the
/// key goes down — reading `NSEvent.modifierFlags` only while the menu is being
/// built would miss a key pressed after the view was laid out.
@MainActor
final class ModifierKeys: ObservableObject {
    @Published private(set) var optionHeld = NSEvent.modifierFlags.contains(.option)

    private var monitor: Any?

    /// Local, not global: a global monitor would ask for accessibility rights,
    /// and the menu can only be opened while this app is frontmost anyway.
    /// The monitor lives as long as the window that starts it.
    func watch() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            let held = event.modifierFlags.contains(.option)
            if self?.optionHeld != held { self?.optionHeld = held }
            return event
        }
    }
}
