import Foundation

/// How cron and launchd start a job.
public enum Launcher: Hashable, Sendable {
    /// The zsh wrapper in Application Support. Used when running unbundled (`swift run`).
    case wrapper
    /// CronBuddy.app's own executable in run mode. The app becomes the process macOS
    /// holds responsible, so one Full Disk Access grant to CronBuddy covers every job.
    case app(path: String)

    public static let runJobFlag = "--run-job"

    func programArguments(jobID: String, paths: Paths) -> [String] {
        switch self {
        case .wrapper:
            [paths.shim.path, jobID]
        case .app(let path):
            [path + "/Contents/MacOS/CronBuddy", Self.runJobFlag, jobID]
        }
    }

    /// cron decides when; launchd starts the job's agent. Running through launchd keeps
    /// CronBuddy responsible for the job's permissions without going through LaunchServices,
    /// which would treat the run as the app itself and swallow attempts to open the window.
    static func cronCommand(jobID: String, paths: Paths) -> String {
        "/bin/launchctl kickstart \(LaunchdBackend.domain)/\(paths.launchdLabel(for: jobID))"
    }
}

/// Run mode: executes a saved job's action script and records the run, like the wrapper does.
public enum ScheduledRun {
    public static func run(jobID: String, paths: Paths, trigger: RunRecord.Trigger = .schedule) -> Int32 {
        let fm = FileManager.default
        let dir = paths.logDir(for: jobID)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)

        let start = Date()
        let logFile = "\(RunHistory.stamp(start))-\(getpid()).log"
        let logURL = dir.appending(path: logFile)
        fm.createFile(atPath: logURL.path, contents: nil)

        let marker = paths.runningMarker(for: jobID)
        try? Data("\(getpid()) \(start.timeIntervalSince1970)".utf8).write(to: marker)
        defer { try? fm.removeItem(at: marker) }

        let action = paths.actionScript(for: jobID)
        let code: Int32
        if !fm.fileExists(atPath: action.path) {
            try? Data("CronBuddy: no action script at \(action.path)\n".utf8).write(to: logURL)
            code = 127
        } else if let handle = try? FileHandle(forWritingTo: logURL) {
            code = execute(arguments: ["/bin/zsh", action.path], output: handle)
            try? handle.close()
        } else {
            code = 126
        }

        RunHistory.appendLine(
            jobID: jobID, start: start, end: Date(), exitCode: code, logFile: logFile, trigger: trigger, paths: paths
        )
        return code
    }

    static func execute(arguments: [String], output: FileHandle) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: arguments[0])
        process.arguments = Array(arguments.dropFirst())
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = Paths.defaultPATH + ":" + (environment["PATH"] ?? "")
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = output
        do {
            try process.run()
        } catch {
            output.write(Data("CronBuddy: couldn’t start: \(error.localizedDescription)\n".utf8))
            return 126
        }
        process.waitUntilExit()
        return process.terminationReason == .uncaughtSignal ? 128 + process.terminationStatus : process.terminationStatus
    }
}

/// Compatibility with CronBuddy 1.x crontab lines:
/// `/usr/bin/open -g -W -n -a CronBuddy.app --args --run '<command>' --name '<job>'`.
public enum LegacyRun {
    public static let runFlag = "--run"
    public static let nameFlag = "--name"

    public static func parse(_ arguments: [String]) -> (command: String, name: String)? {
        guard let index = arguments.firstIndex(of: runFlag) else { return nil }
        let command = index + 1 < arguments.count ? arguments[index + 1] : ""
        var name = "job"
        if let n = arguments.firstIndex(of: nameFlag), n + 1 < arguments.count {
            name = arguments[n + 1]
        }
        return (command, name)
    }

    /// Appends to `~/CronBuddyScripts/logs/cronbuddy_<job>_<date>.log`, exactly as 1.x did.
    public static func run(command: String, name: String, home: URL, now: Date = Date()) -> Int32 {
        let logs = home.appending(path: "CronBuddyScripts/logs", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        let url = logs.appending(path: logFileName(name: name, now: now))
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return 126 }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        handle.write(Data("=== \(name) — \(formatter.string(from: now)) ===\n$ \(command)\n".utf8))
        guard !command.isEmpty else {
            handle.write(Data("No command given.\n=== exit 2 ===\n\n".utf8))
            return 2
        }
        let code = ScheduledRun.execute(arguments: ["/bin/bash", "-lc", command], output: handle)
        handle.write(Data("=== exit \(code) ===\n\n".utf8))
        return code
    }

    static func logFileName(name: String, now: Date) -> String {
        var slug = ""
        var lastWasSeparator = false
        for scalar in name.unicodeScalars {
            if scalar.isASCII && (CharacterSet.alphanumerics.contains(scalar) || scalar == "_" || scalar == "-") {
                slug.unicodeScalars.append(scalar)
                lastWasSeparator = false
            } else if !lastWasSeparator {
                slug += "_"
                lastWasSeparator = true
            }
        }
        slug = slug.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return "cronbuddy_\(slug.isEmpty ? "job" : slug)_\(formatter.string(from: now)).log"
    }

    /// The original command and job name inside a 1.x wrapped crontab command.
    public static func unwrap(_ command: String) -> (command: String, name: String?)? {
        let prefix = "/usr/bin/open -g -W -n -a "
        let trimmed = command.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix(prefix),
              let words = ShellWords.split(String(trimmed.dropFirst(prefix.count))),
              words.count >= 4, words[1] == "--args", words[2] == runFlag
        else { return nil }
        let rest = Array(words.dropFirst(3))
        var name: String?
        if let n = rest.firstIndex(of: nameFlag), n + 1 < rest.count { name = rest[n + 1] }
        return (rest[0], name)
    }
}

/// POSIX shell word splitting with single quotes, double quotes and backslash escapes.
public enum ShellWords {
    public static func split(_ text: String) -> [String]? {
        var words: [String] = []
        var current = ""
        var inWord = false
        var iterator = Array(text).makeIterator()

        while let c = iterator.next() {
            switch c {
            case " ", "\t", "\n":
                if inWord {
                    words.append(current)
                    current = ""
                    inWord = false
                }
            case "'":
                inWord = true
                var closed = false
                while let q = iterator.next() {
                    if q == "'" { closed = true; break }
                    current.append(q)
                }
                if !closed { return nil }
            case "\"":
                inWord = true
                var closed = false
                while let q = iterator.next() {
                    if q == "\"" { closed = true; break }
                    if q == "\\", let escaped = iterator.next() {
                        if "\"\\$`".contains(escaped) {
                            current.append(escaped)
                        } else {
                            current.append(q)
                            current.append(escaped)
                        }
                    } else {
                        current.append(q)
                    }
                }
                if !closed { return nil }
            case "\\":
                inWord = true
                guard let escaped = iterator.next() else { return nil }
                current.append(escaped)
            default:
                inWord = true
                current.append(c)
            }
        }
        if inWord { words.append(current) }
        return words
    }
}
