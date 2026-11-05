import CronBuddyCore
import SwiftUI

struct ScheduleEditor: View {
    @Environment(\.theme) private var theme
    @Binding var schedule: Schedule

    var body: some View {
        Picker("Repeat", selection: kindBinding) {
            ForEach(Schedule.Kind.allCases) { kind in
                Text(kind.title).tag(kind)
            }
        }

        switch schedule {
        case .interval(let minutes):
            IntervalField(minutes: minutes) { schedule = .interval(minutes: $0) }
        case .hourly(let minute):
            Stepper(value: Binding(get: { minute }, set: { schedule = .hourly(minute: $0) }), in: 0...59) {
                LabeledContent("At minute", value: String(format: ":%02d", minute))
            }
        case .daily(let times):
            TimesField(times: times) { schedule = .daily(times: $0) }
        case .weekly(let weekdays, let times):
            LabeledContent("On") {
                WeekdayPicker(selection: weekdays) { schedule = .weekly(weekdays: $0, times: times) }
            }
            TimesField(times: times) { schedule = .weekly(weekdays: weekdays, times: $0) }
        case .monthly(let days, let time):
            LabeledContent("On days") {
                MonthDayPicker(selection: days) { schedule = .monthly(days: $0, time: time) }
            }
            TimePicker(label: "At", time: time) { schedule = .monthly(days: days, time: $0) }
        case .atLogin:
            Text("Runs once each time you log in to this Mac.")
                .font(.callout)
                .foregroundStyle(theme.secondary)
        case .cron(let expression):
            CronField(expression: expression) { schedule = .cron(expression: $0) }
        }
    }

    private var kindBinding: Binding<Schedule.Kind> {
        Binding(
            get: { schedule.kind },
            set: { kind in
                guard kind != schedule.kind else { return }
                schedule = Self.defaultSchedule(for: kind, from: schedule)
            }
        )
    }

    /// Carries times and days across kinds so switching doesn't throw work away.
    static func defaultSchedule(for kind: Schedule.Kind, from current: Schedule) -> Schedule {
        var times = [TimeOfDay(hour: 9, minute: 0)]
        switch current {
        case .daily(let t), .weekly(_, let t): times = t.isEmpty ? times : t
        case .monthly(_, let t): times = [t]
        default: break
        }
        switch kind {
        case .interval: return .interval(minutes: 15)
        case .hourly: return .hourly(minute: 0)
        case .daily: return .daily(times: times)
        case .weekly: return .weekly(weekdays: [1, 2, 3, 4, 5], times: times)
        case .monthly: return .monthly(days: [1], time: times[0])
        case .atLogin: return .atLogin
        case .cron: return .cron(expression: current.cronExpressions()?.first ?? "0 9 * * *")
        }
    }
}

private struct IntervalField: View {
    let minutes: Int
    let onChange: (Int) -> Void

    private enum Unit: String, CaseIterable { case minutes, hours }

    var body: some View {
        let unit: Unit = minutes >= 60 && minutes % 60 == 0 ? .hours : .minutes
        let value = unit == .hours ? minutes / 60 : minutes
        LabeledContent("Every") {
            HStack(spacing: 8) {
                TextField("", value: Binding(
                    get: { value },
                    set: { onChange(max(1, $0) * (unit == .hours ? 60 : 1)) }
                ), format: .number)
                .frame(width: 56)
                .multilineTextAlignment(.trailing)
                Stepper("", value: Binding(
                    get: { value },
                    set: { onChange(max(1, $0) * (unit == .hours ? 60 : 1)) }
                ), in: 1...999)
                .labelsHidden()
                Picker("", selection: Binding(
                    get: { unit },
                    set: { onChange($0 == .hours ? value * 60 : value) }
                )) {
                    Text(value == 1 ? "minute" : "minutes").tag(Unit.minutes)
                    Text(value == 1 ? "hour" : "hours").tag(Unit.hours)
                }
                .labelsHidden()
                .fixedSize()
            }
        }
    }
}

struct TimePicker: View {
    let label: String
    let time: TimeOfDay
    let onChange: (TimeOfDay) -> Void

    var body: some View {
        DatePicker(label, selection: Binding(
            get: {
                Calendar.current.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: Date()) ?? Date()
            },
            set: {
                let parts = Calendar.current.dateComponents([.hour, .minute], from: $0)
                onChange(TimeOfDay(hour: parts.hour ?? 0, minute: parts.minute ?? 0))
            }
        ), displayedComponents: .hourAndMinute)
    }
}

