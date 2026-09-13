// App/Overlay/AuroraOverlayView.swift
//
// H-UI — the "Aurora" HUD style: an alternative, opt-in visual for the
// floating recording overlay. Selectable via `SettingsStore.hudStyle`
// (`OverlayRootView` switches between this and the classic bar-waveform HUD).
// The classic HUD (`TranscriptOverlayView`) is untouched — this file duplicates
// the frame code rather than sharing it, per the zero-regression-risk
// convention below. [decision: zero regression risk]
//
// LAYOUT — the capsule-with-inscribed-circles frame shared with the classic
// HUD, in Aurora's voice (the ambient orb inside the left circle instead of
// the bar waveform):
//
//    ╭─────────╮┌────────────────────────┐╭─────────╮
//   (  voice   )(   text lane — proper   )(  live    )
//   (  anim    )(   rectangle bounded    )( seconds  )
//   (          )(   by the circles       )(  or ✓    )
//    ╰─────────╯└────────────────────────┘╰─────────╯
//      circle                               circle
//
//   • Left circle — `AmbientOrbView` (the style's signature — already
//     circular, a natural fit) inside a `speakSurface` disc + `speakCardBorder`
//     ring inscribed in the capsule's left endcap. Level-reactivity and
//     per-phase gradients unchanged.
//   • Center     — the "proper rectangle": `model.windowText` (the FIFO
//     window — `OverlayController` feeds it for BOTH hud styles) at
//     `.speakMonoFace(.caption)`, multi-line, topLeading, clipped — text can
//     never touch the circles. Quiet control strip in the lane's trailing top
//     corner; stop hint tucked into the lane's trailing bottom corner.
//   • Right circle — the response: live seconds while `.listening`, spinner
//     while `.processing`, delivered ✓ on `.done`, error mark on `.error`.
//
//   All four states share this silhouette — only the lane content and the
//   right circle's glyph swap. Processing/done lane content is REUSED from
//   `SettlingOverlayContent.swift` (`SettlingProcessingContent`,
//   `PolishedDiffContent` — internal, same module) so the felt-speed reveal
//   isn't style-gated.
//
// VISUAL LANGUAGE (unchanged):
//   • `AmbientOrbView` (`Canvas` + `TimelineView`) breathes slowly at rest,
//     swells with live microphone level while listening, and recolors per
//     state: violet→teal aurora gradient (listening), warm flow spectrum
//     (processing — "thinking"), solid green (done), solid red (error).
//   • Same 4-state contract as the classic HUD: listening / processing /
//     done / error — same `OverlayViewModel`, same honest copy.
//
// MOTION + ACCESSIBILITY:
//   • All decorative motion (breathing, ripple, hue drift) is suppressed when
//     `accessibilityReduceMotion` is on. The orb still reflects live state —
//     motion is decoration, information is not.
//   • VoiceOver: the orb is `accessibilityHidden` (decorative); state and
//     transcript text carry the accessibility labels, and state transitions
//     post the same `NSAccessibility.post` announcement pattern as the
//     classic HUD (duplicated here, not shared, to keep `TranscriptOverlayView`
//     fully unmodified per the zero-regression-risk constraint).
//
// Pure math (`cyclicPhase`, `orbRadius`) lives in
// `SpeakCore/Overlay/AuroraMath.swift` so it is unit-testable without a
// Canvas/display — see `AuroraMathTests.swift`.
//
// Tokens: `speakBone` primary text, `speakMica` secondary, `speakOnAir` capture
// tally ONLY (the left circle's ring tint while listening — the orb gradient
// stays agent-violet per its design), `speakDelivered` done, `speakError`
// error, `speakCardBorder` circle rings, `speakSurface` disc fill. No raw hex;
// `SpeakSpacing.*` for all spacing.

import AppKit
import SpeakCore
import SwiftUI

// MARK: - AuroraOverlayView

