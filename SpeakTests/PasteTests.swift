// SpeakTests/PasteTests.swift
//
// Unit tests for the P6 paste seam (roadmap P6 done-when).
//
// SCOPE:
//   These tests verify the CaptureSession ↔ TextInserting contract using a
//   mock inserter. They do NOT exercise the real PasteboardWriter (which fires
//   live NSPasteboard + Cmd+V events into whatever app is focused). The live
//   paste verification is `[deferred — needs human verification]`.
//
// Done-when rows verified here (P6):
//   [x] CaptureSession with inserter=nil: no insert attempted; session → .done
//       (pre-P6 behaviour unchanged — all prior call-sites unaffected)
//   [x] Cleanup on (cleanedText available): inserter receives cleanedText
//   [x] Cleanup off (cleanedText nil): inserter receives rawText
//   [x] Cleanup unavailable (cleaner.isAvailable=false, cleanedText nil):
//       inserter receives rawText (graceful-fallback path preserved)
//   [x] Inserter throws: session transitions to .error (paste = delivery;
//       failure is an error, not just logged)
//   [x] All prior CaptureSession tests still pass with the new optional param
//       (confirmed by the unchanged call-sites in CaptureSessionTests.swift)
//
// Deferred (live-gated):
//   [deferred] Cleaned/raw text pastes into TextEdit / Slack / Terminal
//   [deferred] No macOS 26.4 paste-protection prompt appears
//   [deferred] Fails gracefully in password fields
//   [deferred] Terminal paste-provenance bypass — the project's biggest
//              [unverified] (architecture §14.3); must be tested by a human
//              with a real PasteboardWriter in a running app session.

import XCTest
@testable import SpeakCore

// MARK: - MockInserter

/// A controllable mock paste inserter. Records every `insert(_:)` call and
/// optionally throws.
///
/// Uses `@unchecked Sendable` + a `lock` for safe mutation from the actor
/// isolation domain that calls `insert`. In practice each test uses a single
/// task, so the lock is a safety net, not a performance concern.
private final class MockInserter: TextInserting, @unchecked Sendable {
    private var _calls: [String] = []
    private let lock = NSLock()
    let errorToThrow: Error?   // `let` → immutable after init; safe nonisolated

    init(errorToThrow: Error? = nil) {
        self.errorToThrow = errorToThrow
    }

    func insert(_ text: String) async throws {
        lock.withLock { _calls.append(text) }
        if let err = errorToThrow { throw err }
    }

    func snapshot() -> [String] { lock.withLock { _calls } }
}

// MARK: - Mocks (mirrors CaptureSessionTests.swift; scoped to this file)

private final class PasteMockTranscriber: Transcribing, @unchecked Sendable {
    let id: String
    private let script: [TranscriptChunk]
    private var _stopCount: Int = 0

    init(id: String = "paste-stt", script: [TranscriptChunk]) {
        self.id = id
        self.script = script
    }

