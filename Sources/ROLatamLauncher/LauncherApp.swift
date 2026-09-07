import AppKit
import SwiftUI

@main
struct ROLatamLauncherApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = LauncherModel()

    var body: some Scene {
        Window("RO LATAM", id: "launcher") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 640, minHeight: 560)
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appInfo) {
                Button("Install or Repair") { model.install() }
                    .keyboardShortcut("i")
                    .disabled(model.phase.isBusy)
                Button("Play") { model.play() }
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
