// SpeakCore/Engine/TranscriptionResult.swift
//
// The output of a completed capture session: the raw transcript, the optional
// AI-cleaned text, and provenance. `cleanedText` is nil when cleanup is off or
// the cleanup engine was unavailable (the session still reaches `done`).
// Signatures are verbatim from `docs/architecture.md` §6 (split into its own
// file from CaptureSession.swift for one-type-per-file clarity).
//
// ADDITIVE FIELD (audit fix — cleanup contract): `cleanupStatus` records what
// the cleanup pass actually did — `.cleaned`, `.skipped`, or
// `.fallbackRaw(reason)`. `runCleanup` never throws (failure/timeout fall back
// to raw); without this field, a timed-out 10 s pass was indistinguishable
// from a 200 ms success in `HistoryEntry`/`LatencyStats`, silently polluting
// the "cleanup ran" latency population. Persisted via `storageKey`.

import Foundation

/// The outcome of one dictation's cleanup pass.
///
/// `LatencyStats` and `HistoryEntry` use `storageKey` for persistence and
/// population partitioning: `.cleaned` rows are the "cleanup succeeded"
/// population; `.fallbackRaw` rows are counted separately (they carry real
/// user-experienced cleanup latency but are NOT successful cleanup);
/// `.skipped` rows carry `cleanupSeconds == 0` and join the raw population.
public enum CleanupStatus: Sendable, Equatable {

    /// The cleaner's `clean()` ran and produced non-empty output.
    case cleaned
    /// Cleanup never ran: cleaner nil (toggle off / level `.none`), the user
    /// picked Raw in the live panel, or the session settled before cleanup
    /// (empty transcript, agent response, executed voice action).
    case skipped
    /// Cleanup was attempted but did not produce text — the raw transcript was
    /// delivered instead. NOT an error: fallback is the designed degradation.
    case fallbackRaw(FallbackReason)

    /// Why a cleanup attempt fell back to the raw transcript.
    public enum FallbackReason: String, Sendable, Equatable, CaseIterable {
        /// `cleaner.isAvailable` returned false at cleanup time.
        case cleanerUnavailable
        /// `clean()` threw (any error — SpeakError or otherwise).
        case cleanerError
        /// `clean()` exceeded `T_cleanup` (10 s — benchmark.md §7).
        case timedOut
        /// `clean()` returned an empty string [SM-3].
        case emptyOutput
    }

    /// Stable string form persisted in `HistoryEntry.cleanupStatus`.
    /// `""` in a stored row means "pre-migration row — status unknown".
    public var storageKey: String {
        switch self {
        case .cleaned: return "cleaned"
        case .skipped: return "skipped"
        case .fallbackRaw(let reason): return "fallbackRaw.\(reason.rawValue)"
        }
    }

    /// Parse a stored `storageKey` back into a status. `nil` for empty
    /// (legacy) or unrecognized values.
    public init?(storageKey: String) {
        switch storageKey {
        case "cleaned": self = .cleaned
        case "skipped": self = .skipped
        default:
            guard storageKey.hasPrefix("fallbackRaw."),
                  let reason = FallbackReason(rawValue: String(storageKey.dropFirst("fallbackRaw.".count)))
            else { return nil }
            self = .fallbackRaw(reason)
        }
    }
}

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

    /// What the cleanup pass actually did for this dictation. `.skipped` for
    /// results produced by paths that never reach `runCleanup` (empty
    /// transcript, agent response, executed voice action, manual test
    /// construction). This — not `cleanupSeconds > 0` alone — is the honest
    /// discriminator between "cleanup succeeded" and "cleanup fell back".
    public let cleanupStatus: CleanupStatus

    public init(rawText: String,
                cleanedText: String?,
                duration: TimeInterval,
                engineId: String,
                createdAt: Date,
                latency: LatencyRecord? = nil,
                audioWasSilent: Bool = false,
                cleanupStatus: CleanupStatus = .skipped) {
        self.rawText = rawText
        self.cleanedText = cleanedText
        self.duration = duration
        self.engineId = engineId
        self.audioWasSilent = audioWasSilent
        self.createdAt = createdAt
        self.latency = latency
        self.cleanupStatus = cleanupStatus
    }
}
