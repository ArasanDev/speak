// App/Pet/PetView.swift
//
// FE-1 (specs/frontend-identity.md §5): Voice Desktop Pet's body. A 56×36pt capsule
// containing five 3pt bars — "the body is a live waveform... bars-as-body
// means every animation is a true signal readout, never decoration."
//
// Same technique as the Aurora HUD's `AmbientOrbView` (Canvas + TimelineView,
// driven by pure math), reusing the SAME level signal the HUD consumes
// (`OverlayController`'s smoothed RMS level via `currentLevels()`).
//
// UI RENDERING ITSELF IS [deferred — human visual verification], matching the
// codebase convention (see `AuroraOverlayView.swift`'s "HONESTY BOUNDARY" —
// previews verify layout only, not window-server/pixel behavior). The pure
// math backing this view (`PetState.resolve`, bar-height math below) IS
// unit-tested in `SpeakTests` independent of rendering.

import SwiftUI

// MARK: - PetView

/// Voice Desktop Pet's rendered body: capsule + five bars + tally dot + hover-widened
/// status lozenge. Purely a function of `state`, `level`, and `attentionCount` —
/// no side effects, no engine access (hard rule: Voice Desktop Pet never opens the mic).
struct PetView: View {
    let state: PetState
    /// Smoothed 0…1 microphone/TTS level — same signal the Aurora HUD orb uses.
    let level: Double
    let attentionCount: Int
    let statusText: String
    let isHovering: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Wall-clock time (`.timeIntervalSinceReferenceDate`) at which `state`
    /// most recently changed — drives the `.listening` anticipation dip
    /// (animation-soul amendment, 2026-07-11). Rendering-only plumbing,
    /// [deferred — human visual verification]; the dip MATH itself is pure
    /// and unit-tested via `petBarHeights(enteredStateAt:)`.
    @State private var stateEnteredAt: TimeInterval = Date().timeIntervalSinceReferenceDate

    // Form constants (spec §5).
    private static let robotSize = CGSize(width: 64, height: 60)
    private static let hoverScale: CGFloat = 1.15
    private static let barWidth: CGFloat = 3
    private static let barGap: CGFloat = 2
    private static let barMinHeight: CGFloat = 2
    private static let barMaxHeight: CGFloat = 14
    private static let barCount = 5
    private static let frameInterval: TimeInterval = 1.0 / 60.0

