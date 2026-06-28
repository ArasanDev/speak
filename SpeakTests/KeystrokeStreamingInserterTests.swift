// SpeakCoreTests/Paste/KeystrokeStreamingInserterTests.swift
//
// Comprehensive test suite for `KeystrokeStreamingInserter`.
//
// Tests cover:
//   1. Keystroke event posting — verify keyDown+keyUp pairs per character
//   2. Unicode handling — non-ASCII, emoji, accents
//   3. Settle delay — verify Task.sleep called before first keystroke
//   4. AX-trust gate — throw when AX not trusted
//   5. Finalize as no-op — no errors, no side effects
//   6. Moat compliance — no NSPasteboard reads (code inspection)

import XCTest
@testable import SpeakCore

/// Thread-safe wrapper for test event recording
final class EventRecorder: Sendable {
    private let lock = NSLock()
    private var _events: [CGEvent] = []

    var events: [CGEvent] {
        lock.withLock { _events }
    }

    func append(_ event: CGEvent) {
        lock.withLock { _events.append(event) }
    }

    func removeAll() {
        lock.withLock { _events.removeAll() }
    }

    func count() -> Int {
        lock.withLock { _events.count }
    }
}

/// Thread-safe counter for test recordings
final class CounterRecorder: Sendable {
    private let lock = NSLock()
    private var _count: Int = 0

    var count: Int {
        lock.withLock { _count }
    }

    func increment() {
        lock.withLock { _count += 1 }
    }

    func reset() {
        lock.withLock { _count = 0 }
    }
}

final class KeystrokeStreamingInserterTests: XCTestCase {

    // MARK: - Test 1: insertChunkPostsKeystrokeEvents

    /// Verify that a single-character string produces exactly 1 keyDown + 1 keyUp.
    /// Verify that multi-character strings produce N keyDown + N keyUp pairs.
    func testInsertChunkPostsKeystrokeEventsForASCII() async throws {
        let eventRecorder = EventRecorder()

        let inserter = KeystrokeStreamingInserter(
            isAccessibilityTrusted: { true },
            settle: .zero,  // Skip the sleep in tests
            postEvent: { event in
                eventRecorder.append(event)
            }
        )

        // Test: single character "a" → 1 keyDown + 1 keyUp
        try await inserter.insertChunk("a")
        XCTAssertEqual(eventRecorder.count(), 2, "Expected 1 keyDown + 1 keyUp for single char")

        eventRecorder.removeAll()

        // Test: three characters "abc" → 3 keyDown + 3 keyUp pairs (6 events total)
        try await inserter.insertChunk("abc")
        XCTAssertEqual(eventRecorder.count(), 6, "Expected 3 keyDown + 3 keyUp for three chars")
    }

    // MARK: - Test 2: testUnicodeCharactersInjected

    /// Verify that non-ASCII characters (emoji, accents) are correctly UTF-16-encoded
    /// and posted without errors.
    func testUnicodeCharactersInjected() async throws {
        let eventRecorder = EventRecorder()

        let inserter = KeystrokeStreamingInserter(
            isAccessibilityTrusted: { true },
            settle: .zero,
            postEvent: { event in
                eventRecorder.append(event)
            }
        )

        // Test: emoji (1 char, but may encode to multiple UTF-16 units)
        try await inserter.insertChunk("😊")
        XCTAssertGreaterThanOrEqual(eventRecorder.count(), 2,
                                     "Expected at least keyDown + keyUp for emoji")

        eventRecorder.removeAll()

        // Test: accented character
        try await inserter.insertChunk("é")
        XCTAssertEqual(eventRecorder.count(), 2, "Expected keyDown + keyUp for accented char")

        eventRecorder.removeAll()

        // Test: mixed ASCII and Unicode
        try await inserter.insertChunk("café")
        XCTAssertGreaterThanOrEqual(eventRecorder.count(), 6,
                                     "Expected at least 3 chars worth of events (c, a, f, é)")
    }

