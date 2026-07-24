// App/DesignSystem/SpeakColors.swift
//
// FE-1 (specs/frontend-identity.md §2): the two-temperature palette. The one
// system rule everything obeys: **warm = human, cool = agent.** Every surface,
// badge, waveform, and state color answers "who is acting?"
//
// This file adds a NEW token namespace (`Color.speak*`) alongside the existing
// `SpeakTheme.swift` tokens (`Color.speak*` there are the Monaco-era dashboard
// tokens). No existing surface is restyled by FE-1 (spec §6) — these tokens
// exist for Voice Desktop Pet (FE-1) and are adopted by the HUD/dashboard in FE-2/FE-3.
//
// LIGHT/DARK: dark values are the spec §2 table verbatim. Light-mode values are
// derivations per §2 ("bone surfaces, ink text, identical channel hues at
// adjusted luminance") — [decision: FE-1, no separate light-mode table was
// specified, so light derivations invert surface roles (ink↔bone) and keep
// channel hues fixed while nudging brightness/saturation for legibility on a
// light ground]. Respect system appearance; never force dark (spec §2).
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

import AppKit
import SwiftUI

public extension Color {

    // MARK: - Surfaces

    /// Primary dark surface — not pure black. [decision: spec §2, #16181D]
    static let speakInk = Color(
        light: Color(red: 0xE9 / 255, green: 0xE6 / 255, blue: 0xE0 / 255),
        dark: Color(red: 0x16 / 255, green: 0x18 / 255, blue: 0x1D / 255)
    )

    /// Raised surface / cards. [decision: spec §2, #1F232B]
    static let speakInk2 = Color(
        light: Color(red: 0xFF / 255, green: 0xFF / 255, blue: 0xFF / 255),
        dark: Color(red: 0x1F / 255, green: 0x23 / 255, blue: 0x2B / 255)
    )

    /// Primary text on `speakInk`. [decision: spec §2, #E9E6E0]
    static let speakBone = Color(
        light: Color(red: 0x16 / 255, green: 0x18 / 255, blue: 0x1D / 255),
        dark: Color(red: 0xE9 / 255, green: 0xE6 / 255, blue: 0xE0 / 255)
    )

    /// Secondary text, hairlines. [decision: spec §2, #8A8F98 — same hue both
    /// modes, hairlines read the same regardless of ground.]
    static let speakMica = Color(red: 0x8A / 255, green: 0x8F / 255, blue: 0x98 / 255)

    // MARK: - Channels ("who is acting?")

    /// The HUMAN channel: live mic, dictation levels, hotkey affordances.
    /// [decision: spec §2, #FFB25A]
    static let speakHumanAmber = Color(red: 0xFF / 255, green: 0xB2 / 255, blue: 0x5A / 255)

    /// Recording tally light. HARD RULE (spec §2): appears IFF the microphone
    /// is capturing. No marketing use, no hover states, nothing else.
    /// [decision: spec §2, #FF5C49]
    static let speakOnAir = Color(red: 0xFF / 255, green: 0x5C / 255, blue: 0x49 / 255)

    /// The AGENT channel: agent speech, agent activity, session chips.
    /// [decision: spec §2, #9D8CFF]
    static let speakAgentViolet = Color(red: 0x9D / 255, green: 0x8C / 255, blue: 0xFF / 255)

    /// Terminal success ONLY: pasted, answered, completed. Not a general
    /// "positive" indicator. [decision: spec §2, #5FBF8F]
    static let speakDelivered = Color(red: 0x5F / 255, green: 0xBF / 255, blue: 0x8F / 255)

    // MARK: - Workspace & Slack-Inspired Identity Tokens

    /// Channel Sidebar background — deep ink in dark mode, light slate in light mode.
    static let speakSidebarBg = Color(
        light: Color(red: 0xF3 / 255, green: 0xF2 / 255, blue: 0xEE / 255),
        dark: Color(red: 0x12 / 255, green: 0x14 / 255, blue: 0x18 / 255)
    )

    /// Active channel item highlight.
    static let speakSidebarActiveBg = Color.speakAgentViolet.opacity(0.18)

    /// Tag mention badge background (@Claude, @terminal).
    static let speakTagBadgeBg = Color.speakAgentViolet.opacity(0.15)

    /// Tag mention badge text color.
    static let speakTagBadgeFg = Color.speakAgentViolet

    /// Card & Container subtle border.
    static let speakCardBorder = Color.speakMica.opacity(0.25)
}

// MARK: - Light/dark color helper

private extension Color {
    /// Build a `Color` that resolves to `light` or `dark` per the current
    /// system appearance (`NSAppearance`), tracked live like any other SwiftUI
    /// `Color` — required because `speakInk`/`speakInk2`/`speakBone` invert
    /// their roles between modes (spec §2), unlike the fixed-hue channel colors.
    init(light: Color, dark: Color) {
        self = Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(isDark ? dark : light)
        })
    }
}
