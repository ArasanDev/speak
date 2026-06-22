// SpeakCore/Engine/LatencyRecord.swift
//
// Monotonic timestamps captured by `CaptureSession.stop()` for the four
// milestones in the stop→paste pipeline. Used to derive per-dictation latency
// for the Insights pane (benchmark.md §7).
//
// TERMINOLOGY (aligned to benchmark.md §7):
//   • stop→paste (raw path):  t_stop → t_pasted, cleanup was NOT run.
//                             Population: dictations where cleanedText == nil
//                             because cleaner==nil or cleaner unavailable.
//   • stop→paste (full path): t_stop → t_pasted, cleanup WAS run.
//                             Population: dictations where cleanedText != nil.
//
// [inferred] The brief's parenthetical "raw latency = t_transcript_ready→t_paste"
// differs from benchmark.md §7 "stop→paste". We follow §7 (the objective function).
// `stopToPasteSeconds` is the headline metric; the internal breakdown fields are
// diagnostics. Surfacing this for the orchestrator.
//
// THREADING: `Sendable` struct — safe to create inside the `CaptureSession` actor
// and pass out to `TranscriptionResult`.

import Foundation

/// One dictation's stop→paste timing breakdown.
///
/// All intervals are derived from monotonic uptime nanoseconds
/// (`DispatchTime.uptimeNanoseconds`) — immune to wall-clock adjustments.
public struct LatencyRecord: Sendable {

    // MARK: - Headline metric (benchmark.md §7 L_e2e)

    /// Elapsed seconds from the user-initiated stop to the text being pasted.
    /// This is the metric `benchmark.md §7` calls "stop→paste":
    ///   - raw-only target:  < 1.0 s median [benchmark.md §7 L_e2e]
    ///   - with cleanup:     < 2.0 s median [benchmark.md §7 L_e2e]
    ///
    /// Derived as `(t_pasted − t_stop)` in nanoseconds, converted to seconds.
    /// [verified: derivation is pure arithmetic on injected UInt64 timestamps]
    public let stopToPasteSeconds: Double

    // MARK: - Diagnostic breakdown

    /// Elapsed seconds from stop to the raw transcript being ready
    /// (STT stream fully drained; `transcriber.stop()` returned and the stream
    /// task completed). A subset of `stopToPasteSeconds`.
    public let transcriptReadySeconds: Double

    /// Elapsed seconds spent in the cleanup pass (`runCleanup` returned).
    /// `0.0` when cleanup did not run (cleaner nil or unavailable, or timed out
    /// with raw fallback). Use `> 0` to bucket a dictation as "cleanup ran".
    /// [decision: cleanup-timeout → `runCleanup` still returns promptly ≤ T_cleanup;
    ///  timed-out dictations are in the cleanup-population by engineId convention, but
    ///  cleanupSeconds reflects the actual elapsed time, not T_cleanup.]
    public let cleanupSeconds: Double

    // MARK: - Init (injectable for tests)

    /// Designated initialiser. Takes pre-computed monotonic nanosecond instants.
    ///
    /// - Parameters:
    ///   - tStop: Uptime nanoseconds at the moment `stop()` began.
    ///   - tTranscriptReady: Uptime nanoseconds after STT stream drained.
    ///   - tCleanupDone: Uptime nanoseconds after `runCleanup()` returned.
    ///     Pass the same value as `tTranscriptReady` when cleanup was skipped.
    ///   - tPasted: Uptime nanoseconds after the paste step completed.
    ///     Pass the same value as `tCleanupDone` when no inserter is wired.
    public init(tStop: UInt64, tTranscriptReady: UInt64, tCleanupDone: UInt64, tPasted: UInt64) {
        // Guard against counter wrap (≈580 years at 1 GHz — theoretical, not a live concern)
        // and out-of-order timestamps (defensive; should not happen on a single actor).
        let nanos = { (start: UInt64, end: UInt64) -> Double in
            end >= start ? Double(end - start) : 0
        }

        stopToPasteSeconds     = nanos(tStop, tPasted)         / 1_000_000_000
        transcriptReadySeconds = nanos(tStop, tTranscriptReady) / 1_000_000_000
        // cleanupSeconds is the *additional* time spent in the cleanup pass after
        // the transcript was ready; it is zero when tCleanupDone == tTranscriptReady.
        cleanupSeconds         = nanos(tTranscriptReady, tCleanupDone) / 1_000_000_000
    }
}
