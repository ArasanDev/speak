// SpeakTests/DegradeToRawTests.swift
//
// SM-3 — Degrade-to-raw verification.
//
// Proves every Foundation Models failure path (error, unavailable, timeout,
// empty output) falls back to raw paste — never an error state, always pastes
// something. Each test exercises runCleanup() via the CaptureSession.stop() path.
//
// Contract under test (CaptureSession+Cleanup.swift runCleanup()):
//   - cleaner nil          → cleanedText=nil, raw text is the paste target
//   - cleaner unavailable  → cleanedText=nil, raw text is the paste target, state=.done (NOT .error)
//   - cleaner throws       → cleanedText=nil, raw text is the paste target, state=.done (NOT .error)
//   - cleaner times out    → cleanedText=nil, raw text is the paste target, state=.done (NOT .error)
//   - cleaner returns ""   → cleanedText=nil, raw text is the paste target, state=.done (NOT .error) [SM-3 fix]

@testable import SpeakCore
import XCTest

// MARK: - Local mocks (private to this file)

private final class SM3MockTranscriber: Transcribing, @unchecked Sendable {
    let id: String
    private let chunks: [TranscriptChunk]

    init(id: String = "sm3-stt", text: String) {
        self.id = id
        self.chunks = [TranscriptChunk(text: text, isFinal: true, timestamp: Date())]
    }

