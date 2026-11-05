import CronBuddyCore
import Foundation
import Observation

/// A run started from the app, streaming output live.
@MainActor
@Observable
final class RunSession: Identifiable {
    enum State: Equatable {
        case running
        case finished(exitCode: Int32)
        case failed(String)
    }

    let id = UUID()
    let job: Job
    private(set) var output = ""
    private(set) var state: State = .running
    let startedAt = Date()
    private(set) var endedAt: Date?

    private var process: Process?
    private var reachedEOF = false
    private var exitStatus: Int32?
    private let record: Bool
    private let paths: Paths
    private let onFinish: (RunSession) -> Void

    /// Keep the live buffer bounded so a chatty job can't exhaust memory.
    private static let outputLimit = 400_000

    init(job: Job, record: Bool, paths: Paths, onFinish: @escaping (RunSession) -> Void) {
        self.job = job
        self.record = record
        self.paths = paths
        self.onFinish = onFinish
    }

    var isRunning: Bool { state == .running }

    var elapsed: TimeInterval { (endedAt ?? Date()).timeIntervalSince(startedAt) }

    func start() {
        let script = FileManager.default.temporaryDirectory
            .appending(path: "cronbuddy-run-\(job.id)-\(id.uuidString.prefix(8)).sh")
        do {
            try ActionScript.write(job, to: script)
        } catch {
            fail("Couldn’t prepare the action: \(error.localizedDescription)")
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [script.path]
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = Paths.defaultPATH + ":" + (environment["PATH"] ?? "")
        process.environment = environment
        process.standardInput = FileHandle.nullDevice

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil }
            let text = String(decoding: data, as: UTF8.self)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if data.isEmpty {
                        self.reachedEOF = true
                        self.finishIfDone()
                    } else {
                        self.append(text)
                    }
                }
            }
        }
        process.terminationHandler = { [weak self] finished in
            let status = finished.terminationStatus
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    try? FileManager.default.removeItem(at: script)
                    guard let self else { return }
                    self.exitStatus = status
                    self.finishIfDone()
                }
            }
        }

        do {
            try process.run()
            self.process = process
        } catch {
            fail("Couldn’t start: \(error.localizedDescription)")
        }
    }

    func stop() {
        guard let process, process.isRunning else { return }
        process.terminate()
        let pid = process.processIdentifier
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            if process.isRunning { kill(pid, SIGKILL) }
        }
    }

    private func append(_ text: String) {
        output += text
        if output.count > Self.outputLimit {
            output = "…\n" + output.suffix(Self.outputLimit / 2)
        }
    }

    private func finishIfDone() {
        // Background children can keep the pipe open; don't wait on them forever.
        guard let status = exitStatus, state == .running else { return }
        if !reachedEOF {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self, self.state == .running else { return }
                self.reachedEOF = true
                self.finishIfDone()
            }
            return
        }
        let end = Date()
        endedAt = end
        state = .finished(exitCode: status)
        if record {
            _ = try? RunHistory.append(
                jobID: job.id, start: startedAt, end: end, exitCode: status, output: output, paths: paths
            )
        }
        onFinish(self)
    }

    private func fail(_ message: String) {
        endedAt = Date()
        state = .failed(message)
        onFinish(self)
    }
}
