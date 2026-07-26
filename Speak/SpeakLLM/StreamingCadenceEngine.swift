// SpeakLLM/StreamingCadenceEngine.swift
//
// A pure-logic pacing layer that sits between StreamingChatClient's raw SSE
// chunks and the UI. Buffers word-level tokens and re-emits them at a
// composed cadence: ~45 tok/s floor with 80ms micro-pauses at sentence
// boundaries and commas. This makes streaming feel deliberately authored
// rather than machine-vomited.
//
// No UI dependencies. No networking. Pure timing logic.

import Foundation

// MARK: - StreamingCadenceEngine

/// Paces token delivery to feel like deliberate composition.
///
/// Consumes a raw AsyncThrowingStream of text chunks (word-level from the
/// inference server) and produces a paced stream with:
/// - A minimum inter-token interval (22ms ≈ 45 tok/s ceiling)
/// - Extended pauses (80ms) after sentence-terminal punctuation
/// - Burst smoothing: if the source is slower than the ceiling, zero
///   artificial latency is added (token-bucket: ceiling not floor)
public actor StreamingCadenceEngine {

    // MARK: - Configuration

    /// Minimum interval between token emissions in nanoseconds.
    /// 22ms ≈ 45 tokens/second — the "composed typing" rate.
    private let minIntervalNanos: UInt64 = 22_000_000

    /// Extended pause after sentence-terminal punctuation (. ! ?).
    private let sentencePauseNanos: UInt64 = 80_000_000

    /// Shorter pause after commas and semicolons.
    private let clausePauseNanos: UInt64 = 45_000_000

    // MARK: - Public API

    public init() {}

    /// Paces a raw token stream into a composed delivery stream.
    ///
    /// - Parameter source: The raw word-level chunks from StreamingChatClient.
    /// - Returns: A paced stream with the same text content but deliberate timing.
    public func pace(
        _ source: AsyncThrowingStream<String, Error>
    ) -> AsyncThrowingStream<String, Error> {
        let minInterval = minIntervalNanos
        let sentencePause = sentencePauseNanos
        let clausePause = clausePauseNanos

        return AsyncThrowingStream { continuation in
            let task = Task {
                var lastEmission = ContinuousClock.now

                do {
                    for try await chunk in source {
                        if Task.isCancelled {
                            continuation.finish()
                            return
                        }

                        let now = ContinuousClock.now
                        let elapsed = lastEmission.duration(to: now)
                        let elapsedNanos = UInt64(elapsed.components.seconds * 1_000_000_000
                            + elapsed.components.attoseconds / 1_000_000_000)

                        let requiredPause = Self.pauseDuration(
                            for: chunk,
                            minInterval: minInterval,
                            sentencePause: sentencePause,
                            clausePause: clausePause
                        )

                        if elapsedNanos < requiredPause {
                            let sleepNanos = requiredPause - elapsedNanos
                            try await Task.sleep(nanoseconds: sleepNanos)
                        }

                        lastEmission = ContinuousClock.now
                        continuation.yield(chunk)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    // MARK: - Private

    private static func pauseDuration(
        for chunk: String,
        minInterval: UInt64,
        sentencePause: UInt64,
        clausePause: UInt64
    ) -> UInt64 {
        let trimmed = chunk.trimmingCharacters(in: .whitespaces)
        if trimmed.hasSuffix(".") || trimmed.hasSuffix("!") || trimmed.hasSuffix("?") {
            return sentencePause
        }
        if trimmed.hasSuffix(",") || trimmed.hasSuffix(";") || trimmed.hasSuffix(":") {
            return clausePause
        }
        return minInterval
    }
}
