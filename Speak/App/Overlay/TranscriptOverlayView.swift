// App/Overlay/TranscriptOverlayView.swift
//
// The SwiftUI content hosted inside `TranscriptOverlayPanel`.
// Floating HUD — a flat capsule bar with two hairline dividers (locked design
// per the owner's sketch `img/speak-overlay-ui.png`):
//
//   ╭──┬──────────────────────────────────────────────┬──╮
//   (≋ │  LISTENING · ⌘⌘ to finish                ⚙ ✕  │ ○)
//   (≋ │  streamed transcript text, bounded box        │ ○)
//    ╰─┴──────────────────────────────────────────────┴──╯
//   waveform        text box between the lines      timer/✓
//
//   • Shell     — a Capsule (stadium) with the strong outer edge (frosted
//     glass + border layer). Interior contrast is deliberately low: no discs,
//     no rings, no fills inside — the sketch's circles were positional marks.
//   • Left zone — the live mic-level `WaveformView`, the app's signature
//     asset, centered in the left endcap. `speakOnAir` iff the mic is
//     capturing (the frozen frontend-identity rule); resting mica otherwise.
//   • Divider ×2 — two 1 pt `speakCardBorder` hairlines, inset from the
//     capsule's top/bottom edges. Between them is the text box.
//   • Center    — the bounded text box: a phase header row (LISTENING /
//     POLISHING / DONE / ERROR + inline stop hint + quiet controls) over
//     `model.windowText` (the FIFO window) at `.speakMonoFace(.caption)`,
//     topLeading, clipped — text can never touch an end zone.
//   • Right zone — the response: live elapsed seconds while `.listening`,
//     a spinner while `.processing`, a delivered ✓ + final time on `.done`,
//     an error mark on `.error`.
//
//   All four states share this silhouette — only the lane content and the
//   right zone's glyph swap. Nothing overlays or merges; geometry is fixed.
//
// Decomposed for strict modularity (<800 lines):
//   • State & models in `OverlayViewModel.swift`
//   • Live reactive waveform in `OverlayWaveformView.swift`
//   • Per-dictation knob chips in `OverlayKnobsRow.swift`
//   • Provisional settling content + raw→clean diff in `SettlingOverlayContent.swift`
//
// Tokens: `speakBone` primary text, `speakMica` secondary, `speakOnAir` capture
// tally ONLY (waveform + phase label while listening), `speakAgentViolet`
// polish phase, `speakDelivered` done, `speakError` error, `speakCardBorder`
// divider hairlines. No raw hex; `SpeakSpacing.*` for all spacing.

import AppKit
import SpeakCore
import SwiftUI

// MARK: - TranscriptOverlayView

/// The visible card shown during live dictation.
/// Renders four visual states — listening, processing, done, error — all inside
/// the same capsule-with-inscribed-circles silhouette.
struct TranscriptOverlayView: View {
    let model: OverlayViewModel
    let settingsStore: SettingsStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: Locked geometry constants

    /// Width of each end zone (waveform left, response right) — driven by
    /// `settingsStore.overlaySize` (76 pt panel → 72 pt end zone: the square
    /// end zone centers its content on the capsule endcap). COUPLED to
    /// `OverlayPanelSize.endZoneWidth`.
    private var endZoneWidth: CGFloat { settingsStore.overlaySize.endZoneWidth }

    /// Lane text line budget — one value for every state now that the stop hint
    /// rides inline in the header row instead of claiming its own strip.
    /// [decision: 3 lines — ~15 pt per line at 11 pt mono + 2 pt spacing ≈ 45 pt,
    ///  inside the ~56 pt lane left after the ~14 pt header row.]
    private static let laneLineBudget = 3

    /// Line spacing inside the capture lane. [decision: ~2 pt per spec.]
    private static let laneLineSpacing: CGFloat = SpeakSpacing.xs / 2

    var body: some View {
        ZStack {
            // Inner clipped card (frosted-glass background + HUD content).
            ZStack {
                // Frosted-glass background — pulls from behind the panel.
                VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                    .clipShape(Capsule(style: .continuous))

                contentLayer
            }
            // Capsule — "a full rectangle but on the edges it is fully curvy,
            // like a circle": fully rounded ends shared with the Aurora style.
            // [decision: one structural silhouette for both HUD styles.]
            .clipShape(Capsule(style: .continuous))

            // Animated border layer — switches based on settingsStore.borderAnimationStyle
            borderLayer
        }
        .padding(2)  // prevent shadow clipping at the edge
        .onChange(of: model.overlayState) { _, newState in
            postAccessibilityAnnouncement(for: newState)
        }
    }

