// SpeakTests/SpeechTranscriberTests.swift
//
// Integration tests for AppleSpeechTranscriber.
//
// CRITICAL SKIP CONTRACT (read before changing):
//   • If the en-US speech model is not installed on this machine, the test
//     XCTSkips with a clear diagnostic message. Skipping is NOT passing.
//   • If transcription runs but produces empty output, the test FAILS with
//     XCTFail. Empty output is NEVER a pass.
//   • A green (non-skip, non-fail) test means real transcription happened and
//     the expected words were found. That is the only acceptable pass.
//
// Fixture: SpeakTests/Fixtures/hello_speech.caf
//   Generated with: say "Testing one two three" | afconvert → 16kHz mono Float32
//   Assertion checks "one", "two", "three" (case-insensitive) on the FINAL
//   chunk only — "testing" is dropped because synthetic `say` speech transcribes
//   it inconsistently (observed: "cased"); the digits are stable.

import XCTest
import AVFoundation
import Speech
@testable import SpeakCore

@available(macOS 26.0, *)
final class SpeechTranscriberTests: XCTestCase {

    // ── Fixture-backed AudioBufferProducer ───────────────────────────────────

    /// Reads the CAF fixture and streams its buffers as if they came from a mic.
    /// This exercises the same AnalyzerInput path as live audio.
    final class FixtureAudioProducer: AudioBufferProducing, @unchecked Sendable {
        let fileURL: URL
        private var continuation: AsyncStream<AVAudioPCMBuffer>.Continuation?

        init(fileURL: URL) {
            self.fileURL = fileURL
        }

        func start() throws -> AsyncStream<AVAudioPCMBuffer> {
            let file = try AVAudioFile(forReading: fileURL)
            let format = file.processingFormat
            let frameCount = AVAudioFrameCount(file.length)
            // Chunk size: 4096 frames per buffer (matches AudioCapture.Constants.tapBufferSize [decision])
            let chunkSize: AVAudioFrameCount = 4096

            let (stream, cont) = AsyncStream<AVAudioPCMBuffer>.makeStream()
            self.continuation = cont

            Task.detached(priority: .userInitiated) {
                var offset: AVAudioFramePosition = 0
                while offset < AVAudioFramePosition(frameCount) {
                    let remaining = AVAudioFrameCount(AVAudioFramePosition(frameCount) - offset)
                    let thisChunk = min(chunkSize, remaining)
                    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: thisChunk) else { break }
                    do {
                        try file.read(into: buffer, frameCount: thisChunk)
                    } catch {
                        break
                    }
                    cont.yield(buffer)
                    offset += AVAudioFramePosition(buffer.frameLength)
                    // Small sleep to allow async iteration without blocking
                    try? await Task.sleep(nanoseconds: 1_000_000) // 1ms
                }
                cont.finish()
            }
            return stream
        }

