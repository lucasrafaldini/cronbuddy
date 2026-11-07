import Foundation

/// Persists job definitions and keeps cron/launchd in step with them.
public struct JobStore: Sendable {
    public let paths: Paths
    public let launcher: Launcher

    public init(paths: Paths = .standard, launcher: Launcher = .wrapper) {
        self.paths = paths
        self.launcher = launcher
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    public func load() throws -> [Job] {
        guard FileManager.default.fileExists(atPath: paths.jobsFile.path) else { return [] }
        let data = try Data(contentsOf: paths.jobsFile)
        return try Self.decoder.decode([Job].self, from: data)
    }

    public func save(_ jobs: [Job]) throws {
        try FileManager.default.createDirectory(at: paths.support, withIntermediateDirectories: true)
        try Self.encoder.encode(jobs).write(to: paths.jobsFile, options: .atomic)
    }

    /// Installs one job into its backend (or removes it when paused).
    /// `allJobs` is needed because the crontab is rewritten as a whole.
    public func apply(_ job: Job, allJobs: [Job], previous: Job?) throws {
        try RunWrapper.install(paths: paths)
        try ActionScript.write(job, to: paths.actionScript(for: job.id))

        if let previous, previous.backend != job.backend {
            try remove(fromBackendOf: previous, allJobs: allJobs)
        }

        // Every job has a launch agent: launchd jobs schedule through it, cron jobs are kickstarted into it.
        if job.isEnabled {
            try LaunchdBackend.install(job, paths: paths)
        } else {
            LaunchdBackend.uninstall(id: job.id, paths: paths)
        }
        if job.backend == .cron {
            try CrontabBackend.sync(jobs: allJobs, paths: paths)
        }
    }

    public func delete(_ job: Job, remaining: [Job]) throws {
        try remove(fromBackendOf: job, allJobs: remaining)
        try? FileManager.default.removeItem(at: paths.actionScript(for: job.id))
        RunHistory.removeAll(jobID: job.id, paths: paths)
    }

    private func remove(fromBackendOf job: Job, allJobs: [Job]) throws {
        LaunchdBackend.uninstall(id: job.id, paths: paths)
        if job.backend == .cron {
            try CrontabBackend.sync(jobs: allJobs.filter { $0.id != job.id }, paths: paths)
        }
    }

    /// Brings backends in line with the saved definitions. Returns per-job failures.
    public func reconcile(_ jobs: [Job]) -> [String] {
        var failures: [String] = []
        do {
            try RunWrapper.install(paths: paths)
        } catch {
            return ["Couldn’t install the run wrapper: \(error.localizedDescription)"]
        }

        let ids = Set(jobs.map(\.id))
        for orphan in LaunchdBackend.installedIDs(paths: paths) where !ids.contains(orphan) {
            LaunchdBackend.uninstall(id: orphan, paths: paths)
        }

        for job in jobs {
            do {
                try ActionScript.write(job, to: paths.actionScript(for: job.id))
                if job.isEnabled {
                    try LaunchdBackend.install(job, paths: paths, launcher: launcher)
                } else if FileManager.default.fileExists(atPath: paths.plist(for: job.id).path) {
                    LaunchdBackend.uninstall(id: job.id, paths: paths)
                }
            } catch {
                failures.append("\(job.name): \(error.localizedDescription)")
            }
        }

        do {
            try CrontabBackend.sync(jobs: jobs, paths: paths)
        } catch {
            failures.append(error.localizedDescription)
        }
        return failures
    }
}
