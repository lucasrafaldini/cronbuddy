import AppKit
import CronBuddyCore
import SwiftUI

struct MainWindow: View {
    @Environment(\.theme) private var theme
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            Sidebar()
                .navigationSplitViewColumnWidth(min: 210, ideal: 240, max: 320)
        } detail: {
            Group {
                switch model.selection ?? .overview {
                case .overview: DashboardView()
                case .activity: ActivityView()
                case .templates: TemplatesView()
                case .external: ExternalView()
                case .job(let id):
                    if let job = model.job(id) {
                        JobDetailView(job: job).id(id)
                    } else {
                        DashboardView()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .windowBackground(theme)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { model.newJob() } label: { Label("New Job", systemImage: "plus") }
                    .help("New job (⌘N)")
                    .keyboardShortcut("n")
            }
        }
        .sheet(item: $model.editorRequest) { request in
            JobEditorView(request: request)
                .themed(theme)
        }
        .alert("CronBuddy", isPresented: Binding(
            get: { model.alertMessage != nil },
            set: { if !$0 { model.alertMessage = nil } }
        )) {
            Button("OK") { model.alertMessage = nil }
        } message: {
            Text(model.alertMessage ?? "")
        }
        .toolbarBackground(theme.usesNativeChrome ? Color.clear : theme.background, for: .windowToolbar)
        .toolbarBackground(theme.usesNativeChrome ? .automatic : .visible, for: .windowToolbar)
        .frame(minWidth: 860, minHeight: 560)
        .onAppear {
            // Also covers windows macOS restores or reopens without going through the menu bar.
            if NSApp.activationPolicy() != .regular { AppPresence.show() }
        }
    }
}

private struct Sidebar: View {
    @Environment(\.theme) private var theme
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        List(selection: $model.selection) {
            Section {
                Label("Overview", systemImage: "square.grid.2x2").tag(SidebarItem.overview)
                Label("Activity", systemImage: "list.bullet.rectangle").tag(SidebarItem.activity)
                Label("Templates", systemImage: "sparkles.rectangle.stack").tag(SidebarItem.templates)
                Label("Import from crontab", systemImage: "square.and.arrow.down")
                    .badge(model.externalEntries.count)
                    .tag(SidebarItem.external)
            }

            Section("Jobs") {
                if model.jobs.isEmpty {
                    Text("No jobs yet").foregroundStyle(theme.secondary)
                }
                ForEach(model.sortedJobs) { job in
                    HStack(spacing: 8) {
                        StatusDot(status: model.status(job), size: 7)
                        Text(job.name).lineLimit(1)
                            .foregroundStyle(job.isEnabled ? theme.text : theme.secondary)
                    }
                    .tag(SidebarItem.job(job.id))
                    .contextMenu { JobMenuItems(job: job) }
                }
            }
        }
        .listStyle(.sidebar)
        .themedBackground(theme, \.surface)
    }
}

/// Shared between the sidebar context menu and the detail view's menu.
struct JobMenuItems: View {
    @Environment(AppModel.self) private var model
    let job: Job

    var body: some View {
        Button("Run Now") { model.runNow(job) }
        Button(job.isEnabled ? "Pause" : "Resume") { model.setEnabled(!job.isEnabled, for: job) }
        Button("Edit…") { model.edit(job) }
        Button("Duplicate") {
            let copy = model.duplicate(job)
            model.selection = .job(copy.id)
        }
        Divider()
        Button("Show Action Script in Finder") { Finder.reveal(model.paths.actionScript(for: job.id)) }
        Button("Show Logs in Finder") { Finder.reveal(model.paths.logDir(for: job.id)) }
        Divider()
        Button("Delete", role: .destructive) { confirmDelete() }
    }

    private func confirmDelete() {
        let alert = NSAlert()
        alert.messageText = "Delete “\(job.name)”?"
        alert.informativeText = "The job is unscheduled and its run history is removed. This can’t be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        if alert.runModal() == .alertFirstButtonReturn {
            model.delete(job)
        }
    }
}
