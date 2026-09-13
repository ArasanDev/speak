// App/Overlay/OverlayVoiceAnimation.swift
//
// The HUD's left-zone voice animation — the app's signature asset — as a
// runtime-configurable family. Settings → Appearance & HUD → Recording HUD
// picks the style (`voiceAnimationStyle`) and the color it draws with
// (`voiceAnimationColor`), both live like the color theme.
//
// Selected from the owner's design menu (`img/overlay-anim-options.html`):
// Sonar Ping (04) and Ring Gauge (10), with the original 15-bar spectrum
// kept as a third option. Each variant owns its COMPLETE look — no shared
// chamber wraps them; the menu designs are distinct, not layered.
//
// Every variant is level-driven (`level` = live mic RMS, 0…1) and active only
// while `.listening` — idle dims to a resting state. All motion is suppressed
// under accessibilityReduceMotion; level response is information, not
// decoration, so it is never suppressed.

import SpeakCore
import SwiftUI

// MARK: - VoiceAnimationColor resolution

public extension VoiceAnimationColor {
    /// Resolved display color — a fixed functional palette (the menu's hues),
    /// NOT the system accent, which can be orange on the owner's machine.
    var color: Color {
        switch self {
        case .blue:   return .speakVoiceBlue
        case .cyan:   return Color(red: 0.16, green: 0.71, blue: 0.85)
        case .violet: return .speakAgentViolet
        case .green:  return Color(red: 0.24, green: 0.62, blue: 0.37)
        case .amber:  return .speakHumanAmber
        }
    }
}

// MARK: - VoiceAnimationView (switcher)

/// The left-zone animation, dispatched on the user's configured style.
/// Decorative — callers apply `accessibilityHidden(true)`; the header's
/// tally lamp + phase word carry the accessible state.
struct VoiceAnimationView: View {
    let style: VoiceAnimationStyle
    let tint: Color
    let level: Double
    let isActive: Bool

    var body: some View {
        switch style {
        case .spectrum:
            SpectrumChamberView(tint: tint, level: level, isActive: isActive)
        case .sonar:
            SonarPingView(tint: tint, level: level, isActive: isActive)
        case .ringGauge:
            RingGaugeView(tint: tint, level: level, isActive: isActive)
        }
    }
}

// MARK: - SpectrumChamberView (the original — bars inside two circles)

/// "Waveform inside one circle, then another circle — a colorful animation
/// thing": the 15-bar analyser inside a quiet inner ring, a rotating
/// conic-gradient spectrum ring around it. This layering is SPECTRUM's own
/// look — the other variants draw their own complete design.
struct SpectrumChamberView: View {
    let tint: Color
    let level: Double
    let isActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// [decision: 60/48 pt — outer leaves ~6 pt margin inside the 72 pt end
    ///  zone; inner holds the ~44 pt scaled waveform block with clearance.]
    private static let outerRingSize: CGFloat = 60
    private static let innerCircleSize: CGFloat = 48
    private static let waveformScale: CGFloat = 0.75

    /// Rotation driver for the colorful outer ring.
    @State private var ringAngle: Double = 0

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(
                    AngularGradient(
                        colors: Color.speakFlowInference,
                        center: .center,
                        angle: .degrees(ringAngle)
                    ),
                    lineWidth: 2.5
                )
                .frame(width: Self.outerRingSize, height: Self.outerRingSize)
                .opacity(isActive ? 1 : 0.4)

            Circle()
                .strokeBorder(Color.speakBone.opacity(0.25), lineWidth: 1)
                .frame(width: Self.innerCircleSize, height: Self.innerCircleSize)

            WaveformView(level: level, isActive: isActive, tint: tint)
                .scaleEffect(Self.waveformScale)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 5).repeatForever(autoreverses: false)) {
                ringAngle = 360
            }
        }
    }
}

// MARK: - SonarPingView (design option 04)

/// A live center dot emitting expanding rings — quiet when you're quiet.
/// Ported from `img/overlay-anim-options.html` option 04. The variant's own
/// look: one hairline outer ring, pings inside, nothing else.
struct SonarPingView: View {
    let tint: Color
    let level: Double
    let isActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Fills the endcap like the menu render (Ø60 canvas, ring at ~0.92R).
    private static let diameter: CGFloat = 60
    /// Ring count + cycle pace — ported from the HTML reference (0.55 rev/s).
    private static let ringCount = 3
    private static let cyclesPerSecond = 0.55

    var body: some View {
        if animated {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                rings(at: context.date.timeIntervalSinceReferenceDate)
            }
        } else {
            // Idle or reduce-motion: frozen rings + the level-driven dot.
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

            // The variant's own boundary — a quiet hairline ring.
            let outerR = r * 0.92
            ctx.stroke(
                Path(ellipseIn: CGRect(
                    x: center.x - outerR, y: center.y - outerR,
                    width: outerR * 2, height: outerR * 2
                )),
                with: .color(.speakBone.opacity(0.25)),
                lineWidth: 1
            )

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
                    with: .color(tint.opacity(alpha)),
                    lineWidth: 1.5
                )
            }

            // The live dot — swells with voice energy.
            let d = r * (0.14 + level * 0.16) * 2
            ctx.fill(
                Path(ellipseIn: CGRect(
                    x: center.x - d / 2, y: center.y - d / 2, width: d, height: d
                )),
                with: .color(tint.opacity(live ? 1 : 0.35))
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
    let tint: Color
    let level: Double
    let isActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let diameter: CGFloat = 60
    private static let ringRadius: CGFloat = 22
    private static let ringWidth: CGFloat = 3.5
    private static let barCount = 9
    private static let barSize = CGSize(width: 2, height: 9)
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
                    tint.opacity(isActive ? 1 : 0.35),
                    style: StrokeStyle(lineWidth: Self.ringWidth, lineCap: .round)
                )
                .frame(width: Self.ringRadius * 2, height: Self.ringRadius * 2)
                .rotationEffect(.degrees(-90))

            // Needle dot at the arc tip.
            Circle()
                .fill(tint.opacity(isActive ? 1 : 0.35))
                .frame(width: 5.5, height: 5.5)
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