private struct TimesField: View {
    @Environment(\.theme) private var theme
    let times: [TimeOfDay]
    let onChange: ([TimeOfDay]) -> Void

    var body: some View {
        ForEach(Array(times.enumerated()), id: \.offset) { index, time in
            HStack {
                TimePicker(label: index == 0 ? "At" : "And at", time: time) { newValue in
                    var updated = times
                    updated[index] = newValue
                    onChange(updated)
                }
                if times.count > 1 {
                    Button {
                        var updated = times
                        updated.remove(at: index)
                        onChange(updated)
                    } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless)
                        .help("Remove this time")
                }
            }
        }
        Button {
            let last = times.max() ?? TimeOfDay(hour: 9, minute: 0)
            onChange(times + [TimeOfDay(hour: (last.hour + 3) % 24, minute: last.minute)])
        } label: {
            Label("Add another time", systemImage: "plus.circle")
        }
        .buttonStyle(.borderless)
        .foregroundStyle(theme.accent)
    }
}

private struct WeekdayPicker: View {
    @Environment(\.theme) private var theme
    let selection: [Int]
    let onChange: ([Int]) -> Void

    // Monday-first, cron numbering.
    private let order = [1, 2, 3, 4, 5, 6, 0]

    var body: some View {
        let symbols = Calendar.current.veryShortWeekdaySymbols
        let names = Calendar.current.weekdaySymbols
        VStack(alignment: .trailing, spacing: 6) {
            HStack(spacing: 4) {
                ForEach(order, id: \.self) { day in
                    let isOn = selection.contains(day)
                    Button {
                        var set = Set(selection)
                        if isOn { set.remove(day) } else { set.insert(day) }
                        onChange(set.sorted())
                    } label: {
                        Text(symbols[day])
                            .font(.callout.weight(.semibold))
                            .frame(width: 26, height: 26)
                            .foregroundStyle(isOn ? theme.onAccent : theme.text)
                            .background(isOn ? theme.accent : theme.raised, in: Circle())
                            .overlay(Circle().strokeBorder(theme.border))
                    }
                    .buttonStyle(.plain)
                    .help(names[day])
                    .accessibilityLabel(names[day])
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                }
            }
            HStack(spacing: 10) {
                Button("Weekdays") { onChange([1, 2, 3, 4, 5]) }
                Button("Weekends") { onChange([0, 6]) }
                Button("Every day") { onChange(Array(0...6)) }
            }
            .buttonStyle(.link)
            .font(.caption)
        }
    }
}

private struct MonthDayPicker: View {
    @Environment(\.theme) private var theme
    let selection: [Int]
    let onChange: ([Int]) -> Void

    var body: some View {
        let columns = Array(repeating: GridItem(.fixed(26), spacing: 4), count: 7)
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(1...31, id: \.self) { day in
                let isOn = selection.contains(day)
                Button {
                    var set = Set(selection)
                    if isOn { set.remove(day) } else { set.insert(day) }
                    onChange(set.sorted())
                } label: {
                    Text("\(day)")
                        .font(.caption.weight(.medium))
                        .monospacedDigit()
                        .frame(width: 26, height: 24)
                        .foregroundStyle(isOn ? theme.onAccent : theme.text)
                        .background(isOn ? theme.accent : theme.raised, in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Day \(day)")
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .frame(width: 7 * 26 + 6 * 4)
    }
}

private struct CronField: View {
    @Environment(\.theme) private var theme
    let expression: String
    let onChange: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Expression", text: Binding(get: { expression }, set: { onChange($0) }), prompt: Text("*/15 * * * *"))
                .font(.system(.body, design: .monospaced))
            Text("minute · hour · day of month · month · weekday")
                .font(.caption)
                .foregroundStyle(theme.secondary)
            if let error = Schedule.cron(expression: expression).validationMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(theme.danger)
            }
        }
    }
}

/// Plain-language summary plus the next few fire dates.
struct SchedulePreview: View {
    @Environment(\.theme) private var theme
    let schedule: Schedule
    var count = 3

    var body: some View {
        let dates = schedule.validationMessage == nil ? schedule.nextDates(after: Date(), count: count) : []
        VStack(alignment: .leading, spacing: 6) {
            Text(schedule.summary)
                .font(.callout.weight(.medium))
            if !dates.isEmpty {
                HStack(spacing: 6) {
                    Text(schedule.isApproximate ? "About" : "Next")
                        .foregroundStyle(theme.secondary)
                    ForEach(dates, id: \.self) { date in
                        Pill(text: date.dayAndTime)
                    }
                }
                .font(.caption)
            }
        }
    }
}
