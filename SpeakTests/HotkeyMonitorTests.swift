// SpeakTests/HotkeyMonitorTests.swift
//
// Tests for HotkeyMonitor seam (roadmap P5 done-when, architecture.md §6).
//
// SCOPE (read before changing):
//   These tests cover everything that can be verified autonomously:
//     1. HotkeyBinding Codable round-trip (encode → decode preserves all fields)
//     2. DoubleTapDetector pure logic — no CGEventTap, no clock, timestamps injected
//        a. Two taps within window → .startCapture
//        b. Two taps outside window → no event (only lastTapTime updated)
//        c. .startCapture then single tap → .stopCapture
//        d. Single slow tap → no event
//        e. reset() clears state
//     3. UserDefaultsBindingStore save/load round-trip
//
// NOT tested here (deferred — needs human verification with live OS):
//   - CGEventTap fires while another app has focus
//   - Fn keypress is detected via flagsChanged + maskSecondaryFn
//   - Accessibility + Input Monitoring permission prompts on first run
//   - False-trigger rate < 1/30 min in Notes (benchmark.md §7 F_rate, P13)
//
// The Fn-event model (flagsChanged + maskSecondaryFn) is reasoned in
// HotkeyMonitor.swift [inferred]; runtime confirmation is deferred to P5
// human verification. Green tests here prove the pure detector logic only.

import XCTest
@testable import SpeakCore

// MARK: - HotkeyBinding Codable Tests

final class HotkeyBindingCodableTests: XCTestCase {

    func testRoundTripDefaultBinding() throws {
        let original = HotkeyBinding.defaultBinding
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(HotkeyBinding.self, from: data)

        XCTAssertEqual(decoded.keyCode, original.keyCode)
        XCTAssertEqual(decoded.modifiers.rawValue, original.modifiers.rawValue)
        XCTAssertEqual(decoded.trigger, original.trigger)
        XCTAssertEqual(decoded.doubleTapWindow, original.doubleTapWindow, accuracy: 1e-9)
    }

    func testRoundTripWithModifiers() throws {
        // Uses .hold trigger (Phase B) — .singleTapToggle was removed in Phase B
        // as it was never implemented. [decision: specs/dictation-flow.md §6-B]
        let binding = HotkeyBinding(
            keyCode: 0x09, // kVK_ANSI_V
            modifiers: [.maskCommand, .maskShift],
            trigger: .hold,
            doubleTapWindow: 0.3
        )
        let data = try JSONEncoder().encode(binding)
        let decoded = try JSONDecoder().decode(HotkeyBinding.self, from: data)

        XCTAssertEqual(decoded.keyCode, 0x09)
        XCTAssertEqual(decoded.modifiers.rawValue, CGEventFlags([.maskCommand, .maskShift]).rawValue)
        XCTAssertEqual(decoded.trigger, .hold)
        XCTAssertEqual(decoded.doubleTapWindow, 0.3, accuracy: 1e-9)
    }

    func testHoldTriggerRoundTrip() throws {
        let binding = HotkeyBinding(
            keyCode: 63,
            modifiers: [],
            trigger: .hold,
            doubleTapWindow: 0.4
        )
        let data = try JSONEncoder().encode(binding)
        let decoded = try JSONDecoder().decode(HotkeyBinding.self, from: data)

        XCTAssertEqual(decoded.trigger, .hold)
    }

    func testDoubleTapTriggerRoundTrip() throws {
        let binding = HotkeyBinding.defaultBinding
        let data = try JSONEncoder().encode(binding)
        let decoded = try JSONDecoder().decode(HotkeyBinding.self, from: data)

        XCTAssertEqual(decoded.trigger, .doubleTap)
    }

    func testStalePersistedTriggerDecodesNilAndFallsBack() throws {
        // A JSON payload that has an unknown trigger value (e.g., the removed
        // "singleTapToggle") should fail to decode via try? in the store,
        // and the store returns nil → caller falls back to defaultBinding.
        let staleJSONString = """
        {"keyCode":63,"modifiersRawValue":0,"trigger":"singleTapToggle","doubleTapWindow":0.4}
        """
        let staleJSON = try XCTUnwrap(Data(staleJSONString.utf8))
        let decoded = try? JSONDecoder().decode(HotkeyBinding.self, from: staleJSON)
        XCTAssertNil(decoded, "An unknown trigger case must fail to decode — store returns nil → default binding used.")
    }

    func testRoundTripEmptyModifiers() throws {
        let binding = HotkeyBinding(
            keyCode: 63,
            modifiers: [],
            trigger: .hold,
            doubleTapWindow: 0.5
        )
        let data = try JSONEncoder().encode(binding)
        let decoded = try JSONDecoder().decode(HotkeyBinding.self, from: data)

        XCTAssertEqual(decoded.modifiers.rawValue, 0)
        XCTAssertEqual(decoded.trigger, .hold)
    }

