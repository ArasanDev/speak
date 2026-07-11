// App/DesignSystem/SpeakTypography.swift
//
// FE-1 (specs/frontend-identity.md §3): the three-face type system, all
// Apple-native (zero deps, per the v0 moat). This is a NEW token namespace
// (`Font.speak2*`, distinct from the existing Monaco-era `Font.speakMono*` in
// `SpeakTheme.swift`) — FE-1 does not restyle any existing surface (spec §6).
//
// | Role                                  | Face          |
// |----------------------------------------|---------------|
// | Display / dashboard pane titles        | New York (serif), semibold, tight |
// | UI / controls / body                   | SF Pro (system) |
// | Transcripts, live words, timers, IDs    | SF Mono |
//
// Scale (spec §3): 11 / 13 (base) / 15 / 20 / 28. Weights: regular + semibold
// only — no thin weights, no ALL-CAPS labels except two-letter status tags.

import SwiftUI

public extension Font {

    // MARK: - The 5-step scale (spec §3)

    enum SpeakScale: CGFloat, CaseIterable {
        case caption = 11
        case base = 13
        case body = 15
        case title = 20
        case display = 28
    }

    // MARK: - Display (New York serif) — pane titles only, used with restraint

    /// New York via `.fontDesign(.serif)`, semibold, tight tracking. Titles only.
    /// [decision: spec §3 — "the editorial voice is the distinctive move a
    ///  dev-tool never makes. Used with restraint — titles only."]
    static func speakDisplay(_ scale: SpeakScale = .display) -> Font {
        .system(size: scale.rawValue, weight: .semibold, design: .serif)
    }

    // MARK: - UI / controls / body (SF Pro / system)

    /// Native SF Pro at the given scale step. Regular weight (default) or
    /// semibold — the only two weights the spec allows.
    static func speakBody(_ scale: SpeakScale = .body, semibold: Bool = false) -> Font {
        .system(size: scale.rawValue, weight: semibold ? .semibold : .regular, design: .default)
    }

    // MARK: - Transcripts / live words / timers / session IDs (SF Mono)

    /// SF Mono at the given scale step — "the transcript is material":
    /// monospace says "verbatim record," tabular numerals keep timers steady.
    static func speakMonoFace(_ scale: SpeakScale = .body, semibold: Bool = false) -> Font {
        .system(size: scale.rawValue, weight: semibold ? .semibold : .regular, design: .monospaced)
    }

    // MARK: - Named statics for the 5-step scale (convenience, body face)

    static let speak2Caption = Font.speakBody(.caption)
    static let speak2Base = Font.speakBody(.base)
    static let speak2Body = Font.speakBody(.body)
    static let speak2Title = Font.speakBody(.title, semibold: true)
    static let speak2Display = Font.speakDisplay(.display)
}
