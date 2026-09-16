// App/Overlay/HUDLaneViews.swift
//
// The shared HUD frame for the recording overlay — a minimal floating pill
// (v2 redesign, replacing the divider-segmented capsule bar).
//
//   ╭───────────────────────────────────────────────────────╮
//   │  ≋   LISTENING · 0:12 · ⌘⌘ to finish           ⚙  ✕   │
//   │      the quick brown fox jumps over the lazy dog…     │
//   ╰───────────────────────────────────────────────────────╯
//
// DESIGN (owner direction, 2026-09-17): minimal, calm, glanceable.
//   • No dividers, no icon tiles, no circled timer zone — the sketch-era
//     dotted rules and square end-zones are gone. Separation comes from
//     spacing and weight, not rules.
//   • One LEADING SLOT morphs by state: live voice animation while
//     `.listening`, a spinner while `.processing`, a delivered ✓ on `.done`,
//     an error mark on `.error`. State is glanceable at the same spot.
//   • The timer rides inline in the header (`LISTENING · 0:12`) instead of
//     claiming its own endcap — one row of metadata, one lane of transcript.
//   • State styling is a SUBTLE TINT SHIFT: a hairline `speakCardBorder`
//     edge + a faint phase-colored wash over the frosted glass. The animated
//     traveling/glow borders are opt-in only (`borderAnimationStyle != .none`
//     still layers `HUDBorderLayer` on top — an explicit user choice).
//   • Classic and Aurora HUD styles unified on this pill — the old Aurora
//     differentiator was the animated border, which is now an orthogonal
//     opt-in. [decision: one good design over two divergent ones.]
//
// Invalidation boundaries (unchanged goal): each zone is a real View type
// reading only the `OverlayViewModel` properties it renders, so a ~30 Hz
// `level` tick re-evaluates only `HUDLeadingSlot`, and a `windowText`
// partial only `HUDListeningLane`.
//
// Lane content (header, controls, per-state bodies, border layer) lives in
// `HUDLaneContent.swift`.

import AppKit
import SpeakCore
import SwiftUI

// MARK: - Shared helpers

/// HUD-level constants + pure helpers shared by the pill's subviews.
enum HUDLane {
    /// Lane text line budget — one value for every state now that the stop
    /// hint rides inline in the header row instead of claiming its own strip.
    /// [decision: 3 lines — ~15 pt per line at 11 pt mono + 2 pt spacing ≈ 45 pt,
    ///  inside the ~60 pt lane left after the ~14 pt header row.]
    static let lineBudget = 3

    /// Line spacing inside the capture lane. [decision: ~2 pt per spec.]
    static let lineSpacing: CGFloat = SpeakSpacing.xs / 2

    /// Width of the leading slot (voice animation / spinner / status glyph).
    /// [decision: 44 pt — holds a 60 pt voice-animation canvas at 0.7 scale;
    ///  wide enough to read as a zone, narrow enough to stay a pill.]
    static let leadingSlotWidth: CGFloat = 44

    /// Scale applied to the voice animation's 60 pt design canvas.
    /// [decision: 0.7 → 42 pt rendered; sonar/ring-gauge rings stay legible,
    ///  spectrum bars keep their 2 pt geometry.]
    static let animationScale: CGFloat = 0.7

    /// Panel silhouette corner radius.
    /// [decision: 14 pt continuous — the near-rect "micro edge" the owner
    ///  asked for (2026-09-17); also the Classic-era border call-site radius
    ///  documented in AnimatedGradientBorder.swift.]
    static let panelCornerRadius: CGFloat = 14

    /// The panel's silhouette — a continuous rounded rect shared by the clip
    /// shape, hairline stroke, tint wash, and opt-in animated borders so the
    /// edge can never disagree across layers.
    static var panelShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous)
    }

    /// Format elapsed seconds as `m:ss` for the HUD (e.g. 0:05, 1:23).
    static func durationLabel(_ seconds: Int) -> String {
        let s = max(0, seconds)
        return "\(s / 60):\(String(format: "%02d", s % 60))"
    }

    /// The phase word for the header — the pipeline's current job.
    static func phaseWord(for state: OverlayState, isCleaningUp: Bool) -> String {
        switch state {
        case .listening:  return "LISTENING"
        case .processing: return isCleaningUp ? "POLISHING" : "PASTING"
        case .done:       return "DONE"
        case .error:      return "ERROR"
        }
    }

    /// Phase tint — `speakVoiceBlue` while capturing (fixed voice blue —
    /// never follows the system accent, which can be orange),
    /// `speakAgentViolet` while the LLM polishes, `speakDelivered` on done,
    /// `speakError` on error.
    static func phaseTint(for state: OverlayState) -> Color {
        switch state {
        case .listening:  return .speakVoiceBlue
        case .processing: return .speakAgentViolet
        case .done:       return .speakDelivered
        case .error:      return .speakError
        }
    }

    /// Opacity of the state-colored wash over the frosted glass — the
    /// "subtle tint shift" that carries state across the whole pill.
    /// [decision: ~0.10 — visible against the glass without tinting text.]
    static func stateWashOpacity(for state: OverlayState) -> Double {
        switch state {
        case .listening:  return 0.10
        case .processing: return 0.10
        case .done:       return 0.12
        case .error:      return 0.12
        }
    }

    /// VoiceOver state announcements — one path for all HUD presentation.
    /// `@MainActor`: `NSAccessibility.post` + `NSApp` are main-actor API.
    @MainActor
    static func postAccessibilityAnnouncement(for state: OverlayState, isCleaningUp: Bool) {
        let message: String
        switch state {
        case .listening:   message = "Listening"
        case .processing:  message = isCleaningUp ? "Cleaning up" : "Pasting"
        case .done:        message = "Done"
        case .error:       message = "Dictation error. Press Escape or try again."
        }
        NSAccessibility.post(
            element: NSApp as AnyObject,
            notification: .announcementRequested,
            userInfo: [
                NSAccessibility.NotificationUserInfoKey.announcement: message,
                NSAccessibility.NotificationUserInfoKey.priority: NSAccessibilityPriorityLevel.high.rawValue
            ]
        )
    }
}

