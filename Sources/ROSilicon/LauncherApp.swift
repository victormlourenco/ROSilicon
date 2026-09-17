import AppKit
import SwiftUI

@main
struct ROSiliconApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = LauncherModel()

    var body: some Scene {
        Window("ROSilicon", id: "launcher") {
            ContentView()
                .environmentObject(model)
        }
        // No title bar: the content view draws its own header and the backdrop
        // the glass sits on runs the full height of the window. The traffic
        // lights stay, so the header leaves room for them.
        //
        // The minimum size is the content's own, and the content view sets it —
        // it changes with the log, which only that view knows about.
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appInfo) {
                Button(Strings.installOrRepairCommand) { model.install() }
                    .keyboardShortcut("i")
                    .disabled(model.phase.isBusy)
                Button(Strings.play) { model.play() }
                    .keyboardShortcut("r")
                    .disabled(!model.canPlay)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
