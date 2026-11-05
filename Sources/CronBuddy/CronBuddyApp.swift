import AppKit
import SwiftUI

extension Notification.Name {
    static let openMainWindow = Notification.Name("CronBuddyOpenMainWindow")
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu bar first: no Dock icon until the main window opens.
        NSApp.setActivationPolicy(.accessory)
    }

    /// Opening CronBuddy again from Finder or Spotlight shows the main window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        NotificationCenter.default.post(name: .openMainWindow, object: nil)
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

struct CronBuddyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel()
    @AppStorage("theme") private var themeID = Theme.system.id

    private var theme: Theme { Theme.named(themeID) }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(model)
                .themed(theme)
        } label: {
            MenuBarLabel()
                .environment(model)
        }
        .menuBarExtraStyle(.window)

        Window("CronBuddy", id: "main") {
            MainWindow()
                .environment(model)
                .themed(theme)
        }
        .defaultSize(width: 1100, height: 720)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Job") { model.newJob() }
                    .keyboardShortcut("n")
            }
        }

        Settings {
            SettingsView()
                .environment(model)
                .themed(theme)
        }
    }
}
