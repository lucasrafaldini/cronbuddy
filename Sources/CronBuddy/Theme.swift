import AppKit
import SwiftUI

struct Theme: Identifiable, Hashable {
    let id: String
    let name: String
    let tagline: String
    let scheme: ColorScheme?
    let background: Color
    let surface: Color
    let raised: Color
    let border: Color
    let text: Color
    let secondary: Color
    let accent: Color
    let success: Color
    let warning: Color
    let danger: Color
    /// Text and icons drawn on top of the accent color.
    let onAccent: Color
    let bodyDesign: Font.Design
    let titleDesign: Font.Design
    /// The system theme defers to native window and list backgrounds.
    var isNative: Bool { id == Theme.system.id }

    static let system = Theme(
        id: "system", name: "System", tagline: "Follows macOS appearance and accent color",
        scheme: nil,
        background: Color(nsColor: .windowBackgroundColor),
        surface: Color(nsColor: .controlBackgroundColor),
        raised: Color(nsColor: .textBackgroundColor),
        border: Color(nsColor: .separatorColor),
        text: .primary, secondary: .secondary, accent: .accentColor,
        success: .green, warning: .orange, danger: .red,
        onAccent: .white,
        bodyDesign: .default, titleDesign: .default
    )

    static let thoth = Theme(
        id: "thoth", name: "Thoth", tagline: "Black and gold, set in serif",
        scheme: .dark,
        background: Color(hex: 0x0A0A0A), surface: Color(hex: 0x111111), raised: Color(hex: 0x181818),
        border: Color(hex: 0xC8A030, opacity: 0.16),
        text: Color(hex: 0xEDE9DF), secondary: Color(hex: 0x8A8578), accent: Color(hex: 0xC8A030),
        success: Color(hex: 0x8DB86B), warning: Color(hex: 0xD9A441), danger: Color(hex: 0xD0605E),
        onAccent: Color(hex: 0x0A0A0A),
        bodyDesign: .default, titleDesign: .serif
    )

    static let paper = Theme(
        id: "paper", name: "Paper", tagline: "Warm off-white with ink and terracotta",
        scheme: .light,
        background: Color(hex: 0xF4F0E6), surface: Color(hex: 0xFBF8F1), raised: Color(hex: 0xFFFFFF),
        border: Color(hex: 0x1C1B19, opacity: 0.10),
        text: Color(hex: 0x1C1B19), secondary: Color(hex: 0x6F6A60), accent: Color(hex: 0xB4532A),
        success: Color(hex: 0x4E7D4A), warning: Color(hex: 0xB7832F), danger: Color(hex: 0xB23A3A),
        onAccent: .white,
        bodyDesign: .default, titleDesign: .serif
    )

    static let phosphor = Theme(
        id: "phosphor", name: "Phosphor", tagline: "Green-screen terminal, all monospace",
        scheme: .dark,
        background: Color(hex: 0x050806), surface: Color(hex: 0x0B110D), raised: Color(hex: 0x101813),
        border: Color(hex: 0x39FF88, opacity: 0.16),
        text: Color(hex: 0xC8F7D5), secondary: Color(hex: 0x5E8C6C), accent: Color(hex: 0x39FF88),
        success: Color(hex: 0x39FF88), warning: Color(hex: 0xF2D35B), danger: Color(hex: 0xFF5F56),
        onAccent: Color(hex: 0x050806),
        bodyDesign: .monospaced, titleDesign: .monospaced
    )

    static let nord = Theme(
        id: "nord", name: "Nord", tagline: "Arctic blues, easy on the eyes",
        scheme: .dark,
        background: Color(hex: 0x2E3440), surface: Color(hex: 0x3B4252), raised: Color(hex: 0x434C5E),
        border: Color(hex: 0xECEFF4, opacity: 0.08),
        text: Color(hex: 0xECEFF4), secondary: Color(hex: 0x9AA4B6), accent: Color(hex: 0x88C0D0),
        success: Color(hex: 0xA3BE8C), warning: Color(hex: 0xEBCB8B), danger: Color(hex: 0xBF616A),
        onAccent: Color(hex: 0x2E3440),
        bodyDesign: .rounded, titleDesign: .rounded
    )

    static let all: [Theme] = [.system, .thoth, .paper, .phosphor, .nord]

    static func named(_ id: String) -> Theme {
        all.first { $0.id == id } ?? .system
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

extension EnvironmentValues {
    @Entry var theme: Theme = .system
}

private struct Themed: ViewModifier {
    let theme: Theme

    func body(content: Content) -> some View {
        content
            .environment(\.theme, theme)
            .tint(theme.accent)
            .fontDesign(theme.bodyDesign)
            .foregroundStyle(theme.text)
            .preferredColorScheme(theme.scheme)
    }
}

extension View {
    func themed(_ theme: Theme) -> some View { modifier(Themed(theme: theme)) }

    /// Replaces a scroll view's native background with the theme's, except for the system theme.
    func themedBackground(_ theme: Theme, _ color: KeyPath<Theme, Color> = \.background) -> some View {
        Group {
            if theme.isNative {
                self
            } else {
                self.scrollContentBackground(.hidden).background(theme[keyPath: color])
            }
        }
    }
}
