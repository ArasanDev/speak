// SpeakTests/CommandChordDetectorTests.swift
//
// Wave D — unit tests for the pure Fn+Ctrl Command Mode chord detector. The live tap
// that feeds it is [deferred — human verification]; the edge logic is pure + tested here.

import XCTest
@testable import SpeakCore

final class CommandChordDetectorTests: XCTestCase {

    func testBeginOnBothDown() {
        var d = CommandChordDetector()
        XCTAssertNil(d.update(isFnDown: true, isCtrlDown: false), "Fn alone is not the chord.")
        XCTAssertEqual(d.update(isFnDown: true, isCtrlDown: true), .begin)
        XCTAssertTrue(d.isActive)
    }

    func testEndWhenEitherReleased() {
        var d = CommandChordDetector()
        _ = d.update(isFnDown: true, isCtrlDown: true)   // begin
        XCTAssertEqual(d.update(isFnDown: true, isCtrlDown: false), .end, "Releasing Ctrl ends the chord.")
        XCTAssertFalse(d.isActive)
    }

    func testEndWhenFnReleased() {
        var d = CommandChordDetector()
        _ = d.update(isFnDown: true, isCtrlDown: true)
        XCTAssertEqual(d.update(isFnDown: false, isCtrlDown: true), .end, "Releasing Fn ends the chord.")
    }

    func testNoDuplicateBeginWhileHeld() {
        var d = CommandChordDetector()
        XCTAssertEqual(d.update(isFnDown: true, isCtrlDown: true), .begin)
        XCTAssertNil(d.update(isFnDown: true, isCtrlDown: true), "Holding must not re-fire begin.")
    }

    func testNoEventWhenIdle() {
        var d = CommandChordDetector()
        XCTAssertNil(d.update(isFnDown: false, isCtrlDown: false))
        XCTAssertNil(d.update(isFnDown: false, isCtrlDown: true))
    }

    func testResetClearsActive() {
        var d = CommandChordDetector()
        _ = d.update(isFnDown: true, isCtrlDown: true)
        d.reset()
        XCTAssertFalse(d.isActive)
        // After reset, both-down fires begin again.
        XCTAssertEqual(d.update(isFnDown: true, isCtrlDown: true), .begin)
    }
}