// MARK: - Pill frame

/// The pill's interior layout — a morphing leading slot, then the text lane.
/// No dividers: spacing + the state wash do the separating. The frosted
/// glass, tint wash, hairline edge, and optional animated border are shell
/// layers owned by `TranscriptOverlayView` (this view draws no background).
struct HUDPill: View {
    let model: OverlayViewModel
    let settingsStore: SettingsStore

    var body: some View {
        HStack(alignment: .center, spacing: SpeakSpacing.sm) {
            HUDLeadingSlot(model: model, settingsStore: settingsStore)
            HUDTextLane(model: model, settingsStore: settingsStore)
        }
        .padding(.leading, SpeakSpacing.sm + 2)
        .padding(.trailing, SpeakSpacing.sm)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Leading slot — the morphing state mark

/// The left slot, morphing by state: the live voice animation while the mic
/// captures (the app's signature asset, runtime-configurable via
/// `voiceAnimationStyle`/`voiceAnimationColor`), a spinner while the pipeline
/// works, a delivered ✓ on done, an error mark on error. One glanceable spot
/// replaces the old waveform-endcap + timer-endcap pair.
/// Reads `model.level`/`overlayState` so the high-frequency level stream
/// re-evaluates only this slot, not the whole frame.
struct HUDLeadingSlot: View {
    let model: OverlayViewModel
    let settingsStore: SettingsStore

    var body: some View {
        content
            .frame(width: HUDLane.leadingSlotWidth, height: HUDLane.leadingSlotWidth)
            .frame(maxHeight: .infinity)
    }

    @ViewBuilder
    private var content: some View {
        switch model.overlayState {
        case .listening:
            // The mic IS capturing — the signature animation runs live.
            // (The retired `overlayIdleDim` toggle gated animation in the
            //  non-listening states; those states no longer render it.)
            switch settingsStore.voiceAnimationStyle {
            case .spectrum:
                // Bare 15-bar analyser — the "Spectrum Bars" the settings
                // row promises. The double-ring chamber was the capsule-bar
                // era's endcap furniture; the pill carries just the bars.
                WaveformView(
                    level: model.level,
                    isActive: true,
                    tint: settingsStore.voiceAnimationColor.color
                )
                .accessibilityHidden(true)

            case .sonar, .ringGauge:
                VoiceAnimationView(
                    style: settingsStore.voiceAnimationStyle,
                    tint: settingsStore.voiceAnimationColor.color,
                    level: model.level,
                    isActive: true
                )
                .scaleEffect(HUDLane.animationScale)
                .accessibilityHidden(true)
            }

        case .processing:
            ProgressView()
                .controlSize(.regular)
                .accessibilityLabel(model.isCleaningUp ? "Cleaning up" : "Pasting")

        case .done:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 22, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.speakDelivered)
                .accessibilityLabel("Done in \(HUDLane.durationLabel(model.elapsedSeconds))")

        case .error:
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 22, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.speakError)
                .accessibilityLabel("Error")
        }
    }
}

// MARK: - Text lane

/// The flexible lane: a header row (phase word · inline timer · stop hint ·
/// quiet controls) over the per-state content. `.clipped()` keeps the
/// transcript inside the pill no matter how long the FIFO window runs.
struct HUDTextLane: View {
    let model: OverlayViewModel
    let settingsStore: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.xs / 2) {
            if settingsStore.overlayShowPhaseHeader {
                HUDPillHeader(model: model, settingsStore: settingsStore)
            }
            content
        }
        .padding(.vertical, SpeakSpacing.xs)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    @ViewBuilder
    private var content: some View {
        switch model.overlayState {
        case .listening:
            HUDListeningLane(model: model)

        case .processing:
            // Shared felt-speed settling reveal (SettlingOverlayContent.swift).
            SettlingProcessingContent(
                model: model,
                revealTextWhileProcessing: settingsStore.revealTextWhileProcessing
            )

        case .done:
            HUDDoneLane(model: model)

        case .error:
            HUDErrorLane(model: model)
        }
    }
}
