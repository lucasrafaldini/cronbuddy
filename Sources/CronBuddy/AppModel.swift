import AppKit
import CronBuddyCore
import Foundation
import Observation
import SwiftUI

enum JobStatus: Equatable {
    case running, succeeded, failed, paused, idle

    var label: String {
        switch self {
        case .running: "Running"
        case .succeeded: "Last run succeeded"
        case .failed: "Last run failed"
        case .paused: "Paused"
        case .idle: "Not run yet"
        }
    }

    func color(_ theme: Theme) -> Color {
        switch self {
        case .running: theme.accent
        case .succeeded: theme.success
        case .failed: theme.danger
        case .paused: theme.secondary.opacity(0.6)
        case .idle: theme.secondary
        }
    }
}

enum SidebarItem: Hashable {
    case overview, activity, templates, external
    case job(String)
}

struct UpcomingRun: Identifiable, Hashable {
    let job: Job
    let date: Date
    var id: String { "\(job.id)-\(date.timeIntervalSince1970)" }
}

/// Opens the editor on behalf of any view, including the menu bar.
struct EditorRequest: Identifiable {
    let id = UUID()
    let job: Job
    let isNew: Bool
}

@MainActor
@Observable
final class AppModel {
    let paths: Paths
    private let store: JobStore

    private(set) var jobs: [Job] = []
    private(set) var runs: [String: [RunRecord]] = [:]
    private(set) var runningScheduled: Set<String> = []
    private(set) var sessions: [String: RunSession] = [:]
    private(set) var externalEntries: [ExternalCronEntry] = []
    private(set) var now = Date()

    var selection: SidebarItem? = .overview
    var editorRequest: EditorRequest?
    var alertMessage: String?

    @ObservationIgnored private var runsFileDates: [String: Date] = [:]
    @ObservationIgnored private var lastNotifiedStart: [String: Date] = [:]
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var externalCheckedAt = Date.distantPast

    var logRetention: Int {
        get { max(10, UserDefaults.standard.integer(forKey: "logRetention").nonZero ?? 100) }
        set { UserDefaults.standard.set(newValue, forKey: "logRetention") }
    }

