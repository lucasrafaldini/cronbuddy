import Foundation
import Testing
@testable import CronBuddyCore

private let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0) -> Date {
    utc.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
}

@Suite struct CronExpressionTests {
    @Test func parsesListsRangesAndSteps() throws {
        let e = try CronExpression("*/15 9-17 * * 1-5")
        #expect(e.minutes == [0, 15, 30, 45])
        #expect(e.hours == Set(9...17))
        #expect(e.daysOfWeek == [1, 2, 3, 4, 5])
        #expect(!e.domRestricted)
        #expect(e.dowRestricted)
    }

    @Test func parsesNamesMacrosAndSundaySeven() throws {
        #expect(try CronExpression("0 0 * jan,dec sun").months == [1, 12])
        #expect(try CronExpression("0 0 * * 7").daysOfWeek == [0])
        #expect(try CronExpression("@daily").minutes == [0])
        #expect(try CronExpression("5/20 * * * *").minutes == [5, 25, 45])
    }

    @Test(arguments: ["", "* * * *", "60 * * * *", "* 24 * * *", "* * 0 * *", "*/0 * * * *", "a b c d e", "5-1 * * * *"])
    func rejectsInvalid(_ expression: String) {
        #expect(!CronExpression.isValid(expression))
    }

    @Test func nextDateRollsOverDaysAndMonths() throws {
        let e = try CronExpression("30 8 * * *")
        #expect(e.nextDate(after: date(2026, 1, 31, 9), calendar: utc) == date(2026, 2, 1, 8, 30))
        #expect(e.nextDate(after: date(2026, 1, 31, 8, 29), calendar: utc) == date(2026, 1, 31, 8, 30))
        // Strictly after: the matching minute itself is excluded.
        #expect(e.nextDate(after: date(2026, 1, 31, 8, 30), calendar: utc) == date(2026, 2, 1, 8, 30))
    }

    @Test func dayOfMonthAndWeekdayAreOred() throws {
        // 13th of the month OR any Friday. 2026-03-01 is a Sunday.
        let e = try CronExpression("0 12 13 * 5")
        let next = e.nextDates(after: date(2026, 3, 1), count: 3, calendar: utc)
        #expect(next == [date(2026, 3, 6, 12), date(2026, 3, 13, 12), date(2026, 3, 20, 12)])
    }

    @Test func findsLeapDay() throws {
        let e = try CronExpression("0 0 29 2 *")
        #expect(e.nextDate(after: date(2026, 3, 1), calendar: utc) == date(2028, 2, 29))
    }

    @Test func launchdExpansion() throws {
        let weekdays = try CronExpression("0 9,18 * * 1-5").launchdCalendarIntervals()
        #expect(weekdays?.count == 10)
        #expect(weekdays?.first == ["Minute": 0, "Hour": 9, "Weekday": 1])

        let hourly = try CronExpression("15 * * * *").launchdCalendarIntervals()
        #expect(hourly == [["Minute": 15]])

        #expect(try CronExpression("* * * * *").launchdCalendarIntervals() == [[:]])
        #expect(try CronExpression("0-58 0-22 * * *").launchdCalendarIntervals(limit: 256) == nil)
    }
}
