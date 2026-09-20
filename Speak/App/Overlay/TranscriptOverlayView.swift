// App/Overlay/TranscriptOverlayView.swift
//
// The SwiftUI content hosted inside `TranscriptOverlayPanel` — the minimal
// floating panel (v2 redesign, 2026-09-17; near-rect silhouette per owner):
//
//   ╭───────────────────────────────────────────────────────╮
//   │  ≋   LISTENING · 0:12                          ⚙  ✕   │
//   │      the quick brown fox jumps over the lazy dog…     │
//   ╰───────────────────────────────────────────────────────╯
//
//   • Shell — frosted glass clipped to `HUDLane.panelShape` (a continuous
//     14 pt rounded rect — square-ish, micro-curved edges), a 1 pt
//     `speakCardBorder` hairline, and
//     a faint phase-colored wash (the "subtle tint shift" — blue listening,
//     violet polishing, green done, red error). No traveling lights by
//     default; `borderAnimationStyle` still layers an animated border for
//     users who explicitly pick one.
//   • Leading slot — morphs by state: live voice animation (`.listening`),
//     spinner (`.processing`), delivered ✓ (`.done`), error mark (`.error`).
//   • Header — phase word + inline `· m:ss` timer + quiet
//     controls (customize / readback / re-clean / close).
//   • Lane — the FIFO `model.windowText` at `.speakMonoFace(.caption)`,
//     topLeading, clipped — the transcript can never outgrow the pill.
//
//   All four states share this silhouette — only the leading slot's mark,
//   the wash tint, and the lane content swap. Conversation mode still
//   replaces the content layer wholesale (`ConversationOverlayView`).
//
// Decomposed for strict modularity:
//   • State & models in `OverlayViewModel.swift`
//   • Live waveform + glass + VRule in `OverlayWaveformView.swift`
//   • Per-dictation knob chips in `OverlayKnobsRow.swift`
//   • Settling content + raw→clean diff in `SettlingOverlayContent.swift`
//   • Pill frame + leading slot + text lane in `HUDLaneViews.swift`
//   • Header, controls, lane bodies, opt-in border in `HUDLaneContent.swift`
//   Each zone is a real View type reading only the `OverlayViewModel`
//   properties it renders — a 30 Hz `level` tick or a `windowText` partial
//   re-evaluates one subtree, not the whole pill.
//
// Tokens: `speakBone` primary, `speakMica` secondary, `speakOnAir` capture
// tally ONLY, `speakAgentViolet` polish, `speakDelivered` done, `speakError`
// error, `speakCardBorder` the hairline. No raw hex; `SpeakSpacing.*` only.

import AppKit
import SpeakCore
import SwiftUI

// MARK: - TranscriptOverlayView

/// The visible HUD shown during live dictation — the minimal panel.
/// Renders four states — listening, processing, done, error — inside the
/// same frosted rounded-rect silhouette.
struct TranscriptOverlayView: View {
    let model: OverlayViewModel
    let settingsStore: SettingsStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            // Inner clipped card: frosted glass + state wash + content.
            ZStack {
                VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)

                // The subtle tint shift — the whole panel washes faintly in
                // the phase color. State is ambient, not a light show.
                HUDLane.panelShape
                    .fill(HUDLane.phaseTint(for: model.overlayState)
                        .opacity(HUDLane.stateWashOpacity(for: model.overlayState)))

                contentLayer
            }
            .clipShape(HUDLane.panelShape)
            // The quiet edge — a single hairline, not an animation.
            .overlay(
                HUDLane.panelShape
                    .strokeBorder(Color.speakCardBorder, lineWidth: 1)
            )

            // Opt-in animated border — only when the user explicitly picked
            // a `borderAnimationStyle` other than `.none`.
            HUDBorderLayer(
                model: model,
                settingsStore: settingsStore,
                reduceMotion: reduceMotion
            )
        }
        .padding(2)  // prevent shadow clipping at the edge
        .onChange(of: model.overlayState) { _, newState in
            HUDLane.postAccessibilityAnnouncement(for: newState, isCleaningUp: model.isCleaningUp)
        }
    }

    @ViewBuilder
    private var contentLayer: some View {
        if model.overlayState == .listening, let loopManager = model.conversationLoopManager {
            // Bidirectional conversation mode replaces the content layer entirely.
            ConversationOverlayView(
                loopManager: loopManager,
                model: model,
                settingsStore: settingsStore
            )
        } else {
            HUDPill(model: model, settingsStore: settingsStore)
        }
    }

    /// Format elapsed seconds as `m:ss` for the HUD (e.g. 0:05, 1:23).
    /// Forwarder kept for `OverlayDurationTests`; implementation lives in `HUDLane`.
    static func durationLabel(_ seconds: Int) -> String {
        HUDLane.durationLabel(seconds)
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Listening — placeholder") {
    let model = OverlayViewModel()
    model.overlayState = .listening
    model.level = 0.0
    return TranscriptOverlayView(model: model, settingsStore: SettingsStore())
        .frame(width: 640, height: 76)
}