    private var cloudColor: Color { Color(red: 0.35, green: 0.5, blue: 0.95) }
    private var screenColor: Color { Color(red: 0.08, green: 0.1, blue: 0.2) }
    private var cyanGlow: Color { Color(red: 0.2, green: 0.85, blue: 1.0) }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            robotBody
        }
        .frame(width: Self.robotSize.width, height: Self.robotSize.height)
        .scaleEffect(isHovering ? Self.hoverScale : 1.0)
        .animation(SpeakMotion.micro(reduceMotion: reduceMotion), value: isHovering)
        .overlay(alignment: .leading) {
            if isHovering {
                statusLozenge
                    .offset(x: Self.robotSize.width * Self.hoverScale + 6)
                    .transition(.opacity)
            }
        }
        .animation(SpeakMotion.micro(reduceMotion: reduceMotion), value: isHovering)
        .onChange(of: state) { _, _ in
            stateEnteredAt = Date().timeIntervalSinceReferenceDate
        }
    }

    // MARK: - Robot Body

    private var robotBody: some View {
        VStack(spacing: -4) {
            // Head
            ZStack {
                Image(systemName: "cloud.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(cloudColor)
                    .frame(height: 44)
                
                // Screen face
                RoundedRectangle(cornerRadius: 4)
                    .fill(screenColor)
                    .frame(width: 34, height: 20)
                    .overlay(faceContent)
            }
            
            // Chest
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(cloudColor)
                    .frame(width: 36, height: 16)
                
                chestEmblem
            }
        }
    }

    @ViewBuilder
    private var faceContent: some View {
        switch state {
        case .dormant:
            Text("(u u)")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.gray.opacity(0.8))
        case .listening, .processing, .agentWorking, .idle:
            barsCanvas
        case .speaking:
            speakingFace
        case .attention:
            Text("(! !)")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(cyanGlow)
                .shadow(color: cyanGlow, radius: 2)
        }
    }

    private var speakingFace: some View {
        TimelineView(.animation(minimumInterval: 0.3)) { timeline in
            let tick = Int(timeline.date.timeIntervalSince1970 * 2) % 2 == 0
            HStack(spacing: 1) {
                Text(">")
                Text("_").opacity(tick ? 1 : 0)
            }
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .foregroundStyle(cyanGlow)
            .shadow(color: cyanGlow, radius: 3)
        }
    }

    private var chestEmblem: some View {
        Text(">_")
            .font(.system(size: 8, weight: .bold, design: .monospaced))
            .foregroundStyle(state == .attention ? cyanGlow : Color.white.opacity(0.6))
            .shadow(color: state == .attention ? cyanGlow : .clear, radius: 3)
    }

    private var barsCanvas: some View {
        TimelineView(.animation(
            minimumInterval: Self.frameInterval,
            paused: reduceMotion && level == 0 && state != .idle && state != .dormant
        )) { timeline in
            Canvas { context, size in
                draw(context: context, size: size, date: timeline.date)
            }
        }
        .frame(width: CGFloat(Self.barCount) * Self.barWidth + CGFloat(Self.barCount - 1) * Self.barGap,
               height: Self.barMaxHeight)
        .accessibilityHidden(true)
    }

    private func draw(context: GraphicsContext, size: CGSize, date: Date) {
        let time = date.timeIntervalSinceReferenceDate
        let heights = petBarHeights(
            state: state,
            level: level,
            time: time,
            barCount: Self.barCount,
            minHeight: Self.barMinHeight,
            maxHeight: Self.barMaxHeight,
            reduceMotion: reduceMotion,
            enteredStateAt: stateEnteredAt
        )
        let pulse = petReduceMotionOpacity(state: state, time: time, reduceMotion: reduceMotion)
        // Ensure the bars are cyan during .listening as requested. We can just use cyanGlow.
        let isCyanState = (state == .listening || state == .attention || state == .speaking)
        let baseColor = isCyanState ? cyanGlow : petBarColor(for: state)
        let color = baseColor.opacity(pulse)
        for (index, height) in heights.enumerated() {
            let x = CGFloat(index) * (Self.barWidth + Self.barGap)
            let rect = CGRect(
                x: x,
                y: (size.height - height) / 2,
                width: Self.barWidth,
                height: height
            )
            context.fill(Path(roundedRect: rect, cornerRadius: Self.barWidth / 2), with: .color(color))
        }
    }

    // MARK: - Hover status lozenge (SF Mono per spec §7 copy voice)

    private var statusLozenge: some View {
        Text(statusText)
            .font(.speakMonoFace(.caption))
            .foregroundStyle(Color.speakBone)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous).fill(Color.speakInk2.opacity(0.92))
            )
            .fixedSize()
    }
}

// MARK: - Pure bar/color math (unit-tested independent of rendering)

