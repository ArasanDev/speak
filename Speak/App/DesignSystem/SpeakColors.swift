// App/DesignSystem/SpeakColors.swift
//
// FE-1 (specs/frontend-identity.md §2): the two-temperature palette. The one
// system rule everything obeys: **warm = human, cool = agent.** Every surface,
// badge, waveform, and state color answers "who is acting?"
//
// RUNTIME THEMING [decision]: every token resolves through
// `SpeakThemeRuntime.active` — the palette `ThemeEngine` paints when the user
// picks or edits a theme (Settings → Appearance → Color Theme). Tokens are
// `static var` (not `let`) so the same call sites repaint live when
// `ThemedRoot` re-injects `\.speakTheme` into the environment. Token NAMES
// stay stable across themes — only values change. Role semantics are
// load-bearing (see SEMANTICS below): a theme may change hue, never meaning.
//
// SEMANTICS (load-bearing — future agents must preserve these):
//   - `humanAmber`: the human channel. Live mic, dictation levels, hotkey
//     affordances. Anything the HUMAN is actively doing.
//   - `onAir`: the recording tally. MUST appear iff the microphone is
//     capturing (spec §2 hard rule) — no marketing use, no hover states,
//     nothing else. It is a tally light, not a brand color.
//   - `agentViolet`: the agent channel. Agent speech, agent activity, session
//     chips. Anything an AGENT is doing on the human's behalf.
//   - `delivered`: terminal success only — pasted, answered, completed. Not a
//     general "positive" green; reserve it for completion states.
//
// Light/dark is handled inside each role's `ThemeHexPair`; the pair resolves
// against the current NSAppearance, so system appearance keeps working per
// theme (never force a mode — spec §2).

import AppKit
import SwiftUI

public extension Color {

    // MARK: - Surfaces

    /// Primary dark surface — not pure black. Role: `ink`.
    static var speakInk: Color { SpeakThemeRuntime.color(.ink) }

    /// Raised surface / cards. Role: `ink2`.
    static var speakInk2: Color { SpeakThemeRuntime.color(.ink2) }

    /// Primary text on `speakInk`. Role: `bone`.
    static var speakBone: Color { SpeakThemeRuntime.color(.bone) }

    /// Secondary text, hairlines. Role: `mica`.
    static var speakMica: Color { SpeakThemeRuntime.color(.mica) }

    // MARK: - Channels ("who is acting?")

    /// The HUMAN channel: live mic, dictation levels, hotkey affordances.
    /// Role: `humanAmber`. [spec §2]
    static var speakHumanAmber: Color { SpeakThemeRuntime.color(.humanAmber) }

    /// Recording tally light. HARD RULE (spec §2): appears IFF the microphone
    /// is capturing. No marketing use, no hover states, nothing else.
    /// Role: `onAir`.
    static var speakOnAir: Color { SpeakThemeRuntime.color(.onAir) }

    /// The AGENT channel: agent speech, agent activity, session chips.
    /// Role: `agentViolet`. [spec §2]
    static var speakAgentViolet: Color { SpeakThemeRuntime.color(.agentViolet) }

    /// Terminal success ONLY: pasted, answered, completed. Not a general
    /// "positive" indicator. Role: `delivered`. [spec §2]
    static var speakDelivered: Color { SpeakThemeRuntime.color(.delivered) }

    // MARK: - Status

    /// Failure / error signal. Role: `error`.
    static var speakError: Color { SpeakThemeRuntime.color(.error) }

    /// Attention needed — caution, not failure. Role: `warning`.
    static var speakWarning: Color { SpeakThemeRuntime.color(.warning) }

    /// Healthy / nominal level — the non-terminal positive (e.g. VU body).
    /// Distinct from `delivered`, which is reserved for completion. Role: `ok`.
    static var speakOK: Color { SpeakThemeRuntime.color(.ok) }

    // MARK: - Workspace & Slack-Inspired Identity Tokens

    /// Channel Sidebar background. Role: `sidebarBg`.
    static var speakSidebarBg: Color { SpeakThemeRuntime.color(.sidebarBg) }

    /// Unified window canvas background. Role: `windowCanvas`.
    static var speakWindowCanvas: Color { SpeakThemeRuntime.color(.windowCanvas) }

    /// Main detail card canvas. Role: `cardCanvas`.
    static var speakCardCanvas: Color { SpeakThemeRuntime.color(.cardCanvas) }

    /// Sidebar selection pills. Role: `sidebarSelection`.
    static var speakSidebarSelection: Color { SpeakThemeRuntime.color(.sidebarSelection) }

    /// Active channel item highlight — derived from the agent channel.
    static var speakSidebarActiveBg: Color { speakAgentViolet.opacity(0.18) }

    /// Tag mention badge background (@Claude, @terminal).
    static var speakTagBadgeBg: Color { speakAgentViolet.opacity(0.15) }

    /// Tag mention badge text color.
    static var speakTagBadgeFg: Color { speakAgentViolet }

    /// Card & container hairline border. Role: `cardBorder`.
    static var speakCardBorder: Color { SpeakThemeRuntime.color(.cardBorder) }

    /// Inset/well surface (the legacy `speakSurface` token, now a role).
    /// Role: `surface`.
    static var speakSurface: Color { SpeakThemeRuntime.color(.surface) }