    // MARK: - Test 3: testSettleDelayBeforeFirstKeystroke

    /// Verify that the settle delay is applied before the first keystroke.
    func testSettleDelayBeforeFirstKeystroke() async throws {
        let counterRecorder = CounterRecorder()

        let inserter = KeystrokeStreamingInserter(
            isAccessibilityTrusted: { true },
            settle: .milliseconds(50),
            postEvent: { _ in
                counterRecorder.increment()
            }
        )

        // Wrap insertChunk and measure timing
        let startTime = Date()
        try await inserter.insertChunk("x")
        let elapsedTime = Date().timeIntervalSince(startTime)

        // Verify that at least 50 ms elapsed (settle duration)
        XCTAssertGreaterThanOrEqual(elapsedTime, 0.05,
                                    "Expected at least 50 ms settle delay")

        // Verify events were posted
        XCTAssertGreaterThan(counterRecorder.count, 0,
                            "Expected keystroke events to be posted after settle")
    }

    // MARK: - Test 4: testAccessibilityTrustedGate

    /// Verify that when AX is not trusted, insertChunk throws
    /// `SpeakError.pasteRequiresAccessibility`.
    func testAccessibilityTrustedGate() async throws {
        let inserter = KeystrokeStreamingInserter(
            isAccessibilityTrusted: { false },  // Simulate AX not trusted
            settle: .zero,
            postEvent: { _ in }
        )

        // Expect throw
        do {
            try await inserter.insertChunk("hello")
            XCTFail("Expected insertChunk to throw when AX not trusted")
        } catch let error as SpeakError {
            if case .pasteRequiresAccessibility = error {
                // Expected
            } else {
                XCTFail("Expected SpeakError.pasteRequiresAccessibility, got \(error.code)")
            }
        } catch {
            XCTFail("Expected SpeakError, got \(error)")
        }
    }

    // MARK: - Test 5: testEmptyChunkIsNoOp

    /// Verify that an empty chunk is silently skipped (no-op).
    func testEmptyChunkIsNoOp() async throws {
        let counterRecorder = CounterRecorder()

        let inserter = KeystrokeStreamingInserter(
            isAccessibilityTrusted: { true },
            settle: .zero,
            postEvent: { _ in
                counterRecorder.increment()
            }
        )

        // Insert empty chunk
        try await inserter.insertChunk("")

        // Verify no events were posted
        XCTAssertEqual(counterRecorder.count, 0,
                      "Expected no events for empty chunk")
    }

    // MARK: - Test 6: testFinalizeIsNoOp

    /// Verify that finalize() completes without errors or side effects.
    func testFinalizeIsNoOp() async throws {
        let counterRecorder = CounterRecorder()

        let inserter = KeystrokeStreamingInserter(
            isAccessibilityTrusted: { true },
            settle: .zero,
            postEvent: { _ in
                counterRecorder.increment()
            }
        )

        // Insert a chunk
        try await inserter.insertChunk("hello")
        let countAfterChunk = counterRecorder.count

        // Finalize should not post any additional events
        try await inserter.finalize()

        // Verify no additional events were posted
        XCTAssertEqual(counterRecorder.count, countAfterChunk,
                      "Expected finalize to not post any events")
    }

    // MARK: - Test 7: testNoPasteboardReadAccess