    @ViewBuilder
    private var borderLayer: some View {
        switch settingsStore.borderAnimationStyle {
        case .none:
            EmptyView()

        case .fullGlow:
            AnimatedGradientBorder(
                shape: Capsule(style: .continuous),
                state: model.overlayState,
                level: model.level,
                reduceMotion: reduceMotion,
                customPalette: borderTintPalette
            )

        case .edgeFlow:
            EdgeFlowBorder(
                shape: Capsule(style: .continuous),
                state: model.overlayState,
                level: model.level,
                speed: settingsStore.borderFlowSpeed,
                count: settingsStore.borderFlowCount,
                reduceMotion: reduceMotion,
                customPalette: borderTintPalette
            )
        }
    }

    /// Fixed border tint → a single-color palette both border views accept;
    /// `.adaptive` (nil) keeps the state-aware `speakFlow*` spectra.
    private var borderTintPalette: [Color]? {
        settingsStore.overlayBorderTint.fixedVoiceColor.map { [$0.color] }
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
            capsuleFrame
        }
    }

    // MARK: - The capsule-bar frame

    /// ( zone ) │ bounded text box │ ( zone )
    /// Fixed geometry shared by all four states. The two hairlines ARE the
    /// boundary elements — the box between them is a proper rectangle,
    /// clipped so text can never touch an end zone.
    private var capsuleFrame: some View {
        HStack(alignment: .center, spacing: 0) {
            leftZone
            laneDivider
            centerLane
            // Timer off → the response zone and its divider collapse; the
            // text lane runs to the panel's right edge.
            if settingsStore.overlayShowTimer {
                laneDivider
                rightZone
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// One boundary rule — a straight DOTTED line, top-to-bottom, no inset
    /// (the sketch's two lines: "a little thicker… a dotted line, maybe 3 to
    /// 5"). `speakBone` at 50% reads dark in light themes and light in dark —
    /// visible against the glass either way.
    private var laneDivider: some View {
        VRule()
            .stroke(
                Color.speakBone.opacity(0.5),
                style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [4, 3])
            )
            .frame(width: 4)
    }

    // MARK: Left zone — the voice animation

    /// The live mic-level voice animation — the app's signature asset,
    /// runtime-configurable via `SettingsStore.voiceAnimationStyle`
    /// (sonar / ring gauge / spectrum) and `voiceAnimationColor`. Each
    /// variant owns its complete look (`OverlayVoiceAnimation.swift`) —
    /// no shared chamber wraps them; the menu designs are distinct.
    /// `isActive` is pinned to `.listening` — lit iff the mic is capturing.
    private var leftZone: some View {
        VoiceAnimationView(
            style: settingsStore.voiceAnimationStyle,
            tint: settingsStore.voiceAnimationColor.color,
            level: model.level,
            isActive: model.overlayState == .listening || !settingsStore.overlayIdleDim
        )
        .frame(width: endZoneWidth)
        .frame(maxHeight: .infinity)
        .accessibilityHidden(true)
    }

    // MARK: Right zone — the response

    /// The response zone, centered in the right endcap. Live elapsed seconds
    /// while `.listening`, spinner while `.processing`, delivered ✓ + the
    /// final elapsed time on `.done`, error mark on `.error`.
    private var rightZone: some View {
        rightZoneContent
            .frame(width: endZoneWidth)
            .frame(maxHeight: .infinity)
    }

    @ViewBuilder
    private var rightZoneContent: some View {
        switch model.overlayState {
        case .listening:
            // Live seconds — the "response" while capturing. m:ss at
            // base-scale mono semibold: smaller than title, darker through
            // weight ("make the timer darker and reduce the font size").
            Text(Self.durationLabel(model.elapsedSeconds))
                .font(.speakMonoFace(.base, semibold: true))
                .monospacedDigit()
                .foregroundStyle(Color.speakBone)
                .accessibilityLabel("Elapsed \(Self.durationLabel(model.elapsedSeconds))")
        case .processing:
            ProgressView()
                .controlSize(.small)
                .accessibilityLabel(model.isCleaningUp ? "Cleaning up" : "Pasting")
        case .done:
            // Tick + the frozen final time — "how many seconds it ran."
            VStack(spacing: 2) {
                Image(systemName: "checkmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.speakDelivered)
                Text(Self.durationLabel(model.elapsedSeconds))
                    .font(.speakMonoFace(.caption))
                    .monospacedDigit()
                    .foregroundStyle(Color.speakMica)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Done in \(Self.durationLabel(model.elapsedSeconds))")
        case .error:
            Image(systemName: "exclamationmark")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.speakError)
                .accessibilityLabel("Error")
        }
    }

    // MARK: Center lane — the text box between the hairlines

    /// The bounded text box: a phase header row (LISTENING / POLISHING /
    /// DONE / ERROR, the inline stop hint while listening, and the quiet
    /// control cluster) over the capture text. `.clipped()` is the hard
    /// guarantee that no glyph ever crosses a hairline.
    private var centerLane: some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.xs / 2) {
            if settingsStore.overlayShowPhaseHeader { headerRow }
            centerContent
        }
        .padding(.leading, SpeakSpacing.sm)
        .padding(.trailing, SpeakSpacing.xs)
        .padding(.vertical, SpeakSpacing.xs)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    /// The header row — phase word leading ("maybe listening, then polishing
    /// … on the top, a header kind of"), stop hint inline, controls trailing.
    private var headerRow: some View {
        HStack(alignment: .center, spacing: SpeakSpacing.xs) {
            // The `speakOnAir` tally lamp — a small light iff the mic is
            // capturing (the frozen rule survives: tally light, not a red wall).
            if model.overlayState == .listening {
                Circle()
                    .fill(Color.speakOnAir)
                    .frame(width: 5, height: 5)
                    .accessibilityHidden(true)
            }

            Text(phaseWord)
                .font(.speakMonoFace(.caption, semibold: true))
                .tracking(1.2)
                .foregroundStyle(phaseTint)

            if model.overlayState == .listening, !model.stopHint.isEmpty {
                Text("· \(model.stopHint) to finish")
                    .font(.speakBody(.caption))
                    .foregroundStyle(Color.speakBone.opacity(0.55))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
            controlCluster
        }
    }

    /// The phase word for the header — the pipeline's current job.
    private var phaseWord: String {
        switch model.overlayState {
        case .listening:  return "LISTENING"
        case .processing: return model.isCleaningUp ? "POLISHING" : "PASTING"
        case .done:       return "DONE"
        case .error:      return "ERROR"
        }
    }

    /// Header tint — `speakVoiceBlue` while capturing (fixed voice blue —
    /// never follows the system accent, which can be orange),
    /// `speakAgentViolet` while the LLM polishes, `speakDelivered` on done,
    /// `speakError` on error.
    private var phaseTint: Color {
        switch model.overlayState {
        case .listening:  return .speakVoiceBlue
        case .processing: return .speakAgentViolet
        case .done:       return .speakDelivered
        case .error:      return .speakError
        }
    }

    @ViewBuilder
    private var centerContent: some View {
        switch model.overlayState {
        case .listening:
            listeningCenter
        case .processing:
            SettlingProcessingContent(
                model: model,
                revealTextWhileProcessing: settingsStore.revealTextWhileProcessing
            )
        case .done:
            doneCenter
        case .error:
            errorCenter
        }
    }

    /// The FIFO capture window. `windowText` holds the newest end of the
    /// transcript (oldest leaves when the char budget fills) — long dictation
    /// flows instead of growing. Rendered at footnote-scale mono inside the
    /// bounded box.
    @ViewBuilder
    private var listeningCenter: some View {
        if model.windowText.isEmpty {
            Text("Listening\u{2026}")
                .font(.speakBody(.caption))
                .foregroundStyle(Color.speakBone.opacity(0.55))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .accessibilityLabel("Listening for speech")
                .accessibilityAddTraits(.updatesFrequently)
        } else {
            Text(model.windowText)
                .font(.speakMonoFace(.caption))
                .foregroundStyle(Color.speakBone)
                .lineLimit(Self.laneLineBudget)
                .multilineTextAlignment(.leading)
                .lineSpacing(Self.laneLineSpacing)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .contentTransition(.interpolate)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: model.windowText)
                .accessibilityLabel(model.windowText)
                .accessibilityAddTraits(.updatesFrequently)
        }
    }

    /// `.done` center — "polish inside the line itself": the raw→clean diff
    /// reveals inside the bounded lane (`PolishedDiffContent` →
    /// `AnimatedTranscriptView`, internally scrollable so it stays bounded).
    /// Non-diff fallbacks show the revealed text; the header's DONE word and
    /// the right zone's tick already carry the state, so no extra glyph here.
    @ViewBuilder
    private var doneCenter: some View {
        if model.isDiffTransforming, let cleaned = model.revealedText {
            PolishedDiffContent(model: model, cleaned: cleaned)
        } else if let revealed = model.revealedText, !revealed.isEmpty {
            Text(revealed)
                .font(.speakMonoFace(.caption))
                .foregroundStyle(Color.speakBone)
                .lineLimit(Self.laneLineBudget)
                .multilineTextAlignment(.leading)
                .lineSpacing(Self.laneLineSpacing)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .accessibilityLabel("Dictation complete. \(revealed)")
        } else {
            Text("Pasted at cursor")
                .font(.speakBody(.caption))
                .foregroundStyle(Color.speakMica)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .accessibilityLabel("Dictation complete")
        }
    }

    /// `.error` center — the reason plus the recovery hint, inside the lane.
    private var errorCenter: some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.xs) {
            HStack(spacing: SpeakSpacing.xs) {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(Color.speakError)
                    .font(.system(size: 12))
                if let reason = model.errorReason, !reason.isEmpty {
                    Text(reason)
                        .font(.speakBody(.caption))
                        .foregroundStyle(Color.speakBone)
                        .lineLimit(2)
                        .truncationMode(.tail)
                }
            }
            Text("Press Escape or try again")
                .font(.speakBody(.caption))
                .foregroundStyle(Color.speakMica.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityErrorLabel)
    }

    private var accessibilityErrorLabel: String {
        var label = "Dictation error."
        if let reason = model.errorReason, !reason.isEmpty {
            label += " \(reason)."
        }
        label += " Press Escape or try again."
        return label
    }

    // MARK: - Lane control strip

    /// State-dependent controls, quiet mica glyphs in the lane's trailing top
    /// corner. Listening: customize + close. Processing: close only. Done:
    /// readback / re-clean (when wired) + close. Error: close.
    @ViewBuilder
    private var controlCluster: some View {
        switch model.overlayState {
        case .listening:
            customizeButton
            closeButton
        case .processing:
            closeButton
        case .done:
            if model.onReadback != nil { readbackButton }
            if model.onReclean != nil { recleanButton }
            closeButton
        case .error:
            closeButton
        }
    }

    /// Opens the separate `CodingCustomizationPanel` (per-dictation knobs).
    private var customizeButton: some View {
        Button {
            model.isCodingPanelOpen.toggle()
            model.onCodingPanelOpenChanged?(model.isCodingPanelOpen)
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 12))
                .foregroundStyle(Color.speakBone.opacity(0.55))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Customize the prompt for this dictation")
        .accessibilityAddTraits(model.isCodingPanelOpen ? [.isSelected, .isButton] : .isButton)
    }

    private var closeButton: some View {
        Button {
            model.onCancel?()
        } label: {
            // Plain dark ✕ — the faint mica `xmark.circle.fill` washed out on
            // the light capsule glass (light-on-light feedback).
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.speakBone.opacity(0.65))
        }
        .buttonStyle(.plain)
        .help("Cancel dictation and hide overlay")
        .accessibilityLabel("Cancel dictation")
    }

    private var readbackButton: some View {
        Button {
            model.onReadback?()
        } label: {
            Image(systemName: "speaker.wave.2")
                .font(.system(size: 13))
                .foregroundStyle(Color.speakBone.opacity(0.55))
        }
        .buttonStyle(.plain)
        .help("Read this back aloud")
        .accessibilityLabel("Read the transcript back aloud")
    }

    private var recleanButton: some View {
        Button {
            model.onReclean?()
        } label: {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 13))
                .foregroundStyle(Color.speakBone.opacity(0.55))
        }
        .buttonStyle(.plain)
        .help("Re-clean with current settings")
    }

    /// Format elapsed seconds as `m:ss` for the HUD (e.g. 0:05, 1:23).
    static func durationLabel(_ seconds: Int) -> String {
        let s = max(0, seconds)
        return "\(s / 60):\(String(format: "%02d", s % 60))"
    }

    // MARK: - VoiceOver state announcements

    private func postAccessibilityAnnouncement(for state: OverlayState) {
        let message: String
        switch state {
        case .listening:   message = "Listening"
        case .processing:  message = model.isCleaningUp ? "Cleaning up" : "Pasting"
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

// MARK: - Preview

#if DEBUG
#Preview("Listening — placeholder") {
    let model = OverlayViewModel()
    model.overlayState = .listening
    model.stopHint = "⌘⌘ Right Command"
    model.level = 0.0
    return TranscriptOverlayView(model: model, settingsStore: SettingsStore())
        .frame(width: 640, height: 76)
}

#Preview("Listening — live level 0.6") {
    let model = OverlayViewModel()
    model.overlayState = .listening
    model.windowText = "the quick brown fox jumps over the lazy dog and keeps on streaming words into the bounded capture lane"
    model.stopHint = "⌘⌘ Right Command"
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
    model.stopHint = "Fn ×2"
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
    model.stopHint = "⌘⌘ Right Command"
    model.isCodingPanelOpen = true
    return TranscriptOverlayView(model: model, settingsStore: SettingsStore())
        .frame(width: 640, height: 76)
}
#endif
