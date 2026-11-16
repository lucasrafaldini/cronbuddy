import CronBuddyCore
import SwiftUI

struct JobDetailView: View {
    @Environment(\.theme) private var theme
    @Environment(AppModel.self) private var model
    let job: Job
    @State private var selectedRun: RunRecord.ID?

    var body: some View {
        let status = model.status(job)
        let history = model.runs[job.id] ?? []

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header(status)

                if let session = model.sessions[job.id] {
                    RunConsoleView(session: session) { model.dismissSession(for: job) }
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                HStack(alignment: .top, spacing: 16) {
                    scheduleCard
                    statsCard(history)
                }

                actionCard

                if !job.environment.isEmpty {
                    Card(title: "Environment", symbol: "slider.horizontal.3") {
                        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                            ForEach(job.environment.keys.sorted(), id: \.self) { key in
                                GridRow {
                                    Text(key).font(.system(.callout, design: .monospaced).weight(.medium))
                                    Text(job.environment[key] ?? "").font(.system(.callout, design: .monospaced))
                                        .foregroundStyle(theme.secondary)
                                        .textSelection(.enabled)
                                }
                            }
                        }
                    }
                }

                historyCard(history)
            }
            .padding(24)
            .animation(.easeOut(duration: 0.2), value: model.sessions[job.id]?.id)
        }
    }

    // MARK: Header

    private func header(_ status: JobStatus) -> some View {
        HStack(alignment: .center, spacing: 14) {
            ActionBadge(kind: job.action.kind, size: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text(job.name)
                    .font(.system(size: 26, weight: .semibold)).fontDesign(theme.titleDesign)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    StatusDot(status: status)
                    Text(status.label)
                    Text("·")
                    Text(job.action.kind.title)
                    Text("·")
                    Text("via \(job.backend.title)")
                }
                .font(.callout)
                .foregroundStyle(theme.secondary)
            }
            Spacer()
            Toggle("Enabled", isOn: Binding(
                get: { job.isEnabled },
                set: { model.setEnabled($0, for: job) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .help(job.isEnabled ? "Pause this job" : "Resume this job")

            Button { model.runNow(job) } label: {
                Label("Run Now", systemImage: "play.fill")
            }
            .prominentButton(theme)
            .disabled(status == .running)
            .keyboardShortcut("r")

            Button("Edit") { model.edit(job) }
                .keyboardShortcut("e")

            Menu {
                JobMenuItems(job: job)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }

    // MARK: Cards

    private var scheduleCard: some View {
        Card(title: "Schedule", symbol: "calendar") {
            Text(job.schedule.summary)
                .font(.system(.title3).weight(.medium)).fontDesign(theme.titleDesign)
            let dates = model.nextDates(job, count: 5)
            if !job.isEnabled {
                Text("Paused. Resume to schedule the next run.")
                    .font(.callout)
                    .foregroundStyle(theme.secondary)
            } else if dates.isEmpty {
                Text(job.schedule.kind == .atLogin ? "Runs at your next login." : "No upcoming runs.")
                    .font(.callout)
                    .foregroundStyle(theme.secondary)
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(Array(dates.enumerated()), id: \.offset) { index, date in
                        HStack {
                            Text(date.dayAndTime)
                                .font(.callout.weight(index == 0 ? .semibold : .regular))
                            Spacer()
                            Text((job.schedule.isApproximate ? "≈ " : "") + date.relative(to: model.now))
                                .font(.caption)
                                .foregroundStyle(theme.secondary)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func statsCard(_ history: [RunRecord]) -> some View {
        Card(title: "Health", symbol: "waveform.path.ecg") {
            if history.isEmpty {
                Text("No runs yet. Use Run Now to try it.")
                    .font(.callout)
                    .foregroundStyle(theme.secondary)
            } else {
                let recent = Array(history.prefix(30))
                let successes = recent.filter(\.succeeded).count
                let average = recent.map(\.duration).reduce(0, +) / Double(recent.count)
                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                    GridRow {
                        metric("Success", "\(Int((Double(successes) / Double(recent.count) * 100).rounded()))%")
                        metric("Avg. time", average.compactDuration)
                        metric("Runs", "\(history.count)")
                    }
                }
                RunStrip(runs: Array(recent.reversed()))
                if let last = history.first {
                    Text("Last run \(last.start.relative(to: model.now)), \(last.succeeded ? "succeeded" : "exit code \(last.exitCode)")")
                        .font(.caption)
                        .foregroundStyle(last.succeeded ? theme.secondary : theme.danger)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(.title3).weight(.semibold)).fontDesign(theme.titleDesign).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(theme.secondary)
        }
    }

    private var actionCard: some View {
        Card(title: job.action.kind.title, symbol: job.action.kind.symbol) {
            switch job.action {
            case .shell(let command):
                CodeBlock(text: command)
            case .appleScript(let source):
                CodeBlock(text: source)
            case .script(let path):
                HStack {
                    Text(path).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                    Spacer()
                    Button("Show in Finder") { Finder.reveal(URL(fileURLWithPath: path)) }
                }
            case .shortcut(let name):
                HStack {
                    Text(name).font(.callout.weight(.medium))
                    Spacer()
                    Button("Open in Shortcuts") { Finder.openShortcut(named: name) }
                }
            }
        }
    }

    private func historyCard(_ history: [RunRecord]) -> some View {
        Card(title: "History", symbol: "clock.arrow.circlepath") {
            if history.isEmpty {
                Text("Every run, scheduled or manual, shows up here with its full output.")
                    .font(.callout)
                    .foregroundStyle(theme.secondary)
            } else {
                HStack(alignment: .top, spacing: 12) {
                    List(history, selection: $selectedRun) { record in
                        RunRow(record: record)
                            .tag(record.id)
                    }
                    .listStyle(.plain)
                    .themedBackground(theme, \.surface)
                    .frame(width: 250)

                    if let record = history.first(where: { $0.id == selectedRun }) ?? history.first {
                        LogViewer(record: record)
                    }
                }
                .frame(height: 360)
                .onAppear { if selectedRun == nil { selectedRun = history.first?.id } }
            }
        }
    }
}

struct RunRow: View {
    @Environment(\.theme) private var theme
    let record: RunRecord
    var jobName: String?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: record.succeeded ? "checkmark.circle.fill" : "xmark.octagon.fill")
                .foregroundStyle(record.succeeded ? theme.success : theme.danger)
            VStack(alignment: .leading, spacing: 1) {
                Text(jobName ?? record.start.dayAndTime).font(.callout).lineLimit(1)
                Text(jobName == nil
                     ? "\(record.duration.compactDuration)\(record.trigger == .manual ? " · manual" : "")"
                     : record.start.dayAndTime)
                    .font(.caption)
                    .foregroundStyle(theme.secondary)
            }
            Spacer()
            if !record.succeeded {
                Text("\(record.exitCode)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(theme.danger)
            }
        }
        .padding(.vertical, 2)
    }
}

/// One bar per recent run, coloured by outcome, height by duration.
struct RunStrip: View {
    @Environment(\.theme) private var theme
    let runs: [RunRecord]

    var body: some View {
        let longest = max(runs.map(\.duration).max() ?? 1, 0.001)
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(runs) { run in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(run.succeeded ? theme.success : theme.danger)
                    .frame(width: 6, height: 6 + 22 * CGFloat(run.duration / longest))
                    .help("\(run.start.dayAndTime) · \(run.duration.compactDuration)")
            }
        }
        .frame(height: 28, alignment: .bottom)
        .accessibilityHidden(true)
    }
}
