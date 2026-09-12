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

    /// True when the session ended with an empty transcript AND the input
    /// never crossed the audible floor — i.e. the mic delivered silence
    /// (muted headset, wrong pinned device, dead input). Distinguishes "you
    /// didn't speak" from "the mic heard nothing"; the caller should surface
    /// this instead of quietly completing.
    /// [fix: silent-mic sessions surfaced as silent .done]
    public let audioWasSilent: Bool

    public init(rawText: String,
                cleanedText: String?,
                duration: TimeInterval,
                engineId: String,
                createdAt: Date,
                latency: LatencyRecord? = nil,
                audioWasSilent: Bool = false) {
        self.rawText = rawText
        self.cleanedText = cleanedText
        self.duration = duration
        self.engineId = engineId
        self.audioWasSilent = audioWasSilent
        self.createdAt = createdAt
        self.latency = latency
    }
}
