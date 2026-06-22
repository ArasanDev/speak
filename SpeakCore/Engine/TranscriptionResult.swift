// SpeakCore/Engine/TranscriptionResult.swift
//
// The output of a completed capture session: the raw transcript, the optional
// AI-cleaned text, and provenance. `cleanedText` is nil when cleanup is off or
// the cleanup engine was unavailable (the session still reaches `done`).
// Signatures are verbatim from `docs/architecture.md` §6 (split into its own
// file from CaptureSession.swift for one-type-per-file clarity).

import Foundation

public struct TranscriptionResult: Sendable {
    public let rawText: String
    public let cleanedText: String?   // nil if LLM cleanup off or unavailable
    public let duration: TimeInterval
    public let engineId: String
    public let createdAt: Date
    /// Stop→paste latency breakdown. `nil` for results produced outside the
    /// live pipeline (tests, fixture runs without an inserter). When present,
    /// `latency.stopToPasteSeconds` is the benchmark.md §7 `L_e2e` measurement.
    public let latency: LatencyRecord?

    public init(rawText: String,
                cleanedText: String?,
                duration: TimeInterval,
                engineId: String,
                createdAt: Date,
                latency: LatencyRecord? = nil) {
        self.rawText = rawText
        self.cleanedText = cleanedText
        self.duration = duration
        self.engineId = engineId
        self.createdAt = createdAt
        self.latency = latency
    }
}
