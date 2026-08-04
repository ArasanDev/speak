// App/Overlay/AuroraOverlayView.swift
//
// H-UI — the "Aurora" HUD style: an alternative, opt-in visual for the
// floating recording overlay. Selectable via `SettingsStore.hudStyle`
// (`OverlayRootView` switches between this and the classic bar-waveform HUD).
// The classic HUD (`TranscriptOverlayView`) is untouched — this file adds a
// new surface, it does not modify the default path. [decision: zero
// regression risk — .classic stays the default in SettingsStore]
//
// VISUAL LANGUAGE:
//   • An ambient orb (`AmbientOrbView`, `Canvas` + `TimelineView`) breathes
//     slowly at rest, swells with live microphone level while listening, and
//     recolors per state: violet→teal aurora gradient (listening), slow
//     hue-drifting gradient (processing — "thinking"), solid green (done),
//     solid red (error).
//   • Partial transcript words materialize one at a time in a trailing
//     ticker (`WordTickerView`) as they arrive, rather than the classic HUD's
//     static 3-line paragraph — the "Jarvis" streaming-words effect.
//   • Same 4-state contract as the classic HUD: listening / processing /
//     done / error — reusing the same `OverlayViewModel` and the same
//     honest copy ("Cleaning up…" vs "Pasting…", error reason + retry hint).
//
// MOTION + ACCESSIBILITY:
//   • All decorative motion (breathing, ripple, hue drift, word slide-in) is
//     suppressed when `accessibilityReduceMotion` is on. The orb and word
//     ticker still reflect live state (level, text) — motion is decoration,
//     information is not.
//   • VoiceOver: the orb is `accessibilityHidden` (decorative); state and
//     transcript text carry the accessibility labels, and state transitions
//     post the same `NSAccessibility.post` announcement pattern as the
//     classic HUD (duplicated here, not shared, to keep `TranscriptOverlayView`
//     fully unmodified per the zero-regression-risk constraint).
//
// Pure math (`cyclicPhase`, `orbRadius`, `wordWindow`) lives in
// `SpeakCore/Overlay/AuroraMath.swift` so it is unit-testable without a
// Canvas/display — see `AuroraMathTests.swift`.

import AppKit
import SpeakCore
import SwiftUI

// MARK: - AuroraOverlayView

/// The Aurora-style HUD content. Same panel footprint as the classic HUD
/// (hosted inside the same `TranscriptOverlayPanel`), different visual voice.
struct AuroraOverlayView: View {
    let model: OverlayViewModel
    let settingsStore: SettingsStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Orb frame size. [decision H-UI: 44pt — matches the classic HUD's
    /// waveform block width so panel geometry does not need to change.]
    private static let orbSize: CGFloat = 44

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

    @ViewBuilder
    private var contentLayer: some View {
        switch model.overlayState {
        case .listening:
            listeningContent

        case .processing:
            processingContent

        case .done:
            doneContent

        case .error:
            errorContent
        }
    }

    // MARK: - Listening

    private var listeningContent: some View {
        HStack(alignment: .center, spacing: SpeakSpacing.sm) {
            AmbientOrbView(level: model.level, phase: .listening, reduceMotion: reduceMotion)
                .frame(width: Self.orbSize, height: Self.orbSize)
            WordTickerView(fullText: model.partialText, reduceMotion: reduceMotion)
            Text(Self.durationLabel(model.elapsedSeconds))
                .font(.speakMonoCaption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, SpeakSpacing.md)
        .padding(.vertical, SpeakSpacing.sm + SpeakSpacing.xs)
    }

    /// Format elapsed seconds as `m:ss`. Duplicated from `TranscriptOverlayView`
    /// (small, pure, private) rather than sharing — keeps the classic HUD file
    /// fully unmodified. [decision: zero-regression-risk duplication]
    private static func durationLabel(_ seconds: Int) -> String {
        let s = max(0, seconds)
        return "\(s / 60):\(String(format: "%02d", s % 60))"
    }

    // MARK: - Processing

    private var processingContent: some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.xs) {
            HStack(spacing: SpeakSpacing.sm) {
                AmbientOrbView(level: 0, phase: .processing, reduceMotion: reduceMotion)
                    .frame(width: Self.orbSize, height: Self.orbSize)
                Text(model.isCleaningUp ? "Cleaning up\u{2026}" : "Pasting\u{2026}")
                    .font(.speakMonoBody)
                    .foregroundStyle(.secondary)
            }
            // [input-felt-speed §3.3] Same progressive reveal as `TranscriptOverlayView`
            // (classic HUD) — kept in sync so the felt-speed benefit isn't style-gated.
            if settingsStore.revealTextWhileProcessing, !model.partialText.isEmpty {
                Text(model.partialText)
                    .font(.speakMonoBody)
                    .foregroundStyle(.secondary.opacity(0.75))
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel("Settling: \(model.partialText)")
            }
        }
        .padding(.horizontal, SpeakSpacing.md)
        .padding(.vertical, SpeakSpacing.sm + SpeakSpacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.isCleaningUp ? "Cleaning up transcription" : "Pasting transcription")
    }

