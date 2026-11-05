import Foundation

public enum Backend: String, Codable, CaseIterable, Identifiable, Sendable {
    case launchd
    case cron

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .launchd: "launchd"
        case .cron: "cron"
        }
    }

    public var explanation: String {
        switch self {
        case .launchd:
            "macOS-native scheduler. Catches up on runs missed while the Mac slept. Recommended."
        case .cron:
            "Classic Unix crontab. Skips runs missed during sleep; may need Full Disk Access for protected folders."
        }
    }
}

public enum JobAction: Codable, Hashable, Sendable {
    case shell(command: String)
    /// Any executable file: shell, Python, Ruby, AppleScript (.scpt), JXA (.js) or Automator (.workflow).
    case script(path: String)
    case appleScript(source: String)
    case shortcut(name: String)

    public enum Kind: String, CaseIterable, Identifiable, Sendable {
        case shell, script, appleScript, shortcut
        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .shell: "Command"
            case .script: "Script file"
            case .appleScript: "AppleScript"
            case .shortcut: "Shortcut"
            }
        }

        public var symbol: String {
            switch self {
            case .shell: "terminal"
            case .script: "doc.text"
            case .appleScript: "applescript"
            case .shortcut: "square.stack.3d.up"
            }
        }
    }

    public var kind: Kind {
        switch self {
        case .shell: .shell
        case .script: .script
        case .appleScript: .appleScript
        case .shortcut: .shortcut
        }
    }

    public static func empty(_ kind: Kind) -> JobAction {
        switch kind {
        case .shell: .shell(command: "")
        case .script: .script(path: "")
        case .appleScript: .appleScript(source: "")
        case .shortcut: .shortcut(name: "")
        }
    }

    public var subtitle: String {
        switch self {
        case .shell(let command):
            let firstLine = command.split(separator: "\n").first.map(String.init) ?? ""
            return firstLine.isEmpty ? "Command" : firstLine
        case .script(let path):
            return path.isEmpty ? "Script" : (path as NSString).lastPathComponent
        case .appleScript:
            return "AppleScript"
        case .shortcut(let name):
            return name.isEmpty ? "Shortcut" : "Shortcut · \(name)"
        }
    }

    public var isEmpty: Bool {
        switch self {
        case .shell(let s), .appleScript(let s), .shortcut(let s), .script(let s):
            s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}

public struct Job: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var action: JobAction
    public var schedule: Schedule
    public var backend: Backend
    public var isEnabled: Bool
    public var notifyOnFailure: Bool
    public var notifyOnSuccess: Bool
    public var environment: [String: String]
    public var createdAt: Date

    public init(
        id: String = Job.makeID(),
        name: String = "",
        action: JobAction = .shell(command: ""),
        schedule: Schedule = .daily(times: [TimeOfDay(hour: 9, minute: 0)]),
        backend: Backend = .launchd,
        isEnabled: Bool = true,
        notifyOnFailure: Bool = true,
        notifyOnSuccess: Bool = false,
        environment: [String: String] = [:],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.action = action
        self.schedule = schedule
        self.backend = backend
        self.isEnabled = isEnabled
        self.notifyOnFailure = notifyOnFailure
        self.notifyOnSuccess = notifyOnSuccess
        self.environment = environment
        self.createdAt = createdAt
    }

    public static func makeID() -> String {
        UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(10).lowercased()
    }

    /// Blocking problems that prevent saving.
    public var problems: [String] {
        var problems: [String] = []
        if name.trimmingCharacters(in: .whitespaces).isEmpty { problems.append("Give the job a name.") }
        if action.isEmpty {
            switch action.kind {
            case .shell: problems.append("Enter a command to run.")
            case .script: problems.append("Choose a script file.")
            case .appleScript: problems.append("Write the AppleScript to run.")
            case .shortcut: problems.append("Pick a Shortcut.")
            }
        }
        for key in environment.keys where !Job.isValidEnvironmentName(key) {
            problems.append("“\(key)” isn’t a valid environment variable name.")
        }
        if let message = schedule.validationMessage {
            problems.append(message)
        } else {
            switch backend {
            case .cron:
                if schedule.cronExpressions() == nil {
                    problems.append("cron can’t repeat at this interval. Use launchd, or an interval that divides an hour or a day evenly.")
                }
            case .launchd:
                do { _ = try schedule.launchdTrigger() } catch {
                    problems.append(error.localizedDescription)
                }
            }
        }
        return problems
    }

    /// Non-blocking caveats worth showing in the editor.
    public var warnings: [String] {
        var warnings: [String] = []
        if backend == .cron, case .atLogin = schedule {
            warnings.append("cron runs @reboot jobs when the Mac boots, not when you log in.")
        }
        if case .monthly(let days, _) = schedule, days.contains(where: { $0 > 28 }) {
            warnings.append("Months without that day are skipped.")
        }
        if case .script(let path) = action, !path.isEmpty, !FileManager.default.fileExists(atPath: path) {
            warnings.append("The script file doesn’t exist at that path.")
        }
        return warnings
    }

    public static func isValidEnvironmentName(_ name: String) -> Bool {
        guard let first = name.unicodeScalars.first,
              CharacterSet.letters.contains(first) || first == "_"
        else { return false }
        return name.unicodeScalars.allSatisfy {
            ($0.isASCII && CharacterSet.alphanumerics.contains($0)) || $0 == "_"
        }
    }
}