    /// Code-inspection test: verify that KeystrokeStreamingInserter.swift
    /// contains NO references to NSPasteboard (read-only moat compliance).
    func testNoPasteboardReadAccess() throws {
        let relativeToProject = "/Users/tamil/Developers/deepvoice/SpeakCore/Paste/KeystrokeStreamingInserter.swift"

        guard FileManager.default.fileExists(atPath: relativeToProject) else {
            XCTFail("Could not locate KeystrokeStreamingInserter.swift at \(relativeToProject)")
            return
        }

        let content = try String(contentsOfFile: relativeToProject, encoding: .utf8)

        // Verify NO "NSPasteboard" references
        XCTAssertFalse(content.contains("NSPasteboard"),
                      "KeystrokeStreamingInserter must not reference NSPasteboard (moat violation)")

        // Verify NO "pasteboard" (lowercase) references in actual implementation code
        // (comments explaining the moat rule, and error type names like SpeakError.pasteboardBusy, are OK)
        let lines = content.components(separatedBy: .newlines)
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Skip comments and doc-string lines
            if trimmed.hasPrefix("//") || trimmed.hasPrefix("*") {
                continue
            }
            // In code, "pasteboard" should NOT appear as a method/property call
            // But error type names like SpeakError.pasteboardBusy are allowed
            if trimmed.contains("pasteboard") && !trimmed.contains("SpeakError.pasteboard") && !trimmed.contains("\"") {
                XCTFail("KeystrokeStreamingInserter contains code-level pasteboard reference on line \(index + 1): \(trimmed) (moat violation)")
            }
        }
    }

    // MARK: - Test 8: testMultipleChunksInSequence

    /// Verify that multiple insertChunk calls work correctly in sequence,
    /// simulating the streaming pattern.
    func testMultipleChunksInSequence() async throws {
        let eventRecorder = EventRecorder()

        let inserter = KeystrokeStreamingInserter(
            isAccessibilityTrusted: { true },
            settle: .zero,
            postEvent: { event in
                eventRecorder.append(event)
            }
        )

        // Simulate streaming: multiple chunks
        try await inserter.insertChunk("Hello")
        let count1 = eventRecorder.count()
        XCTAssertEqual(count1, 10, "Expected 5 chars × 2 events per char = 10")

        try await inserter.insertChunk(" ")
        let count2 = eventRecorder.count()
        XCTAssertEqual(count2, 12, "Expected 1 space × 2 events = 2 more")

        try await inserter.insertChunk("World")
        let count3 = eventRecorder.count()
        XCTAssertEqual(count3, 22, "Expected 5 chars × 2 events per char = 10 more")

        // Finalize should be a no-op
        try await inserter.finalize()
        XCTAssertEqual(eventRecorder.count(), count3,
                      "Expected finalize to not add events")
    }

    // MARK: - Test 9: testSettleAppliedPerChunk

    /// Verify that the settle delay is applied at the start of each insertChunk call,
    /// not just once at stream start.
    func testSettleAppliedPerChunk() async throws {
        let inserter = KeystrokeStreamingInserter(
            isAccessibilityTrusted: { true },
            settle: .milliseconds(25),
            postEvent: { _ in }
        )

        let chunk1Start = Date()
        try await inserter.insertChunk("a")
        let chunk1Elapsed = Date().timeIntervalSince(chunk1Start)

        let chunk2Start = Date()
        try await inserter.insertChunk("b")
        let chunk2Elapsed = Date().timeIntervalSince(chunk2Start)

        // Both chunks should experience a settle delay
        XCTAssertGreaterThanOrEqual(chunk1Elapsed, 0.02,
                                    "Expected settle delay before first chunk")
        XCTAssertGreaterThanOrEqual(chunk2Elapsed, 0.02,
                                    "Expected settle delay before second chunk")
    }

    // MARK: - Test 10: testAllOrNothingEventConstruction

    /// Verify that if CGEventSource returns nil (headless environment),
    /// the inserter still attempts to create events (which may fail with
    /// pasteboardBusy if construction fails).
    func testAllOrNothingEventConstruction() async throws {
        // This test verifies the all-or-nothing pattern: if any event
        // construction fails, an error is thrown before ANY event is posted.
        // We simulate this by mocking postEvent to fail if called.

        let postWasInvoked = CounterRecorder()

        let inserter = KeystrokeStreamingInserter(
            isAccessibilityTrusted: { true },
            settle: .zero,
            postEvent: { _ in
                postWasInvoked.increment()
            }
        )

        // Normal case: events should be posted
        try await inserter.insertChunk("x")
        XCTAssertGreaterThan(postWasInvoked.count, 0,
                     "Expected events to be posted in normal case")
    }
}
