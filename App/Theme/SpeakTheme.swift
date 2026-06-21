// App/Theme/SpeakTheme.swift
//
// The single source of truth for `speak`'s typographic + color theme.
//
// DESIGN DECISION (user, 2026-06-21): the typographic theme is **Monaco** — the
// macOS-native monospace — chosen for its calm, even, log-file rhythm. Native +
// zero-dependency, which fits the Apple-only wedge (AGENTS.md §2.4). Monaco is used
// for *content + data* (history rows, timestamps, HUD transcript, keycaps); the
// system UI font is kept for chrome/labels.
//
// RULE (acceleration-plan.md, Design system): define the family string ONCE here.
// Never hardcode `"Monaco"` in a view — always go through `Font.speakMono(...)` or a
// named semantic token below. This is the only file that knows the family name.
//
// All sizes are tagged `[decision]` — they are deliberate design values, not derived
// from a platform constraint or measurement, which the no-magic-numbers rule
// (CLAUDE.md) admits as a valid provenance.

import SwiftUI

// MARK: - Font tokens

public extension Font {

    /// The one place the Monaco family string is named. Every monospaced text in
    /// the app funnels through here so the theme can be retargeted in one edit.
    /// [decision: Monaco, user-locked 2026-06-21]
    static func speakMono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom("Monaco", size: size).weight(weight)
    }

    // Semantic content tokens — prefer these over raw sizes at call sites.

    /// Primary content text (history rows, transcript bodies). [decision: 13pt]
    static let speakMonoBody = Font.speakMono(13)

    /// Secondary metadata (timestamps, engine ids). [decision: 11pt]
    static let speakMonoCaption = Font.speakMono(11)

    /// Section / pane titles rendered in the content voice. [decision: 18pt semibold]
    static let speakMonoTitle = Font.speakMono(18, weight: .semibold)

    /// Large display numerals (Insights stats). [decision: 34pt medium]
    static let speakMonoStat = Font.speakMono(34, weight: .medium)

    /// Keycap glyphs (KeyCapView). [decision: 12pt medium]
    static let speakMonoKeycap = Font.speakMono(12, weight: .medium)
}

// MARK: - Color tokens

public extension Color {

    /// The brand accent — a warm amber used for the active keycap and selection
    /// highlights. [decision: orange keycap, acceleration-plan.md Wave A]
    static let speakAccent = Color(red: 0.95, green: 0.55, blue: 0.18)

    /// Resting keycap face fill (the un-pressed key). [decision]
    static let speakKeycapFace = Color(nsColor: .controlBackgroundColor)

    /// Subtle panel background for cards/sections inside the dashboard. [decision]
    static let speakSurface = Color(nsColor: .underPageBackgroundColor)
}

// MARK: - Spacing tokens

/// Layout rhythm constants for the dashboard. One scale, used everywhere, so the
/// panes share a consistent gutter/padding cadence. [decision: 4pt base grid]
public enum SpeakSpacing {
    public static let xs: CGFloat = 4
    public static let sm: CGFloat = 8
    public static let md: CGFloat = 16
    public static let lg: CGFloat = 24
    public static let xl: CGFloat = 32
}
