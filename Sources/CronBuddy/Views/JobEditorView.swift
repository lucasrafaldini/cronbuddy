import AppKit
import CronBuddyCore
import SwiftUI
import UniformTypeIdentifiers

struct JobEditorView: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model

    @State private var draft: Job
    private let isNew: Bool
    @State private var testSession: RunSession?
    @State private var shortcuts: [String] = []
    @State private var loadingShortcuts = false
    @State private var environmentRows: [EnvironmentRow]

    struct EnvironmentRow: Identifiable, Hashable {
        let id = UUID()
        var key: String
        var value: String
    }

    init(request: EditorRequest) {
        _draft = State(initialValue: request.job)
        isNew = request.isNew
        _environmentRows = State(initialValue: request.job.environment.keys.sorted().map {
            EnvironmentRow(key: $0, value: request.job.environment[$0] ?? "")
        })
    }

    private var assembled: Job {
        var job = draft
        job.environment = Dictionary(
            environmentRows
                .filter { !$0.key.trimmingCharacters(in: .whitespaces).isEmpty }
                .map { ($0.key.trimmingCharacters(in: .whitespaces), $0.value) },
            uniquingKeysWith: { _, last in last }
        )
        return job
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ActionBadge(kind: draft.action.kind, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(isNew ? "New Job" : "Edit Job")
                        .font(.system(.title2).weight(.semibold)).fontDesign(theme.titleDesign)
                    Text(draft.schedule.summary)
                        .font(.callout)
                        .foregroundStyle(theme.secondary)
                }
                Spacer()
            }
            .padding(20)

            Form {
                Section {
                    TextField("Name", text: $draft.name, prompt: Text("Morning backup"))
                }

                Section("Action") {
                    Picker("Type", selection: actionKind) {
                        ForEach(JobAction.Kind.allCases) { kind in
                            Label(kind.title, systemImage: kind.symbol).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)
                    actionFields
                }

                Section("Schedule") {
                    ScheduleEditor(schedule: $draft.schedule)
                    SchedulePreview(schedule: draft.schedule)
                }

                Section {
                    Picker("Scheduler", selection: $draft.backend) {
                        ForEach(Backend.allCases) { backend in
                            Text(backend == .launchd ? "launchd (recommended)" : "cron").tag(backend)
                        }
                    }
                    .pickerStyle(.radioGroup)
                    Text(draft.backend.explanation)
                        .font(.caption)
                        .foregroundStyle(theme.secondary)
                } header: {
                    Text("Runs with")
                }

                Section {
                    ForEach($environmentRows) { $row in
                        HStack {
                            TextField("NAME", text: $row.key)
                                .font(.system(.body, design: .monospaced))
                                .frame(maxWidth: 170)
                            TextField("value", text: $row.value)
                            Button {
                                environmentRows.removeAll { $0.id == row.id }
                            } label: { Image(systemName: "minus.circle") }
                                .buttonStyle(.borderless)
                        }
                    }
                    Button {
                        environmentRows.append(EnvironmentRow(key: "", value: ""))
                    } label: { Label("Add variable", systemImage: "plus.circle") }
                        .buttonStyle(.borderless)
                } header: {
                    Text("Environment")
                } footer: {
                    Text("Exported before the action runs. Templates use these for settings like your city or a URL.")
                        .font(.caption)
                        .foregroundStyle(theme.secondary)
                }

                Section("Notifications") {
                    Toggle("Notify when a run fails", isOn: $draft.notifyOnFailure)
                    Toggle("Notify when a run succeeds, with its output", isOn: $draft.notifyOnSuccess)
                }

                let job = assembled
                if !job.problems.isEmpty || !job.warnings.isEmpty {
                    Section {
                        ForEach(job.problems, id: \.self) { problem in
                            Label(problem, systemImage: "xmark.circle.fill").foregroundStyle(theme.danger)
                        }
                        ForEach(job.warnings, id: \.self) { warning in
                            Label(warning, systemImage: "exclamationmark.triangle.fill").foregroundStyle(theme.warning)
                        }
                    }
                    .font(.callout)
                }

                if let testSession {
                    Section("Test run") {
                        RunConsoleView(session: testSession) { self.testSession = nil }
                            .listRowInsets(EdgeInsets())
                    }
                }
            }
            .formStyle(.grouped)
            .themedBackground(theme)

            Divider()
            HStack {
                Button {
                    testSession?.stop()
                    testSession = model.testRun(assembled)
                } label: {
                    Label("Test Run", systemImage: "play")
                }
                .disabled(assembled.action.isEmpty || testSession?.isRunning == true)
                .help("Runs the action now, as written, without saving")

                Spacer()
                Button("Cancel", role: .cancel) {
                    testSession?.stop()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button(isNew ? "Create Job" : "Save") {
                    testSession?.stop()
                    model.save(assembled)
                    model.selection = .job(draft.id)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .prominentButton(theme)
                .disabled(!assembled.problems.isEmpty)
            }
            .padding(16)
        }
        .frame(width: 640, height: 760)
        .windowBackground(theme, backdrop: false)
        .task {
            if case .shortcut = draft.action { await loadShortcuts() }
        }
    }

    // MARK: Action

    private var actionKind: Binding<JobAction.Kind> {
        Binding(
            get: { draft.action.kind },
            set: { kind in
                guard kind != draft.action.kind else { return }
                draft.action = .empty(kind)
                if kind == .shortcut, shortcuts.isEmpty { Task { await loadShortcuts() } }
            }
        )
    }

    @ViewBuilder
    private var actionFields: some View {
        switch draft.action {
        case .shell(let command):
            CodeEditor(text: Binding(get: { command }, set: { draft.action = .shell(command: $0) }),
                       placeholder: "echo \"Hello from CronBuddy\"")
            Text("Runs with zsh. Homebrew and /usr/local are on the PATH.")
                .font(.caption)
                .foregroundStyle(theme.secondary)

        case .script(let path):
            HStack {
                TextField("Path", text: Binding(get: { path }, set: { draft.action = .script(path: $0) }),
                          prompt: Text("~/Scripts/backup.sh"))
                    .font(.system(.body, design: .monospaced))
                Button("Choose…") { chooseScript() }
            }
            Text("Shell, Python, Ruby, AppleScript (.scpt), JavaScript for Automation (.js) and Automator workflows (.workflow).")
                .font(.caption)
                .foregroundStyle(theme.secondary)

        case .appleScript(let source):
            CodeEditor(text: Binding(get: { source }, set: { draft.action = .appleScript(source: $0) }),
                       placeholder: "display notification \"Hello\" with title \"CronBuddy\"")
            Text("macOS asks for permission the first time a script controls another app.")
                .font(.caption)
                .foregroundStyle(theme.secondary)

        case .shortcut(let name):
            HStack {
                Picker("Shortcut", selection: Binding(get: { name }, set: { draft.action = .shortcut(name: $0) })) {
                    Text("Choose a shortcut").tag("")
                    if !name.isEmpty, !shortcuts.contains(name) { Text(name).tag(name) }
                    ForEach(shortcuts, id: \.self) { Text($0).tag($0) }
                }
                if loadingShortcuts {
                    ProgressView().controlSize(.small)
                } else {
                    Button { Task { await loadShortcuts() } } label: { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(.borderless)
                        .help("Reload shortcuts")
                }
            }
            HStack {
                Text(shortcuts.isEmpty && !loadingShortcuts ? "No shortcuts found." : "Runs in the background through the Shortcuts app.")
                    .font(.caption)
                    .foregroundStyle(theme.secondary)
                Spacer()
                Button(name.isEmpty ? "Open Shortcuts" : "Open in Shortcuts") {
                    name.isEmpty ? Finder.openShortcutsApp() : Finder.openShortcut(named: name)
                }
                .buttonStyle(.link)
                .font(.caption)
            }
        }
    }

    private func loadShortcuts() async {
        loadingShortcuts = true
        shortcuts = await Task.detached(priority: .userInitiated) { ShortcutsCatalog.names() }.value
        loadingShortcuts = false
    }

    private func chooseScript() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.treatsFilePackagesAsDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose a script or Automator workflow to run"
        if panel.runModal() == .OK, let url = panel.url {
            draft.action = .script(path: url.path)
        }
    }
}

/// A monospaced multi-line editor with a placeholder.
struct CodeEditor: View {
    @Environment(\.theme) private var theme
    @Binding var text: String
    var placeholder: String

    var body: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $text)
                .font(.system(.callout, design: .monospaced))
                .scrollContentBackground(.hidden)
                .autocorrectionDisabled()
                .padding(6)
            if text.isEmpty {
                Text(placeholder)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(theme.secondary.opacity(0.7))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .allowsHitTesting(false)
            }
        }
        .frame(minHeight: 110, maxHeight: 220)
        .background(theme.raised, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(theme.border))
    }
}