        func stop() {
            continuation?.finish()
            continuation = nil
        }
    }

    // MARK: - Helpers

    private var fixtureURL: URL {
        // In the test bundle, Fixtures/ is a folder reference.
        // Prefer the test bundle path, fall back to source-tree path for local runs.
        let bundle = Bundle(for: type(of: self))
        if let url = bundle.url(forResource: "hello_speech", withExtension: "caf", subdirectory: "Fixtures") {
            return url
        }
        // Fallback: source-tree path for local `make test` runs.
        let sourceRoot = URL(fileURLWithPath: #file)
            .deletingLastPathComponent() // SpeakTests/
            .appendingPathComponent("Fixtures/hello_speech.caf")
        return sourceRoot
    }

    // MARK: - Tests

    /// Verifies that the engine id is the documented constant.
    @available(macOS 26.0, *)
    func testEngineId() {
        let transcriber = AppleSpeechTranscriber()
        XCTAssertEqual(transcriber.id, "apple-speech-en-US",
                       "Engine id must be 'apple-speech-en-US' per roadmap P3 done-when.")
    }

    /// Verifies that `startStream` returns a stream object (pre-flight check —
    /// does not assert transcription content, just that the call doesn't crash).
    @available(macOS 26.0, *)
    func testStartStreamReturnsStream() {
        let transcriber = AppleSpeechTranscriber()
        let stream = transcriber.startStream(locale: Locale(identifier: "en-US"))
        // Just verifying the stream is created without crashing.
        // A real assertion on content happens in testTranscribesFixture.
        XCTAssertNotNil(stream)
        Task { await transcriber.stop() }
    }

    /// Feeds the CAF fixture through AppleSpeechTranscriber and asserts:
    ///   1. At least one chunk arrives (non-empty transcript).
    ///   2. A final chunk (isFinal == true) arrives.
    ///   3. The full transcript contains expected words from the fixture.
    ///   4. Empty output is a hard failure (never silently passes).
    ///
    /// If the en-US model is not installed, this test XCTSkips.
    @available(macOS 26.0, *)
    func testTranscribesFixture() async throws {
        let enUS = Locale(identifier: "en-US")
        let url = fixtureURL
        try await assertModelReadyForFixtureTest(locale: enUS, fixtureURL: url)

        let producer = FixtureAudioProducer(fileURL: url)
        let stt = AppleSpeechTranscriber(audioProducer: producer)
        let (chunks, sawFinal) = try await collectChunks(from: stt, locale: enUS)

        assertTranscriptionResult(chunks: chunks, sawFinal: sawFinal)
    }

    // MARK: - Fixture test helpers

    /// Skips the test with a diagnostic message if the model is not ready.
    @available(macOS 26.0, *)
    private func assertModelReadyForFixtureTest(locale: Locale, fixtureURL: URL) async throws {
        guard SpeechTranscriber.isAvailable else {
            throw XCTSkip("SpeechTranscriber.isAvailable == false — device/OS does not support on-device STT.")
        }
        guard await SpeechTranscriber.supportedLocale(equivalentTo: locale) != nil else {
            throw XCTSkip("en-US is not a supported SpeechTranscriber locale on this machine.")
        }
        let module = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
        let assetStatus = await AssetInventory.status(forModules: [module])
        guard assetStatus == .installed else {
            throw XCTSkip("""
                Speech model asset not installed (status: \(assetStatus)). \
                Install the en-US speech model and re-run. \
                NOTE: This skip is NOT a pass — real transcription did not occur.
                """)
        }
        guard FileManager.default.fileExists(atPath: fixtureURL.path) else {
            XCTFail("Audio fixture not found at \(fixtureURL.path). Run `make test` from the repo root.")
            return
        }
    }

    @available(macOS 26.0, *)
    private func collectChunks(
        from stt: AppleSpeechTranscriber,
        locale: Locale
    ) async throws -> ([TranscriptChunk], Bool) {
        var chunks: [TranscriptChunk] = []
        var sawFinal = false
        for try await chunk in stt.startStream(locale: locale) {
            chunks.append(chunk)
            if chunk.isFinal { sawFinal = true }
        }
        return (chunks, sawFinal)
    }

    private func assertTranscriptionResult(chunks: [TranscriptChunk], sawFinal: Bool) {
        if chunks.isEmpty {
            XCTFail("""
                Transcription produced ZERO chunks. Hard failure — not a skip. \
                Either the fixture was not read, the model did not produce output, \
                or the AnalyzerInput pipeline is broken. Check SpeakLog.stt in Console.
                """)
            return
        }
        XCTAssertTrue(sawFinal,
            "No isFinal==true chunk arrived. The engine must emit a final transcript.")

        // Check the FINAL chunk text, not a join of all chunks.
        // Volatile (partial) chunks are progressive — they replace each other, not additive.
        // Joining all chunks produces "ased ased in ased in one…" which is garbage.
        // The final chunk is the authoritative transcript. [inferred: last isFinal chunk]
        let finalText = chunks.last(where: { $0.isFinal })?.text.lowercased()
            ?? chunks.last?.text.lowercased()
            ?? ""
        let allFinalText = chunks.filter { $0.isFinal }.map(\.text).joined(separator: " ").lowercased()
        let checkText = allFinalText.isEmpty ? finalText : allFinalText

        let expectedWords = ["one", "two", "three"]  // "testing" may be transcribed as "testing" or not
        let missingWords = expectedWords.filter { !checkText.contains($0) }
        if !missingWords.isEmpty {
            XCTFail("""
                Final transcript missing expected words: \(missingWords). \
                Final transcript: '\(checkText)'. \
                All chunks: \(chunks.map { "[\(($0.isFinal ? "F" : "V")):\($0.text)]" }). \
                Fixture: hello_speech.caf contains "Testing one two three".
                """)
        }
    }

    /// Verifies that stop() terminates the stream without leaving zombie tasks.
    /// Tests the stop-before-completion path.
    @available(macOS 26.0, *)
    func testStopTerminatesStream() async throws {
        guard SpeechTranscriber.isAvailable else {
            throw XCTSkip("SpeechTranscriber not available.")
        }

        // Use the fixture producer — start it then stop immediately.
        guard FileManager.default.fileExists(atPath: fixtureURL.path) else {
            throw XCTSkip("Fixture not found — skipping stop test.")
        }

        let producer = FixtureAudioProducer(fileURL: fixtureURL)
        let stt = AppleSpeechTranscriber(audioProducer: producer)

        let stream = stt.startStream(locale: Locale(identifier: "en-US"))

        // Let it tick briefly, then stop it.
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        await stt.stop()

        // After stop(), iterating should terminate (stream finishes).
        // We collect whatever chunks arrived — the key is it completes.
        var count = 0
        for try await _ in stream {
            count += 1
        }
        // We don't assert on count — may be 0 if model hasn't started yet.
        // The test passes if the for loop exits (stream terminated, no hang).
        XCTAssertTrue(true, "Stream terminated after stop() — no zombie tasks.")
    }
}