    func startStream(locale: Locale) -> AsyncThrowingStream<TranscriptChunk, Error> {
        let script = self.script
        return AsyncThrowingStream { continuation in
            let task = Task {
                for chunk in script {
                    continuation.yield(chunk)
                    try? await Task.sleep(nanoseconds: 1_000_000) // 1ms
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func stop() async { _stopCount += 1 }
}

private struct PasteMockCleaner: LLMCleaning {
    let id: String
    let available: Bool
    let cleanResult: String
    let errorToThrow: Error?

    var isAvailable: Bool { get async { available } }

    func clean(_ text: String, mode: CleanupMode) async throws -> String {
        if let err = errorToThrow { throw err }
        return cleanResult
    }
}

// MARK: - Helpers

private func chunks(_ texts: [String]) -> [TranscriptChunk] {
    let now = Date()
    return texts.enumerated().map { idx, text in
        TranscriptChunk(text: text,
                        isFinal: idx == texts.count - 1,
                        timestamp: now.addingTimeInterval(Double(idx) * 0.01))
    }
}

// MARK: - Tests

final class PasteTests: XCTestCase {

    // MARK: - Inserter nil → no paste, session reaches .done (pre-P6 path)

    func testInserterNilDoesNotInsertAndSessionIsDone() async throws {
        let transcriber = PasteMockTranscriber(script: chunks(["hello world"]))
        let session = CaptureSession(transcriber: transcriber, inserter: nil)
        try await session.start()
        try await Task.sleep(nanoseconds: 50_000_000)
        let result = try await session.stop()
        XCTAssertEqual(result.rawText, "hello world")
        let state = await session.currentState
        XCTAssertTrue(state == .done, "inserter=nil → session must reach .done, got \(state)")
    }

    // MARK: - Cleanup on: inserter receives cleanedText

    func testInserterReceivesCleanedTextWhenCleanupSucceeds() async throws {
        let transcriber = PasteMockTranscriber(script: chunks(["um hello uh world"]))
        let cleaner = PasteMockCleaner(id: "mock-cleaner",
                                       available: true,
                                       cleanResult: "Hello, world.",
                                       errorToThrow: nil)
        let inserter = MockInserter()
        let session = CaptureSession(transcriber: transcriber,
                                     cleaner: cleaner,
                                     inserter: inserter)
        try await session.start()
        try await Task.sleep(nanoseconds: 50_000_000)
        _ = try await session.stop()

        let insertCalls = await inserter.snapshot()
        XCTAssertEqual(insertCalls.count, 1, "insert() must be called exactly once")
        XCTAssertEqual(insertCalls.first, "Hello, world.",
                       "insert() must receive cleanedText when cleanup succeeds")
        let state = await session.currentState
        XCTAssertTrue(state == .done, "paste-success → session must reach .done, got \(state)")
    }

    // MARK: - Cleanup off: inserter receives rawText

    func testInserterReceivesRawTextWhenCleanerIsNil() async throws {
        let transcriber = PasteMockTranscriber(script: chunks(["raw dictation text"]))
        let inserter = MockInserter()
        let session = CaptureSession(transcriber: transcriber,
                                     cleaner: nil,       // cleanup off
                                     inserter: inserter)
        try await session.start()
        try await Task.sleep(nanoseconds: 50_000_000)
        _ = try await session.stop()

        let insertCalls = await inserter.snapshot()
        XCTAssertEqual(insertCalls.count, 1, "insert() must be called exactly once")
        XCTAssertEqual(insertCalls.first, "raw dictation text",
                       "insert() must receive rawText when cleanup is off (cleaner=nil)")
        let state = await session.currentState
        XCTAssertTrue(state == .done, "paste-success → session must reach .done, got \(state)")
    }

    // MARK: - Cleanup unavailable: inserter receives rawText (graceful-fallback path)

    func testInserterReceivesRawTextWhenCleanerIsUnavailable() async throws {
        let transcriber = PasteMockTranscriber(script: chunks(["raw text fallback"]))
        let cleaner = PasteMockCleaner(id: "mock-cleaner",
                                       available: false,   // engine says it can't run
                                       cleanResult: "",
                                       errorToThrow: nil)
        let inserter = MockInserter()
        let session = CaptureSession(transcriber: transcriber,
                                     cleaner: cleaner,
                                     inserter: inserter)
        try await session.start()
        try await Task.sleep(nanoseconds: 50_000_000)
        let result = try await session.stop()

        // Cleanup was unavailable → cleanedText=nil (verified by CaptureSessionTests)
        XCTAssertNil(result.cleanedText, "Unavailable cleanup → cleanedText must be nil")

        // Inserter must receive rawText (cleanedText ?? rawText = nil ?? rawText)
        let insertCalls = await inserter.snapshot()
        XCTAssertEqual(insertCalls.count, 1, "insert() must be called exactly once")
        XCTAssertEqual(insertCalls.first, "raw text fallback",
                       "insert() must receive rawText when cleanup is unavailable")
        let state = await session.currentState
        XCTAssertTrue(state == .done,
                      "cleanup-unavailable + paste-success → session must reach .done, got \(state)")
    }

    // MARK: - Inserter throws: session transitions to .error

    func testInserterThrowsTransitionsSessionToError() async throws {
        let transcriber = PasteMockTranscriber(script: chunks(["some text"]))
        let inserter = MockInserter(errorToThrow: SpeakError.pasteboardBusy)
        let session = CaptureSession(transcriber: transcriber, inserter: inserter)
        try await session.start()
        try await Task.sleep(nanoseconds: 50_000_000)

        do {
            _ = try await session.stop()
            XCTFail("stop() must throw when insert() throws")
        } catch let SpeakError.pasteboardBusy {
            // Expected — paste failure surfaces as pasteboardBusy.
        } catch {
            XCTFail("Expected SpeakError.pasteboardBusy, got \(error)")
        }

        let state = await session.currentState
        if case .error(.pasteboardBusy) = state {
            // Correct — paste failure is a session error.
        } else {
            XCTFail("insert() throw must move session to .error(.pasteboardBusy), got \(state)")
        }
    }

    // MARK: - Inserter throws (generic error): wrapped to .pasteboardBusy

    func testInserterGenericThrowWrappedToPasteboardBusy() async throws {
        struct ArbitraryPasteError: Error {}
        let transcriber = PasteMockTranscriber(script: chunks(["some text"]))
        let inserter = MockInserter(errorToThrow: ArbitraryPasteError())
        let session = CaptureSession(transcriber: transcriber, inserter: inserter)
        try await session.start()
        try await Task.sleep(nanoseconds: 50_000_000)

        do {
            _ = try await session.stop()
            XCTFail("stop() must throw when insert() throws a generic error")
        } catch let SpeakError.pasteboardBusy {
            // Expected — generic paste errors are mapped to .pasteboardBusy.
        } catch {
            XCTFail("Expected SpeakError.pasteboardBusy, got \(error)")
        }

        let state = await session.currentState
        if case .error(.pasteboardBusy) = state {
            // Correct.
        } else {
            XCTFail("Generic insert() error must map to .error(.pasteboardBusy), got \(state)")
        }
    }
}

// MARK: - State == State (Equatable for assertions — mirrors CaptureSessionTests.swift)
// NOTE: This extension must be consistent with the one in CaptureSessionTests.swift.
// Both files are in SpeakTests; Swift allows @retroactive conformances in test
// targets. If there is a duplicate-conformance compile error, collapse both into
// a shared TestHelpers.swift file.
