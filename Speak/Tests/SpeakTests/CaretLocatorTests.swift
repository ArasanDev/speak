// SpeakTests/CaretLocatorTests.swift
//
// Tests for CaretLocator (roadmap P2.1).
//
// SCOPE:
//   1. Invalid / edge-case PIDs return nil without crashing.
//   2. Self-PID query (no focused AX text element in this test process) does
//      not crash and returns nil or a valid-looking CGPoint.
//   3. AXValue extraction helpers (rect, point, cfRange) — round-trip via
//      AXValueCreate → helper → verify recovered value.
//   4. Helpers return nil gracefully when passed a non-AXValue object.
//
// NOT tested here (requires live OS + focused text editor):
//   - Actual caret position in Notes, TextEdit, Xcode.
//   - Web app / Electron / terminal returns nil (graceful degradation).
//   - Returned coordinates are in Quartz screen space (P2.2 integration test).

import ApplicationServices
@testable import SpeakCore
import XCTest

// MARK: - Invalid PID guard

final class CaretLocatorPIDTests: XCTestCase {

    func testZeroPidReturnsNil() {
        XCTAssertNil(CaretLocator.caretScreenPosition(pid: 0))
    }

    func testNegativePidReturnsNil() {
        XCTAssertNil(CaretLocator.caretScreenPosition(pid: -1))
    }

    func testSelfPidDoesNotCrash() {
        // The test process has no focused AX text element; nil is expected.
        // Contract: no crash regardless of return value.
        let result = CaretLocator.caretScreenPosition(pid: getpid())
        if let point = result {
            XCTAssertFalse(point.x.isNaN, "x must not be NaN")
            XCTAssertFalse(point.y.isNaN, "y must not be NaN")
        }
        // Reaching here (no crash) is the primary assertion.
    }
}

// MARK: - AXValue extraction helpers

final class CaretLocatorAXValueTests: XCTestCase {

    func testRectHelperRoundTrip() {
        let original = CGRect(x: 100.0, y: 200.0, width: 50.0, height: 18.0)
        var mutable = original
        guard let axValue = AXValueCreate(.cgRect, &mutable) else {
            XCTFail("AXValueCreate(.cgRect) unexpectedly returned nil")
            return
        }
        let recovered = CaretLocator.rect(from: axValue)
        XCTAssertNotNil(recovered)
        XCTAssertEqual(recovered?.origin.x ?? -1, original.origin.x, accuracy: 0.001)
        XCTAssertEqual(recovered?.origin.y ?? -1, original.origin.y, accuracy: 0.001)
        XCTAssertEqual(recovered?.size.width ?? -1, original.size.width, accuracy: 0.001)
        XCTAssertEqual(recovered?.size.height ?? -1, original.size.height, accuracy: 0.001)
    }

    func testPointHelperRoundTrip() {
        let original = CGPoint(x: 42.5, y: 99.0)
        var mutable = original
        guard let axValue = AXValueCreate(.cgPoint, &mutable) else {
            XCTFail("AXValueCreate(.cgPoint) unexpectedly returned nil")
            return
        }
        let recovered = CaretLocator.point(from: axValue)
        XCTAssertNotNil(recovered)
        XCTAssertEqual(recovered?.x ?? -1, original.x, accuracy: 0.001)
        XCTAssertEqual(recovered?.y ?? -1, original.y, accuracy: 0.001)
    }

    func testCFRangeHelperRoundTrip() {
        let original = CFRange(location: 42, length: 7)
        var mutable = original
        guard let axValue = AXValueCreate(.cfRange, &mutable) else {
            XCTFail("AXValueCreate(.cfRange) unexpectedly returned nil")
            return
        }
        let recovered = CaretLocator.cfRange(from: axValue)
        XCTAssertNotNil(recovered)
        XCTAssertEqual(recovered?.location, original.location)
        XCTAssertEqual(recovered?.length, original.length)
    }

    func testRectHelperWithNonAXValueReturnsNil() {
        let notAXValue = "not an AXValue" as AnyObject
        XCTAssertNil(CaretLocator.rect(from: notAXValue))
    }

    func testPointHelperWithNonAXValueReturnsNil() {
        let notAXValue = 42 as AnyObject
        XCTAssertNil(CaretLocator.point(from: notAXValue))
    }

    func testCFRangeHelperWithNonAXValueReturnsNil() {
        let notAXValue = NSArray()
        XCTAssertNil(CaretLocator.cfRange(from: notAXValue))
    }

    func testRectHelperWithWrongAXValueTypeReturnsNil() {
        // Pack a CGPoint but ask for CGRect — type mismatch should return nil.
        var point = CGPoint(x: 1, y: 2)
        guard let axValue = AXValueCreate(.cgPoint, &point) else {
            XCTFail("AXValueCreate(.cgPoint) unexpectedly returned nil")
            return
        }
        XCTAssertNil(CaretLocator.rect(from: axValue))
    }
}
