import Foundation
import Testing
@testable import CronBuddyCore

private func t(_ h: Int, _ m: Int = 0) -> TimeOfDay { TimeOfDay(hour: h, minute: m) }

@Suite struct ScheduleTests {
    @Test func cronExpressions() {
        #expect(Schedule.interval(minutes: 15).cronExpressions() == ["*/15 * * * *"])
        #expect(Schedule.interval(minutes: 120).cronExpressions() == ["0 */2 * * *"])
        #expect(Schedule.interval(minutes: 7).cronExpressions() == nil)
        #expect(Schedule.daily(times: [t(18), t(9)]).cronExpressions() == ["0 9,18 * * *"])
        #expect(Schedule.daily(times: [t(9), t(9, 30)]).cronExpressions() == ["0 9 * * *", "30 9 * * *"])
        #expect(Schedule.weekly(weekdays: [5, 1, 3], times: [t(7, 45)]).cronExpressions() == ["45 7 * * 1,3,5"])
        #expect(Schedule.monthly(days: [15, 1], time: t(0)).cronExpressions() == ["0 0 1,15 * *"])
        #expect(Schedule.atLogin.cronExpressions() == ["@reboot"])
    }

    @Test func launchdTriggers() throws {
        #expect(try Schedule.interval(minutes: 7).launchdTrigger() == .interval(seconds: 420))
        #expect(try Schedule.atLogin.launchdTrigger() == .runAtLoad)
        #expect(try Schedule.cron(expression: "* * * * *").launchdTrigger() == .interval(seconds: 60))
        #expect(try Schedule.daily(times: [t(9, 30)]).launchdTrigger() == .calendar([["Minute": 30, "Hour": 9]]))
        #expect(throws: ScheduleError.self) { try Schedule.cron(expression: "nope").launchdTrigger() }
    }

    @Test func summaries() {
        #expect(Schedule.interval(minutes: 1).summary == "Every minute")
        #expect(Schedule.interval(minutes: 90).summary == "Every 90 minutes")
        #expect(Schedule.interval(minutes: 180).summary == "Every 3 hours")
        #expect(Schedule.hourly(minute: 5).summary == "Every hour at :05")
        #expect(Schedule.daily(times: [t(18), t(9)]).summary == "Every day at 09:00 and 18:00")
        #expect(Schedule.weekly(weekdays: [1, 2, 3, 4, 5], times: [t(9)]).summary == "Weekdays at 09:00")
        #expect(Schedule.monthly(days: [1, 2, 3, 11, 22], time: t(8)).summary == "Monthly on the 1st, 2nd, 3rd, 11th and 22nd at 08:00")
        #expect(Schedule.cron(expression: "0 9,18 * * 1-5").summary == "Weekdays at 09:00 and 18:00")
        #expect(Schedule.cron(expression: "0 0 1 1 *").summary == "Cron · 0 0 1 1 *")
    }

    @Test func structuringCron() {
        #expect(Schedule.structured(fromCron: "*/10 * * * *") == .interval(minutes: 10))
        #expect(Schedule.structured(fromCron: "0 */6 * * *") == .interval(minutes: 360))
        #expect(Schedule.structured(fromCron: "20 * * * *") == .hourly(minute: 20))
        #expect(Schedule.structured(fromCron: "0 10,14,17 * * 1-5") == .weekly(weekdays: [1, 2, 3, 4, 5], times: [t(10), t(14), t(17)]))
        #expect(Schedule.structured(fromCron: "30 6 1 * *") == .monthly(days: [1], time: t(6, 30)))
        #expect(Schedule.structured(fromCron: "@reboot") == .atLogin)
        #expect(Schedule.structured(fromCron: "garbage") == nil)
    }

    @Test func intervalNextDatesFollowLastRun() {
        let now = Date(timeIntervalSince1970: 10_000)
        let last = Date(timeIntervalSince1970: 9_000)
        let next = Schedule.interval(minutes: 10).nextDates(after: now, count: 2, lastRun: last)
        #expect(next == [Date(timeIntervalSince1970: 10_200), Date(timeIntervalSince1970: 10_800)])
    }

    @Test func multiExpressionNextDatesAreMerged() {
        let next = Schedule.daily(times: [t(9), t(9, 30)]).nextDates(after: Date(), count: 4)
        #expect(next.count == 4)
        #expect(next == next.sorted())
        #expect(Set(next).count == 4)
    }
}