    func startStream(locale: Locale) -> AsyncThrowingStream<TranscriptChunk, Error> {
        let chunks = self.chunks
        return AsyncThrowingStream { continuation in
            let task = Task {
                for chunk in chunks {
                    continuation.yield(chunk)
                    try? await Task.sleep(nanoseconds: 1_000_000)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func stop() async {}
}

/// Controllable mock cleaner. Configure `available`, `cleanError`, `cleanResult`.
private struct SM3MockCleaner: LLMCleaning {
    let id: String
    let available: Bool
    let cleanError: Error?
    let cleanResult: String

    var isAvailable: Bool { get async { available } }

    func clean(_ text: String, mode: CleanupMode) async throws -> String {
        if let err = cleanError { throw err }
        return cleanResult
    }
}

/// Non-cooperative hanging cleaner — sleeps indefinitely until timed out.
/// Simulates a non-cooperative hung model without leaking a Swift CheckedContinuation.
private struct SM3HangingCleaner: LLMCleaning, Sendable {
    let id: String
    var isAvailable: Bool { get async { true } }

    func clean(_ text: String, mode: CleanupMode) async throws -> String {
        while !Task.isCancelled {
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        throw CancellationError()
    }
}

// MARK: - SM-3 Tests

final class DegradeToRawTests: XCTestCase {

    // MARK: Helpers

    private func makeSession(rawText: String, cleaner: (any LLMCleaning)?) -> CaptureSession {
        let transcriber = SM3MockTranscriber(text: rawText)
        return CaptureSession(transcriber: transcriber, cleaner: cleaner)
    }

    private func startAndWait(_ session: CaptureSession) async throws {
        try await session.start()
        try await Task.sleep(nanoseconds: 50_000_000) // 50ms — let stream emit
    }

    // MARK: - [SM-3-1] Cleaner throws → raw fallback

    func testCleanupErrorFallsBackToRaw() async throws {
        struct CleanupAPIError: LocalizedError {
            var errorDescription: String? { "model rejected input" }
        }
        let cleaner = SM3MockCleaner(
            id: "sm3-cleaner",
            available: true,
            cleanError: SpeakError.llmCleanupFailed("model rejected input"),
            cleanResult: ""
        )
        let session = makeSession(rawText: "hello world", cleaner: cleaner)
        try await startAndWait(session)

        // stop() must NOT throw — cleanup errors must not become session errors.
        let result = try await session.stop()

        XCTAssertNil(result.cleanedText,
            "[SM-3-1] cleanup error → cleanedText must be nil (raw fallback)")
        XCTAssertEqual(result.rawText, "hello world",
            "[SM-3-1] raw text must be preserved on cleanup error")
        XCTAssertEqual(result.engineId, "sm3-stt",
            "[SM-3-1] cleanup error → engineId is STT id only, not combined")
        let state = await session.currentState
        XCTAssertTrue(state == .done,
            "[SM-3-1] cleanup error → .done (NOT .error), got \(state)")
    }

    func testCleanupGenericErrorFallsBackToRaw() async throws {
        struct GenericError: LocalizedError {
            var errorDescription: String? { "transient failure" }
        }
        let cleaner = SM3MockCleaner(
            id: "sm3-cleaner",
            available: true,
            cleanError: GenericError(),
            cleanResult: ""
        )
        let session = makeSession(rawText: "hello world", cleaner: cleaner)
        try await startAndWait(session)

        let result = try await session.stop()

        XCTAssertNil(result.cleanedText,
            "[SM-3-1] generic error → cleanedText must be nil")
        XCTAssertEqual(result.rawText, "hello world",
            "[SM-3-1] raw text must be preserved on generic error")
        let state = await session.currentState
        XCTAssertTrue(state == .done,
            "[SM-3-1] generic error → .done (NOT .error), got \(state)")
    }

    // MARK: - [SM-3-2] Cleaner unavailable → raw fallback

    func testCleanupUnavailableFallsBackToRaw() async throws {
        let cleaner = SM3MockCleaner(
            id: "sm3-cleaner",
            available: false,         // engine reports it cannot run
            cleanError: nil,
            cleanResult: ""
        )
        let session = makeSession(rawText: "hello world", cleaner: cleaner)
        try await startAndWait(session)

        let result = try await session.stop()

        XCTAssertNil(result.cleanedText,
            "[SM-3-2] unavailable cleaner → cleanedText must be nil")
        XCTAssertEqual(result.rawText, "hello world",
            "[SM-3-2] raw text must be preserved when cleaner is unavailable")
        XCTAssertEqual(result.engineId, "sm3-stt",
            "[SM-3-2] unavailable → engineId is STT id only")
        let state = await session.currentState
        XCTAssertTrue(state == .done,
            "[SM-3-2] unavailable → .done (NOT .error), got \(state)")
    }

    // MARK: - [SM-3-3] Timeout → raw fallback
    //
    // Uses a NON-COOPERATIVE hanging cleaner to prove the timeout mechanism fires
    // even when the cleaner ignores Task.cancel(). This test takes up to T_cleanup
    // (10 s) — that is expected and verifies the production guarantee.

    func testCleanupTimeoutFallsBackToRaw() async throws {
        let hangingCleaner = SM3HangingCleaner(id: "sm3-hanging")
        let session = makeSession(rawText: "hello world", cleaner: hangingCleaner)
        try await startAndWait(session)

        // Blocks until the 10 s T_cleanup timeout fires.
        let result = try await session.stop()

        XCTAssertNil(result.cleanedText,
            "[SM-3-3] timeout → cleanedText must be nil (raw fallback)")
        XCTAssertEqual(result.rawText, "hello world",
            "[SM-3-3] raw text must be preserved when cleanup hangs")
        XCTAssertEqual(result.engineId, "sm3-stt",
            "[SM-3-3] timeout → engineId is STT id only (not combined)")
        let state = await session.currentState
        XCTAssertTrue(state == .done,
            "[SM-3-3] timeout → .done (NOT stuck in .processing), got \(state)")
    }

    // MARK: - [SM-3-4] Empty output → raw fallback
    //
    // If the cleaner returns "" (e.g. Foundation Models returns empty content),
    // cleanedText ?? rawText would paste "" — an empty paste, not the raw text.
    // runCleanup() must treat empty output as a fallback signal, setting cleanedText=nil.
    // [decision SM-3] Fixed in CaptureSession+Cleanup.swift: guard !cleaned.isEmpty.

    func testEmptyOutputFallsBackToRaw() async throws {
        let cleaner = SM3MockCleaner(
            id: "sm3-cleaner",
            available: true,
            cleanError: nil,
            cleanResult: ""             // cleaner returns empty string
        )
        let session = makeSession(rawText: "hello world", cleaner: cleaner)
        try await startAndWait(session)

        let result = try await session.stop()

        XCTAssertNil(result.cleanedText,
            "[SM-3-4] empty cleaner output → cleanedText must be nil (not \"\"), so raw text is pasted")
        XCTAssertEqual(result.rawText, "hello world",
            "[SM-3-4] raw text must be preserved when cleaner returns empty string")
        XCTAssertEqual(result.engineId, "sm3-stt",
            "[SM-3-4] empty output → engineId is STT id only (fallback path)")
        let state = await session.currentState
        XCTAssertTrue(state == .done,
            "[SM-3-4] empty output → .done (NOT .error), got \(state)")
    }

    // MARK: - Regression: successful cleanup still works

    func testSuccessfulCleanupIsNotAffectedByFixes() async throws {
        let cleaner = SM3MockCleaner(
            id: "sm3-cleaner",
            available: true,
            cleanError: nil,
            cleanResult: "Hello, world."   // non-empty output
        )
        let session = makeSession(rawText: "um hello world", cleaner: cleaner)
        try await startAndWait(session)

        let result = try await session.stop()

        XCTAssertEqual(result.cleanedText, "Hello, world.",
            "Successful cleanup → cleanedText must be populated")
        XCTAssertEqual(result.rawText, "um hello world",
            "Raw text must always be preserved")
        XCTAssertEqual(result.engineId, "sm3-stt+sm3-cleaner",
            "Successful cleanup → combined engineId")
        let state = await session.currentState
        XCTAssertTrue(state == .done,
            "Successful cleanup → .done, got \(state)")
    }
}

// CaptureSession.State: @retroactive Equatable is declared in CaptureSessionTests.swift
// and is visible to the whole SpeakTests module — no re-declaration needed here.