    // MARK: - Done

    private var doneContent: some View {
        HStack(spacing: SpeakSpacing.sm) {
            AmbientOrbView(level: 0, phase: .done, reduceMotion: reduceMotion)
                .frame(width: Self.orbSize, height: Self.orbSize)
            Text("Done")
                .font(.speakMonoBody)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, SpeakSpacing.md)
        .padding(.vertical, SpeakSpacing.sm + SpeakSpacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Dictation complete")
    }

    // MARK: - Error

    private var errorContent: some View {
        HStack(spacing: SpeakSpacing.sm) {
            AmbientOrbView(level: 0, phase: .error, reduceMotion: reduceMotion)
                .frame(width: Self.orbSize, height: Self.orbSize)
            VStack(alignment: .leading, spacing: 2) {
                Text("Error")
                    .font(.speakMonoBody)
                    .foregroundStyle(.primary)
                if let reason = model.errorReason, !reason.isEmpty {
                    Text(reason)
                        .font(.speakMonoCaption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Text("Press Escape or try again")
                    .font(.speakMonoCaption)
                    .foregroundStyle(Color.secondary.opacity(0.7))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, SpeakSpacing.md)
        .padding(.vertical, SpeakSpacing.sm + SpeakSpacing.xs)
        .accessibilityElement(children: .ignore)
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

// MARK: - WordTickerView

/// Trailing window of the partial transcript, materializing new words with a
/// slide-in + fade transition as they arrive. Falls back to "Listening…"
/// placeholder copy when no words have arrived yet (matches the classic HUD).
private struct WordTickerView: View {
    let fullText: String
    let reduceMotion: Bool

    /// [decision H-UI: 6 words — fits the 340pt panel width at body font size
    /// alongside the 44pt orb and the duration label without wrapping.]
    private static let maxWords = 6

    var body: some View {
        HStack(spacing: 6) {
            if fullText.isEmpty {
                Text("Listening\u{2026}")
                    .font(.speakMonoBody)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(wordWindow(fullText: fullText, maxWords: Self.maxWords), id: \.id) { token in
                    Text(token.word)
                        .font(.speakMonoBody)
                        .foregroundStyle(.primary)
                        .transition(
                            reduceMotion
                                ? .identity
                                : .asymmetric(
                                    insertion: .opacity.combined(with: .move(edge: .trailing)),
                                    removal: .opacity
                                )
                        )
                }
            }
        }
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: fullText)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(fullText.isEmpty ? "Listening for speech" : fullText)
        .accessibilityAddTraits(.updatesFrequently)
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
            // Aurora palette: violet core → teal edge. [decision H-UI]
            return [
                Color(hue: 0.58, saturation: 0.75, brightness: 0.95),
                Color(hue: 0.78, saturation: 0.65, brightness: 0.85)
            ]

        case .processing:
            // Slow hue drift signals "thinking" — suppressed to a fixed amber
            // hue under Reduce Motion (still distinct from listening/done/error).
            let hue = reduceMotion ? 0.12 : cyclicPhase(time: time, cycleDuration: Self.hueCycle)
            let edgeHue = (hue + 0.15).truncatingRemainder(dividingBy: 1.0)
            return [
                Color(hue: hue, saturation: 0.7, brightness: 0.95),
                Color(hue: edgeHue, saturation: 0.6, brightness: 0.8)
            ]

        case .done:
            return [Color.green.opacity(0.95), Color.green.opacity(0.6)]

        case .error:
            return [Color.red.opacity(0.95), Color.red.opacity(0.6)]
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
    model.partialText = ""
    model.level = 0.0
    return AuroraOverlayView(model: model, settingsStore: SettingsStore())
        .frame(width: 340, height: 80)
}

#Preview("Aurora — listening, live words") {
    let model = OverlayViewModel()
    model.overlayState = .listening
    model.partialText = "the quick brown fox jumps over the lazy dog"
    model.level = 0.6
    return AuroraOverlayView(model: model, settingsStore: SettingsStore())
        .frame(width: 340, height: 80)
}

#Preview("Aurora — processing") {
    let model = OverlayViewModel()
    model.overlayState = .processing
    model.isCleaningUp = true
    return AuroraOverlayView(model: model, settingsStore: SettingsStore())
        .frame(width: 340, height: 80)
}

#Preview("Aurora — done") {
    let model = OverlayViewModel()
    model.overlayState = .done
    return AuroraOverlayView(model: model, settingsStore: SettingsStore())
        .frame(width: 340, height: 80)
}

#Preview("Aurora — error") {
    let model = OverlayViewModel()
    model.overlayState = .error
    model.errorReason = "Speech engine unavailable"
    return AuroraOverlayView(model: model, settingsStore: SettingsStore())
        .frame(width: 340, height: 80)
}
#endif