/// Per-bar heights for one animation frame, driven by `state` + `level` + `time`.
/// Pure function — no Canvas/AppKit dependency — see `PetViewMathTests`.
///
/// - Parameter enteredStateAt: The `time` at which Voice Desktop Pet most recently entered
///   `state` (nil if unknown). Only consulted for `.listening`, to drive the
///   ~100ms anticipation dip on capture-start (animation-soul amendment,
///   2026-07-11) — the dip composes with spec §4's "ignites within 100ms"
///   budget; the dip IS the first 100ms, not additional latency.
func petBarHeights(
    state: PetState,
    level: Double,
    time: TimeInterval,
    barCount: Int,
    minHeight: CGFloat,
    maxHeight: CGFloat,
    reduceMotion: Bool,
    enteredStateAt: TimeInterval? = nil
) -> [CGFloat] {
    guard barCount > 0 else { return [] }
    let clampedLevel = min(max(level, 0.0), 1.0)
    let span = maxHeight - minHeight

    switch state {
    case .dormant:
        // Sleep: flat line + barely-visible 6s breath (animation-soul
        // amendment, 2026-07-11). [decision: 6s cycle, ≤5% amplitude — must
        // read as "asleep," not "idle."]
        let cycle: TimeInterval = 6.0
        let phase = reduceMotion ? 0 : (time.truncatingRemainder(dividingBy: cycle)) / cycle
        let wave = reduceMotion ? 0 : sin(phase * 2 * .pi)
        let amplitude = max(0, 0.02 + 0.03 * wave)
        return Array(repeating: minHeight + span * amplitude, count: barCount)

    case .idle:
        // Slow breath ripple, center-out (~4s). [decision FE-1: sin ripple
        // with a per-bar phase offset from the center bar, matching "center-out."]
        // Plus an irregular BLINK: all five bars dip in unison for ~120ms at
        // irregular 30–90s intervals (animation-soul amendment, 2026-07-11).
        // Reduce Motion: blink is skipped entirely — it is decoration, the
        // breath ripple already carries the "alive" signal.
        let cycle = SpeakMotion.idleBreathCycle
        let phase = reduceMotion ? 0 : (time.truncatingRemainder(dividingBy: cycle)) / cycle
        let center = Double(barCount - 1) / 2.0
        let blinking = !reduceMotion && isIdleBlinking(time: time)
        return (0..<barCount).map { i in
            let distanceFromCenter = abs(Double(i) - center) / max(center, 1)
            let wave = sin((phase - distanceFromCenter * 0.25) * 2 * .pi)
            var amplitude = reduceMotion ? 0.15 : (0.15 + 0.15 * wave)
            if blinking { amplitude *= 0.15 }  // unison dip, all bars together
            return minHeight + span * max(0, amplitude)
        }

    case .listening:
        // Live audio levels — every bar reflects the same smoothed level with
        // a slight per-bar jitter derived from time, so it reads as a live
        // waveform rather than a single flat block. [decision FE-1]
        //
        // Anticipation dip (animation-soul amendment, 2026-07-11): the first
        // 100ms after entering `.listening` dips below rest BEFORE the jump
        // to live levels — the dip composes with, not adds to, spec §4's
        // "ignites within 100ms" handshake. Skipped under Reduce Motion (a
        // plain crossfade replaces it, per the amendment).
        if !reduceMotion, let enteredAt = enteredStateAt {
            let elapsed = time - enteredAt
            let anticipationWindow: TimeInterval = 0.1  // 100ms
            if elapsed >= 0, elapsed < anticipationWindow {
                let dipPhase = elapsed / anticipationWindow  // 0...1
                let dipAmplitude = 0.05 * (1 - dipPhase)  // eases back up toward the jump
                return Array(repeating: minHeight + span * max(0, dipAmplitude), count: barCount)
            }
        }
        return (0..<barCount).map { i in
            let jitter = reduceMotion ? 0 : sin(time * 6 + Double(i) * 1.3) * 0.08
            let amplitude = max(0, min(1, clampedLevel + jitter))
            return minHeight + span * amplitude
        }

    case .processing:
        // Left→right metronome sweep. [decision FE-1: 1.2s per sweep]
        let sweepCycle: TimeInterval = 1.2
        let phase = (time.truncatingRemainder(dividingBy: sweepCycle)) / sweepCycle
        let sweepPos = phase * Double(barCount - 1)
        return (0..<barCount).map { i in
            let distance = abs(Double(i) - sweepPos)
            let amplitude = reduceMotion ? 0.4 : max(0, 1 - distance)
            return minHeight + span * amplitude
        }

    case .agentWorking:
        // Gentle alternating tick (outer bars). [decision FE-1]
        let cycle: TimeInterval = 1.0
        let phase = (time.truncatingRemainder(dividingBy: cycle)) / cycle
        let tick = phase < 0.5
        return (0..<barCount).map { i in
            let isOuter = i == 0 || i == barCount - 1
            let amplitude: Double
            if reduceMotion {
                amplitude = isOuter ? 0.4 : 0.2
            } else {
                amplitude = isOuter ? (tick ? 0.5 : 0.2) : 0.2
            }
            return minHeight + span * amplitude
        }

    case .attention:
        // Double-knock pulse every 6s. Rate-limited to ≥6s between knocks —
        // this is now a HARD RULE (animation-soul amendment, 2026-07-11), not
        // just a cadence choice: the 6s cycle below is the single source of
        // the rate limit (one knock-pair per cycle, never more often).
        let cycle: TimeInterval = 6.0
        let phase = time.truncatingRemainder(dividingBy: cycle)
        let knock1 = phase < 0.15
        let knock2 = phase > 0.25 && phase < 0.4
        let amplitude = reduceMotion ? 0.3 : ((knock1 || knock2) ? 0.9 : 0.3)
        return Array(repeating: minHeight + span * amplitude, count: barCount)

    case .speaking:
        // Levels mirror TTS output envelope — identical shape to `.listening`.
        return (0..<barCount).map { i in
            let jitter = reduceMotion ? 0 : sin(time * 5 + Double(i) * 1.1) * 0.08
            let amplitude = max(0, min(1, clampedLevel + jitter))
            return minHeight + span * amplitude
        }
    }
}

