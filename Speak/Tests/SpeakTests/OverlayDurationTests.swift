// SpeakTests/OverlayDurationTests.swift
//
// Wave D — unit test for the HUD duration formatter. The live counter + overlay render
// are [deferred — human verification], but the m:ss formatting is pure and testable.

@testable import Speak
import XCTest

final class OverlayDurationTests: XCTestCase {

    func testDurationLabel_formatsMinutesAndSeconds() {
        XCTAssertEqual(TranscriptOverlayView.durationLabel(0), "0:00")
        XCTAssertEqual(TranscriptOverlayView.durationLabel(5), "0:05")
        XCTAssertEqual(TranscriptOverlayView.durationLabel(59), "0:59")
        XCTAssertEqual(TranscriptOverlayView.durationLabel(60), "1:00")
        XCTAssertEqual(TranscriptOverlayView.durationLabel(83), "1:23")
        XCTAssertEqual(TranscriptOverlayView.durationLabel(600), "10:00")
    }

    func testDurationLabel_clampsNegative() {
        XCTAssertEqual(TranscriptOverlayView.durationLabel(-5), "0:00")
    }
}