    /// UI accent — selection pills, focus, `.tint`. A theme that leaves
    /// `accent` unset resolves to `Color.accentColor` (system).
    static var speakUIAccent: Color { SpeakThemeRuntime.color(.accent) }

    /// Text/glyph drawn on the `accent` fill — dark when the accent is bright
    /// (ember dark), white on the system accent. Role: `onAccent`.
    static var speakOnAccent: Color { SpeakThemeRuntime.color(.onAccent) }

    // MARK: - Flow Border Spectra (AnimatedFlowBorderModifier)
    //
    // Spectra keep their pivot hues but take endpoints from the themed
    // channel colors, so a theme re-tints the border animations too.
    // HARD RULE (mirrors speakOnAir): onAir spectrum shows only while the
    // microphone is capturing.

    /// On-Air / dictation-active border — humanAmber → onAir → deep red.
    static var speakFlowOnAir: [Color] {
        [
            speakHumanAmber,
            speakOnAir,
            Color(red: 1.0, green: 0.2,   blue: 0.1  ),   // deep red pivot
            speakOnAir,
            speakHumanAmber,
        ]
    }

    /// Agent-working border — agentViolet → electric blue → cyan → violet.
    static var speakFlowAgent: [Color] {
        [
            speakAgentViolet,
            Color(red: 0.2,   green: 0.5,   blue: 1.0),   // electric blue
            Color(red: 0.0,   green: 0.75,  blue: 1.0),   // cyan pivot
            Color(red: 0.2,   green: 0.5,   blue: 1.0),   // electric blue mirror
            speakAgentViolet,
        ]
    }

    /// Inference-running border — blue → cyan → agentViolet → blue.
    static var speakFlowInference: [Color] {
        [
            Color(red: 0.2,   green: 0.5,   blue: 1.0),   // electric blue
            Color(red: 0.0,   green: 0.85,  blue: 1.0),   // cyan
            speakAgentViolet,
            Color(red: 0.4,   green: 0.2,   blue: 1.0),   // deep violet pivot
            Color(red: 0.2,   green: 0.5,   blue: 1.0),   // electric blue close
        ]
    }

    /// Processing / cleanup-in-flight border — humanAmber → warm pivots.
    static var speakFlowProcessing: [Color] {
        [
            speakHumanAmber,
            Color(red: 1.0,  green: 0.6,  blue: 0.1 ),   // warm amber pivot
            Color(red: 0.95, green: 0.45, blue: 0.05),   // deep amber pivot
            Color(red: 1.0,  green: 0.6,  blue: 0.1 ),   // warm amber mirror
            speakHumanAmber,
        ]
    }

    /// Hover / glass shimmer — subtle white sheen for always-on brand mark.
    /// Unthemed: it is a light effect, not a palette color.
    static let speakFlowGlass: [Color] = [
        Color.white.opacity(0.08),
        Color.white.opacity(0.35),
        Color.white.opacity(0.08),
        Color.white.opacity(0.35),
        Color.white.opacity(0.08),
    ]

    /// Error state border — error role → deep red pivot → error.
    static var speakFlowError: [Color] {
        [
            speakError,
            Color(red: 0.7, green: 0.0, blue: 0.0),   // deep red pivot
            speakError,
        ]
    }

    /// Success / delivered border — delivered → deep green → delivered.
    static var speakFlowSuccess: [Color] {
        [
            speakDelivered,
            Color(red: 0.0, green: 0.6, blue: 0.35),  // deep green pivot
            speakDelivered,
        ]
    }
}

// ShapeStyle shim — same mechanism SwiftUI uses for `.primary`/`.secondary`:
// lets `.speakMica` shorthand resolve inside `.foregroundStyle(...)`, which
// looks members up on `ShapeStyle`, not `Color`.
public extension ShapeStyle where Self == Color {
    static var speakInk: Color { SpeakThemeRuntime.color(.ink) }
    static var speakInk2: Color { SpeakThemeRuntime.color(.ink2) }
    static var speakBone: Color { SpeakThemeRuntime.color(.bone) }
    static var speakMica: Color { SpeakThemeRuntime.color(.mica) }
    static var speakHumanAmber: Color { SpeakThemeRuntime.color(.humanAmber) }
    static var speakOnAir: Color { SpeakThemeRuntime.color(.onAir) }
    static var speakAgentViolet: Color { SpeakThemeRuntime.color(.agentViolet) }
    static var speakDelivered: Color { SpeakThemeRuntime.color(.delivered) }
    static var speakError: Color { SpeakThemeRuntime.color(.error) }
    static var speakWarning: Color { SpeakThemeRuntime.color(.warning) }
    static var speakOK: Color { SpeakThemeRuntime.color(.ok) }
    static var speakSidebarBg: Color { SpeakThemeRuntime.color(.sidebarBg) }
    static var speakWindowCanvas: Color { SpeakThemeRuntime.color(.windowCanvas) }
    static var speakCardCanvas: Color { SpeakThemeRuntime.color(.cardCanvas) }
    static var speakSidebarSelection: Color { SpeakThemeRuntime.color(.sidebarSelection) }
    static var speakCardBorder: Color { SpeakThemeRuntime.color(.cardBorder) }
    static var speakSurface: Color { SpeakThemeRuntime.color(.surface) }
    static var speakUIAccent: Color { SpeakThemeRuntime.color(.accent) }
    static var speakOnAccent: Color { SpeakThemeRuntime.color(.onAccent) }
}
