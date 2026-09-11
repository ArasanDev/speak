// SpeakTests/VUSegmentFillTests.swift
//
// Unit tests for `levelSegmentFill` — the LevelMath helper mapping a
// perceptual level to a lit-segment count for the Settings mic-check VU meter
// (`VUMeterView`). Synchronous and deterministic; no audio hardware required.

@testable import SpeakCore
import XCTest

final class VUSegmentFillTests: XCTestCase {

    // Zero level lights nothing.
    func testZeroLevelLightsNothing() {
        XCTAssertEqual(levelSegmentFill(level: 0, segmentCount: 20), 0)
    }

    // Full level lights every segment.
    func testFullLevelLightsAll() {
        XCTAssertEqual(levelSegmentFill(level: 1.0, segmentCount: 20), 20)
    }

    // Half level rounds to half the segments.
    func testHalfLevelLightsHalf() {
        XCTAssertEqual(levelSegmentFill(level: 0.5, segmentCount: 20), 10)
    }

    // Out-of-range levels are clamped rather than overflowing the meter.
    func testOutOfRangeClamped() {
        XCTAssertEqual(levelSegmentFill(level: 2.0, segmentCount: 20), 20)
        XCTAssertEqual(levelSegmentFill(level: -1.0, segmentCount: 20), 0)
    }

    // Zero-segment meter lights nothing rather than dividing by zero.
    func testZeroSegmentsLightsNothing() {
        XCTAssertEqual(levelSegmentFill(level: 1.0, segmentCount: 0), 0)
    }

    // Lit count is monotonically non-decreasing in level.
    func testMonotonicInLevel() {
        var last = 0
        for i in 0 ... 100 {
            let lit = levelSegmentFill(level: Double(i) / 100.0, segmentCount: 20)
            XCTAssertGreaterThanOrEqual(lit, last)
            last = lit
        }
        XCTAssertEqual(last, 20)
    }
}
