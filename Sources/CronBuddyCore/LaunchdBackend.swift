import Foundation

public enum LaunchdBackend {
    static var domain: String { "gui/\(getuid())" }

    /// cron jobs get an agent with no trigger of its own; their crontab line kickstarts it.
    public static func plistData(for job: Job, paths: Paths, launcher: Launcher = .wrapper) throws -> Data {
        var plist: [String: Any] = [
            "Label": paths.launchdLabel(for: job.id),
            "ProgramArguments": launcher.programArguments(jobID: job.id, paths: paths),
            "ProcessType": "Background",
        ]
        guard job.backend == .launchd else {
            return try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        }
        switch try job.schedule.launchdTrigger() {
        case .interval(let seconds):
            plist["StartInterval"] = seconds
        case .calendar(let entries):
            plist["StartCalendarInterval"] = entries.count == 1 ? entries[0] as Any : entries as Any
        case .runAtLoad:
            plist["RunAtLoad"] = true
        }
        return try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    }

    public static func isLoaded(id: String, paths: Paths) -> Bool {
        let result = try? Shell.run("/bin/launchctl", ["print", "\(domain)/\(paths.launchdLabel(for: id))"])
        return result?.status == 0
    }

    /// Writes the job's agent and (re)loads it. Skips work when nothing changed.
    public static func install(_ job: Job, paths: Paths, launcher: Launcher = .wrapper) throws {
        let data = try plistData(for: job, paths: paths, launcher: launcher)
        let url = paths.plist(for: job.id)
        let unchanged = (try? Data(contentsOf: url)) == data
        if unchanged, isLoaded(id: job.id, paths: paths) { return }

        try FileManager.default.createDirectory(at: paths.launchAgents, withIntermediateDirectories: true)
        bootout(id: job.id, paths: paths)
        try data.write(to: url, options: .atomic)

        let result = try Shell.run("/bin/launchctl", ["bootstrap", domain, url.path])
        guard result.status == 0 else {
            throw CronBuddyError("launchd refused “\(job.name)”: \(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
    }

    public static func uninstall(id: String, paths: Paths) {
        bootout(id: id, paths: paths)
        try? FileManager.default.removeItem(at: paths.plist(for: id))
    }

    private static func bootout(id: String, paths: Paths) {
        _ = try? Shell.run("/bin/launchctl", ["bootout", "\(domain)/\(paths.launchdLabel(for: id))"])
    }

    /// Ids of CronBuddy agents present on disk.
    public static func installedIDs(paths: Paths) -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: paths.launchAgents.path)) ?? []
        return names.compactMap { name in
            guard name.hasPrefix(Paths.labelPrefix), name.hasSuffix(".plist") else { return nil }
            return String(name.dropFirst(Paths.labelPrefix.count).dropLast(".plist".count))
        }
    }
}

public enum ShortcutsCatalog {
    public static func names() -> [String] {
        guard let result = try? Shell.run("/usr/bin/shortcuts", ["list"]), result.status == 0 else { return [] }
        return result.stdout
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
}
