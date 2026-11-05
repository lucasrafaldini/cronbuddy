import Foundation

public struct TimeOfDay: Codable, Hashable, Comparable, Sendable {
    public var hour: Int
    public var minute: Int

    public init(hour: Int, minute: Int) {
        self.hour = hour
        self.minute = minute
    }

    public static func < (lhs: TimeOfDay, rhs: TimeOfDay) -> Bool {
        (lhs.hour, lhs.minute) < (rhs.hour, rhs.minute)
    }

    public var formatted: String { String(format: "%02d:%02d", hour, minute) }
}

public enum Schedule: Codable, Hashable, Sendable {
    case interval(minutes: Int)
    case hourly(minute: Int)
    case daily(times: [TimeOfDay])
    /// Weekdays use cron numbering: 0 = Sunday … 6 = Saturday.
    case weekly(weekdays: [Int], times: [TimeOfDay])
    case monthly(days: [Int], time: TimeOfDay)
    case atLogin
    case cron(expression: String)

    public enum Kind: String, CaseIterable, Identifiable, Sendable {
        case interval, hourly, daily, weekly, monthly, atLogin, cron
        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .interval: "Every…"
            case .hourly: "Hourly"
            case .daily: "Daily"
            case .weekly: "Weekly"
            case .monthly: "Monthly"
            case .atLogin: "At login"
            case .cron: "Custom (cron)"
            }
        }
    }

    public var kind: Kind {
        switch self {
        case .interval: .interval
        case .hourly: .hourly
        case .daily: .daily
        case .weekly: .weekly
        case .monthly: .monthly
        case .atLogin: .atLogin
        case .cron: .cron
        }
    }

    // MARK: Conversions

    /// Cron expressions that together reproduce this schedule, or nil when cron can't express it.
    public func cronExpressions() -> [String]? {
        switch self {
        case .interval(let n):
            if n == 1 { return ["* * * * *"] }
            if n > 0, n < 60, 60 % n == 0 { return ["*/\(n) * * * *"] }
            if n >= 60, n % 60 == 0 {
                let h = n / 60
                if h == 1 { return ["0 * * * *"] }
                if 24 % h == 0 { return ["0 */\(h) * * *"] }
                if h == 24 { return ["0 0 * * *"] }
            }
            return nil
        case .hourly(let m):
            return ["\(m) * * * *"]
        case .daily(let times):
            guard !times.isEmpty else { return nil }
            return Self.grouped(times).map { "\($0.minute) \($0.hours) * * *" }
        case .weekly(let weekdays, let times):
            guard !weekdays.isEmpty, !times.isEmpty else { return nil }
            let dow = weekdays.count == 7 ? "*" : Self.list(weekdays)
            return Self.grouped(times).map { "\($0.minute) \($0.hours) * * \(dow)" }
        case .monthly(let days, let time):
            guard !days.isEmpty else { return nil }
            return ["\(time.minute) \(time.hour) \(Self.list(days)) * *"]
        case .atLogin:
            return ["@reboot"]
        case .cron(let expression):
            return [expression.trimmingCharacters(in: .whitespaces)]
        }
    }

    private static func list(_ values: [Int]) -> String {
        Array(Set(values)).sorted().map(String.init).joined(separator: ",")
    }

    private static func grouped(_ times: [TimeOfDay]) -> [(minute: Int, hours: String)] {
        let byMinute = Dictionary(grouping: Set(times), by: \.minute)
        return byMinute.keys.sorted().map { minute in
            (minute, list(byMinute[minute]!.map(\.hour)))
        }
    }

    private func parsedExpressions() -> [CronExpression]? {
        guard let expressions = cronExpressions() else { return nil }
        let parsed = expressions.compactMap { try? CronExpression($0) }
        return parsed.count == expressions.count ? parsed : nil
    }

    public enum LaunchdTrigger: Equatable, Sendable {
        case interval(seconds: Int)
        case calendar([[String: Int]])
        case runAtLoad
    }

    public func launchdTrigger() throws -> LaunchdTrigger {
        switch self {
        case .interval(let n):
            guard n > 0 else { throw ScheduleError.invalid("Interval must be at least one minute.") }
            return .interval(seconds: n * 60)
        case .atLogin:
            return .runAtLoad
        default:
            guard let expressions = parsedExpressions() else {
                throw ScheduleError.invalid(validationMessage ?? "Invalid schedule.")
            }
            var entries: [[String: Int]] = []
            for expression in expressions {
                if expression.minutes.count == 60, expression.hours.count == 24,
                   !expression.domRestricted, !expression.dowRestricted, expression.months.count == 12 {
                    return .interval(seconds: 60)
                }
                guard let more = expression.launchdCalendarIntervals() else {
                    throw ScheduleError.tooComplexForLaunchd
                }
                entries += more
            }
            guard entries.count <= 256 else { throw ScheduleError.tooComplexForLaunchd }
            return .calendar(entries)
        }
    }

    // MARK: Validation

    /// A user-facing reason this schedule is invalid regardless of backend, or nil.
    public var validationMessage: String? {
        switch self {
        case .interval(let n):
            return n >= 1 ? nil : "Interval must be at least one minute."
        case .hourly(let m):
            return (0...59).contains(m) ? nil : "Minute must be between 0 and 59."
        case .daily(let times):
            return times.isEmpty ? "Add at least one time." : nil
        case .weekly(let weekdays, let times):
            if weekdays.isEmpty { return "Pick at least one weekday." }
            return times.isEmpty ? "Add at least one time." : nil
        case .monthly(let days, _):
            return days.isEmpty ? "Pick at least one day of the month." : nil
        case .atLogin:
            return nil
        case .cron(let expression):
            do {
                _ = try CronExpression(expression)
                return nil
            } catch {
                return String(describing: error)
            }
        }
    }

    // MARK: Next fire dates

    /// Interval schedules depend on when launchd loaded the job, so their times are estimates.
    public var isApproximate: Bool {
        if case .interval = self { return true }
        return false
    }

    public func nextDates(
        after date: Date, count: Int, lastRun: Date? = nil, calendar: Calendar = .current
    ) -> [Date] {
        switch self {
        case .atLogin:
            return []
        case .interval(let n):
            guard n > 0 else { return [] }
            let step = TimeInterval(n * 60)
            var next = (lastRun ?? date).addingTimeInterval(step)
            if next <= date {
                let missed = ((date.timeIntervalSince(next)) / step).rounded(.down) + 1
                next = next.addingTimeInterval(missed * step)
            }
            return (0..<count).map { next.addingTimeInterval(Double($0) * step) }
        default:
            guard let expressions = parsedExpressions() else { return [] }
            let merged = expressions.flatMap { $0.nextDates(after: date, count: count, calendar: calendar) }
            return Array(Set(merged)).sorted().prefix(count).map { $0 }
        }
    }

    // MARK: Description

    public var summary: String {
        switch self {
        case .interval(let n):
            if n == 1 { return "Every minute" }
            if n % 1440 == 0 { return n == 1440 ? "Every day" : "Every \(n / 1440) days" }
            if n % 60 == 0 { return n == 60 ? "Every hour" : "Every \(n / 60) hours" }
            return "Every \(n) minutes"
        case .hourly(let m):
            return m == 0 ? "Every hour, on the hour" : String(format: "Every hour at :%02d", m)
        case .daily(let times):
            return "Every day at \(Self.join(times.sorted().map(\.formatted)))"
        case .weekly(let weekdays, let times):
            return "\(Self.describe(weekdays: weekdays)) at \(Self.join(times.sorted().map(\.formatted)))"
        case .monthly(let days, let time):
            let ordinals = Array(Set(days)).sorted().map(Self.ordinal)
            return "Monthly on the \(Self.join(ordinals)) at \(time.formatted)"
        case .atLogin:
            return "At login"
        case .cron(let expression):
            if let structured = Schedule.structured(fromCron: expression), structured.kind != .cron {
                return structured.summary
            }
            return "Cron · \(expression)"
        }
    }

    static func join(_ items: [String]) -> String {
        switch items.count {
        case 0: return ""
        case 1: return items[0]
        default: return items.dropLast().joined(separator: ", ") + " and " + items.last!
        }
    }

    static func ordinal(_ n: Int) -> String {
        let suffix: String
        switch (n % 10, n % 100) {
        case (_, 11...13): suffix = "th"
        case (1, _): suffix = "st"
        case (2, _): suffix = "nd"
        case (3, _): suffix = "rd"
        default: suffix = "th"
        }
        return "\(n)\(suffix)"
    }

    static func describe(weekdays: [Int]) -> String {
        let set = Set(weekdays)
        if set.count == 7 { return "Every day" }
        if set == [1, 2, 3, 4, 5] { return "Weekdays" }
        if set == [0, 6] { return "Weekends" }
        let symbols = Calendar.current.shortWeekdaySymbols
        // Start the week on Monday for readability.
        let ordered = set.sorted { (($0 + 6) % 7) < (($1 + 6) % 7) }
        return ordered.map { symbols[$0] }.joined(separator: ", ")
    }

    // MARK: Structuring cron

    /// Turns a cron expression into the friendliest equivalent schedule, if one exists.
    public static func structured(fromCron expression: String) -> Schedule? {
        let trimmed = expression.trimmingCharacters(in: .whitespaces)
        if trimmed.lowercased() == "@reboot" { return .atLogin }
        guard let e = try? CronExpression(trimmed) else { return nil }
        guard e.months.count == 12 else { return .cron(expression: trimmed) }

        if !e.domRestricted && !e.dowRestricted {
            if e.hours.count == 24 {
                if e.minutes.count == 1 { return .hourly(minute: e.minutes.first!) }
                for step in [1, 2, 3, 4, 5, 6, 10, 12, 15, 20, 30]
                where e.minutes == Set(stride(from: 0, to: 60, by: step)) {
                    return .interval(minutes: step)
                }
            } else if e.minutes == [0] {
                for step in [2, 3, 4, 6, 8, 12] where e.hours == Set(stride(from: 0, to: 24, by: step)) {
                    return .interval(minutes: step * 60)
                }
            }
        }

        let times = e.hours.flatMap { h in e.minutes.map { TimeOfDay(hour: h, minute: $0) } }.sorted()
        guard e.hours.count < 24, !times.isEmpty, times.count <= 12 else { return .cron(expression: trimmed) }

        switch (e.domRestricted, e.dowRestricted) {
        case (false, false):
            return .daily(times: times)
        case (false, true):
            return .weekly(weekdays: e.daysOfWeek.sorted(), times: times)
        case (true, false) where times.count == 1:
            return .monthly(days: e.daysOfMonth.sorted(), time: times[0])
        default:
            return .cron(expression: trimmed)
        }
    }
}

public enum ScheduleError: LocalizedError, Equatable {
    case invalid(String)
    case tooComplexForLaunchd

    public var errorDescription: String? {
        switch self {
        case .invalid(let message): message
        case .tooComplexForLaunchd:
            "This cron expression expands to too many launchd entries. Use the cron backend for it."
        }
    }
}
