// SpeakTests/AuroraMathTests.swift
//
// Unit tests for the pure math beneath the Aurora HUD (H-UI):
// `cyclicPhase`, `orbRadius`, and `wordWindow`. These are value-type/logic
// tests only — no Canvas, no NSHostingView, no pixels (matching the
// "no pixel tests" constraint on H-UI).

import Foundation
@testable import SpeakCore
import Testing

@Suite("AuroraMath — cyclicPhase")
struct CyclicPhaseTests {

    @Test("phase 0 at time 0")
    func phaseZeroAtTimeZero() {
        #expect(cyclicPhase(time: 0, cycleDuration: 2.0) == 0.0)
    }

    @Test("phase 0.5 at half the cycle")
    func phaseHalfway() {
        #expect(cyclicPhase(time: 1.0, cycleDuration: 2.0) == 0.5)
    }

    @Test("phase wraps back to ~0 at exactly one full cycle")
    func phaseWrapsAtFullCycle() {
        let phase = cyclicPhase(time: 2.0, cycleDuration: 2.0)
        #expect(phase == 0.0)
    }

    @Test("phase is always within [0, 1) for arbitrary positive times", arguments: [0.0, 0.3, 1.0, 3.7, 100.25])
    func phaseStaysInRange(time: Double) {
        let phase = cyclicPhase(time: time, cycleDuration: 1.6)
        #expect(phase >= 0.0 && phase < 1.0)
    }

    @Test("non-positive cycleDuration returns 0 defensively")
    func nonPositiveCycleDurationReturnsZero() {
        #expect(cyclicPhase(time: 5.0, cycleDuration: 0.0) == 0.0)
        #expect(cyclicPhase(time: 5.0, cycleDuration: -1.0) == 0.0)
    }
}

@Suite("AuroraMath — orbRadius")
struct OrbRadiusTests {

    static let geometry = OrbGeometry(baseRadius: 12.0, breatheAmplitude: 3.0, levelBoost: 8.0)

    @Test("at level 0, phase 0, radius is exactly baseRadius (sin(0) == 0)")
    func restingRadiusEqualsBase() {
        let radius = orbRadius(
            geometry: Self.geometry, level: 0.0, breathePhase: 0.0, reduceMotion: false
        )
        #expect(radius == 12.0)
    }

    @Test("level 1.0 adds the full levelBoost on top of the breathing term")
    func fullLevelAddsFullBoost() {
        let radius = orbRadius(
            geometry: Self.geometry, level: 1.0, breathePhase: 0.0, reduceMotion: false
        )
        // phase 0 → sin(0) == 0, so radius == base + level*boost
        #expect(radius == 20.0)
    }

    @Test("level is clamped above 1.0")
    func levelClampedAboveOne() {
        let radius = orbRadius(
            geometry: Self.geometry, level: 5.0, breathePhase: 0.0, reduceMotion: false
        )
        #expect(radius == 20.0)
    }

    @Test("level is clamped below 0.0")
    func levelClampedBelowZero() {
        let radius = orbRadius(
            geometry: Self.geometry, level: -5.0, breathePhase: 0.0, reduceMotion: false
        )
        #expect(radius == 12.0)
    }

    @Test("reduceMotion suppresses the breathing term entirely")
    func reduceMotionSuppressesBreathing() {
        // phase 0.25 → sin(0.25 * 2π) == sin(π/2) == 1.0 → would add full amplitude
        let withMotion = orbRadius(
            geometry: Self.geometry, level: 0.0, breathePhase: 0.25, reduceMotion: false
        )
        let reduced = orbRadius(
            geometry: Self.geometry, level: 0.0, breathePhase: 0.25, reduceMotion: true
        )
        #expect(withMotion == 15.0)
        #expect(reduced == 12.0)
    }

    @Test("reduceMotion does NOT suppress the level boost — level is information, not decoration")
    func reduceMotionKeepsLevelBoost() {
        let reduced = orbRadius(
            geometry: Self.geometry, level: 1.0, breathePhase: 0.25, reduceMotion: true
        )
        #expect(reduced == 20.0)
    }
}

@Suite("AuroraMath — wordWindow")
struct WordWindowTests {

    @Test("empty text returns an empty window")
    func emptyTextReturnsEmpty() {
        #expect(wordWindow(fullText: "", maxWords: 6).isEmpty)
    }

    @Test("whitespace-only text returns an empty window")
    func whitespaceOnlyReturnsEmpty() {
        #expect(wordWindow(fullText: "   \n\t ", maxWords: 6).isEmpty)
    }

    @Test("fewer words than maxWords returns all of them with sequential ids from 0")
    func fewerWordsThanWindowReturnsAll() {
        let tokens = wordWindow(fullText: "hello world", maxWords: 6)
        #expect(tokens.map(\.word) == ["hello", "world"])
        #expect(tokens.map(\.id) == [0, 1])
    }

    @Test("more words than maxWords returns only the trailing window")
    func moreWordsThanWindowReturnsTrailingSlice() {
        let tokens = wordWindow(fullText: "one two three four five six seven eight", maxWords: 3)
        #expect(tokens.map(\.word) == ["six", "seven", "eight"])
    }

    @Test("ids are absolute positions in the full transcript, not window-relative")
    func idsAreAbsolutePositions() {
        let tokens = wordWindow(fullText: "one two three four five six seven eight", maxWords: 3)
        #expect(tokens.map(\.id) == [5, 6, 7])
    }

    @Test("maxWords of 0 or negative returns an empty window")
    func nonPositiveMaxWordsReturnsEmpty() {
        #expect(wordWindow(fullText: "hello world", maxWords: 0).isEmpty)
        #expect(wordWindow(fullText: "hello world", maxWords: -1).isEmpty)
    }

    @Test("multiple whitespace runs (including newlines) are collapsed between words")
    func multipleWhitespaceRunsCollapsed() {
        let tokens = wordWindow(fullText: "hello   world\nfoo", maxWords: 6)
        #expect(tokens.map(\.word) == ["hello", "world", "foo"])
    }

    @Test("word window stays stable as the transcript grows — appending one word shifts ids by one")
    func stableIdsAsTranscriptGrows() {
        let before = wordWindow(fullText: "the quick brown fox", maxWords: 3)
        let after = wordWindow(fullText: "the quick brown fox jumps", maxWords: 3)
        // Oldest word visible before ("brown", id 2) should have scrolled out;
        // the two carried-over words ("brown" id2->fox id3 shift) — verify the
        // newest word gets the next sequential id, not a reused one.
        #expect(before.map(\.id) == [1, 2, 3])
        #expect(after.map(\.id) == [2, 3, 4])
        #expect(after.last?.word == "jumps")
    }
}
