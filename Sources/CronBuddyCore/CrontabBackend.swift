import Foundation

/// A crontab line CronBuddy doesn't manage, offered for adoption.
public struct ExternalCronEntry: Hashable, Identifiable, Sendable {
    public let line: String
    public let schedule: String
    public let command: String
    public let comment: String?
    /// Written by CronBuddy 1.x, which ran commands through the app with `--run`.
    public let isLegacyCronBuddy: Bool

    public var id: String { line }
}

public enum CrontabBackend {
    public static let marker = "# cronbuddy:"

    public static func read() throws -> String {
        let result = try Shell.run("/usr/bin/crontab", ["-l"])
        if result.status == 0 { return result.stdout }
        if result.stderr.contains("no crontab") { return "" }
        throw CronBuddyError("Couldn’t read your crontab: \(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))")
    }

    public static func write(_ text: String) throws {
        let result = try Shell.run("/usr/bin/crontab", ["-"], input: text)
        guard result.status == 0 else {
            throw CronBuddyError("Couldn’t update your crontab: \(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
    }

    public static func lines(for job: Job, paths: Paths, launcher: Launcher = .wrapper) -> [String] {
        guard job.backend == .cron, job.isEnabled, let expressions = job.schedule.cronExpressions() else {
            return []
        }
        let command = launcher.cronCommand(jobID: job.id, paths: paths)
        return expressions.map { "\($0) \(command) \(marker)\(job.id)" }
    }

    /// Replaces every CronBuddy-managed line, leaving the user's own entries untouched.
    public static func merged(existing: String, jobs: [Job], paths: Paths, launcher: Launcher = .wrapper) -> String {
        var kept = existing
            .components(separatedBy: "\n")
            .filter { !$0.contains(marker) }
        while let last = kept.last, last.trimmingCharacters(in: .whitespaces).isEmpty {
            kept.removeLast()
        }
        let managed = jobs.flatMap { lines(for: $0, paths: paths, launcher: launcher) }
        let all = kept + managed
        return all.isEmpty ? "" : all.joined(separator: "\n") + "\n"
    }

    /// Re-writes the crontab only when its managed section actually changes.
    public static func sync(jobs: [Job], paths: Paths, launcher: Launcher = .wrapper) throws {
        let existing = try read()
        let updated = merged(existing: existing, jobs: jobs, paths: paths, launcher: launcher)
        // Never rewrite the crontab over trailing whitespace alone.
        if updated.trimmingCharacters(in: .whitespacesAndNewlines) != existing.trimmingCharacters(in: .whitespacesAndNewlines) {
            try write(updated)
        }
    }

    public static func externalEntries(in text: String) -> [ExternalCronEntry] {
        text.components(separatedBy: "\n").compactMap { raw in
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#"), !line.contains(marker) else { return nil }

            let tokens = line.split(separator: " ", omittingEmptySubsequences: true)
            let scheduleTokenCount: Int
            if let first = tokens.first, first.hasPrefix("@") {
                scheduleTokenCount = 1
            } else {
                // Environment assignments such as MAILTO=… or PATH=…
                if let first = tokens.first, first.contains("=") { return nil }
                scheduleTokenCount = 5
            }
            guard tokens.count > scheduleTokenCount else { return nil }

            let schedule = tokens.prefix(scheduleTokenCount).joined(separator: " ")
            guard schedule.lowercased() == "@reboot" || CronExpression.isValid(schedule) else { return nil }

            var command = tokens.dropFirst(scheduleTokenCount).joined(separator: " ")
            var comment: String?
            if let range = command.range(of: " # ", options: .backwards) {
                comment = String(command[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                command = String(command[..<range.lowerBound])
            }
            var isLegacy = false
            if let unwrapped = LegacyRun.unwrap(command) {
                command = unwrapped.command
                comment = unwrapped.name ?? comment
                isLegacy = true
            }
            return ExternalCronEntry(
                line: raw, schedule: schedule, command: command, comment: comment, isLegacyCronBuddy: isLegacy
            )
        }
    }

    public static func removing(_ entry: ExternalCronEntry, from text: String) -> String {
        var lines = text.components(separatedBy: "\n")
        if let index = lines.firstIndex(of: entry.line) {
            lines.remove(at: index)
        }
        return lines.joined(separator: "\n")
    }
}
