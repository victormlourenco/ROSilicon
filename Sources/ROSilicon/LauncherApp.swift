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
        // The content view owns both the minimum size and the brief exact size
        // used while its log opens or closes. With no maximum in steady state,
        // the window remains freely resizable.
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
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