    func testDefaultBindingKeyCodeIsKVKFunction() {
        // kVK_Function = 0x3F = 63 [verified: Carbon/HIToolbox, 2026-06-20]
        XCTAssertEqual(HotkeyBinding.defaultBinding.keyCode, 63)
    }

    func testDefaultBindingWindowIs400ms() {
        // 0.4 s = benchmark.md §7 [decision]; tune at P13
        XCTAssertEqual(HotkeyBinding.defaultBinding.doubleTapWindow, 0.4, accuracy: 1e-9)
    }

    func testDefaultBindingTriggerIsDoubleTap() {
        XCTAssertEqual(HotkeyBinding.defaultBinding.trigger, .doubleTap)
    }
}

// MARK: - DoubleTapDetector Tests

final class DoubleTapDetectorTests: XCTestCase {

    // Timestamps are synthetic; the detector has no wall-clock dependency.
    // Window = 0.4 s unless otherwise noted.

    private let window: TimeInterval = 0.4 // benchmark.md §7 [decision]

    func testTwoTapsWithinWindowEmitsStartCapture() {
        var detector = DoubleTapDetector()
        let t0: TimeInterval = 1000.0
        let t1 = t0 + 0.3 // within window

        let first = detector.register(tapAt: t0, window: window)
        let second = detector.register(tapAt: t1, window: window)

        XCTAssertNil(first, "First tap should not emit an event")
        XCTAssertEqual(second, .startCapture, "Second tap within window should emit startCapture")
    }

    func testTwoTapsExactlyAtWindowEdgeEmitsStartCapture() {
        var detector = DoubleTapDetector()
        let t0: TimeInterval = 500.0
        let t1 = t0 + window // exactly at the boundary (≤ window)

        _ = detector.register(tapAt: t0, window: window)
        let second = detector.register(tapAt: t1, window: window)

        XCTAssertEqual(second, .startCapture, "Tap exactly at window edge should trigger start")
    }

    func testTwoTapsOutsideWindowDoesNotEmit() {
        var detector = DoubleTapDetector()
        let t0: TimeInterval = 1000.0
        let t1 = t0 + 0.5 // > window (0.4)

        let first = detector.register(tapAt: t0, window: window)
        let second = detector.register(tapAt: t1, window: window)

        XCTAssertNil(first, "First tap should not emit")
        XCTAssertNil(second, "Second tap outside window should not emit startCapture (becomes new first tap)")
    }

    func testSingleTapDoesNotEmit() {
        var detector = DoubleTapDetector()
        let result = detector.register(tapAt: 100.0, window: window)
        XCTAssertNil(result, "A single isolated tap should not emit an event")
    }

    func testStartCaptureThenSingleTapEmitsStopCapture() {
        var detector = DoubleTapDetector()
        let t0: TimeInterval = 1000.0
        let t1 = t0 + 0.2 // double-tap start

        _ = detector.register(tapAt: t0, window: window)
        let startEvent = detector.register(tapAt: t1, window: window)
        XCTAssertEqual(startEvent, .startCapture)

        // Single tap after capture is active → stop
        let stopEvent = detector.register(tapAt: t1 + 5.0, window: window)
        XCTAssertEqual(stopEvent, .stopCapture)
    }

    func testIsCapturingTrueAfterStart() {
        var detector = DoubleTapDetector()
        let t0: TimeInterval = 0.0
        let t1 = t0 + 0.1
        _ = detector.register(tapAt: t0, window: window)
        _ = detector.register(tapAt: t1, window: window)
        XCTAssertTrue(detector.isCapturing)
    }

    func testIsCapturingFalseAfterStop() {
        var detector = DoubleTapDetector()
        _ = detector.register(tapAt: 0.0, window: window)
        _ = detector.register(tapAt: 0.1, window: window) // start
        _ = detector.register(tapAt: 5.0, window: window) // stop
        XCTAssertFalse(detector.isCapturing)
    }

    func testResetClearsCapturingState() {
        var detector = DoubleTapDetector()
        _ = detector.register(tapAt: 0.0, window: window)
        _ = detector.register(tapAt: 0.1, window: window) // now capturing
        XCTAssertTrue(detector.isCapturing)

        detector.reset()

        XCTAssertFalse(detector.isCapturing)
        // After reset, a single tap should not start a new session yet
        let result = detector.register(tapAt: 1.0, window: window)
        XCTAssertNil(result, "After reset, first tap should start the double-tap wait, not emit")
    }

