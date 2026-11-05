import AppKit
import Foundation
import ServiceManagement
import UserNotifications

/// Notifications and login items only work from a bundled .app, not from `swift run`.
enum AppBundle {
    static var isBundled: Bool {
        Bundle.main.bundleURL.pathExtension == "app" && Bundle.main.bundleIdentifier != nil
    }
}

enum Notifier {
    static func requestAuthorization() {
        guard AppBundle.isBundled else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func post(title: String, body: String, failed: Bool) {
        guard AppBundle.isBundled else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = failed ? .defaultCritical : .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

enum LoginItem {
    static var isEnabled: Bool {
        AppBundle.isBundled && SMAppService.mainApp.status == .enabled
    }

    static func set(_ enabled: Bool) throws {
        guard AppBundle.isBundled else {
            throw NSError(domain: "CronBuddy", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Open at login only works from the installed CronBuddy.app.",
            ])
        }
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}

enum Finder {
    static func reveal(_ url: URL) {
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            NSWorkspace.shared.open(url)
        }
    }

    static func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    static func openShortcut(named name: String) {
        var components = URLComponents()
        components.scheme = "shortcuts"
        components.host = "open-shortcut"
        components.queryItems = [URLQueryItem(name: "name", value: name)]
        if let url = components.url { NSWorkspace.shared.open(url) }
    }

    static func openShortcutsApp() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.shortcuts") {
            NSWorkspace.shared.open(url)
        }
    }
}
