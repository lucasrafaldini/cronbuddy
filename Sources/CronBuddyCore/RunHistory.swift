import Foundation

public struct RunRecord: Hashable, Identifiable, Sendable {
    public enum Trigger: String, Sendable {
        case schedule, manual
    }

    public let jobID: String
    public let start: Date
    public let end: Date
    public let exitCode: Int32
    public let logFile: String
    public let trigger: Trigger

    public var id: String { "\(jobID)/\(logFile)" }
    public var duration: TimeInterval { end.timeIntervalSince(start) }
    public var succeeded: Bool { exitCode == 0 }
}

public enum RunHistory {
    private struct Line: Codable {
        var start: Double
        var end: Double
        var exit: Int32
        var log: String
        var trigger: String
    }

    /// Newest first.
    public static func load(jobID: String, paths: Paths) -> [RunRecord] {
        guard let data = try? Data(contentsOf: paths.runsFile(for: jobID)) else { return [] }
        return parse(data, jobID: jobID)
    }

    static func parse(_ data: Data, jobID: String) -> [RunRecord] {
        let decoder = JSONDecoder()
        return data.split(separator: UInt8(ascii: "\n")).compactMap { line -> RunRecord? in
            guard let l = try? decoder.decode(Line.self, from: Data(line)) else { return nil }
            return RunRecord(
                jobID: jobID,
                start: Date(timeIntervalSince1970: l.start),
                end: Date(timeIntervalSince1970: l.end),
                exitCode: l.exit,
                logFile: l.log,
                trigger: RunRecord.Trigger(rawValue: l.trigger) ?? .schedule
            )
        }
        .sorted { $0.start > $1.start }
    }

    public static func logURL(_ record: RunRecord, paths: Paths) -> URL {
        paths.logDir(for: record.jobID).appending(path: record.logFile)
    }

    public static func logText(_ record: RunRecord, paths: Paths) -> String {
        guard let data = try? Data(contentsOf: logURL(record, paths: paths)) else {
            return ""
        }
        return String(decoding: data, as: UTF8.self)
    }

    /// Records a run started from the app, in the same format the wrapper uses.
    @discardableResult
    public static func append(
        jobID: String, start: Date, end: Date, exitCode: Int32, output: String, paths: Paths
    ) throws -> RunRecord {
        let dir = paths.logDir(for: jobID)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let logFile = "\(stamp(start))-manual-\(Int.random(in: 1000...9999)).log"
        try Data(output.utf8).write(to: dir.appending(path: logFile))
        appendLine(jobID: jobID, start: start, end: end, exitCode: exitCode, logFile: logFile, trigger: .manual, paths: paths)
        return RunRecord(
            jobID: jobID, start: start, end: end, exitCode: exitCode, logFile: logFile, trigger: .manual
        )
    }

    static func stamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }

    static func appendLine(
        jobID: String, start: Date, end: Date, exitCode: Int32, logFile: String,
        trigger: RunRecord.Trigger, paths: Paths
    ) {
        let line = Line(
            start: start.timeIntervalSince1970, end: end.timeIntervalSince1970,
            exit: exitCode, log: logFile, trigger: trigger.rawValue
        )
        guard var data = try? JSONEncoder().encode(line) else { return }
        data.append(UInt8(ascii: "\n"))
        let runs = paths.runsFile(for: jobID)
        if let handle = try? FileHandle(forWritingTo: runs) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: runs)
        }
    }

    /// Keeps the newest `keep` runs and deletes older logs.
    public static func prune(jobID: String, keep: Int, paths: Paths) {
        let runs = paths.runsFile(for: jobID)
        guard let data = try? Data(contentsOf: runs) else { return }
        let lines = data.split(separator: UInt8(ascii: "\n"))
        guard lines.count > keep else { return }

        let decoder = JSONDecoder()
        let dropped = lines.dropLast(keep)
        for line in dropped {
            if let l = try? decoder.decode(Line.self, from: Data(line)) {
                try? FileManager.default.removeItem(at: paths.logDir(for: jobID).appending(path: l.log))
            }
        }
        var kept = Data()
        for line in lines.suffix(keep) {
            kept.append(contentsOf: line)
            kept.append(UInt8(ascii: "\n"))
        }
        try? kept.write(to: runs, options: .atomic)
    }

    public static func removeAll(jobID: String, paths: Paths) {
        try? FileManager.default.removeItem(at: paths.logDir(for: jobID))
    }

    /// The pid of a scheduled run in progress, if the wrapper's marker points at a live process.
    public static func runningPID(jobID: String, paths: Paths) -> Int32? {
        let marker = paths.runningMarker(for: jobID)
        guard let text = try? String(contentsOf: marker, encoding: .utf8),
              let pid = text.split(separator: " ").first.flatMap({ Int32($0) })
        else { return nil }
        if kill(pid, 0) == 0 { return pid }
        try? FileManager.default.removeItem(at: marker)
        return nil
    }
}
