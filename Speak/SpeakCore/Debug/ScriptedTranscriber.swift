// SpeakCore/Debug/ScriptedTranscriber.swift
//
// DEBUG-ONLY: A scripted `Transcribing` fake that emits a canned sequence of
// `TranscriptChunk`s (progressive partials, then one final chunk) on a timer —
// zero microphone, zero SpeechAnalyzer involvement. Backs
// `--debug-open simulate-dictation-scripted:<text>` so the real
// CaptureSession → cleanup → paste → history → overlay pipeline can be
// exercised repeatedly and rapidly with arbitrary text, without speaking and
// without re-recording fixture audio for every phrase under test.
//
// This file is entirely wrapped in `#if DEBUG` so zero bytes reach the release
// binary — same contract as `FixtureAudioProducer.swift`.

#if DEBUG
import Foundation
import os

// MARK: - ScriptedTranscript

/// The canned content a `ScriptedTranscriber` plays back.
///
/// `.failure` is test-only — nothing in `DebugLaunchDispatcher`'s CLI parsing
/// constructs it, so it's reachable only from unit tests that build a
/// `ScriptedTranscriber` directly, not from `--debug-open`.
public enum ScriptedTranscript: Sendable {
    /// Reveal `text` word-by-word as growing partial chunks (mimics real
    /// streaming STT partial-result arrival), then emit one final chunk
    /// holding the full text.
    case progressiveReveal(text: String, wordDelayNanoseconds: UInt64)

    /// Emit no chunks and throw immediately — exercises the `.error` overlay
    /// / error-handling path without needing a real STT failure.
    case failure(ScriptedTranscriberError)

    fileprivate func emit(
        into continuation: AsyncThrowingStream<TranscriptChunk, Error>.Continuation
    ) async throws {
        switch self {
        case .progressiveReveal(let text, let wordDelayNanoseconds):
            let words = text.split(separator: " ").map(String.init)
            guard !words.isEmpty else { return }
            var accumulated = ""
            for (index, word) in words.enumerated() {
                try Task.checkCancellation()
                accumulated += (accumulated.isEmpty ? "" : " ") + word
                let isLast = index == words.count - 1
                continuation.yield(TranscriptChunk(text: accumulated, isFinal: isLast, timestamp: Date()))
                if !isLast {
                    try await Task.sleep(nanoseconds: wordDelayNanoseconds)
                }
            }

        case .failure(let error):
            throw error
        }
    }
}

/// The error thrown by `ScriptedTranscript.failure`.
public struct ScriptedTranscriberError: Error, Sendable, CustomStringConvertible {
    public let reason: String
    public init(reason: String) { self.reason = reason }
    public var description: String { reason }
}

// MARK: - ScriptedTranscriber

/// DEBUG-ONLY `Transcribing` conformance that plays back a `ScriptedTranscript`
/// instead of transcribing real audio. Default word-reveal cadence (80ms/word)
/// approximates a comfortable human speaking pace so downstream partial-text
/// rendering (overlay, pet reactions) exercises realistically.
public final class ScriptedTranscriber: Transcribing, @unchecked Sendable {

    public let id = "scripted-fixture"

    /// Default per-word reveal delay — approximates ~150 wpm speech.
    public static let defaultWordDelayNanoseconds: UInt64 = 80_000_000

    private let script: ScriptedTranscript
    private let log = SpeakLog.stt
    private var streamTask: Task<Void, Never>?

    public init(script: ScriptedTranscript) {
        self.script = script
    }

    /// Convenience: progressively reveal `text` word-by-word, then finalize.
    public convenience init(
        revealingWordsIn text: String,
        wordDelayNanoseconds: UInt64 = ScriptedTranscriber.defaultWordDelayNanoseconds
    ) {
        self.init(script: .progressiveReveal(text: text, wordDelayNanoseconds: wordDelayNanoseconds))
    }

    public func startStream(locale: Locale) -> AsyncThrowingStream<TranscriptChunk, Error> {
        AsyncThrowingStream { [script, log] continuation in
            let task = Task {
                do {
                    try await script.emit(into: continuation)
                    continuation.finish()
                } catch {
                    log.error("ScriptedTranscriber: script threw — \(String(describing: error), privacy: .public)")
                    continuation.finish(throwing: error)
                }
            }
            self.streamTask = task
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func stop() async {
        streamTask?.cancel()
        streamTask = nil
        log.info("ScriptedTranscriber: stop() called.")
    }
}
#endif