/// The Aurora-style HUD content. Same capsule-with-inscribed-circles frame and
/// panel footprint as the classic HUD (hosted inside the same
/// `TranscriptOverlayPanel`), different visual voice: the ambient orb lives
/// inside the left circle.
struct AuroraOverlayView: View {
    let model: OverlayViewModel
    let settingsStore: SettingsStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: Locked geometry constants (mirrors the classic HUD's frame)

    /// Inscribed circle diameter. [decision: 90 pt — the panel is 112 pt tall,
    ///  so the card interior is 108 pt (4 pt of outer shadow padding); a 90 pt
    ///  circle centered in a 108 pt endcap leaves a 9 pt margin on every side —
    ///  it reads as inscribed inside the rounded end, never touching it.
    ///  COUPLED to `TranscriptOverlayPanel.panelHeight` = 112.]
    private static let circleSize: CGFloat = 80

    /// Width of each end zone holding an inscribed circle. [decision: 108 pt =
    ///  the card interior height — the endcap is a semicircle of radius 54 whose
    ///  center sits at x = 54; a zone this wide centers the 90 pt circle exactly
    ///  on the cap's center, so the ring is concentric with the capsule end.]
    private static let endZoneWidth: CGFloat = 96

    /// Circle ring stroke. [decision: 1 pt ring.]
    private static let ringWidth: CGFloat = 1

    /// Orb frame size inside the left circle. [decision: 56 pt — centered in the
    ///  ~78 pt clear disc; max drawn radius (~23 pt core + ripple ring to 22 pt
    ///  radius) fits with headroom.]
    private static let orbSize: CGFloat = 56

    /// Lane line budget WITHOUT the stop-hint strip (processing / done / error).
    /// [decision: 5 lines — ~15 pt per line at 11 pt mono + 2 pt spacing; the
    ///  lane has ~82 pt of text height once the control strip is reserved.]
    private static let centerLineBudget = 5

    /// Lane line budget while `.listening` (the stop-hint strip is visible).
    /// [decision: 4 lines — the hint row reclaims ~18 pt, leaving ~64 pt.]
    private static let listeningLineBudget = 4

    /// Line spacing inside the capture lane. [decision: ~2 pt per spec.]
    private static let laneLineSpacing: CGFloat = SpeakSpacing.xs / 2

    var body: some View {
        ZStack {
            // Inner clipped card (frosted-glass background + HUD content).
            ZStack {
                VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                    .clipShape(Capsule(style: .continuous))

                contentLayer
            }
            // Capsule (vs. the classic HUD's rounded rectangle) is the primary
            // shape differentiator for the Aurora style. [decision H-UI]
            .clipShape(Capsule(style: .continuous))

            // Animated border layer — switches based on settingsStore.borderAnimationStyle
            borderLayer
        }
        .padding(2)
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
                reduceMotion: reduceMotion
            )

        case .edgeFlow:
            EdgeFlowBorder(
                shape: Capsule(style: .continuous),
                state: model.overlayState,
                level: model.level,
                speed: settingsStore.borderFlowSpeed,
                count: settingsStore.borderFlowCount,
                reduceMotion: reduceMotion
            )
        }
    }

    /// All four states render inside the shared capsule-with-circles frame —
    /// Aurora has no alternate content layer (the conversation-loop path is a
    /// classic-HUD surface; unchanged behavior).
    private var contentLayer: some View {
        capsuleFrame
    }

    // MARK: - The capsule-with-inscribed-circles frame (Aurora voice)

    /// ( circle ) [ bounded text lane ] ( circle )
    /// Fixed geometry shared by all four states. The two circles ARE the
    /// boundary elements — the lane between them is a proper rectangle,
    /// clipped so text can never touch a ring.
    private var capsuleFrame: some View {
        HStack(alignment: .center, spacing: 0) {
            leftCircleZone
            centerLane
            rightCircleZone
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// A circle inscribed in one capsule endcap: `speakSurface` disc for subtle
    /// separation from the frosted glass, `speakCardBorder` ring. The zone width
    /// equals the interior height so the circle lands concentric with the
    /// capsule's rounded end.
    private func inscribedCircle<Content: View>(
        ringTint: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        ZStack {
            Circle()
                .fill(Color.speakBone.opacity(0.06))
                .overlay(Circle().strokeBorder(ringTint, lineWidth: Self.ringWidth))
            content()
        }
        .frame(width: Self.circleSize, height: Self.circleSize)
        .frame(width: Self.endZoneWidth)
        .frame(maxHeight: .infinity)
    }

    // MARK: Left circle — the ambient orb

    /// `AmbientOrbView` is the style's signature — already circular, so it sits
    /// naturally inside the inscribed ring. The orb's gradient follows the
    /// overlay phase (aurora gradient while listening, warm spectrum while
    /// processing, delivered green on done, error red on error); its
    /// level-reactivity is live only while the mic is capturing (the controller
    /// zeroes `level` at `.processing`).
    private var leftCircleZone: some View {
        inscribedCircle(ringTint: leftRingTint) {
            AmbientOrbView(level: model.level, phase: orbPhase, reduceMotion: reduceMotion)
                .frame(width: Self.orbSize, height: Self.orbSize)
        }
    }

    /// The left ring takes a restrained onAir tint while the mic is capturing —
    /// the circle is the capture chamber. Card border otherwise.
    private var leftRingTint: Color {
        model.overlayState == .listening ? .speakOnAir.opacity(0.6) : .speakCardBorder
    }

    private var orbPhase: AmbientOrbView.Phase {
        switch model.overlayState {
        case .listening:  return .listening
        case .processing: return .processing
        case .done:       return .done
        case .error:      return .error
        }
    }

    // MARK: Right circle — the response

    /// The response chamber. Live elapsed seconds while `.listening`, spinner
    /// while `.processing`, delivered ✓ on `.done`, error mark on `.error`.
    private var rightCircleZone: some View {
        inscribedCircle(ringTint: rightRingTint) {
            rightCircleContent
        }
    }

    /// Restrained state tint on the response ring — delivered on done, error on
    /// error, neutral card border while working.
    private var rightRingTint: Color {
        switch model.overlayState {
        case .done:  return .speakDelivered.opacity(0.6)
        case .error: return .speakError.opacity(0.6)
        case .listening, .processing: return .speakCardBorder
        }
    }

    @ViewBuilder
    private var rightCircleContent: some View {
        switch model.overlayState {
        case .listening:
            // Live seconds — the "response" while capturing. m:ss at title-scale
            // mono: "10:00" is ~5 glyphs ≈ 60 pt, inside the ~78 pt clear disc.
            Text(Self.durationLabel(model.elapsedSeconds))
                .font(.speakMonoFace(.title))
                .monospacedDigit()
                .foregroundStyle(Color.speakBone)
                .accessibilityLabel("Elapsed \(Self.durationLabel(model.elapsedSeconds))")
        case .processing:
            ProgressView()
                .controlSize(.regular)
                .scaleEffect(1.1)  // [decision: present, not lost, inside the 90 pt disc]
                .accessibilityLabel(model.isCleaningUp ? "Cleaning up" : "Pasting")
        case .done:
            Image(systemName: "checkmark")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Color.speakDelivered)
                .accessibilityLabel("Done")
        case .error:
            Image(systemName: "exclamationmark")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.speakError)
                .accessibilityLabel("Error")
        }
    }

    // MARK: Center lane — the bounded rectangle between the circles

    /// The "proper rectangle": a bounded text lane with a quiet control strip
    /// in its trailing top corner and the stop hint tucked into its trailing
    /// bottom corner (while listening). `.clipped()` is the hard guarantee that
    /// no glyph ever touches a circle.
    private var centerLane: some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.xs) {
            // Quiet control strip — trailing top corner of the lane.
            HStack(spacing: SpeakSpacing.sm) {
                Spacer(minLength: 0)
                controlCluster
            }

            centerContent

            // Stop hint — lane bottom, trailing edge, tucked under the right
            // circle's side. Never breaks the circle's silhouette.
            if model.overlayState == .listening, !model.stopHint.isEmpty {
                HStack {
                    Spacer(minLength: 0)
                    Text("\(model.stopHint) to finish")
                        .font(.speakBody(.caption))
                        .foregroundStyle(Color.speakMica.opacity(0.8))
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, SpeakSpacing.sm)
        .padding(.vertical, SpeakSpacing.xs)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    @ViewBuilder
    private var centerContent: some View {
        switch model.overlayState {
        case .listening:
            listeningCenter
        case .processing:
            // Shared with the classic HUD (internal type, same module) — the
            // felt-speed settling reveal is identical in both styles.
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

    /// The FIFO capture window — same lane as classic. `windowText` holds the
    /// newest end of the transcript (oldest leaves when the char budget fills),
    /// rendered at footnote-scale mono so multiple lines fit inside the lane.
    /// The line budget shrinks to 4 while the stop-hint strip is visible.
    @ViewBuilder
    private var listeningCenter: some View {
        if model.windowText.isEmpty {
            Text("Listening\u{2026}")
                .font(.speakBody(.caption))
                .foregroundStyle(Color.speakMica)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .accessibilityLabel("Listening for speech")
                .accessibilityAddTraits(.updatesFrequently)
        } else {
            Text(model.windowText)
                .font(.speakMonoFace(.caption))
                .foregroundStyle(Color.speakBone)
                .lineLimit(model.stopHint.isEmpty ? Self.centerLineBudget : Self.listeningLineBudget)
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
    /// reveals inside the bounded lane (shared `PolishedDiffContent` →
    /// `AnimatedTranscriptView`, internally scrollable so it stays bounded).
    /// Non-diff fallbacks show the revealed text, else a quiet confirmation.
    @ViewBuilder
    private var doneCenter: some View {
        if model.isDiffTransforming, let cleaned = model.revealedText {
            PolishedDiffContent(model: model, cleaned: cleaned)
        } else {
            HStack(alignment: .center, spacing: SpeakSpacing.xs) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.speakDelivered)
                    .font(.system(size: 12))
                if let revealed = model.revealedText, !revealed.isEmpty {
                    Text(revealed)
                        .font(.speakMonoFace(.caption))
                        .foregroundStyle(Color.speakBone)
                        .lineLimit(Self.centerLineBudget)
                        .multilineTextAlignment(.leading)
                        .lineSpacing(Self.laneLineSpacing)
                } else {
                    Text("Done")
                        .font(.speakBody(.base))
                        .foregroundStyle(Color.speakMica)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
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

    // MARK: Controls — the lane's quiet strip

    /// State-dependent controls in the center lane's trailing top corner.
    /// Aurora keeps the strip minimal (no customize button — that entry point
    /// is a classic-HUD affordance): close ✕ in every state; DONE adds
    /// readback / re-clean when those callbacks are wired.
    @ViewBuilder
    private var controlCluster: some View {
        HStack(spacing: SpeakSpacing.sm) {
            switch model.overlayState {
            case .listening, .processing, .error:
                closeButton
            case .done:
                if model.onReadback != nil { readbackButton }
                if model.onReclean != nil { recleanButton }
                closeButton
            }
        }
    }

    /// Aurora previously had no close affordance — added so the HUD is
    /// dismissible without the hotkey. Same `model.onCancel` wiring as classic.
    private var closeButton: some View {
        Button {
            model.onCancel?()
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(Color.speakMica.opacity(0.8))
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
                .foregroundStyle(Color.speakMica)
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
                .foregroundStyle(Color.speakMica)
        }
        .buttonStyle(.plain)
        .help("Re-clean with current settings")
    }

    /// Format elapsed seconds as `m:ss`. Duplicated from `TranscriptOverlayView`
    /// (small, pure, private) rather than sharing — keeps the classic HUD file
    /// fully unmodified. [decision: zero-regression-risk duplication]
    private static func durationLabel(_ seconds: Int) -> String {
        let s = max(0, seconds)
        return "\(s / 60):\(String(format: "%02d", s % 60))"
    }

    // MARK: - VoiceOver state announcements
    //
    // Duplicated from `TranscriptOverlayView.postAccessibilityAnnouncement` —
    // identical behavior, kept as a separate small copy so the classic HUD
    // file is untouched. [decision: zero-regression-risk duplication]
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

// MARK: - AmbientOrbView

/// The breathing/reactive orb — the Aurora HUD's signature element. Pure
/// `Canvas` + `TimelineView` drawing, driven entirely by `SpeakCore`'s
/// `cyclicPhase(time:cycleDuration:)` and `orbRadius(...)` so the numeric
/// behavior is unit-testable independent of rendering.
private struct AmbientOrbView: View {
    enum Phase: Equatable {
        case listening, processing, done, error
    }

    let level: Double
    let phase: Phase
    let reduceMotion: Bool

    // Geometry/cadence constants — all [decision H-UI], no measured source
    // (this is a new decorative element, not a physical/platform constraint).
    private static let geometry = OrbGeometry(baseRadius: 12.0, breatheAmplitude: 3.0, levelBoost: 8.0)
    private static let rippleMaxExtra: Double = 10.0
    private static let breatheCycle: TimeInterval = 3.0      // slow ambient "alive" feel
    private static let rippleCycle: TimeInterval = 1.6       // matches classic HUD ripple cadence
    private static let hueCycle: TimeInterval = 6.0          // slow "thinking" color drift
    // Refresh cadence for the TimelineView while animating. [decision H-UI: 60fps —
    // matches the "fluid, 60fps" requirement; a single small decorative Canvas
    // redraw at this size is negligible cost.]
    private static let frameInterval: TimeInterval = 1.0 / 60.0

    var body: some View {
        TimelineView(.animation(minimumInterval: Self.frameInterval, paused: reduceMotion && level == 0)) { timeline in
            Canvas { context, size in
                draw(context: context, size: size, date: timeline.date)
            }
        }
        // Decorative — state is conveyed via text + VoiceOver announcements, not the orb.
        .accessibilityHidden(true)
    }

    private func draw(context: GraphicsContext, size: CGSize, date: Date) {
        let time = date.timeIntervalSinceReferenceDate
        let center = CGPoint(x: size.width / 2, y: size.height / 2)

        let breathePhase = reduceMotion ? 0 : cyclicPhase(time: time, cycleDuration: Self.breatheCycle)
        let radius = orbRadius(
            geometry: Self.geometry,
            level: level,
            breathePhase: breathePhase,
            reduceMotion: reduceMotion
        )

        let colors = gradientColors(for: phase, time: time)
        let coreRect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        context.fill(
            Path(ellipseIn: coreRect),
            with: .radialGradient(Gradient(colors: colors), center: center, startRadius: 0, endRadius: radius)
        )

        // Ripple ring — only while actively listening with audible level, and
        // only when motion is not reduced (purely decorative reinforcement).
        guard !reduceMotion, phase == .listening, level > 0.05 else { return }
        let rippleT = cyclicPhase(time: time, cycleDuration: Self.rippleCycle)
        let rippleRadius = Self.geometry.baseRadius + rippleT * Self.rippleMaxExtra
        let rippleOpacity = (1 - rippleT) * 0.5
        let ringRect = CGRect(
            x: center.x - rippleRadius, y: center.y - rippleRadius,
            width: rippleRadius * 2, height: rippleRadius * 2
        )
        context.stroke(
            Path(ellipseIn: ringRect),
            with: .color((colors.first ?? .white).opacity(rippleOpacity)),
            lineWidth: 1.5
        )
    }

    private func gradientColors(for phase: Phase, time: Double) -> [Color] {
        switch phase {
        case .listening:
            // Aurora palette: teal → agent violet. Cyan stop is fixed; violet stop
            // is themed so the orb follows the agent channel. [decision H-UI]
            return [
                Color(hue: 0.58, saturation: 0.75, brightness: 0.95),
                Color.speakAgentViolet
            ]

        case .processing:
            // Processing / cleanup-in-flight — anchored on the warm amber flow spectrum.
            let _ = time
            return Color.speakFlowProcessing

        case .done:
            return [Color.speakDelivered.opacity(0.95), Color.speakDelivered.opacity(0.6)]

        case .error:
            return [Color.speakError.opacity(0.95), Color.speakError.opacity(0.6)]
        }
    }
}

// MARK: - Preview

// HONESTY BOUNDARY: same as `TranscriptOverlayView` previews — these verify
// content layout only, not panel/window-server behavior.

#if DEBUG
#Preview("Aurora — listening, idle") {
    let model = OverlayViewModel()
    model.overlayState = .listening
    model.stopHint = "⌘⌘ Right Command"
    model.level = 0.0
    return AuroraOverlayView(model: model, settingsStore: SettingsStore())
        .frame(width: 600, height: 112)
}

#Preview("Aurora — listening, live words") {
    let model = OverlayViewModel()
    model.overlayState = .listening
    model.windowText = "the quick brown fox jumps over the lazy dog and keeps streaming words into the bounded capture lane"
    model.stopHint = "⌘⌘ Right Command"
    model.elapsedSeconds = 12
    model.level = 0.6
    return AuroraOverlayView(model: model, settingsStore: SettingsStore())
        .frame(width: 600, height: 112)
}

#Preview("Aurora — listening, long stream") {
    let model = OverlayViewModel()
    model.overlayState = .listening
    model.windowText = "newest speech stays in the window while the oldest words flow out first so a long dictation "
            + "keeps streaming inside the two circles without ever overflowing the lane or growing the panel"
    model.stopHint = "Fn ×2"
    model.elapsedSeconds = 83
    model.level = 0.45
    return AuroraOverlayView(model: model, settingsStore: SettingsStore())
        .frame(width: 600, height: 112)
}

#Preview("Aurora — processing") {
    let model = OverlayViewModel()
    model.overlayState = .processing
    model.isCleaningUp = true
    model.settlingText = "the quick brown fox jumps over the lazy dog while the model polishes the raw transcript in place"
    model.isSettling = true
    model.elapsedSeconds = 14
    return AuroraOverlayView(model: model, settingsStore: SettingsStore())
        .frame(width: 600, height: 112)
}

#Preview("Aurora — done") {
    let model = OverlayViewModel()
    model.overlayState = .done
    model.elapsedSeconds = 14
    return AuroraOverlayView(model: model, settingsStore: SettingsStore())
        .frame(width: 600, height: 112)
}

#Preview("Aurora — done, diff + actions") {
    let model = OverlayViewModel()
    model.overlayState = .done
    model.settlingText = "um so i think we should uh meet on tuesday maybe to go over the budget"
    model.revealedText = "I think we should meet on Tuesday to go over the budget."
    model.isDiffTransforming = true
    model.elapsedSeconds = 9
    model.onReadback = {}
    model.onReclean = {}
    return AuroraOverlayView(model: model, settingsStore: SettingsStore())
        .frame(width: 600, height: 112)
}

#Preview("Aurora — error") {
    let model = OverlayViewModel()
    model.overlayState = .error
    model.errorReason = "Speech engine unavailable"
    return AuroraOverlayView(model: model, settingsStore: SettingsStore())
        .frame(width: 600, height: 112)
}
#endif
