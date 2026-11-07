import CronBuddyCore
import SwiftUI

struct TemplatesView: View {
    @Environment(\.theme) private var theme
    @Environment(AppModel.self) private var model
    @State private var category: TemplateCategory?
    @State private var search = ""

    private var templates: [JobTemplate] {
        Templates.all.filter { template in
            (category == nil || template.category == category)
                && (search.isEmpty
                    || template.name.localizedCaseInsensitiveContains(search)
                    || template.summary.localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .bottom) {
                    SectionTitle(title: "Templates", subtitle: "Ready-made jobs. Every one opens in the editor first, so you can adjust it.")
                    Spacer()
                    TextField("Search templates", text: $search)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 200)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        chip(nil, title: "All", symbol: "square.grid.2x2")
                        ForEach(TemplateCategory.allCases) { chip($0, title: $0.title, symbol: $0.symbol) }
                    }
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 14)], spacing: 14) {
                    ForEach(templates) { template in
                        TemplateCard(template: template) { model.newJob(from: template) }
                    }
                }
            }
            .padding(24)
        }
    }

    private func chip(_ value: TemplateCategory?, title: String, symbol: String) -> some View {
        let selected = category == value
        return Button { category = value } label: {
            Label(title, systemImage: symbol)
                .font(.callout.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .foregroundStyle(selected ? theme.onAccent : theme.text)
                .background(selected ? theme.accent : theme.surface, in: Capsule())
                .overlay(Capsule().strokeBorder(theme.border))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct TemplateCard: View {
    @Environment(\.theme) private var theme
    let template: JobTemplate
    let onUse: () -> Void
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Image(systemName: template.symbol)
                    .font(.title2)
                    .foregroundStyle(theme.accent)
                    .frame(width: 42, height: 42)
                    .background(theme.accent.opacity(0.13), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                Spacer()
                Pill(text: template.action.kind.title, symbol: template.action.kind.symbol)
            }
            Text(template.name)
                .font(.system(.headline)).fontDesign(theme.titleDesign)
            Text(template.summary)
                .font(.callout)
                .foregroundStyle(theme.secondary)
                .lineLimit(2, reservesSpace: true)
            HStack(spacing: 6) {
                Image(systemName: "calendar").foregroundStyle(theme.secondary)
                Text(template.schedule.summary).lineLimit(1)
            }
            .font(.caption)
            if !template.requirements.isEmpty {
                HStack(spacing: 4) {
                    ForEach(template.requirements, id: \.self) { Pill(text: $0) }
                }
            }
            Spacer(minLength: 4)
            Button(action: onUse) {
                Text("Use Template").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 210, alignment: .topLeading)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(hovering ? theme.accent.opacity(0.6) : theme.border)
        )
        .scaleEffect(hovering ? 1.01 : 1)
        .animation(.easeOut(duration: 0.15), value: hovering)
        .onHover { hovering = $0 }
    }
}
