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

    /// The themed accent role — used for the active keycap and selection
    /// highlights. [decision: orange keycap, acceleration-plan.md Wave A]
    static var speakAccent: Color { SpeakThemeRuntime.color(.accent) }

    /// Resting keycap face fill (the un-pressed key). Role: `surface`. [decision]
    static var speakKeycapFace: Color { SpeakThemeRuntime.color(.surface) }

    // `speakSurface` moved to SpeakColors.swift — it is now the themed
    // `surface` role resolved through `SpeakThemeRuntime` (see
    // SpeakThemeSystem.swift).

    // MARK: - Menubar icon state colors (roadmap P8)
    //
    // These tokens provide the per-state tint for the menubar icon.
    // They are applied via `.foregroundStyle(color)` on a non-template
    // SwiftUI Image — see SpeakApp.swift §MenuBarLabel for the rendering
    // mechanism and its [unverified] caveat.
    //
    // [decision: roadmap P8 — idle=neutral, listening=on-air, processing=amber,
    //  done=delivered, error=error+X. Themed roles are preferred so they adapt
    //  correctly between light and dark menu bars and repaint with the theme.]

    /// Idle — neutral gray, blends into the menubar. Role: `mica`. [decision: P8]
    static var speakStateIdle: Color { SpeakThemeRuntime.color(.mica) }

    /// Listening (recording active) — the on-air tally to signal mic-on.
    /// Role: `onAir`. [decision: P8]
    static var speakStateListening: Color { SpeakThemeRuntime.color(.onAir) }

    /// Processing (cleanup / paste in flight) — warm amber to signal work.
    /// Role: `humanAmber`. [decision: P8]
    static var speakStateProcessing: Color { SpeakThemeRuntime.color(.humanAmber) }

    /// Done flash (success) — held 600ms then returns to idle.
    /// Role: `delivered`. [decision: P8]
    static var speakStateDone: Color { SpeakThemeRuntime.color(.delivered) }

    /// Error — paired with an xmark symbol. Role: `error`. [decision: P8]
    static var speakStateError: Color { SpeakThemeRuntime.color(.error) }
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