#Preview("Listening — live level 0.6") {
    let model = OverlayViewModel()
    model.overlayState = .listening
    model.windowText = "the quick brown fox jumps over the lazy dog and keeps on streaming words into the bounded capture lane"
    model.elapsedSeconds = 12
    model.level = 0.6
    return TranscriptOverlayView(model: model, settingsStore: SettingsStore())
        .frame(width: 640, height: 76)
}

#Preview("Listening — long stream (FIFO window full)") {
    let model = OverlayViewModel()
    model.overlayState = .listening
    model.windowText = "newest speech stays in the window while the oldest words flow out first so a long dictation "
            + "keeps streaming inside the two circles without ever overflowing the lane or growing the panel"
    model.elapsedSeconds = 83
    model.level = 0.45
    return TranscriptOverlayView(model: model, settingsStore: SettingsStore())
        .frame(width: 640, height: 76)
}

#Preview("Processing — cleanup on") {
    let model = OverlayViewModel()
    model.overlayState = .processing
    model.isCleaningUp = true
    model.settlingText = "the quick brown fox jumps over the lazy dog while the model polishes the raw transcript in place"
    model.isSettling = true
    model.elapsedSeconds = 14
    return TranscriptOverlayView(model: model, settingsStore: SettingsStore())
        .frame(width: 640, height: 76)
}

#Preview("Processing — cleanup off") {
    let model = OverlayViewModel()
    model.overlayState = .processing
    model.isCleaningUp = false
    return TranscriptOverlayView(model: model, settingsStore: SettingsStore())
        .frame(width: 640, height: 76)
}

#Preview("Done") {
    let model = OverlayViewModel()
    model.overlayState = .done
    model.elapsedSeconds = 14
    return TranscriptOverlayView(model: model, settingsStore: SettingsStore())
        .frame(width: 640, height: 76)
}

#Preview("Done — readback + re-clean") {
    let model = OverlayViewModel()
    model.overlayState = .done
    model.elapsedSeconds = 21
    model.onReadback = {}
    model.onReclean = {}
    return TranscriptOverlayView(model: model, settingsStore: SettingsStore())
        .frame(width: 640, height: 76)
}

#Preview("Done — raw→clean diff") {
    let model = OverlayViewModel()
    model.overlayState = .done
    model.settlingText = "um so i think we should uh meet on tuesday maybe to go over the budget"
    model.revealedText = "I think we should meet on Tuesday to go over the budget."
    model.isDiffTransforming = true
    model.elapsedSeconds = 9
    return TranscriptOverlayView(model: model, settingsStore: SettingsStore())
        .frame(width: 640, height: 76)
}

#Preview("Error") {
    let model = OverlayViewModel()
    model.overlayState = .error
    model.errorReason = "Speech engine unavailable"
    return TranscriptOverlayView(model: model, settingsStore: SettingsStore())
        .frame(width: 640, height: 76)
}

#Preview("Error — no reason") {
    let model = OverlayViewModel()
    model.overlayState = .error
    model.errorReason = nil
    return TranscriptOverlayView(model: model, settingsStore: SettingsStore())
        .frame(width: 640, height: 76)
}

#Preview("Listening — customize panel open") {
    let model = OverlayViewModel()
    model.overlayState = .listening
    model.windowText = "open the customization panel"
    model.isCodingPanelOpen = true
    return TranscriptOverlayView(model: model, settingsStore: SettingsStore())
        .frame(width: 640, height: 76)
}
#endif
