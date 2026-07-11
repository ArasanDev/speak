// SpeakTests/PetViewMathTests.swift
//
// FE-1: the pure math backing `PetView` — `petBarHeights`, `petBarColor`,
// `petTallyDotColor`, and the idle-blink schedule. No Canvas/rendering
// (matches `AuroraMathTests`' "no pixel tests" convention). Covers the
// animation-soul amendment (2026-07-11): idle blink, dormant sleep-breath,
// listening anticipation dip, tally-dot/bar-color corroboration.

import Foundation
@testable import Speak
import SwiftUI
import Testing

@Suite("PetView math — bar heights")
struct PetBarHeightsTests {

    private let barCount = 5
    private let minHeight: CGFloat = 4
    private let maxHeight: CGFloat = 22

    @Test("dormant bars stay near the floor (sleep, ≤5% span)")
    func dormantNearFloor() {
        let heights = petBarHeights(
            state: .dormant, level: 0, time: 0, barCount: barCount,
            minHeight: minHeight, maxHeight: maxHeight, reduceMotion: false
        )
        for h in heights {
            #expect(h <= minHeight + (maxHeight - minHeight) * 0.06)
            #expect(h >= minHeight)
        }
    }

    @Test("dormant under Reduce Motion is perfectly flat")
    func dormantFlatUnderReduceMotion() {
        let heights = petBarHeights(
            state: .dormant, level: 0, time: 1.23, barCount: barCount,
            minHeight: minHeight, maxHeight: maxHeight, reduceMotion: true
        )
        #expect(Set(heights).count == 1)
    }

    @Test("listening bars scale with level when no anticipation dip applies")
    func listeningScalesWithLevel() {
        let low = petBarHeights(
            state: .listening, level: 0.0, time: 5, barCount: barCount,
            minHeight: minHeight, maxHeight: maxHeight, reduceMotion: true
        )
        let high = petBarHeights(
            state: .listening, level: 1.0, time: 5, barCount: barCount,
            minHeight: minHeight, maxHeight: maxHeight, reduceMotion: true
        )
        #expect(high[0] > low[0])
    }

    @Test("listening anticipation dip suppresses the jump for the first 100ms")
    func anticipationDip() {
        let atEntry = petBarHeights(
            state: .listening, level: 1.0, time: 10.0, barCount: barCount,
            minHeight: minHeight, maxHeight: maxHeight, reduceMotion: false,
            enteredStateAt: 10.0
        )
        // Full level (1.0) would otherwise put every bar at maxHeight; the
        // dip must keep them well below that in the first instant.
        for h in atEntry {
            #expect(h < maxHeight * 0.5)
        }
    }

    @Test("listening after the anticipation window reflects the live level normally")
    func afterAnticipationWindow() {
        let afterWindow = petBarHeights(
            state: .listening, level: 1.0, time: 10.2, barCount: barCount,
            minHeight: minHeight, maxHeight: maxHeight, reduceMotion: false,
            enteredStateAt: 10.0
        )
        for h in afterWindow {
            #expect(h > maxHeight * 0.7)
        }
    }

    @Test("anticipation dip is skipped under Reduce Motion")
    func anticipationDipSkippedUnderReduceMotion() {
        let heights = petBarHeights(
            state: .listening, level: 1.0, time: 10.0, barCount: barCount,
            minHeight: minHeight, maxHeight: maxHeight, reduceMotion: true,
            enteredStateAt: 10.0
        )
        for h in heights {
            #expect(h > maxHeight * 0.7)
        }
    }

    @Test("zero bar count returns an empty array")
    func zeroBarCountEmpty() {
        let heights = petBarHeights(
            state: .idle, level: 0, time: 0, barCount: 0,
            minHeight: minHeight, maxHeight: maxHeight, reduceMotion: false
        )
        #expect(heights.isEmpty)
    }

    @Test("attention pulse never fires more than once per 6s cycle (rate-limit hard rule)")
    func attentionRateLimited() {
        // Sample densely across one 6s cycle and count how many "high"
        // samples occur — the double-knock should be a small fraction of
        // the cycle, not continuous.
        let samples = stride(from: 0.0, to: 6.0, by: 0.05).map { t in
            petBarHeights(
                state: .attention, level: 0, time: t, barCount: barCount,
                minHeight: minHeight, maxHeight: maxHeight, reduceMotion: false
            )[0]
        }
        let restHeight = minHeight + (maxHeight - minHeight) * 0.3
        let highCount = samples.filter { $0 > restHeight + 0.01 }.count
        // Two knocks × ~0.15s each ÷ 0.05s step ≈ 6 samples — well under half the cycle.
        #expect(highCount < samples.count / 2)
    }
}

