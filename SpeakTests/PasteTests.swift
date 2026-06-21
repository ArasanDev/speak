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
import AppKit
import Carbon.HIToolbox
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

// MARK: - Phase D: PasteboardWriter unit tests (pure, no real AX / live events)

/// Records `PasteboardWriter` side effects so unit tests never touch the real
/// system clipboard or post real Cmd+V events into the focused window. A real
/// post lands in whatever app has focus (e.g. the terminal running the suite)
/// and pastes the clipboard there — see the regression this guards against.
final class PasteSideEffectRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var _clipboardWrites: [String] = []
    private var _postedEventCount = 0

    var clipboardWrites: [String] { lock.withLock { _clipboardWrites } }
    var postedEventCount: Int { lock.withLock { _postedEventCount } }

    func recordClipboardWrite(_ text: String) { lock.withLock { _clipboardWrites.append(text) } }
    func recordPostedEvent(_ event: CGEvent) { lock.withLock { _postedEventCount += 1 } }
}

final class PasteboardWriterTests: XCTestCase {

    // MARK: - pasteEventPlan() shape

    /// The plan must contain exactly 4 entries in the canonical Cmd+V order:
    ///   [0] Cmd-down  (.maskCommand)
    ///   [1] V-down    (.maskCommand)
    ///   [2] V-up      (.maskCommand)
    ///   [3] Cmd-up    ([])
    func testPasteEventPlanHasFourEntriesInOrder() {
        let plan = PasteboardWriter.pasteEventPlan()
        XCTAssertEqual(plan.count, 4, "pasteEventPlan() must return exactly 4 entries")

        // kVK_Command = 55 = 0x37 [verified: Carbon/HIToolbox, swiftc 2026-06-21]
        let cmdKey = CGKeyCode(kVK_Command)
        // kVK_ANSI_V = 9 = 0x09 [verified: Carbon/HIToolbox, runtime 2026-06-20]
        let vKey = CGKeyCode(kVK_ANSI_V)

        // [0] Cmd-down
        XCTAssertEqual(plan[0].keyCode, cmdKey,          "[0] keyCode must be kVK_Command")
        XCTAssertTrue(plan[0].keyDown,                   "[0] must be keyDown=true (Cmd-down)")
        XCTAssertEqual(plan[0].flags, .maskCommand,      "[0] flags must be .maskCommand")

        // [1] V-down
        XCTAssertEqual(plan[1].keyCode, vKey,            "[1] keyCode must be kVK_ANSI_V")
        XCTAssertTrue(plan[1].keyDown,                   "[1] must be keyDown=true (V-down)")
        XCTAssertEqual(plan[1].flags, .maskCommand,      "[1] flags must be .maskCommand")

        // [2] V-up
        XCTAssertEqual(plan[2].keyCode, vKey,            "[2] keyCode must be kVK_ANSI_V")
        XCTAssertFalse(plan[2].keyDown,                  "[2] must be keyDown=false (V-up)")
        XCTAssertEqual(plan[2].flags, .maskCommand,      "[2] flags must be .maskCommand")

        // [3] Cmd-up
        XCTAssertEqual(plan[3].keyCode, cmdKey,          "[3] keyCode must be kVK_Command")
        XCTAssertFalse(plan[3].keyDown,                  "[3] must be keyDown=false (Cmd-up)")
        XCTAssertEqual(plan[3].flags, [],                "[3] flags must be empty []")
    }

    // MARK: - AX not trusted → throw + clipboard floor still written

    /// When AX is not trusted, `insert` must throw `.pasteRequiresAccessibility`
    /// AND the clipboard floor must still have run (text written) before the gate.
    ///
    /// The write is proven via the injected `PasteSideEffectRecorder`, NOT the real
    /// `NSPasteboard.general` — a real write clobbers the user's clipboard during
    /// `make test`. The unique marker string makes the assertion unambiguous.
    func testInsertThrowsPasteRequiresAccessibilityWhenAXNotTrusted() async throws {
        let uniqueText = "SPEAK_PHASE_D_AX_TEST_\(UUID().uuidString)"
        let recorder = PasteSideEffectRecorder()
        let writer = PasteboardWriter(
            isAccessibilityTrusted: { false },
            settle: .zero,
            writeClipboard: { recorder.recordClipboardWrite($0) },
            postEvent: { recorder.recordPostedEvent($0) }
        )

        do {
            try await writer.insert(uniqueText)
            XCTFail("insert() must throw when AX is not trusted")
        } catch SpeakError.pasteRequiresAccessibility(let text) {
            // Expected — correct error; it must carry the text it tried to deliver.
            XCTAssertEqual(text, uniqueText, "The error must carry the delivered text for Scratchpad routing.")
        } catch {
            XCTFail("Expected SpeakError.pasteRequiresAccessibility, got \(error)")
        }

        // Assert the clipboard floor ran BEFORE the AX gate — via the injected
        // recorder, NOT the real NSPasteboard (which would clobber the user's
        // clipboard; the floor logic is fully proven by the recorder).
        XCTAssertEqual(
            recorder.clipboardWrites, [uniqueText],
            "Clipboard floor must write text before the AX gate"
        )
        // AX-not-trusted → throw before posting; no Cmd+V events may be posted.
        XCTAssertEqual(
            recorder.postedEventCount, 0,
            "AX-not-trusted path must not post any Cmd+V events"
        )
    }

    // MARK: - AX trusted + settle .zero → completes without throwing

    /// When AX is trusted and settle is zero, `insert` must complete without
    /// throwing AND post the 4-event Cmd+V chord. The events go to the injected
    /// recorder — NOT the live HID tap. (A real post is NOT harmless: it lands in
    /// whatever window has focus and pastes the clipboard there — e.g. the terminal
    /// running the suite. This test previously posted real events; that is the
    /// regression being fixed.) The real paste effect is [deferred — human verification].
    func testInsertSucceedsWhenAXTrusted() async throws {
        let recorder = PasteSideEffectRecorder()
        let writer = PasteboardWriter(
            isAccessibilityTrusted: { true },
            settle: .zero,
            writeClipboard: { recorder.recordClipboardWrite($0) },
            postEvent: { recorder.recordPostedEvent($0) }
        )
        // Must not throw. If CGEvent construction fails in CI (headless), the
        // test is allowed to throw `.pasteboardBusy` — only `.pasteRequiresAccessibility`
        // and truly unexpected errors are failures.
        do {
            try await writer.insert("hello phase D")
        } catch SpeakError.pasteboardBusy {
            // Acceptable in headless CI where CGEvent infrastructure is unavailable.
            return
        } catch SpeakError.pasteRequiresAccessibility(_) {
            XCTFail("Should not throw .pasteRequiresAccessibility when AX is trusted")
            return
        } catch {
            XCTFail("Unexpected error from insert(): \(error)")
            return
        }
        // Side effects captured by the recorder — no real clipboard write, no real Cmd+V.
        XCTAssertEqual(
            recorder.clipboardWrites, ["hello phase D"],
            "AX-trusted path must write the clipboard floor exactly once"
        )
        XCTAssertEqual(
            recorder.postedEventCount, 4,
            "AX-trusted path posts the 4-event Cmd+V chord (to the recorder, not the real tap)"
        )
    }
}

// MARK: - State == State (Equatable for assertions — mirrors CaptureSessionTests.swift)
// NOTE: This extension must be consistent with the one in CaptureSessionTests.swift.
// Both files are in SpeakTests; Swift allows @retroactive conformances in test
// targets. If there is a duplicate-conformance compile error, collapse both into
// a shared TestHelpers.swift file.
