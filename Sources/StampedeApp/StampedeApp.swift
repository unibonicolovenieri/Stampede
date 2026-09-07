import AppKit
import StampedeCore
import SwiftUI

@main
struct StampedeApp: App {
    @StateObject private var model = AppModel()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 1040, minHeight: 700)
        }
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appInfo) {
                Button("Ricarica i preset") { model.reloadPresets() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                Button("Rileggi i remote di Drive") { model.refreshRemotes() }
            }
        }
    }
}

/// Un'app a finestra singola: quando si chiude la finestra si esce, come fanno
/// Anteprima o Calcolatrice, invece di restare in un Dock vuoto.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}