    func testResetBeforeCaptureAllowsFreshDoubleTap() {
        var detector = DoubleTapDetector()
        // Partial state: first tap recorded
        _ = detector.register(tapAt: 0.0, window: window)
        detector.reset()

        // After reset, a fresh double-tap should work
        _ = detector.register(tapAt: 10.0, window: window)
        let event = detector.register(tapAt: 10.2, window: window)
        XCTAssertEqual(event, .startCapture)
    }

    func testThreeTapsStartsThenStops() {
        // tap1, tap2 (double → start), tap3 (single → stop)
        var detector = DoubleTapDetector()
        _ = detector.register(tapAt: 0.0, window: window)
        let startEvent = detector.register(tapAt: 0.3, window: window)
        let stopEvent = detector.register(tapAt: 1.0, window: window)

        XCTAssertEqual(startEvent, .startCapture)
        XCTAssertEqual(stopEvent, .stopCapture)
    }

    func testImmediateDoubleTapAfterStop() {
        // Start → stop → another double-tap → start again
        var detector = DoubleTapDetector()
        _ = detector.register(tapAt: 0.0, window: window)
        _ = detector.register(tapAt: 0.2, window: window) // start
        _ = detector.register(tapAt: 1.0, window: window) // stop
        _ = detector.register(tapAt: 2.0, window: window) // first tap of next cycle
        let event = detector.register(tapAt: 2.3, window: window)
        XCTAssertEqual(event, .startCapture, "Should be able to restart after a stop")
    }
}

// MARK: - HoldEdge Tests

/// Tests for the `holdEdge(isFnDown:wasDown:)` pure free function.
/// No CGEventTap, no clock, no side effects — all inputs injected.
final class HoldEdgeTests: XCTestCase {

    func testPressEdgeEmitsStartCapture() {
        // Transition: not pressed → pressed
        let event = holdEdge(isFnDown: true, wasDown: false)
        XCTAssertEqual(event, .startCapture, "Press leading edge must emit startCapture")
    }

    func testReleaseEdgeEmitsStopCapture() {
        // Transition: pressed → released
        let event = holdEdge(isFnDown: false, wasDown: true)
        XCTAssertEqual(event, .stopCapture, "Release trailing edge must emit stopCapture")
    }

    func testKeyRepeatWhileHeldEmitsNil() {
        // Both pressed → no transition (e.g., key-repeat flagsChanged event)
        let event = holdEdge(isFnDown: true, wasDown: true)
        XCTAssertNil(event, "Key-repeat while held must emit nil")
    }

    func testNoChangeWhileReleasedEmitsNil() {
        // Both released → no transition
        let event = holdEdge(isFnDown: false, wasDown: false)
        XCTAssertNil(event, "No change while released must emit nil")
    }

    func testPressReleaseCycle() {
        // Full press-and-release cycle yields start then stop
        let start = holdEdge(isFnDown: true, wasDown: false)
        let stop  = holdEdge(isFnDown: false, wasDown: true)
        XCTAssertEqual(start, .startCapture)
        XCTAssertEqual(stop, .stopCapture)
    }
}

// MARK: - UserDefaultsBindingStore Tests

final class UserDefaultsBindingStoreTests: XCTestCase {

    private let testKey = "com.speak.hotkeyBinding.test"

    override func setUp() {
        super.setUp()
        // Clean any stale value from a previous test run.
        UserDefaults.standard.removeObject(forKey: "com.speak.hotkeyBinding")
    }

    func testSaveAndLoadRoundTrip() throws {
        let store = UserDefaultsBindingStore()
        let binding = HotkeyBinding.defaultBinding
        store.save(binding)

        let loaded = try XCTUnwrap(store.load())
        XCTAssertEqual(loaded.keyCode, binding.keyCode)
        XCTAssertEqual(loaded.modifiers.rawValue, binding.modifiers.rawValue)
        XCTAssertEqual(loaded.trigger, binding.trigger)
        XCTAssertEqual(loaded.doubleTapWindow, binding.doubleTapWindow, accuracy: 1e-9)
    }

    func testLoadReturnsNilWhenNothingStored() {
        let store = UserDefaultsBindingStore()
        // setUp cleared the key, so nothing should be there
        let loaded = store.load()
        XCTAssertNil(loaded)
    }
}

// MARK: - InMemoryBindingStore (helper for other tests)

/// A mock BindingStoring that stores in memory.
/// Used by other tests that need a HotkeyMonitor without touching UserDefaults.
final class InMemoryBindingStore: BindingStoring, @unchecked Sendable {
    private var stored: HotkeyBinding?

    func load() -> HotkeyBinding? { stored }
    func save(_ binding: HotkeyBinding) { stored = binding }
}
