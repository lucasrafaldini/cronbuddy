import CronBuddyCore
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings().tabItem { Label("General", systemImage: "gearshape") }
            AppearanceSettings().tabItem { Label("Appearance", systemImage: "paintpalette") }
            AdvancedSettings().tabItem { Label("Advanced", systemImage: "wrench.and.screwdriver") }
        }
        .frame(width: 560)
    }
}

private struct GeneralSettings: View {
    @Environment(\.theme) private var theme
    @Environment(AppModel.self) private var model
    @AppStorage("showCountdown") private var showCountdown = true
    @State private var openAtLogin = LoginItem.isEnabled
    @State private var loginError: String?

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                Toggle("Open CronBuddy at login", isOn: Binding(
                    get: { openAtLogin },
                    set: { newValue in
                        do {
                            try LoginItem.set(newValue)
                            openAtLogin = newValue
                            loginError = nil
                        } catch {
                            loginError = error.localizedDescription
                        }
                    }
                ))
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(theme.danger)
                }
                Text("Jobs keep running while CronBuddy is closed; the app is only needed for notifications and the menu bar.")
                    .font(.caption)
                    .foregroundStyle(theme.secondary)
            }
            Section("Menu bar") {
                Toggle("Show time until the next run", isOn: $showCountdown)
            }
            Section("History") {
                Stepper(value: $model.logRetention, in: 10...1000, step: 10) {
                    LabeledContent("Keep the last", value: "\(model.logRetention) runs per job")
                }
            }
        }
        .formStyle(.grouped)
        .themedBackground(theme)
        .frame(height: 340)
    }
}

private struct AppearanceSettings: View {
    @Environment(\.theme) private var current
    @AppStorage("theme") private var themeID = Theme.system.id

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 14)], spacing: 14) {
                ForEach(Theme.all) { theme in
                    Button { themeID = theme.id } label: {
                        ThemeSwatch(theme: theme, selected: themeID == theme.id)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(theme.name)
                    .accessibilityAddTraits(themeID == theme.id ? .isSelected : [])
                }
            }
            .padding(20)
        }
        .frame(height: 340)
        .themedBackground(current)
    }
}

private struct ThemeSwatch: View {
    let theme: Theme
    let selected: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(theme.background)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 5) {
                        Circle().fill(theme.success).frame(width: 7, height: 7)
                        RoundedRectangle(cornerRadius: 2).fill(theme.text).frame(width: 54, height: 6)
                    }
                    HStack(spacing: 5) {
                        Circle().fill(theme.danger).frame(width: 7, height: 7)
                        RoundedRectangle(cornerRadius: 2).fill(theme.secondary).frame(width: 40, height: 6)
                    }
                    Spacer()
                    HStack {
                        Spacer()
                        Capsule().fill(theme.accent).frame(width: 44, height: 14)
                    }
                }
                .padding(10)
                .background(theme.surface, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .padding(8)
            }
            .frame(height: 96)
            .environment(\.colorScheme, theme.scheme ?? scheme)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(selected ? theme.accent : Color.secondary.opacity(0.3), lineWidth: selected ? 2.5 : 1)
            )
            VStack(alignment: .leading, spacing: 1) {
                Text(theme.name).font(.system(.headline)).fontDesign(theme.titleDesign)
                Text(theme.tagline).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }
    }
}

private struct AdvancedSettings: View {
    @Environment(\.theme) private var theme
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section("Folders") {
                folder("Run logs", model.paths.logs)
                folder("Action scripts", model.paths.actionsDir)
                folder("Job definitions", model.paths.support)
                folder("Launch agents", model.paths.launchAgents)
            }
            Section("Maintenance") {
                LabeledContent("Reinstall every job") {
                    Button("Reinstall") { model.reinstallAll() }
                }
                Text("Rewrites action scripts, launch agents and crontab lines from your saved jobs. Useful after moving to a new Mac.")
                    .font(.caption)
                    .foregroundStyle(theme.secondary)
            }
            Section("Permissions") {
                LabeledContent("cron and protected folders") {
                    Button("Open Full Disk Access") { Finder.openFullDiskAccessSettings() }
                }
                Text("cron jobs that touch Documents, Desktop or Downloads need /usr/sbin/cron in Full Disk Access. launchd jobs don’t.")
                    .font(.caption)
                    .foregroundStyle(theme.secondary)
            }
        }
        .formStyle(.grouped)
        .themedBackground(theme)
        .frame(height: 340)
    }

    private func folder(_ title: String, _ url: URL) -> some View {
        LabeledContent(title) {
            Button((url.path as NSString).abbreviatingWithTildeInPath) { Finder.reveal(url) }
                .buttonStyle(.link)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}
