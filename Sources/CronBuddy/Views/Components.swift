import CronBuddyCore
import SwiftUI

struct Card<Content: View>: View {
    @Environment(\.theme) private var theme
    var title: String?
    var symbol: String?
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                HStack(spacing: 6) {
                    if let symbol {
                        Image(systemName: symbol).foregroundStyle(theme.accent)
                    }
                    Text(title.uppercased())
                        .font(.caption.weight(.semibold))
                        .tracking(1.2)
                        .foregroundStyle(theme.secondary)
                }
            }
            content
        }
        .padding(padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(theme.border))
    }
}

struct StatusDot: View {
    @Environment(\.theme) private var theme
    let status: JobStatus
    var size: CGFloat = 8
    @State private var pulse = false

    var body: some View {
        Circle()
            .fill(status.color(theme))
            .frame(width: size, height: size)
            .overlay {
                if status == .running {
                    Circle()
                        .stroke(status.color(theme), lineWidth: 1.5)
                        .scaleEffect(pulse ? 2.4 : 1)
                        .opacity(pulse ? 0 : 0.8)
                        .onAppear {
                            withAnimation(.easeOut(duration: 1.2).repeatForever(autoreverses: false)) { pulse = true }
                        }
                }
            }
            .help(status.label)
            .accessibilityLabel(status.label)
    }
}

struct ActionBadge: View {
    @Environment(\.theme) private var theme
    let kind: JobAction.Kind
    var size: CGFloat = 28

    var body: some View {
        Image(systemName: kind.symbol)
            .font(.system(size: size * 0.46, weight: .medium))
            .foregroundStyle(theme.accent)
            .frame(width: size, height: size)
            .background(theme.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
            .accessibilityLabel(kind.title)
    }
}

struct Pill: View {
    @Environment(\.theme) private var theme
    let text: String
    var symbol: String?
    var color: Color?

    var body: some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol) }
            Text(text)
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .foregroundStyle(color ?? theme.secondary)
        .background((color ?? theme.secondary).opacity(0.14), in: Capsule())
    }
}

struct CodeBlock: View {
    @Environment(\.theme) private var theme
    let text: String
    var maxHeight: CGFloat? = 220

    var body: some View {
        ScrollView([.vertical, .horizontal]) {
            Text(text.isEmpty ? " " : text)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
        }
        .frame(maxHeight: maxHeight)
        .fixedSize(horizontal: false, vertical: true)
        .background(theme.raised, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(theme.border))
    }
}

struct Stat: View {
    @Environment(\.theme) private var theme
    let label: String
    let value: String
    var detail: String?
    var tint: Color?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.caption2.weight(.semibold))
                .tracking(1)
                .foregroundStyle(theme.secondary)
            Text(value)
                .font(.system(size: 26, weight: .semibold)).fontDesign(theme.titleDesign)
                .foregroundStyle(tint ?? theme.text)
                .contentTransition(.numericText())
            if let detail {
                Text(detail).font(.caption).foregroundStyle(theme.secondary).lineLimit(1)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(theme.border))
    }
}

struct EmptyState: View {
    @Environment(\.theme) private var theme
    let symbol: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(theme.accent)
            Text(title)
                .font(.system(.title3).weight(.semibold)).fontDesign(theme.titleDesign)
            Text(message)
                .font(.callout)
                .foregroundStyle(theme.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 4)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct SectionTitle: View {
    @Environment(\.theme) private var theme
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 28, weight: .semibold)).fontDesign(theme.titleDesign)
            if let subtitle {
                Text(subtitle).font(.callout).foregroundStyle(theme.secondary)
            }
        }
    }
}

extension Date {
    func relative(to now: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        if abs(timeIntervalSince(now)) < 45 { return timeIntervalSince(now) >= 0 ? "now" : "just now" }
        return formatter.localizedString(for: self, relativeTo: now)
    }

    var timeString: String { formatted(.dateTime.hour().minute()) }

    var dayAndTime: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(self) { return "Today, \(timeString)" }
        if calendar.isDateInTomorrow(self) { return "Tomorrow, \(timeString)" }
        if calendar.isDateInYesterday(self) { return "Yesterday, \(timeString)" }
        return "\(formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))), \(timeString)"
    }
}
