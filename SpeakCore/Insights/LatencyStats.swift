// SpeakCore/Insights/LatencyStats.swift
//
// A pure, fully unit-testable value type that derives stop→paste latency
// statistics from a slice of dictation history.
//
// METRIC DEFINITIONS (aligned to benchmark.md §7):
//   The headline metric is always the SAME interval — t_stop to t_pasted —
//   segmented by whether cleanup ran:
//
//   • rawMedian / rawP95:
//       Population: entries where `stopToPasteSeconds > 0` AND `cleanupSeconds == 0`.
//       (Cleanup did not run: cleaner nil, unavailable, or cleanupLevel=.none.)
//       Budget: < 1.0 s median [benchmark.md §7 L_e2e, raw-only path].
//
//   • cleanupMedian / cleanupP95:
//       Population: entries where `stopToPasteSeconds > 0` AND `cleanupSeconds > 0`.
//       (Cleanup ran — the Foundation Models pass contributed time.)
//       Budget: < 2.0 s median [benchmark.md §7 L_e2e, incl. on-device cleanup].
//
//   Entries where `stopToPasteSeconds == 0` are pre-P13 rows or headless-test
//   rows with no live inserter — excluded from both populations.
//
// [inferred] The brief's item-1 parenthetical "raw latency = t_transcript_ready→t_paste"
// differs from benchmark.md §7 "stop→paste". We follow §7 (the objective function).
// Surfaced for the orchestrator.
//
// THREADING: `Sendable` struct — safe to create on any actor and publish to main.

import Foundation

// MARK: - Latency budget constants (benchmark.md §7)

/// Stop→paste raw-path median budget — 1.0 s [benchmark.md §7 L_e2e].
public let latencyBudgetRawMedianSeconds: Double = 1.0

/// Stop→paste full-path (incl. cleanup) median budget — 2.0 s [benchmark.md §7 L_e2e].
public let latencyBudgetCleanupMedianSeconds: Double = 2.0

// MARK: - LatencyStats

/// Aggregated stop→paste latency statistics derived from a slice of `HistoryEntry` values.
public struct LatencyStats: Sendable, Equatable {

    // MARK: - Raw-path population (cleanup did NOT run)

    /// Median stop→paste seconds over dictations where cleanup did not run.
    /// `nil` when there are no raw-path samples (no dictations yet, or all used cleanup).
    public let rawMedian: Double?

    /// p95 stop→paste seconds over the raw-path population. `nil` when n < 1.
    /// [decision P13: percentile clamped to last element when n*0.95 rounds past the end]
    public let rawP95: Double?

    /// Number of raw-path samples in the computed window.
    public let rawSampleCount: Int

    // MARK: - Cleanup population (cleanup DID run)

    /// Median stop→paste seconds over dictations where cleanup ran.
    /// `nil` when there are no cleanup-path samples.
    public let cleanupMedian: Double?

    /// p95 stop→paste seconds over the cleanup-path population. `nil` when n < 1.
    public let cleanupP95: Double?

    /// Number of cleanup-path samples in the computed window.
    public let cleanupSampleCount: Int

    // MARK: - Init

    /// Creates a `LatencyStats` from a flat list of history entries.
    ///
    /// - Parameter entries: All entries to aggregate — caller decides the fetch window.
    public init(entries: [HistoryEntry]) {
        // Partition into populations.
        // Entries where stopToPasteSeconds == 0 are pre-P13 or headless-test rows — excluded.
        let measured = entries.filter { $0.stopToPasteSeconds > 0 }
        let rawSamples     = measured.filter { $0.cleanupSeconds == 0 }.map(\.stopToPasteSeconds)
        let cleanupSamples = measured.filter { $0.cleanupSeconds  > 0 }.map(\.stopToPasteSeconds)

        rawSampleCount     = rawSamples.count
        cleanupSampleCount = cleanupSamples.count

        (rawMedian, rawP95)         = LatencyStats.percentiles(rawSamples)
        (cleanupMedian, cleanupP95) = LatencyStats.percentiles(cleanupSamples)
    }

    // MARK: - Private helpers

    /// Compute median and p95 from a sample array.
    ///
    /// Returns `(nil, nil)` for an empty array.
    /// p95 is clamped to the last element when n*0.95 rounds past bounds — safe on n==1.
    ///
    /// [verified: arithmetic derivation, tested in LatencyRecordTests]
    private static func percentiles(_ samples: [Double]) -> (median: Double?, p95: Double?) {
        guard !samples.isEmpty else { return (nil, nil) }
        let sorted = samples.sorted()
        let n = sorted.count
        let medianIdx = n / 2
        let p95Idx    = min(n - 1, Int((Double(n) * 0.95).rounded(.up)) - 1)
        return (sorted[medianIdx], sorted[max(0, p95Idx)])
    }
}
