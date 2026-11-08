import AppKit
import CronBuddyCore
import SwiftUI

/// Live output of a run started from the app.
struct RunConsoleView: View {
    @Environment(\.theme) private var theme
    let session: RunSession
    var onClose: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            ScrollViewReader { proxy in
                ScrollView {
                    Text(session.output.isEmpty ? placeholder : session.output)
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(session.output.isEmpty ? theme.secondary : theme.text)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                    Color.clear.frame(height: 1).id("bottom")
                }
                .frame(minHeight: 120, maxHeight: 300)
                .background(theme.raised, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(theme.border))
                .onChange(of: session.output) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
        }
        .padding(14)
        .surface(theme, in: RoundedRectangle(cornerRadius: theme.isGlass ? 18 : 12, style: .continuous), bordered: false)
        .overlay(RoundedRectangle(cornerRadius: theme.isGlass ? 18 : 12, style: .continuous).strokeBorder(stateColor.opacity(0.5)))
    }

    private var placeholder: String {
        session.isRunning ? "Waiting for output…" : "No output."
    }

    private var stateColor: Color {
        switch session.state {
        case .running: theme.accent
        case .finished(let code): code == 0 ? theme.success : theme.danger
        case .failed: theme.danger
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            switch session.state {
            case .running:
                ProgressView().controlSize(.small)
                Text("Running…").font(.headline)
            case .finished(let code):
                Image(systemName: code == 0 ? "checkmark.circle.fill" : "xmark.octagon.fill")
                    .foregroundStyle(stateColor)
                Text(code == 0 ? "Finished" : "Exited with code \(code)").font(.headline)
            case .failed(let message):
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(theme.danger)
                Text(message).font(.headline).lineLimit(2)
            }

            TimelineView(.periodic(from: session.startedAt, by: 0.1)) { _ in
                Text(session.elapsed.compactDuration)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(theme.secondary)
                    .monospacedDigit()
            }

            Spacer()

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(session.output, forType: .string)
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .disabled(session.output.isEmpty)

            if session.isRunning {
                Button(role: .destructive) { session.stop() } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
            } else if let onClose {
                Button { onClose() } label: { Image(systemName: "xmark") }
                    .buttonStyle(.borderless)
                    .help("Dismiss")
            }
        }
        .controlSize(.small)
    }
}

/// Output of a past run, with search.
struct LogViewer: View {
    @Environment(\.theme) private var theme
    @Environment(AppModel.self) private var model
    let record: RunRecord
    var jobName: String?
    @State private var query = ""
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: record.succeeded ? "checkmark.circle.fill" : "xmark.octagon.fill")
                    .foregroundStyle(record.succeeded ? theme.success : theme.danger)
                VStack(alignment: .leading, spacing: 1) {
                    Text(jobName.map { "\($0) · \(record.start.dayAndTime)" } ?? record.start.dayAndTime)
                        .font(.headline)
                    Text("\(record.trigger == .manual ? "Manual run" : "Scheduled run") · exit \(record.exitCode) · \(record.duration.compactDuration)")
                        .font(.caption)
                        .foregroundStyle(theme.secondary)
                }
                Spacer()
                TextField("Search output", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 170)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                } label: { Image(systemName: "doc.on.doc") }
                    .help("Copy output")
                Button {
                    Finder.reveal(RunHistory.logURL(record, paths: model.paths))
                } label: { Image(systemName: "folder") }
                    .help("Show log file in Finder")
            }
            .controlSize(.small)

            ScrollView([.vertical, .horizontal]) {
                Text(highlighted)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.raised, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(theme.border))
        }
        .task(id: record.id) {
            text = RunHistory.logText(record, paths: model.paths)
        }
    }

    private var highlighted: AttributedString {
        var attributed = AttributedString(text.isEmpty ? "No output." : text)
        if text.isEmpty { attributed.foregroundColor = theme.secondary }
        guard !query.isEmpty else { return attributed }
        var searchRange = attributed.startIndex..<attributed.endIndex
        while let found = attributed[searchRange].range(of: query, options: .caseInsensitive) {
            attributed[found].backgroundColor = theme.accent.opacity(0.35)
            searchRange = found.upperBound..<attributed.endIndex
        }
        return attributed
    }
}
