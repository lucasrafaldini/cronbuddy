"""Six CronBuddy themes translated into GTK3 CSS."""

from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class Theme:
    id: str
    name: str
    tagline: str
    is_native: bool
    is_dark: bool
    background: str
    surface: str
    raised: str
    border: str
    text: str
    secondary: str
    accent: str
    on_accent: str
    success: str
    warning: str
    danger: str
    body_font: str
    title_font: str


THEMES: list[Theme] = [
    Theme(
        id="system",
        name="System",
        tagline="Follows your GTK desktop theme and accent color",
        is_native=True,
        is_dark=False,
        background="",
        surface="",
        raised="",
        border="rgba(128,128,128,0.22)",
        text="",
        secondary="#777777",
        accent="#3584e4",
        on_accent="#ffffff",
        success="#26a269",
        warning="#e5a50a",
        danger="#e01b24",
        body_font="Sans",
        title_font="Sans",
    ),
    Theme(
        id="glass",
        name="Liquid Glass",
        tagline="Translucent frosted surfaces tinted with accent blue",
        is_native=False,
        is_dark=True,
        background="rgba(24, 28, 36, 0.90)",
        surface="rgba(255, 255, 255, 0.06)",
        raised="rgba(255, 255, 255, 0.10)",
        border="rgba(255, 255, 255, 0.14)",
        text="#f3f5f8",
        secondary="#a9b2c3",
        accent="#5e9eff",
        on_accent="#0d1522",
        success="#4ade80",
        warning="#fbbf24",
        danger="#f87171",
        body_font="Sans",
        title_font="Sans",
    ),
    Theme(
        id="thoth",
        name="Thoth",
        tagline="Black and gold, set in serif",
        is_native=False,
        is_dark=True,
        background="#0A0A0A",
        surface="#111111",
        raised="#181818",
        border="rgba(200, 160, 48, 0.25)",
        text="#EDE9DF",
        secondary="#8A8578",
        accent="#C8A030",
        on_accent="#0A0A0A",
        success="#8DB86B",
        warning="#D9A441",
        danger="#D0605E",
        body_font="Sans",
        title_font="Serif",
    ),
    Theme(
        id="paper",
        name="Paper",
        tagline="Warm off-white with ink and terracotta",
        is_native=False,
        is_dark=False,
        background="#F4F0E6",
        surface="#FBF8F1",
        raised="#FFFFFF",
        border="rgba(28, 27, 25, 0.14)",
        text="#1C1B19",
        secondary="#6F6A60",
        accent="#B4532A",
        on_accent="#FFFFFF",
        success="#4E7D4A",
        warning="#B7832F",
        danger="#B23A3A",
        body_font="Sans",
        title_font="Serif",
    ),
    Theme(
        id="phosphor",
        name="Phosphor",
        tagline="Green-screen terminal, all monospace",
        is_native=False,
        is_dark=True,
        background="#050806",
        surface="#0B110D",
        raised="#101813",
        border="rgba(57, 255, 136, 0.24)",
        text="#C8F7D5",
        secondary="#5E8C6C",
        accent="#39FF88",
        on_accent="#050806",
        success="#39FF88",
        warning="#F2D35B",
        danger="#FF5F56",
        body_font="Monospace",
        title_font="Monospace",
    ),
    Theme(
        id="nord",
        name="Nord",
        tagline="Arctic blues, easy on the eyes",
        is_native=False,
        is_dark=True,
        background="#2E3440",
        surface="#3B4252",
        raised="#434C5E",
        border="rgba(236, 239, 244, 0.14)",
        text="#ECEFF4",
        secondary="#9AA4B6",
        accent="#88C0D0",
        on_accent="#2E3440",
        success="#A3BE8C",
        warning="#EBCB8B",
        danger="#BF616A",
        body_font="Sans",
        title_font="Sans",
    ),
]


def theme_by_id(theme_id: str) -> Theme:
    for t in THEMES:
        if t.id == theme_id:
            return t
    return THEMES[0]


def build_gtk_css(theme: Theme) -> str:
    common = f"""
.cb-card {{
    border: 1px solid {theme.border};
    border-radius: 10px;
    padding: 12px;
}}
.cb-title {{
    font-family: {theme.title_font};
    font-weight: bold;
    font-size: 16px;
}}
.cb-subtitle {{
    color: {theme.secondary};
    font-size: 11px;
}}
.cb-mono {{
    font-family: Monospace;
    font-size: 11px;
}}
.cb-dot-ok {{ color: {theme.success}; font-weight: bold; }}
.cb-dot-fail {{ color: {theme.danger}; font-weight: bold; }}
.cb-dot-warn {{ color: {theme.warning}; font-weight: bold; }}
.cb-dot-muted {{ color: {theme.secondary}; font-weight: bold; }}
"""
    if theme.is_native:
        return common
    return common + f"""
window, .cb-root {{
    background-color: {theme.background};
    color: {theme.text};
    font-family: {theme.body_font};
}}
.cb-sidebar {{
    background-color: {theme.surface};
    border-right: 1px solid {theme.border};
}}
.cb-card {{
    background-color: {theme.surface};
    color: {theme.text};
}}
.cb-raised, entry, textview, textview text {{
    background-color: {theme.raised};
    color: {theme.text};
    border-color: {theme.border};
}}
button.suggested-action {{
    background-color: {theme.accent};
    color: {theme.on_accent};
    background-image: none;
    border-color: {theme.accent};
}}
list, list row {{
    background-color: transparent;
    color: {theme.text};
}}
list row:selected {{
    background-color: {theme.accent};
    color: {theme.on_accent};
}}
"""
