#if DEBUG
import AppKit
import CronBuddyCore
import SwiftUI

/// Debug builds only: drive the UI and capture the app's own windows for visual checks.
/// Enabled by CRONBUDDY_SNAPSHOT_DIR; commands arrive as "CronBuddyDebug" distributed notifications.
@MainActor
enum DebugHooks {
    static func install(model: AppModel) {
        guard let dir = ProcessInfo.processInfo.environment["CRONBUDDY_SNAPSHOT_DIR"] else { return }
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("CronBuddyDebug"), object: nil, queue: .main
        ) { note in
            let command = note.object as? String ?? ""
            MainActor.assumeIsolated { handle(command, model: model, dir: dir) }
        }
    }

    private static func handle(_ command: String, model: AppModel, dir: String) {
        let parts = command.split(separator: " ", maxSplits: 1).map(String.init)
        let argument = parts.count > 1 ? parts[1] : ""
        switch parts.first ?? "" {
        case "window": NotificationCenter.default.post(name: .openMainWindow, object: nil)
        case "select":
            switch argument {
            case "overview": model.selection = .overview
            case "activity": model.selection = .activity
            case "templates": model.selection = .templates
            case "external": model.selection = .external
            default: model.selection = .job(argument)
            }
        case "theme": UserDefaults.standard.set(argument, forKey: "theme")
        case "template": model.newJob(from: Templates.all.first { $0.id == argument })
        case "edit": if let job = model.job(argument) { model.edit(job) }
        case "close-sheet": model.editorRequest = nil
        case "run": if let job = model.job(argument) { model.runNow(job) }
        case "pause": if let job = model.job(argument) { model.setEnabled(false, for: job) }
        case "resume": if let job = model.job(argument) { model.setEnabled(true, for: job) }
        case "menubar": showMenuPreview(model: model)
        case "menubar-close": preview?.close(); preview = nil
        case "snap": snapshot(name: argument, dir: dir)
        default: break
        }
    }

    private static var preview: NSWindow?

    /// Renders the menu bar content in a plain window. Never clicks anything.
    private static func showMenuPreview(model: AppModel) {
        let theme = Theme.named(UserDefaults.standard.string(forKey: "theme") ?? Theme.system.id)
        let host = NSHostingView(rootView: MenuBarView().environment(model).themed(theme))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 600),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = "Menu preview"
        window.contentView = host
        window.setContentSize(host.fittingSize)
        window.center()
        window.orderFront(nil)
        preview = window
    }

    private static func snapshot(name: String, dir: String) {
        var index = 0
        for window in NSApp.windows where window.isVisible && window.frame.height > 60 {
            guard let view = window.contentView?.superview ?? window.contentView,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)
            else { continue }
            view.cacheDisplay(in: view.bounds, to: rep)
            guard let data = rep.representation(using: .png, properties: [:]) else { continue }
            let url = URL(fileURLWithPath: dir).appending(path: "\(name)-\(index).png")
            try? data.write(to: url)
            index += 1
        }
    }
}
#endif
