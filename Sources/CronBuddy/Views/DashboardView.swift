import CronBuddyCore
import SwiftUI

struct DashboardView: View {
    @Environment(\.theme) private var theme
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.jobs.isEmpty {
            EmptyState(
                symbol: "clock.badge.checkmark",
                title: "Welcome to CronBuddy",
                message: "Schedule commands, scripts, AppleScripts and Shortcuts. Start from a template or build your own.",
                actionTitle: "Browse Templates"
            ) {
                model.selection = .templates
            }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    SectionTitle(title: "Overview", subtitle: model.now.formatted(date: .complete, time: .omitted))
                    stats
                    Card(title: "Next 24 hours", symbol: "timeline.selection") {
                        DayTimeline(now: model.now)
                    }
                    Card(title: "Up next", symbol: "forward.end") {
                        upcomingList
                    }
                    recentCard
                }
                .padding(24)
            }
        }
    }

    private var stats: some View {
        let dayAgo = model.now.addingTimeInterval(-24 * 3600)
        let today = model.allRuns.filter { $0.start > dayAgo }
        let failures = today.filter { !$0.succeeded }.count
        let next = model.nextRunPerJob(limit: 1).first
        return HStack(spacing: 14) {
            Stat(label: "Active jobs", value: "\(model.jobs.filter(\.isEnabled).count)",
                 detail: "\(model.jobs.count) total")
            Stat(label: "Runs, 24 h", value: "\(today.count)",
                 detail: today.isEmpty ? "Nothing ran yet" : "\(today.count - failures) succeeded")
            Stat(label: "Failures, 24 h", value: "\(failures)",
                 detail: failures == 0 ? "All clear" : "Review in Activity",
                 tint: failures > 0 ? theme.danger : nil)
            Stat(label: "Next run", value: next.map { $0.date.timeString } ?? "—",
                 detail: next.map { "\($0.job.name) · \($0.date.relative(to: model.now))" })
        }
    }

    @ViewBuilder
    private var upcomingList: some View {
        let runs = model.nextRunPerJob()
        if runs.isEmpty {
            Text("Nothing scheduled.").foregroundStyle(theme.secondary)
        } else {
            VStack(spacing: 0) {
                ForEach(runs) { run in
                    Button { model.selection = .job(run.job.id) } label: {
                        HStack(spacing: 12) {
                            Text(run.date.dayAndTime)
                                .font(.system(.callout, design: .monospaced))
                                .frame(width: 170, alignment: .leading)
                            ActionBadge(kind: run.job.action.kind, size: 20)
                            Text(run.job.name).lineLimit(1)
                            Spacer()
                            Text((run.job.schedule.isApproximate ? "≈ " : "") + run.date.relative(to: model.now))
                                .font(.caption)
                                .foregroundStyle(theme.secondary)
                        }
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if run.id != runs.last?.id { Divider().overlay(theme.border) }
                }
            }
        }
    }

    private var recentCard: some View {
        Card(title: "Recent runs", symbol: "clock.arrow.circlepath") {
            let recent = Array(model.allRuns.prefix(8))
            if recent.isEmpty {
                Text("Runs appear here as they happen.").foregroundStyle(theme.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(recent) { record in
                        Button { model.selection = .job(record.jobID) } label: {
                            RunRow(record: record, jobName: model.job(record.jobID)?.name ?? "Deleted job")
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 3)
                        if record.id != recent.last?.id { Divider().overlay(theme.border) }
                    }
                }
            }
        }
    }
}

/// One lane per job across the next 24 hours, with a mark for each run.
private struct DayTimeline: View {
    @Environment(\.theme) private var theme
    @Environment(AppModel.self) private var model
    let now: Date
    private let horizon: TimeInterval = 24 * 3600
    private let labelWidth: CGFloat = 170
    private let denseThreshold = 48

    private var lanes: [(job: Job, dates: [Date])] {
        model.sortedJobs.compactMap { job in
            let dates = model.nextDates(job, count: denseThreshold + 1).filter { $0.timeIntervalSince(now) <= horizon }
            return dates.isEmpty ? nil : (job, dates)
        }
    }

    var body: some View {
        let lanes = lanes
        VStack(alignment: .leading, spacing: 10) {
            if lanes.isEmpty {
                Text("Nothing runs in the next 24 hours.").foregroundStyle(theme.secondary)
            }
            ForEach(lanes, id: \.job.id) { lane in
                HStack(spacing: 12) {
                    Text(lane.job.name)
                        .font(.callout)
                        .lineLimit(1)
                        .frame(width: labelWidth, alignment: .leading)
                    GeometryReader { geometry in
                        let width = geometry.size.width
                        ZStack(alignment: .leading) {
                            Capsule().fill(theme.raised).frame(height: 6)
                            if lane.dates.count > denseThreshold {
                                // Too dense for individual marks: it runs throughout the day.
                                Capsule()
                                    .fill(theme.accent.opacity(0.55))
                                    .frame(width: width, height: 6)
                            } else {
                                ForEach(lane.dates, id: \.self) { date in
                                    Circle()
                                        .fill(theme.accent)
                                        .frame(width: 9, height: 9)
                                        .overlay(Circle().strokeBorder(theme.surface, lineWidth: 1.5))
                                        .offset(x: width * CGFloat(position(date)) - 4.5)
                                        .help("\(lane.job.name) · \(date.timeString)")
                                }
                            }
                        }
                        .frame(height: 12)
                    }
                    .frame(height: 12)
                    Text(lane.dates.count > denseThreshold ? "\(denseThreshold)+ runs" : lane.dates.count == 1 ? "1 run" : "\(lane.dates.count) runs")
                        .font(.caption)
                        .foregroundStyle(theme.secondary)
                        .frame(width: 60, alignment: .trailing)
                }
            }
            HStack(spacing: 12) {
                Color.clear.frame(width: labelWidth, height: 1)
                HStack {
                    ForEach(0..<5) { i in
                        Text(i == 0 ? "Now" : now.addingTimeInterval(Double(i) * 6 * 3600).timeString)
                            .font(.caption2)
                            .foregroundStyle(theme.secondary)
                        if i < 4 { Spacer() }
                    }
                }
                Color.clear.frame(width: 60, height: 1)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func position(_ date: Date) -> Double {
        min(max(date.timeIntervalSince(now) / horizon, 0), 1)
    }
}