/// Bar color per state — the two-temperature rule (spec §2): human states use
/// `humanAmber`, agent states use `agentViolet`, at-rest states use neutral
/// `bone`/`mica` tones.
func petBarColor(for state: PetState) -> Color {
    switch state {
    case .dormant: return .speakMica.opacity(0.4)
    case .idle: return .speakBone.opacity(0.7)
    case .listening: return .speakHumanAmber
    case .processing: return .speakHumanAmber
    case .agentWorking: return .speakAgentViolet
    case .attention: return .speakAgentViolet
    case .speaking: return .speakAgentViolet
    }
}

/// Tally dot color — `nil` means hidden. Spec §5: onAir when mic open,
/// agentViolet when an agent is speaking/waiting, hidden otherwise.
///
/// INVARIANT (animation-soul amendment, 2026-07-11 — "tally dot is a
/// secondary action, must always corroborate the bars"): both this function
/// and `petBarColor(for:)` are pure functions of the SAME single `state`
/// value — there is no separate tally-dot state to fall out of sync. A
/// future change must preserve this: never introduce a second state input
/// for the dot.
func petTallyDotColor(for state: PetState) -> Color? {
    switch state {
    case .listening: return .speakOnAir
    case .speaking, .attention, .agentWorking: return .speakAgentViolet
    case .dormant, .idle, .processing: return nil
    }
}

// MARK: - Idle blink schedule (animation-soul amendment, 2026-07-11)

/// Whether `time` falls inside an idle blink window: all five bars dip in
/// unison for ~120ms at irregular 30–90s intervals. Deterministic-seeded
/// (not true randomness) so the schedule is unit-testable: one blink occurs
/// near the midpoint of each 60s cycle, jittered ±30s by a hash of the cycle
/// index — irregular in appearance, reproducible in tests.
///
/// [decision FE-1: 60s base cycle (midpoint of the specified 30–90s range);
///  120ms window (60ms half-width) matches the "~120ms" spec.]
func isIdleBlinking(time: TimeInterval) -> Bool {
    let baseCycle: TimeInterval = 60
    let blinkWindow: TimeInterval = 0.120
    let cycleIndex = (time / baseCycle).rounded(.down)
    let jitter = (petPseudoRandom(seed: cycleIndex) - 0.5) * baseCycle  // -30...+30
    let blinkTime = cycleIndex * baseCycle + baseCycle / 2 + jitter
    return abs(time - blinkTime) < blinkWindow / 2
}

/// A deterministic pseudo-random value in `[0, 1)` for a given `seed` — the
/// classic `sin`-hash trick. Not cryptographic; only needed to look irregular
/// while staying a pure, reproducible function of `seed` for tests.
func petPseudoRandom(seed: Double) -> Double {
    let x = sin(seed * 12.9898) * 43758.5453
    return x - x.rounded(.down)
}

// MARK: - Reduce Motion opacity pulse (review fix, 2026-07-11 — spec §4)

/// Opacity multiplier for the bars under Reduce Motion: the idle/dormant
/// "breath" becomes a slow opacity pulse (heights stay static). Returns 1.0
/// (no modulation) when motion is not reduced or the state has no breath.
///
/// Pulse range 0.55↔0.70 — subtle, per the review's locked direction; cycle
/// matches the state's breath cadence (idle ~4s, dormant 6s). Pure function,
/// unit-tested in `PetViewMathTests`.
func petReduceMotionOpacity(state: PetState, time: TimeInterval, reduceMotion: Bool) -> Double {
    guard reduceMotion else { return 1.0 }
    let cycle: TimeInterval
    switch state {
    case .idle:
        cycle = SpeakMotion.idleBreathCycle           // ~4s (spec §4)
    case .dormant:
        cycle = 6.0                                    // sleep-breath cadence
    case .listening, .processing, .agentWorking, .attention, .speaking:
        return 1.0
    }
    let phase = (time.truncatingRemainder(dividingBy: cycle)) / cycle
    let wave = (sin(phase * 2 * .pi) + 1) / 2          // 0…1
    return min(0.70, max(0.55, 0.55 + 0.15 * wave))    // clamp: 0.55 + 0.15·1.0 can exceed 0.70 by one ulp
}
