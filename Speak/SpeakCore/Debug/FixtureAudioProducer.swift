// SpeakCore/Debug/FixtureAudioProducer.swift
//
// DEBUG-ONLY: A fixture-backed AudioBufferProducing implementation that streams
// buffers from a CAF audio file on disk. Used by the `--debug-open simulate-dictation`
// verification path to exercise the real engine pipeline without live mic input.
//
// This file is entirely wrapped in `#if DEBUG` so zero bytes reach the release binary.
//
// Fixture resolution strategy:
//   Source-tree relative path (`#filePath`-anchored) — the fixture is not
//   bundled into Speak.app, so the DEBUG app resolves it from the checkout.
//   The CAF file is Speak/Tests/SpeakTests/Fixtures/hello_speech.caf.
//   [decision: source-tree-relative path for dev builds; moat-safe since DEBUG only]

#if DEBUG
@preconcurrency import AVFoundation
import os

// MARK: - FixtureAudioProducer

/// Streams PCM buffers from a CAF fixture file, matching the interface expected
/// by `AppleSpeechTranscriber(audioProducer:)`. Semantically equivalent to the
/// test target's `SpeechTranscriberTests.FixtureAudioProducer`; promoted here
/// under `#if DEBUG` so the app target can reference it without touching test code.
public final class FixtureAudioProducer: AudioBufferProducing, @unchecked Sendable {

    /// URL of the audio fixture file to stream.
    public let fileURL: URL

    private var continuation: AsyncThrowingStream<AVAudioPCMBuffer, Error>.Continuation?

    private let log = SpeakLog.stt

    /// Create a producer backed by the given file.
    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// Convenience: resolve the `hello_speech.caf` fixture from the source tree.
    ///
    /// Walks up from this source file's directory to find
    /// `Tests/SpeakTests/Fixtures/hello_speech.caf` under `Speak/`. Returns
    /// `nil` if the file does not exist at the expected location.
    ///
    /// [decision: source-tree-relative path via `#filePath`; works for dev DEBUG
    ///  builds on the same machine; not a release concern (DEBUG only)]
    public static func helloSpeechFixture() -> URL? {
        // #filePath resolves to SpeakCore/Debug/FixtureAudioProducer.swift at build time.
        // Walk up three levels: Debug/ → SpeakCore/ → Speak/ — then down into
        // Tests/SpeakTests/Fixtures/. [fix: stale path — the previous walk
        // expected repoRoot/SpeakTests but tests live under Speak/Tests/.]
        let thisFile = URL(fileURLWithPath: #filePath)
        let speakDir = thisFile
            .deletingLastPathComponent() // Debug/
            .deletingLastPathComponent() // SpeakCore/
            .deletingLastPathComponent() // Speak/
        let fixtureURL = speakDir
            .appendingPathComponent("Tests")
            .appendingPathComponent("SpeakTests")
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("hello_speech.caf")
        guard FileManager.default.fileExists(atPath: fixtureURL.path) else {
            return nil
        }
        return fixtureURL
    }

    // MARK: - AudioBufferProducing

    public func start() throws -> AsyncThrowingStream<AVAudioPCMBuffer, Error> {
        let file = try AVAudioFile(forReading: fileURL)
        let format = file.processingFormat
        let frameCount = AVAudioFrameCount(file.length)
        // Chunk size matches AudioCapture.Constants.tapBufferSize to exercise the
        // same AnalyzerInput path as live audio. [decision: 4096 frames, matching
        // AudioCapture.Constants.tapBufferSize documented in SpeechTranscriberTests]
        let chunkSize: AVAudioFrameCount = 4096

        let (stream, cont) = AsyncThrowingStream<AVAudioPCMBuffer, Error>.makeStream()
        self.continuation = cont

        let log = self.log

        Task.detached(priority: .userInitiated) {
            var offset: AVAudioFramePosition = 0
            while offset < AVAudioFramePosition(frameCount) {
                let remaining = AVAudioFrameCount(AVAudioFramePosition(frameCount) - offset)
                let thisChunk = min(chunkSize, remaining)
                guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: thisChunk) else {
                    log.error("FixtureAudioProducer: failed to allocate PCM buffer at offset \(offset, privacy: .public).")
                    break
                }
                do {
                    try file.read(into: buffer, frameCount: thisChunk)
                } catch {
                    log.error("FixtureAudioProducer: file read error — \(error.localizedDescription, privacy: .public)")
                    break
                }
                cont.yield(buffer)
                offset += AVAudioFramePosition(buffer.frameLength)
                // 1 ms between chunks to allow async iteration without blocking.
                // [decision: 1ms inter-chunk delay, matches SpeechTranscriberTests]
                try? await Task.sleep(nanoseconds: 1_000_000)
            }
            cont.finish()
            log.info("FixtureAudioProducer: finished streaming \(frameCount, privacy: .public) frames.")
        }

        return stream
    }

    public func stop() {
        continuation?.finish()
        continuation = nil
        log.info("FixtureAudioProducer: stop() called.")
    }
}
#endif
