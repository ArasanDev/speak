// App/Overlay/OverlayVoiceAnimation.swift
//
// The HUD's left-zone voice animation — the app's signature asset — as a
// runtime-configurable family (`SettingsStore.voiceAnimationStyle`, picked in
// Settings → Appearance & HUD). Selected from the owner's design menu
// (`img/overlay-anim-options.html`): Sonar Ping (04) and Ring Gauge (10),
// with the original 15-bar spectrum kept as a third option.
//
// Every variant is level-driven (`level` = live mic RMS, 0…1) and active only
// while `.listening` — idle dims to a resting state. All motion is suppressed
// under accessibilityReduceMotion; level response is information, not
// decoration, so it is never suppressed.

import SpeakCore
import SwiftUI

// MARK: - VoiceAnimationView (switcher)

/// The left-zone animation, dispatched on the user's configured style.
/// Callers wrap it in the shared chamber (inner quiet ring + rotating
/// spectrum outer ring) and `accessibilityHidden(true)` — it is decorative.
struct VoiceAnimationView: View {
    let style: VoiceAnimationStyle
    let level: Double
    let isActive: Bool

    var body: some View {
        switch style {
        case .spectrum:
            WaveformView(level: level, isActive: isActive)
                .scaleEffect(Self.spectrumScale)
        case .sonar:
            SonarPingView(level: level, isActive: isActive)
        case .ringGauge:
            RingGaugeView(level: level, isActive: isActive)
        }
    }

    /// The 15-bar block is ~58 pt wide; 0.75 lands it inside the Ø48 chamber
    /// with ring clearance (same scale callers used before this switcher).
    private static let spectrumScale: CGFloat = 0.75
}

// MARK: - SonarPingView (design option 04)

/// A live center dot emitting expanding rings — quiet when you're quiet.
/// Ported from `img/overlay-anim-options.html` option 04.
struct SonarPingView: View {
    let level: Double
    let isActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Natural size; fits inside the Ø48 inner chamber with clearance.
    private static let diameter: CGFloat = 44
    /// Ring count + cycle pace — ported from the HTML reference (0.55 rev/s).
    private static let ringCount = 3
    private static let cyclesPerSecond = 0.55

    var body: some View {
        if animated {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                rings(at: context.date.timeIntervalSinceReferenceDate)
            }
        } else {
            // Idle or reduce-motion: three frozen rings + the level-driven dot.
            rings(at: 0)
        }
    }

    /// Motion runs only while listening and only when motion is allowed.
    private var animated: Bool { isActive && !reduceMotion }

    private func rings(at time: TimeInterval) -> some View {
        Canvas { ctx, size in
            let r = min(size.width, size.height) / 2
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let live = isActive

            for i in 0 ..< Self.ringCount {
                let p = (time * Self.cyclesPerSecond + Double(i) / Double(Self.ringCount))
                    .truncatingRemainder(dividingBy: 1)
                let ringR = r * 0.14 + p * r * 0.72
                let alpha = live ? (1 - p) * (0.25 + level * 0.6) : 0.15
                ctx.stroke(
                    Path(ellipseIn: CGRect(
                        x: center.x - ringR, y: center.y - ringR,
                        width: ringR * 2, height: ringR * 2
                    )),
                    with: .color(.speakVoiceBlue.opacity(alpha)),
                    lineWidth: 1.5
                )
            }

            // The live dot — swells with voice energy.
            let d = r * (0.14 + level * 0.16) * 2
            ctx.fill(
                Path(ellipseIn: CGRect(
                    x: center.x - d / 2, y: center.y - d / 2, width: d, height: d
                )),
                with: .color(.speakVoiceBlue.opacity(live ? 1 : 0.35))
            )
        }
        .frame(width: Self.diameter, height: Self.diameter)
    }
}

// MARK: - RingGaugeView (design option 10)

/// The ring itself is the meter: it fills with voice level, a needle dot rides
/// the arc tip, and a row of micro-bars in the center shows the same level in
/// discrete steps. Ported from `img/overlay-anim-options.html` option 10.
struct RingGaugeView: View {
    let level: Double
    let isActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let diameter: CGFloat = 44
    private static let ringRadius: CGFloat = 16.5
    private static let ringWidth: CGFloat = 3
    private static let barCount = 9
    private static let barSize = CGSize(width: 2, height: 7)
    private static let barGap: CGFloat = 1.5

    private var clampedLevel: Double { min(max(level, 0), 1) }

    var body: some View {
        ZStack {
            // Track ring.
            Circle()
                .stroke(Color.speakBone.opacity(isActive ? 0.16 : 0.10),
                        lineWidth: Self.ringWidth)
                .frame(width: Self.ringRadius * 2, height: Self.ringRadius * 2)

            // Level fill — grows clockwise from 12 o'clock.
            Circle()
                .trim(from: 0, to: clampedLevel)
                .stroke(
                    Color.speakVoiceBlue.opacity(isActive ? 1 : 0.35),
                    style: StrokeStyle(lineWidth: Self.ringWidth, lineCap: .round)
                )
                .frame(width: Self.ringRadius * 2, height: Self.ringRadius * 2)
                .rotationEffect(.degrees(-90))

            // Needle dot at the arc tip.
            Circle()
                .fill(Color.speakVoiceBlue.opacity(isActive ? 1 : 0.35))
                .frame(width: 5, height: 5)
                .offset(needleOffset)

            // Center micro-bars — discrete steps of the same level.
            HStack(spacing: Self.barGap) {
                ForEach(0 ..< Self.barCount, id: \.self) { i in
                    let lit = Double(i) / Double(Self.barCount) < clampedLevel
                    RoundedRectangle(cornerRadius: Self.barSize.width / 2, style: .continuous)
                        .fill(Color.speakBone.opacity(lit ? (isActive ? 0.9 : 0.4) : 0.18))
                        .frame(width: Self.barSize.width, height: Self.barSize.height)
                }
            }
        }
        .frame(width: Self.diameter, height: Self.diameter)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.08), value: clampedLevel)
    }

    /// Tip position of the fill arc (angle = -90° + level·360°).
    private var needleOffset: CGSize {
        let angle = (-Double.pi / 2) + clampedLevel * 2 * Double.pi
        return CGSize(
            width: cos(angle) * Self.ringRadius,
            height: sin(angle) * Self.ringRadius
        )
    }
}