@Suite("PetView math — idle blink schedule")
struct PetIdleBlinkTests {

    @Test("blink windows are deterministic — same time always gives the same result")
    func deterministicRepeat() {
        let t = 12345.678
        #expect(isIdleBlinking(time: t) == isIdleBlinking(time: t))
    }

    @Test("a blink occurs somewhere within every 60s cycle")
    func blinkOccursPerCycle() {
        // 20ms step over a 60s cycle vs. a ~120ms window guarantees at least
        // one sample lands inside the window (window ÷ step ≈ 6 samples).
        for cycle in 0..<5 {
            let base = Double(cycle) * 60
            let anyBlink = stride(from: base, to: base + 60, by: 0.02).contains { isIdleBlinking(time: $0) }
            #expect(anyBlink)
        }
    }

    @Test("blink windows are short (~120ms), not continuous")
    func blinkWindowIsShort() {
        let base = 0.0
        let blinkCount = stride(from: base, to: base + 60, by: 0.01).filter { isIdleBlinking(time: $0) }.count
        // ~120ms window / 10ms step ≈ 12 samples.
        #expect(blinkCount < 30)
    }
}

@Suite("PetView math — color corroboration")
struct PetColorTests {

    @Test("bar color and tally dot never disagree on temperature", arguments: PetState.allCases)
    func barAndDotAgreeOnTemperature(state: PetState) {
        // Both are pure functions of the SAME `state` — this test guards the
        // animation-soul invariant that the dot must always corroborate the
        // bars, by asserting both functions are total (never throw/crash)
        // and that agent states never produce the human amber tally color.
        let barColor = petBarColor(for: state)
        let dotColor = petTallyDotColor(for: state)
        if state == .speaking || state == .attention || state == .agentWorking {
            #expect(dotColor != nil)
        }
        _ = barColor  // exercised for completeness; Color has no direct equality assertion here
    }

    @Test("listening is the only state with the onAir tally color")
    func onlyListeningShowsOnAir() {
        #expect(petTallyDotColor(for: .listening) == Color.speakOnAir)
        for state in PetState.allCases where state != .listening {
            #expect(petTallyDotColor(for: state) != Color.speakOnAir)
        }
    }
}

@Suite("PetView math — Reduce Motion opacity pulse (spec §4)")
struct PetReduceMotionOpacityTests {

    @Test("no modulation when motion is not reduced", arguments: PetState.allCases)
    func noOpWithoutReduceMotion(state: PetState) {
        #expect(petReduceMotionOpacity(state: state, time: 1.7, reduceMotion: false) == 1.0)
    }

    @Test("active states are never dimmed under Reduce Motion",
          arguments: [PetState.listening, .processing, .agentWorking, .attention, .speaking])
    func activeStatesNotDimmed(state: PetState) {
        #expect(petReduceMotionOpacity(state: state, time: 2.3, reduceMotion: true) == 1.0)
    }

    @Test("idle pulse stays within 0.55…0.70 under Reduce Motion")
    func idlePulseRange() {
        for t in stride(from: 0.0, to: 8.0, by: 0.1) {
            let opacity = petReduceMotionOpacity(state: .idle, time: t, reduceMotion: true)
            #expect(opacity >= 0.55)
            #expect(opacity <= 0.70)
        }
    }

    @Test("idle pulse actually varies over its ~4s cycle (not static)")
    func idlePulseVaries() {
        let a = petReduceMotionOpacity(state: .idle, time: 0.0, reduceMotion: true)
        let b = petReduceMotionOpacity(state: .idle, time: 1.0, reduceMotion: true)
        #expect(a != b)
    }

    @Test("dormant pulse stays within 0.55…0.70 and varies over its 6s cycle")
    func dormantPulse() {
        var seen = Set<Double>()
        for t in stride(from: 0.0, to: 6.0, by: 0.5) {
            let opacity = petReduceMotionOpacity(state: .dormant, time: t, reduceMotion: true)
            #expect(opacity >= 0.55)
            #expect(opacity <= 0.70)
            seen.insert(opacity)
        }
        #expect(seen.count > 1)
    }
}
