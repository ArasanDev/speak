// SpeakCore/Engine/LatencyRecord.swift
//
// Per-dictation stop→paste timing breakdown captured by `CaptureSession.stop()`.
// Used to derive latency statistics for the Insights pane (benchmark.md §7).
//
// TERMINOLOGY (aligned to benchmark.md §7):
//   The headline metric is `stopToPasteSeconds` for BOTH populations:
//   • stop→paste (raw path):     t_stop → t_pasted, cleanup was NOT run.
//                                Population: `cleanupSeconds == 0.0` (exact sentinel).
//   • stop→paste (full path):    t_stop → t_pasted, cleanup WAS run.
//                                Population: `cleanupSeconds > 0`.
//
// SENTINEL DESIGN (P13):
//   `cleanupSeconds` is NOT a DispatchTime delta between two DispatchTime.now() calls
//   in `stop()`. It comes from `runCleanup()`, which returns the **exact literal 0.0**
//   for the cleaner-nil and unavailable paths — not a measured interval. This is the
//   only way to make the `== 0` discriminator in `LatencyStats` reliable in production.
//   If this were a live delta, actor re-scheduling jitter would produce ~1µs on the
//   no-cleanup paths, and the "raw" population would appear empty (every entry misclassified
//   as cleanup). [decision P13: sentinel from runCleanup, not a delta in stop().]
//
// [inferred] The brief's item-1 parenthetical "raw latency = t_transcript_ready→t_paste"
// differs from benchmark.md §7 "stop→paste". We follow §7 (the objective function).
// Surfaced for the orchestrator.
//
// THREADING: `Sendable` struct — safe to create inside the `CaptureSession` actor
// and pass out to `TranscriptionResult`.

import Foundation

/// One dictation's stop→paste timing breakdown.
///
/// `stopToPasteSeconds` and `transcriptReadySeconds` are derived from monotonic
/// uptime nanoseconds (`DispatchTime.uptimeNanoseconds`) — immune to wall-clock
/// adjustments. `cleanupSeconds` is the value returned by `runCleanup()`, which
/// may be `0.0` exactly (sentinel: cleanup did not run) or a measured interval
/// (cleanup ran — success, error, or timeout). See module-level note.
public struct LatencyRecord: Sendable {

    // MARK: - Headline metric (benchmark.md §7 L_e2e)

    /// Elapsed seconds from the user-initiated stop to the text being pasted.
    /// This is the metric `benchmark.md §7` calls "stop→paste":
    ///   - raw-only target:  < 1.0 s median [benchmark.md §7 L_e2e]
    ///   - with cleanup:     < 2.0 s median [benchmark.md §7 L_e2e]
    ///
    /// Derived as `(t_pasted − t_stop)` in nanoseconds, converted to seconds.
    /// [verified: derivation is pure arithmetic on injected timestamps]
    public let stopToPasteSeconds: Double

    // MARK: - Diagnostic breakdown

    /// Elapsed seconds from stop to the raw transcript being ready
    /// (STT stream fully drained; `transcriber.stop()` returned and the stream
    /// task completed). A subset of `stopToPasteSeconds`.
    public let transcriptReadySeconds: Double

    /// Seconds spent in the on-device cleanup pass.
    ///
    /// **Sentinel contract**: `0.0` (exact) means cleanup did NOT run (cleaner nil
    /// or unavailable). This is the literal value returned by `runCleanup()` for
    /// no-cleanup paths — not a clock measurement. `LatencyStats` partitions
    /// populations using `== 0 / > 0`; this invariant must be preserved.
    ///
    /// `> 0` means the cleaner's `clean()` was called; value is elapsed seconds
    /// from before the continuation to after it returned. Timed-out runs carry
    /// their actual elapsed time (≤ T_cleanup = 10 s [benchmark.md §7]).
    public let cleanupSeconds: Double

    // MARK: - Init (injectable for tests)

    /// Designated initialiser.
    ///
    /// - Parameters:
    ///   - tStop: Uptime nanoseconds at the moment `stop()` began.
    ///   - tTranscriptReady: Uptime nanoseconds after STT stream drained.
    ///   - tPasted: Uptime nanoseconds after the paste step completed.
    ///   - cleanupSeconds: Value from `runCleanup()`. Pass `0.0` when cleanup
    ///     did not run (the sentinel that drives population partitioning in `LatencyStats`).
    public init(tStop: UInt64, tTranscriptReady: UInt64, tPasted: UInt64, cleanupSeconds: Double) {
        // Guard against counter wrap (≈580 years at 1 GHz — theoretical, not a live concern)
        // and out-of-order timestamps (defensive; should not happen on a single actor).
        let nanos = { (start: UInt64, end: UInt64) -> Double in
            end >= start ? Double(end - start) : 0
        }

        stopToPasteSeconds     = nanos(tStop, tPasted)          / 1_000_000_000
        transcriptReadySeconds = nanos(tStop, tTranscriptReady) / 1_000_000_000
        self.cleanupSeconds    = max(0, cleanupSeconds)  // floor at 0 for safety
    }
}
