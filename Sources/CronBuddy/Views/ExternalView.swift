import AppKit
import CronBuddyCore
import SwiftUI

struct ExternalView: View {
    @Environment(\.theme) private var theme
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .bottom) {
                SectionTitle(
                    title: "Import from crontab",
                    subtitle: "Entries already in your crontab that CronBuddy doesn’t manage yet. Importing moves them under CronBuddy with logging and history."
                )
                Spacer()
                Button { model.refreshExternal() } label: { Label("Refresh", systemImage: "arrow.clockwise") }
            }

            if model.externalEntries.isEmpty {
                EmptyState(
                    symbol: "checkmark.seal",
                    title: "Nothing to import",
                    message: "Your crontab has no entries outside CronBuddy."
                )
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(model.externalEntries) { entry in
                            row(entry)
                        }
                    }
                }
            }
        }
        .padding(24)
    }

    private func row(_ entry: ExternalCronEntry) -> some View {
        Card {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text(entry.comment ?? "Untitled entry").font(.headline)
                        Pill(text: entry.schedule, symbol: "clock")
                        if entry.isLegacyCronBuddy {
                            Pill(text: "CronBuddy 1.x", symbol: "shield.lefthalf.filled", color: theme.accent)
                        }
                    }
                    Text((Schedule.structured(fromCron: entry.schedule) ?? .cron(expression: entry.schedule)).summary)
                        .font(.callout)
                        .foregroundStyle(theme.secondary)
                    CodeBlock(text: entry.command, maxHeight: 90)
                }
                Spacer()
                Button("Import") { confirm(entry) }
                    .prominentButton(theme)
            }
        }
    }

    private func confirm(_ entry: ExternalCronEntry) {
        let alert = NSAlert()
        alert.messageText = "Import this crontab entry?"
        alert.informativeText = "CronBuddy replaces the line in your crontab with a managed one that runs the same command on the same schedule, now with logs and history."
        alert.addButton(withTitle: "Import")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            model.adopt(entry)
        }
    }
}
