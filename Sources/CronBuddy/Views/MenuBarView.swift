import AppKit
import CronBuddyCore
import SwiftUI

struct MenuBarLabel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @AppStorage("showCountdown") private var showCountdown = true
    @AppStorage("didOnboard") private var didOnboard = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
            if showCountdown, let next = model.nextRunPerJob(limit: 1).first {
                Text(countdown(to: next.date))
                    .monospacedDigit()
            }
        }
        .accessibilityLabel("CronBuddy")
        // The label is the only view alive at launch, so it owns window requests.
        .onReceive(NotificationCenter.default.publisher(for: .openMainWindow)) { _ in showMainWindow() }
        .onReceive(NotificationCenter.default.publisher(for: .openSettingsWindow)) { _ in
            AppPresence.show { openSettings() }
        }
        .task {
            if !didOnboard {
                didOnboard = true
                showMainWindow()
            }
        }
    }

    private func showMainWindow() {
        AppPresence.show { openWindow(id: "main") }
    }

    private var symbol: String {
        if model.isAnythingRunning { return "clock.arrow.2.circlepath" }
        if model.hasRecentFailure { return "clock.badge.exclamationmark" }
        return "clock"
    }

    private func countdown(to date: Date) -> String {
        let minutes = Int(ceil(date.timeIntervalSince(model.now) / 60))
        if minutes <= 1 { return "<1m" }
        if minutes < 60 { return "\(minutes)m" }
        if minutes < 24 * 60 { return "\(minutes / 60)h" }
        return "\(minutes / (24 * 60))d"
    }
}

struct MenuBarView: View {
    @Environment(\.theme) private var theme
    @Environment(AppModel.self) private var model
    @AppStorage("theme") private var themeID = Theme.system.id
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(theme.border)

            if model.jobs.isEmpty {
                EmptyState(
                    symbol: "clock.badge.checkmark",
                    title: "Nothing scheduled",
                    message: "Start from a template or create your own job.",
                    actionTitle: "Browse Templates"
                ) {
                    open(.templates)
                }
                .frame(height: 260)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: theme.isGlass ? 10 : 14) {
                        upNext
                        jobsList
                    }
                    .padding(12)
                }
                .frame(maxHeight: 460)
                .fixedSize(horizontal: false, vertical: true)
            }

            Divider().overlay(theme.border)
            footer
        }
        .frame(width: 380)
        .windowBackground(theme, backdrop: false)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "clock")
                .font(.title3.weight(.semibold))
                .foregroundStyle(theme.accent)
            VStack(alignment: .leading, spacing: 0) {
                Text("CronBuddy")
                    .font(.system(.headline)).fontDesign(theme.titleDesign)
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(theme.secondary)
            }
            Spacer()
            Group {
                Button { newJob() } label: { Image(systemName: "plus") }
                    .help("New job")
                Button { open(.overview) } label: { Image(systemName: "macwindow") }
                    .help("Open CronBuddy")
                Menu {
                    Picker("Theme", selection: $themeID) {
                        ForEach(Theme.all) { Text($0.name).tag($0.id) }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Image(systemName: "paintpalette")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Theme")
                .accessibilityLabel("Theme")
                Button {
                    AppPresence.show { openSettings() }
                } label: { Image(systemName: "gearshape") }
                    .help("Settings (⌘,)")
            }
            .buttonStyle(.borderless)
            .font(.body.weight(.medium))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var summary: String {
        let active = model.jobs.filter(\.isEnabled).count
        let paused = model.jobs.count - active
        var parts = ["\(active) active"]
        if paused > 0 { parts.append("\(paused) paused") }
        let failing = model.jobs.filter { model.status($0) == .failed }.count
        if failing > 0 { parts.append("\(failing) failing") }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var upNext: some View {
        let upcoming = model.nextRunPerJob(limit: 4)
        if !upcoming.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                caption("Up next")
                ForEach(upcoming) { run in
                    HStack(spacing: 10) {
                        Text(run.date.timeString)
                            .font(.system(.callout, design: .monospaced).weight(.medium))
                            .frame(width: 64, alignment: .leading)
                        Text(run.job.name)
                            .lineLimit(1)
                        Spacer()
                        Text((run.job.schedule.isApproximate ? "≈ " : "") + run.date.relative(to: model.now))
                            .font(.caption)
                            .foregroundStyle(theme.secondary)
                    }
                    .font(.callout)
                }
            }
            .glassPlatter(theme)
        }
    }

    private var jobsList: some View {
        VStack(alignment: .leading, spacing: 4) {
            caption("Jobs")
            ForEach(model.sortedJobs) { job in
                MenuJobRow(job: job) { open(.job(job.id)) }
            }
        }
        .glassPlatter(theme)
    }

    private func caption(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.caption2.weight(.semibold))
            .tracking(1.1)
            .foregroundStyle(theme.secondary)
            .padding(.horizontal, 2)
    }

    private var footer: some View {
        HStack {
            if model.hasRecentFailure {
                Button { open(.activity) } label: {
                    Label("Review failures", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(theme.danger)
                }
                .buttonStyle(.borderless)
            } else {
                Text("Logs in ~/Library/Logs/CronBuddy")
                    .font(.caption)
                    .foregroundStyle(theme.secondary)
            }
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.borderless)
                .keyboardShortcut("q")
        }
        .font(.callout)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func open(_ item: SidebarItem) {
        model.selection = item
        AppPresence.show { openWindow(id: "main") }
    }

    private func newJob() {
        open(.overview)
        model.newJob()
    }
}

private struct MenuJobRow: View {
    @Environment(\.theme) private var theme
    @Environment(AppModel.self) private var model
    let job: Job
    let onOpen: () -> Void
    @State private var hovering = false

    var body: some View {
        let status = model.status(job)
        HStack(spacing: 10) {
            StatusDot(status: status)
            VStack(alignment: .leading, spacing: 1) {
                Text(job.name)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .foregroundStyle(job.isEnabled ? theme.text : theme.secondary)
                Text(detail(status))
                    .font(.caption)
                    .foregroundStyle(status == .failed ? theme.danger : theme.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if hovering || status == .running {
                HStack(spacing: 2) {
                    if status == .running {
                        ProgressView().controlSize(.mini)
                    } else {
                        iconButton("play.fill", help: "Run now") { model.runNow(job) }
                    }
                    iconButton(job.isEnabled ? "pause.fill" : "arrow.clockwise", help: job.isEnabled ? "Pause" : "Resume") {
                        model.setEnabled(!job.isEnabled, for: job)
                    }
                }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(hovering ? theme.raised : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .onTapGesture(perform: onOpen)
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: "Run now") { model.runNow(job) }
        .accessibilityAction(named: job.isEnabled ? "Pause" : "Resume") { model.setEnabled(!job.isEnabled, for: job) }
    }

    private func detail(_ status: JobStatus) -> String {
        var parts = [job.schedule.summary]
        if let last = model.lastRun(job) {
            parts.append((last.succeeded ? "ran " : "failed ") + last.start.relative(to: model.now))
        } else if !job.isEnabled {
            parts.append("paused")
        }
        return parts.joined(separator: " · ")
    }

    private func iconButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.caption)
                .frame(width: 22, height: 22)
                .surface(theme, in: Circle(), interactive: true)
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
