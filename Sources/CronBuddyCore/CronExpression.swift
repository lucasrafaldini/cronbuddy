import Foundation

/// A parsed five-field cron expression (minute hour day-of-month month day-of-week).
public struct CronExpression: Hashable, Sendable {
    public let minutes: Set<Int>
    public let hours: Set<Int>
    public let daysOfMonth: Set<Int>
    public let months: Set<Int>
    /// 0 = Sunday … 6 = Saturday.
    public let daysOfWeek: Set<Int>
    /// Cron treats a day field as restricted when it does not start with `*`.
    /// When both day fields are restricted, a day matches if *either* matches.
    public let domRestricted: Bool
    public let dowRestricted: Bool
    public let source: String

    public enum ParseError: Error, Equatable, CustomStringConvertible {
        case fieldCount(Int)
        case invalidField(name: String, value: String)

        public var description: String {
            switch self {
            case .fieldCount(let n):
                return "Expected 5 fields (minute hour day month weekday), found \(n)."
            case .invalidField(let name, let value):
                return "Invalid \(name) field: “\(value)”."
            }
        }
    }

    static let macros: [String: String] = [
        "@yearly": "0 0 1 1 *", "@annually": "0 0 1 1 *", "@monthly": "0 0 1 * *",
        "@weekly": "0 0 * * 0", "@daily": "0 0 * * *", "@midnight": "0 0 * * *",
        "@hourly": "0 * * * *",
    ]

    static let monthNames: [String: Int] = [
        "jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "jun": 6,
        "jul": 7, "aug": 8, "sep": 9, "oct": 10, "nov": 11, "dec": 12,
    ]

    static let dayNames: [String: Int] = [
        "sun": 0, "mon": 1, "tue": 2, "wed": 3, "thu": 4, "fri": 5, "sat": 6,
    ]

    public init(_ expression: String) throws {
        let trimmed = expression.trimmingCharacters(in: .whitespaces)
        let expanded = Self.macros[trimmed.lowercased()] ?? trimmed
        let parts = expanded.split(whereSeparator: \.isWhitespace).map(String.init)
        guard parts.count == 5 else { throw ParseError.fieldCount(parts.count) }

        minutes = try Self.parse(parts[0], name: "minute", range: 0...59)
        hours = try Self.parse(parts[1], name: "hour", range: 0...23)
        daysOfMonth = try Self.parse(parts[2], name: "day of month", range: 1...31)
        months = try Self.parse(parts[3], name: "month", range: 1...12, names: Self.monthNames)
        var dow = try Self.parse(parts[4], name: "weekday", range: 0...7, names: Self.dayNames)
        if dow.remove(7) != nil { dow.insert(0) }
        daysOfWeek = dow
        domRestricted = !parts[2].hasPrefix("*")
        dowRestricted = !parts[4].hasPrefix("*")
        source = trimmed
    }

    static func parse(
        _ field: String, name: String, range: ClosedRange<Int>, names: [String: Int] = [:]
    ) throws -> Set<Int> {
        let invalid = ParseError.invalidField(name: name, value: field)
        func value(_ s: Substring) -> Int? { Int(s) ?? names[s.lowercased()] }

        var result = Set<Int>()
        for item in field.split(separator: ",", omittingEmptySubsequences: false) {
            let stepParts = item.split(separator: "/", omittingEmptySubsequences: false)
            guard (1...2).contains(stepParts.count), !stepParts[0].isEmpty else { throw invalid }

            var step = 1
            if stepParts.count == 2 {
                guard let s = Int(stepParts[1]), s > 0 else { throw invalid }
                step = s
            }

            let base = stepParts[0]
            let lower: Int
            let upper: Int
            if base == "*" {
                lower = range.lowerBound
                upper = range.upperBound
            } else if let dash = base.firstIndex(of: "-") {
                guard let a = value(base[..<dash]),
                      let b = value(base[base.index(after: dash)...]),
                      a <= b
                else { throw invalid }
                lower = a
                upper = b
            } else {
                guard let a = value(base) else { throw invalid }
                lower = a
                upper = stepParts.count == 2 ? range.upperBound : a
            }

            guard range.contains(lower), range.contains(upper) else { throw invalid }
            result.formUnion(stride(from: lower, through: upper, by: step))
        }
        return result
    }

