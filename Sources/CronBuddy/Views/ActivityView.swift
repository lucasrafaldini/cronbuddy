import CronBuddyCore
import SwiftUI

struct ActivityView: View {
    @Environment(\.theme) private var theme
    @Environment(AppModel.self) private var model
    @State private var selection: RunRecord.ID?
    @State private var onlyFailures = false
    @State private var search = ""

    private var filtered: [RunRecord] {
        model.allRuns.filter { record in
            (!onlyFailures || !record.succeeded)
                && (search.isEmpty || name(record).localizedCaseInsensitiveContains(search))
        }
    }

    private func name(_ record: RunRecord) -> String {
        model.job(record.jobID)?.name ?? "Deleted job"
    }

    var body: some View {
        let runs = filtered
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .bottom) {
                SectionTitle(title: "Activity", subtitle: "Every run from every job, newest first.")
                Spacer()
                Picker("", selection: $onlyFailures) {
                    Text("All runs").tag(false)
                    Text("Failures").tag(true)
                }
                .pickerStyle(.segmented)
                .fixedSize()
                TextField("Filter by job", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
            }

            if runs.isEmpty {
                EmptyState(
                    symbol: onlyFailures ? "checkmark.seal" : "tray",
                    title: onlyFailures ? "No failures" : "No runs yet",
                    message: onlyFailures ? "Everything that ran exited cleanly." : "Runs appear here as soon as a job fires or you use Run Now."
                )
            } else {
                VSplitView {
                    Table(runs, selection: $selection) {
                        TableColumn("") { record in
                            Image(systemName: record.succeeded ? "checkmark.circle.fill" : "xmark.octagon.fill")
                                .foregroundStyle(record.succeeded ? theme.success : theme.danger)
                        }
                        .width(22)
                        TableColumn("Job") { record in Text(name(record)) }
                        TableColumn("Started") { record in Text(record.start.dayAndTime) }
                            .width(min: 140, ideal: 170)
                        TableColumn("Duration") { record in Text(record.duration.compactDuration).monospacedDigit() }
                            .width(80)
                        TableColumn("Trigger") { record in
                            Text(record.trigger == .manual ? "Manual" : "Schedule").foregroundStyle(theme.secondary)
                        }
                        .width(80)
                        TableColumn("Exit") { record in
                            Text("\(record.exitCode)")
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(record.succeeded ? theme.secondary : theme.danger)
                        }
                        .width(44)
                    }
                    .themedBackground(theme, \.surface)
                    .frame(minHeight: 180)

                    Group {
                        if let record = runs.first(where: { $0.id == selection }) {
                            LogViewer(record: record, jobName: name(record))
                        } else {
                            Text("Select a run to see its output.")
                                .foregroundStyle(theme.secondary)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                    .padding(.top, 12)
                    .frame(minHeight: 200)
                }
            }
        }
        .padding(24)
        .onAppear { if selection == nil { selection = filtered.first?.id } }
    }
}
