import Foundation

public struct Paths: Sendable {
    public static let labelPrefix = "com.lucasrafaldini.cronbuddy.job."
    /// Scheduled jobs inherit an almost empty environment, so give them a sensible PATH.
    public static let defaultPATH =
        "/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

    public let home: URL

    public init(home: URL) {
        self.home = home
    }

    public static var standard: Paths {
        Paths(home: FileManager.default.homeDirectoryForCurrentUser)
    }

    public var support: URL { home.appending(path: "Library/Application Support/CronBuddy", directoryHint: .isDirectory) }
    public var jobsFile: URL { support.appending(path: "jobs.json") }
    public var actionsDir: URL { support.appending(path: "actions", directoryHint: .isDirectory) }
    public var shim: URL { support.appending(path: "bin/cb-run") }
    public var logs: URL { home.appending(path: "Library/Logs/CronBuddy", directoryHint: .isDirectory) }
    public var launchAgents: URL { home.appending(path: "Library/LaunchAgents", directoryHint: .isDirectory) }

    public func actionScript(for id: String) -> URL { actionsDir.appending(path: "\(id).sh") }
    public func logDir(for id: String) -> URL { logs.appending(path: id, directoryHint: .isDirectory) }
    public func runsFile(for id: String) -> URL { logDir(for: id).appending(path: "runs.jsonl") }
    public func runningMarker(for id: String) -> URL { logDir(for: id).appending(path: ".running") }
    public func launchdLabel(for id: String) -> String { Self.labelPrefix + id }
    public func plist(for id: String) -> URL { launchAgents.appending(path: "\(launchdLabel(for: id)).plist") }
}