    public static func isValid(_ expression: String) -> Bool {
        (try? CronExpression(expression)) != nil
    }

    func dayMatches(day: Int, weekday: Int) -> Bool {
        let domOK = daysOfMonth.contains(day)
        let dowOK = daysOfWeek.contains(weekday)
        if domRestricted && dowRestricted { return domOK || dowOK }
        return domOK && dowOK
    }

    /// The first matching minute strictly after `date`.
    public func nextDate(after date: Date, calendar: Calendar = .current) -> Date? {
        let floored = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        guard let minuteStart = calendar.date(from: floored),
              let earliest = calendar.date(byAdding: .minute, value: 1, to: minuteStart)
        else { return nil }

        let sortedHours = hours.sorted()
        let sortedMinutes = minutes.sorted()
        var day = calendar.startOfDay(for: earliest)

        // Five years covers leap-day-only schedules.
        for _ in 0..<(366 * 5) {
            let parts = calendar.dateComponents([.year, .month, .day, .weekday], from: day)
            if let month = parts.month, let dom = parts.day, let weekday = parts.weekday,
               months.contains(month), dayMatches(day: dom, weekday: weekday - 1) {
                for hour in sortedHours {
                    for minute in sortedMinutes {
                        var c = DateComponents()
                        c.year = parts.year
                        c.month = month
                        c.day = dom
                        c.hour = hour
                        c.minute = minute
                        guard let candidate = calendar.date(from: c),
                              calendar.component(.hour, from: candidate) == hour
                        else { continue }
                        if candidate >= earliest { return candidate }
                    }
                }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { return nil }
            day = next
        }
        return nil
    }

    public func nextDates(after date: Date, count: Int, calendar: Calendar = .current) -> [Date] {
        var result: [Date] = []
        var cursor = date
        while result.count < count, let next = nextDate(after: cursor, calendar: calendar) {
            result.append(next)
            cursor = next
        }
        return result
    }

    /// launchd `StartCalendarInterval` entries equivalent to this expression,
    /// or nil when the expansion would be unreasonably large.
    public func launchdCalendarIntervals(limit: Int = 256) -> [[String: Int]]? {
        let minuteValues: [Int?] = minutes.count == 60 ? [nil] : minutes.sorted()
        let hourValues: [Int?] = hours.count == 24 ? [nil] : hours.sorted()
        let monthValues: [Int?] = months.count == 12 ? [nil] : months.sorted()

        // Both day fields restricted means OR in cron, so emit the two sets separately.
        var dayVariants: [(day: Int?, weekday: Int?)] = []
        switch (domRestricted, dowRestricted) {
        case (false, false):
            dayVariants = [(nil, nil)]
        case (true, false):
            dayVariants = daysOfMonth.sorted().map { ($0, nil) }
        case (false, true):
            dayVariants = daysOfWeek.count == 7 ? [(nil, nil)] : daysOfWeek.sorted().map { (nil, $0) }
        case (true, true):
            dayVariants = daysOfMonth.sorted().map { ($0, nil) } + daysOfWeek.sorted().map { (nil, $0) }
        }

        let total = minuteValues.count * hourValues.count * monthValues.count * dayVariants.count
        guard total <= limit else { return nil }

        var entries: [[String: Int]] = []
        for month in monthValues {
            for variant in dayVariants {
                for hour in hourValues {
                    for minute in minuteValues {
                        var entry: [String: Int] = [:]
                        if let minute { entry["Minute"] = minute }
                        if let hour { entry["Hour"] = hour }
                        if let day = variant.day { entry["Day"] = day }
                        if let weekday = variant.weekday { entry["Weekday"] = weekday }
                        if let month { entry["Month"] = month }
                        entries.append(entry)
                    }
                }
            }
        }
        return entries
    }
}
