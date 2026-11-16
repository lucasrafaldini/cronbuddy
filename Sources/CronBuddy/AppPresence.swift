import AppKit

/// CronBuddy lives in the menu bar as an accessory app: no Dock icon, no menus.
/// While its main or Settings window is open it becomes a regular app, so the
/// window comes to the front and the menu bar (CronBuddy, File, Edit…) works.
@MainActor
enum AppPresence {
    /// Becomes a regular app, runs `open` (an `openWindow` or `openSettings` call)
    /// and brings the window it opened to the front.
    static func show(_ open: @escaping @MainActor () -> Void = {}) {
        Task { @MainActor in
            let wasAgent = NSApp.activationPolicy() != .regular
            if wasAgent { NSApp.setActivationPolicy(.regular) }
            activate()
            open()
            // SwiftUI creates the window asynchronously; front it once it exists, even if
            // macOS declined the activation request (cooperative activation, macOS 14+).
            try? await Task.sleep(for: .milliseconds(150))
            frontWindow()

            guard wasAgent else { return }
            // AppKit bug (FB7743313): an agent app (LSUIElement) that turns regular gets a
            // menu bar that draws but ignores clicks until the app is activated again.
            // Hand activation to the Dock for a moment and take it back.
            if let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first {
                dock.activate()
                try? await Task.sleep(for: .milliseconds(200))
                activate()
                frontWindow()
            }
        }
    }

    private static func activate() {
        // The forceful variant: plain activate() is only a request macOS may decline.
        NSApp.activate(ignoringOtherApps: true)
    }

    private static func frontWindow() {
        guard let window = NSApp.orderedWindows.first(where: isAppWindow) else { return }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    /// Back to the menu bar once the last CronBuddy window has closed.
    static func windowWillClose(_ closing: NSWindow) {
        guard isAppWindow(closing) else { return }
        DispatchQueue.main.async {
            let stillOpen = NSApp.windows.contains { $0 !== closing && isAppWindow($0) }
            if !stillOpen { NSApp.setActivationPolicy(.accessory) }
        }
    }

    /// Titled, visible windows: the main window and Settings. The menu bar panel is an NSPanel.
    private static func isAppWindow(_ window: NSWindow) -> Bool {
        window.isVisible && window.styleMask.contains(.titled) && !(window is NSPanel)
    }
}