    init(paths: Paths = .standard) {
        self.paths = paths
        let launcher: Launcher = AppBundle.isBundled ? .app(path: Bundle.main.bundlePath) : .wrapper
        self.store = JobStore(paths: paths, launcher: launcher)

        do {
            jobs = try store.load()
        } catch {
            alertMessage = "Couldn’t read saved jobs: \(error.localizedDescription)"
        }
        refreshRuns(notify: false)
        refreshExternal()

        let snapshot = jobs
        let store = store
        Task.detached(priority: .utility) {
            let failures = store.reconcile(snapshot)
            if !failures.isEmpty {
                await MainActor.run { [weak self] in
                    self?.alertMessage = "Some jobs couldn’t be installed:\n" + failures.joined(separator: "\n")
                }
            }
        }

        let timer = Timer(timeInterval: 3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        Notifier.requestAuthorization()
        #if DEBUG
        DebugHooks.install(model: self)
        #endif
    }

    private func tick() {
        now = Date()
        refreshRuns(notify: true)
        if now.timeIntervalSince(externalCheckedAt) > 60 {
            refreshExternal()
        }
    }

    // MARK: Queries

    func job(_ id: String) -> Job? { jobs.first { $0.id == id } }

    func lastRun(_ job: Job) -> RunRecord? { runs[job.id]?.first }

    func status(_ job: Job) -> JobStatus {
        if runningScheduled.contains(job.id) || sessions[job.id]?.isRunning == true { return .running }
        if !job.isEnabled { return .paused }
        guard let last = lastRun(job) else { return .idle }
        return last.succeeded ? .succeeded : .failed
    }

    func nextDates(_ job: Job, count: Int) -> [Date] {
        guard job.isEnabled else { return [] }
        let lastScheduled = runs[job.id]?.first { $0.trigger == .schedule }?.start
        return job.schedule.nextDates(after: now, count: count, lastRun: lastScheduled)
    }

    /// Each job's next run once, soonest first, so frequent jobs don't crowd out the rest.
    func nextRunPerJob(limit: Int = .max) -> [UpcomingRun] {
        jobs
            .compactMap { job in nextDates(job, count: 1).first.map { UpcomingRun(job: job, date: $0) } }
            .sorted { $0.date < $1.date }
            .prefix(limit)
            .map { $0 }
    }

    var allRuns: [RunRecord] {
        runs.values.flatMap { $0 }.sorted { $0.start > $1.start }
    }

    var hasRecentFailure: Bool {
        jobs.contains { $0.isEnabled && status($0) == .failed }
    }

    var isAnythingRunning: Bool {
        !runningScheduled.isEmpty || sessions.values.contains { $0.isRunning }
    }

    var sortedJobs: [Job] {
        jobs.sorted { a, b in
            if a.isEnabled != b.isEnabled { return a.isEnabled }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    // MARK: Mutations

    func save(_ job: Job) {
        var job = job
        job.name = job.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let previous = self.job(job.id)
        if let index = jobs.firstIndex(where: { $0.id == job.id }) {
            jobs[index] = job
        } else {
            jobs.append(job)
        }
        persist()
        perform("Couldn’t install “\(job.name)”") {
            try store.apply(job, allJobs: jobs, previous: previous)
        }
    }

    func setEnabled(_ enabled: Bool, for job: Job) {
        guard var updated = self.job(job.id), updated.isEnabled != enabled else { return }
        updated.isEnabled = enabled
        save(updated)
    }

    func delete(_ job: Job) {
        sessions[job.id]?.stop()
        jobs.removeAll { $0.id == job.id }
        runs[job.id] = nil
        sessions[job.id] = nil
        if selection == .job(job.id) { selection = .overview }
        persist()
        perform("Couldn’t remove “\(job.name)”") {
            try store.delete(job, remaining: jobs)
        }
    }

    func duplicate(_ job: Job) -> Job {
        var copy = job
        copy.id = Job.makeID()
        copy.name = job.name + " copy"
        copy.isEnabled = false
        copy.createdAt = Date()
        save(copy)
        return copy
    }

    /// Runs a saved job now and records it in its history.
    @discardableResult
    func runNow(_ job: Job) -> RunSession {
        if let existing = sessions[job.id], existing.isRunning { return existing }
        let session = RunSession(job: job, record: true, paths: paths) { [weak self] session in
            self?.refreshRuns(notify: false)
            if case .finished(let code) = session.state, code != 0, !NSApp.isActive {
                Notifier.post(title: "\(session.job.name) failed", body: "Exited with code \(code).", failed: true)
            }
        }
        sessions[job.id] = session
        session.start()
        return session
    }

    /// Runs a draft from the editor without recording history.
    func testRun(_ job: Job) -> RunSession {
        let session = RunSession(job: job, record: false, paths: paths) { _ in }
        session.start()
        return session
    }

    func dismissSession(for job: Job) {
        if sessions[job.id]?.isRunning == false { sessions[job.id] = nil }
    }

    func adopt(_ entry: ExternalCronEntry) {
        let schedule = Schedule.structured(fromCron: entry.schedule) ?? .cron(expression: entry.schedule)
        let name = entry.comment.flatMap { $0.hasPrefix("CronBuddy_") ? nil : $0 }
            ?? String(entry.command.split(separator: "/").last?.prefix(40) ?? "Imported job")
        let job = Job(name: name, action: .shell(command: entry.command), schedule: schedule, backend: .cron)
        do {
            let text = try CrontabBackend.read()
            try CrontabBackend.write(CrontabBackend.removing(entry, from: text))
        } catch {
            alertMessage = "Couldn’t import that crontab entry.\n\(error.localizedDescription)"
            return
        }
        save(job)
        refreshExternal()
        selection = .job(job.id)
    }

    func reinstallAll() {
        let failures = store.reconcile(jobs)
        alertMessage = failures.isEmpty ? nil : failures.joined(separator: "\n")
    }

    func newJob(from template: JobTemplate? = nil) {
        editorRequest = EditorRequest(job: template?.makeJob() ?? Job(), isNew: true)
    }

    func edit(_ job: Job) {
        editorRequest = EditorRequest(job: job, isNew: false)
    }

    // MARK: Refreshing

    func refreshRuns(notify: Bool) {
        var running: Set<String> = []
        for job in jobs {
            if RunHistory.runningPID(jobID: job.id, paths: paths) != nil { running.insert(job.id) }

            let file = paths.runsFile(for: job.id)
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            guard modified != runsFileDates[job.id] || runs[job.id] == nil else { continue }
            runsFileDates[job.id] = modified

            var records = RunHistory.load(jobID: job.id, paths: paths)
            if records.count > Int(Double(logRetention) * 1.2) {
                RunHistory.prune(jobID: job.id, keep: logRetention, paths: paths)
                records = Array(records.prefix(logRetention))
            }
            runs[job.id] = records

            if notify { notifyNewRuns(of: job, records: records) }
            lastNotifiedStart[job.id] = records.first?.start ?? lastNotifiedStart[job.id]
        }
        if running != runningScheduled { runningScheduled = running }
    }

    private func notifyNewRuns(of job: Job, records: [RunRecord]) {
        let since = lastNotifiedStart[job.id] ?? .distantPast
        for record in records where record.start > since && record.trigger == .schedule {
            if !record.succeeded, job.notifyOnFailure {
                Notifier.post(title: "\(job.name) failed", body: "Exited with code \(record.exitCode) after \(record.duration.compactDuration).", failed: true)
            } else if record.succeeded, job.notifyOnSuccess {
                let preview = RunHistory.logText(record, paths: paths)
                    .trimmingCharacters(in: .whitespacesAndNewlines).prefix(160)
                Notifier.post(title: job.name, body: preview.isEmpty ? "Finished successfully." : String(preview), failed: false)
            }
        }
    }

    func refreshExternal() {
        externalCheckedAt = Date()
        let entries = (try? CrontabBackend.externalEntries(in: CrontabBackend.read())) ?? []
        if entries != externalEntries { externalEntries = entries }
    }

    // MARK: Helpers

    private func persist() {
        perform("Couldn’t save jobs") { try store.save(jobs) }
    }

    private func perform(_ context: String, _ work: () throws -> Void) {
        do {
            try work()
        } catch {
            alertMessage = "\(context).\n\(error.localizedDescription)"
        }
    }
}

private extension Int {
    var nonZero: Int? { self == 0 ? nil : self }
}

extension TimeInterval {
    var compactDuration: String {
        if self < 1 { return String(format: "%.0f ms", self * 1000) }
        if self < 60 { return String(format: "%.1f s", self) }
        let minutes = Int(self) / 60
        let seconds = Int(self) % 60
        if minutes < 60 { return "\(minutes)m \(seconds)s" }
        return "\(minutes / 60)h \(minutes % 60)m"
    }
}
