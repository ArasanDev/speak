// SpeakTests/OverlayLevelTests.swift
//
// Unit tests for `LevelMath` — the pure level-conversion utilities in
// `SpeakCore/Overlay/LevelMath.swift`. All tests are synchronous and
// deterministic; no AppKit, no SwiftUI, no audio hardware required.
//
// Coverage:
//   1.  levelLinear(fromDB:)          — 0 dB → 1.0 (full scale)
//   2.  levelLinear(fromDB:)          — −∞ / −160 dB → ≈ 0.0
//   3.  levelLinear(fromDB:)          — above 0 dB clamped to 1.0
//   4.  levelLinear(fromDB:)          — known mid value (−20 dB → 0.1)
//   5.  levelSmoothed(previous:target:) — stationary (prev = target) is identity
//   6.  levelSmoothed(previous:target:) — 0 → 1 converges toward 1 over iterations
//   7.  levelSmoothed(previous:target:) — explicit math (0.7/0.3 split)
//   8.  levelBarHeights(level:)       — zero level → all bars at minHeight
//   9.  levelBarHeights(level:)       — full level → center bar at maxHeight
//   10. levelBarHeights(level:)       — returns exactly barCount elements
//   11. levelBarHeights(level:)       — barCount=0 returns empty
//   12. levelBarHeights(level:)       — all bars within [minHeight, maxHeight]
//   13. levelBarHeights(level:)       — waveform is symmetric (center-peaked)

import XCTest
@testable import SpeakCore

final class OverlayLevelTests: XCTestCase {

    // MARK: - levelLinear(fromDB:)

    // 1. 0 dB → 1.0 (full scale, power → amplitude)
    func testLevelLinearZeroDBIsFullScale() {
        XCTAssertEqual(levelLinear(fromDB: 0.0), 1.0, accuracy: 1e-9)
    }

    // 2. −160 dB → effectively 0 (silence floor clamped)
    func testLevelLinearSilenceFloor() {
        let result = levelLinear(fromDB: -160.0)
        XCTAssertLessThan(result, 1e-7, "−160 dB should be effectively 0")
        XCTAssertGreaterThanOrEqual(result, 0.0, "Must not go negative")
    }

    // 3. Values above 0 dB are clamped to 1.0
    func testLevelLinearAboveZeroDBClampedToOne() {
        XCTAssertEqual(levelLinear(fromDB: 6.0), 1.0, accuracy: 1e-9)
        XCTAssertEqual(levelLinear(fromDB: 100.0), 1.0, accuracy: 1e-9)
    }

    // 4. −20 dB → 0.1 (known reference: pow(10, −20/20) = pow(10, −1) = 0.1)
    func testLevelLinearMinus20DB() {
        let result = levelLinear(fromDB: -20.0)
        XCTAssertEqual(result, 0.1, accuracy: 1e-9)
    }

    // MARK: - levelSmoothed(previous:target:)

    // 5. Stationary: prev == target → output == target (fixed point)
    func testLevelSmoothedStationaryIsIdentity() {
        for value in [0.0, 0.5, 1.0] {
            let result = levelSmoothed(previous: value, target: value)
            XCTAssertEqual(result, value, accuracy: 1e-12,
                "levelSmoothed should be a fixed point when prev == target")
        }
    }

    // 6. Converging: repeated smoothing of 0→1 reaches the target asymptotically
    func testLevelSmoothedConvergesOver10Frames() {
        var prev = 0.0
        for _ in 0 ..< 30 {
            prev = levelSmoothed(previous: prev, target: 1.0)
        }
        XCTAssertGreaterThan(prev, 0.99, "After 30 frames, smoothed value should be close to 1.0")
    }

    // 7. Explicit math: prev=0.8, target=0.2 → 0.8*0.7 + 0.2*0.3 = 0.56 + 0.06 = 0.62
    func testLevelSmoothedExplicitMath() {
        let result = levelSmoothed(previous: 0.8, target: 0.2)
        XCTAssertEqual(result, 0.62, accuracy: 1e-10)
    }

    // MARK: - levelBarHeights(level:barCount:minHeight:maxHeight:)

    // 8. Level=0 → all bars at minHeight
    func testBarHeightsZeroLevelAllMin() {
        let heights = levelBarHeights(level: 0.0, barCount: 5, minHeight: 3.0, maxHeight: 20.0)
        for h in heights {
            XCTAssertEqual(h, 3.0, accuracy: 1e-9,
                "At level=0 every bar should be at minHeight")
        }
    }

    // 9. Level=1 → center bar at maxHeight
    func testBarHeightsFullLevelCenterIsMax() {
        let barCount = 5
        let heights = levelBarHeights(level: 1.0, barCount: barCount, minHeight: 3.0, maxHeight: 20.0)
        let centerIndex = barCount / 2   // index 2 for 5 bars
        XCTAssertEqual(heights[centerIndex], 20.0, accuracy: 1e-9,
            "At level=1 the center bar should be at maxHeight")
    }

    // 10. Returns exactly barCount elements
    func testBarHeightsReturnCountMatchesBarCount() {
        for n in [1, 3, 5, 7] {
            let heights = levelBarHeights(level: 0.5, barCount: n)
            XCTAssertEqual(heights.count, n, "Expected \(n) bars, got \(heights.count)")
        }
    }

    // 11. barCount=0 → empty array
    func testBarHeightsZeroBarCountIsEmpty() {
        let heights = levelBarHeights(level: 0.5, barCount: 0)
        XCTAssertTrue(heights.isEmpty, "barCount=0 must return an empty array")
    }

    // 12. All bar heights are within [minHeight, maxHeight]
    func testBarHeightsAllWithinBounds() {
        for level in [0.0, 0.25, 0.5, 0.75, 1.0] {
            let heights = levelBarHeights(level: level, barCount: 5, minHeight: 3.0, maxHeight: 20.0)
            for h in heights {
                XCTAssertGreaterThanOrEqual(h, 3.0, "Bar below minHeight at level=\(level)")
                XCTAssertLessThanOrEqual(h, 20.0, "Bar above maxHeight at level=\(level)")
            }
        }
    }

    // 13. Waveform is symmetric: bar[i] == bar[n-1-i] for all i (cosine envelope)
    func testBarHeightsSymmetric() {
        let heights = levelBarHeights(level: 0.7, barCount: 5, minHeight: 3.0, maxHeight: 20.0)
        for i in 0 ..< heights.count / 2 {
            let mirror = heights.count - 1 - i
            XCTAssertEqual(heights[i], heights[mirror], accuracy: 1e-9,
                "Bar \(i) and bar \(mirror) should be equal (symmetric envelope)")
        }
    }
}
