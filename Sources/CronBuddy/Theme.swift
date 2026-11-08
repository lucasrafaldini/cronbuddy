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
    var finish: Finish = .solid

    enum Finish: Hashable {
        /// Surfaces are painted with the theme's colors.
        case solid
        /// Surfaces are Liquid Glass over a translucent window (macOS 26+, materials before).
        case glass
    }

    /// The system theme defers to native window and list backgrounds.
    var isNative: Bool { id == Theme.system.id }
    var isGlass: Bool { finish == .glass }
    /// Toolbars, sheets and the menu bar panel keep the system's own chrome.
    var usesNativeChrome: Bool { isNative || isGlass }

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

    static let glass = Theme(
        id: "glass", name: "Liquid Glass", tagline: "Translucent glass that follows light and dark",
        scheme: nil,
        background: .clear,
        surface: Color.primary.opacity(0.05),
        raised: Color.primary.opacity(0.06),
        border: Color.primary.opacity(0.10),
        text: .primary, secondary: .secondary, accent: .accentColor,
        success: .green, warning: .orange, danger: .red,
        onAccent: .white,
        bodyDesign: .default, titleDesign: .default,
        finish: .glass
    )

    static let all: [Theme] = [.system, .glass, .thoth, .paper, .phosphor, .nord]

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
    /// Glass hides it, so the glass or window behind shows through.
    func themedBackground(_ theme: Theme, _ color: KeyPath<Theme, Color> = \.background) -> some View {
        Group {
            if theme.isNative {
                self
            } else if theme.isGlass {
                self.scrollContentBackground(.hidden)
            } else {
                self.scrollContentBackground(.hidden).background(theme[keyPath: color])
            }
        }
    }

    /// The background of a window or panel. `backdrop` adds the translucent glass backdrop;
    /// sheets and the menu bar panel already have the system's material.
    func windowBackground(_ theme: Theme, backdrop: Bool = true) -> some View {
        Group {
            if theme.isNative {
                self
            } else if theme.isGlass {
                if backdrop { self.background(GlassBackdrop(tint: theme.accent).ignoresSafeArea()) } else { self }
            } else {
                self.background(theme.background)
            }
        }
    }

    /// A floating surface: the theme's fill and hairline, or Liquid Glass.
    /// `tint` colors the surface (a selected chip, for instance).
    func surface<S: InsettableShape>(
        _ theme: Theme, in shape: S, fill: KeyPath<Theme, Color> = \.surface,
        tint: Color? = nil, bordered: Bool = true, interactive: Bool = false
    ) -> some View {
        modifier(Surface(theme: theme, shape: shape, fill: fill, tint: tint, bordered: bordered, interactive: interactive))
    }

    /// Groups content on its own glass platter, Control Center style. No change for solid themes.
    func glassPlatter(_ theme: Theme) -> some View {
        Group {
            if theme.isGlass {
                self.padding(10).surface(theme, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                self
            }
        }
    }

    /// The prominent button of a screen: glass in the glass theme, bordered elsewhere.
    func prominentButton(_ theme: Theme) -> some View {
        Group {
            if #available(macOS 26, *), theme.isGlass {
                self.buttonStyle(.glassProminent)
            } else {
                self.buttonStyle(.borderedProminent)
            }
        }
    }

    func secondaryButton(_ theme: Theme) -> some View {
        Group {
            if #available(macOS 26, *), theme.isGlass {
                self.buttonStyle(.glass)
            } else {
                self.buttonStyle(.bordered)
            }
        }
    }
}

private struct Surface<S: InsettableShape>: ViewModifier {
    let theme: Theme
    let shape: S
    let fill: KeyPath<Theme, Color>
    let tint: Color?
    let bordered: Bool
    let interactive: Bool

    func body(content: Content) -> some View {
        if theme.isGlass {
            if #available(macOS 26, *) {
                content.glassEffect(glass, in: shape)
            } else {
                content
                    .background(tint.map { AnyShapeStyle($0.opacity(0.85)) } ?? AnyShapeStyle(.regularMaterial), in: shape)
                    .overlay(shape.strokeBorder(Color.white.opacity(0.14)))
            }
        } else {
            content
                .background(tint ?? theme[keyPath: fill], in: shape)
                .overlay { if bordered { shape.strokeBorder(theme.border) } }
        }
    }

    @available(macOS 26, *)
    private var glass: Glass {
        var glass = Glass.regular
        if let tint { glass = glass.tint(tint) }
        if interactive { glass = glass.interactive() }
        return glass
    }
}

/// The window backdrop of the glass theme. On macOS 26 the window itself turns
/// transparent and its background is Liquid Glass, so the desktop shows through,
/// refracted. Earlier versions get the behind-window blur.
struct GlassBackdrop: View {
    let tint: Color

    var body: some View {
        if #available(macOS 26, *) {
            WindowGlass(tint: NSColor(tint))
        } else {
            ZStack {
                BehindWindowBlur()
                LinearGradient(
                    colors: [tint.opacity(0.16), tint.opacity(0.04), .clear],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            }
        }
    }
}

@available(macOS 26, *)
private struct WindowGlass: NSViewRepresentable {
    let tint: NSColor

    func makeNSView(context: Context) -> TransparentWindowGlass {
        let view = TransparentWindowGlass()
        view.style = .regular
        view.tintColor = tint.withAlphaComponent(0.10)
        return view
    }

    func updateNSView(_ view: TransparentWindowGlass, context: Context) {
        view.tintColor = tint.withAlphaComponent(0.10)
    }
}

/// Glass needs to see past the window, so it makes its window transparent while it is
/// installed and puts the window back the way it was when the theme changes.
@available(macOS 26, *)
private final class TransparentWindowGlass: NSGlassEffectView {
    private var restore: (opaque: Bool, background: NSColor)?

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil, let window, let restore {
            window.isOpaque = restore.opaque
            window.backgroundColor = restore.background
            self.restore = nil
        }
        super.viewWillMove(toWindow: newWindow)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window, restore == nil else { return }
        restore = (window.isOpaque, window.backgroundColor)
        window.isOpaque = false
        window.backgroundColor = .clear
    }
}

private struct BehindWindowBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
