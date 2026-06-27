// SpeakTests/LatencyRecordTests.swift
//
// Unit tests for `LatencyRecord` derivation math and `LatencyStats` aggregation.
//
// All tests are PURE: no I/O, no actors, no clock calls — timestamps and
// cleanupSeconds are injected directly. This matches the InsightsStats pattern.
//
// COVERAGE:
//   LatencyRecord:
//     - Normal derivation from well-ordered timestamps + injected cleanupSeconds.
//     - stopToPasteSeconds spans the full t_stop→t_pasted range.
//     - cleanupSeconds passthrough: 0.0 (sentinel) and > 0 (measured).
//     - Defensive: out-of-order timestamps → 0 (no crash).
//     - Negative cleanupSeconds floored to 0.
//
//   LatencyStats:
//     - Empty input → all nil / zero counts.
//     - Single raw-only sample.
//     - Single cleanup sample.
//     - Zero-stopToPaste entries excluded.
//     - rawMedian/rawP95 correct on multiple samples.
//     - cleanupMedian/cleanupP95 correct on multiple samples.
//     - Mixed population: raw vs cleanup correctly partitioned.
//     - Even vs odd sample count: median picks middle correctly.
//     - p95 clamped to last element on small n.
//     - cleanupSeconds == 0 (sentinel) → raw bucket; > 0 → cleanup bucket.
//
// HONESTY BOUNDARY:
//   These tests verify pure arithmetic derivation. Live wall-clock accuracy
//   (real mic + paste + FM) requires human verification [deferred — human-verification.md].

@testable import SpeakCore
import XCTest

@available(macOS 26.0, *)
final class LatencyRecordTests: XCTestCase {

    // MARK: - Helpers

    /// Build a `HistoryEntry` with injected latency values.
    private func entry(
        stopToPaste: Double = 0,
        cleanup: Double = 0
    ) -> HistoryEntry {
        HistoryEntry(
            rawText: "test",
            cleanedText: nil,
            engineId: "test",
            stopToPasteSeconds: stopToPaste,
            cleanupSeconds: cleanup
        )
    }

    // MARK: - LatencyRecord: derivation math

    func testLatencyRecord_normalDerivation_withCleanup() {
        // Exact nanosecond values:
        //   t_stop            =           0 ns  →  0.0 s
        //   t_transcript_ready = 500_000_000 ns  →  0.5 s
        //   t_pasted          = 1_600_000_000 ns →  1.6 s
        //   cleanupSeconds    =            0.9 s  (injected from runCleanup)
        //
        // Expected derivations:
        //   stopToPasteSeconds     = 1.6 - 0.0 = 1.6 s
        //   transcriptReadySeconds = 0.5 - 0.0 = 0.5 s
        //   cleanupSeconds         = 0.9 s (passthrough from runCleanup)
        let record = LatencyRecord(
            tStop: 0,
            tTranscriptReady: 500_000_000,
            tPasted: 1_600_000_000,
            cleanupSeconds: 0.9
        )
        XCTAssertEqual(record.stopToPasteSeconds, 1.6, accuracy: 0.001,
            "stopToPasteSeconds must span t_stop to t_pasted")
        XCTAssertEqual(record.transcriptReadySeconds, 0.5, accuracy: 0.001,
            "transcriptReadySeconds must span t_stop to t_transcriptReady")
        XCTAssertEqual(record.cleanupSeconds, 0.9, accuracy: 0.001,
            "cleanupSeconds must be the injected value from runCleanup")
    }

    func testLatencyRecord_noCleanup_sentinelZero() {
        // When cleanup did not run, cleanupSeconds is exactly 0.0 (sentinel).
        let record = LatencyRecord(
            tStop: 1_000_000_000,
            tTranscriptReady: 1_300_000_000,   // +300ms
            tPasted: 1_350_000_000,            // +50ms paste
            cleanupSeconds: 0.0                // sentinel: cleanup did not run
        )
        XCTAssertEqual(record.cleanupSeconds, 0.0,
            "cleanupSeconds must be exactly 0.0 when cleanup did not run (sentinel)")
        XCTAssertEqual(record.stopToPasteSeconds, 0.35, accuracy: 0.001,
            "stopToPasteSeconds still reflects the full stop→paste interval")
        XCTAssertEqual(record.transcriptReadySeconds, 0.3, accuracy: 0.001)
    }

    func testLatencyRecord_outOfOrderTimestamps_noCrash() {
        // t_pasted < t_stop → should not crash, should produce 0 not negative.
        let record = LatencyRecord(
            tStop: 1_000_000_000,
            tTranscriptReady: 900_000_000,    // out of order (< t_stop)
            tPasted: 700_000_000,             // out of order
            cleanupSeconds: 0.0
        )
        XCTAssertEqual(record.stopToPasteSeconds, 0,
            "Out-of-order timestamps must produce 0, not negative or crash")
        XCTAssertEqual(record.transcriptReadySeconds, 0,
            "Out-of-order tTranscriptReady must produce 0")
    }

    func testLatencyRecord_allZeroTimestamps_zeroResult() {
        let record = LatencyRecord(tStop: 0, tTranscriptReady: 0, tPasted: 0, cleanupSeconds: 0)
        XCTAssertEqual(record.stopToPasteSeconds, 0)
        XCTAssertEqual(record.transcriptReadySeconds, 0)
        XCTAssertEqual(record.cleanupSeconds, 0)
    }

    func testLatencyRecord_exactOneSecond() {
        // Sanity check: exactly 1,000,000,000 ns → 1.0 s.
        let record = LatencyRecord(
            tStop: 0,
            tTranscriptReady: 1_000_000_000,
            tPasted: 1_000_000_000,
            cleanupSeconds: 0.0
        )
        XCTAssertEqual(record.stopToPasteSeconds, 1.0, accuracy: 0.000_001,
            "1,000,000,000 ns must convert to exactly 1.0 s")
    }

    func testLatencyRecord_negativeCleanupSeconds_flooredToZero() {
        // Defensive: runCleanup should never return negative, but guard at the boundary.
        let record = LatencyRecord(
            tStop: 0,
            tTranscriptReady: 100_000_000,
            tPasted: 200_000_000,
            cleanupSeconds: -0.5
        )
        XCTAssertEqual(record.cleanupSeconds, 0,
            "Negative cleanupSeconds must be floored to 0")
    }

    // MARK: - LatencyStats: empty input

    func testLatencyStats_empty_allNilZeroCounts() {
        let stats = LatencyStats(entries: [])
        XCTAssertNil(stats.rawMedian)
        XCTAssertNil(stats.rawP95)
        XCTAssertEqual(stats.rawSampleCount, 0)
        XCTAssertNil(stats.cleanupMedian)
        XCTAssertNil(stats.cleanupP95)
        XCTAssertEqual(stats.cleanupSampleCount, 0)
    }

    func testLatencyStats_zeroStopToPaste_excluded() {
        // Entries with stopToPasteSeconds == 0 are pre-P13 rows — must be excluded.
        let entries = [
            entry(stopToPaste: 0, cleanup: 0),
            entry(stopToPaste: 0, cleanup: 0.5)
        ]
        let stats = LatencyStats(entries: entries)
        XCTAssertNil(stats.rawMedian, "Zero stopToPasteSeconds rows must be excluded")
        XCTAssertNil(stats.cleanupMedian, "Zero stopToPasteSeconds rows must be excluded")
        XCTAssertEqual(stats.rawSampleCount, 0)
        XCTAssertEqual(stats.cleanupSampleCount, 0)
    }

    // MARK: - LatencyStats: sentinel discrimination

    func testLatencyStats_sentinelZero_bucketedAsRaw() {
        // cleanupSeconds == 0.0 (exact sentinel from runCleanup off/unavailable path)
        // must be bucketed as raw, not cleanup. This is the core correctness test.
        let entries = [entry(stopToPaste: 0.7, cleanup: 0.0)]
        let stats = LatencyStats(entries: entries)
        XCTAssertEqual(stats.rawSampleCount, 1,
            "Sentinel cleanupSeconds==0 must be bucketed as raw")
        XCTAssertEqual(stats.cleanupSampleCount, 0,
            "Sentinel cleanupSeconds==0 must NOT appear in cleanup population")
    }

    func testLatencyStats_nonZeroCleanup_bucketedAsCleanup() {
        // cleanupSeconds > 0 (cleanup ran) must be bucketed as cleanup, not raw.
        let entries = [entry(stopToPaste: 1.2, cleanup: 0.8)]
        let stats = LatencyStats(entries: entries)
        XCTAssertEqual(stats.rawSampleCount, 0,
            "Entries with cleanupSeconds > 0 must NOT appear in raw population")
        XCTAssertEqual(stats.cleanupSampleCount, 1,
            "Entries with cleanupSeconds > 0 must be bucketed as cleanup")
    }

    // MARK: - LatencyStats: single samples

    func testLatencyStats_singleRawSample() {
        let entries = [entry(stopToPaste: 0.8, cleanup: 0)]
        let stats = LatencyStats(entries: entries)
        XCTAssertEqual(stats.rawMedian ?? 0, 0.8, accuracy: 0.001)
        XCTAssertEqual(stats.rawP95 ?? 0, 0.8, accuracy: 0.001,
            "p95 of a single element must equal that element")
        XCTAssertEqual(stats.rawSampleCount, 1)
        XCTAssertNil(stats.cleanupMedian)
    }

    func testLatencyStats_singleCleanupSample() {
        let entries = [entry(stopToPaste: 1.5, cleanup: 0.7)]
        let stats = LatencyStats(entries: entries)
        XCTAssertNil(stats.rawMedian)
        XCTAssertEqual(stats.cleanupMedian ?? 0, 1.5, accuracy: 0.001)
        XCTAssertEqual(stats.cleanupP95 ?? 0, 1.5, accuracy: 0.001)
        XCTAssertEqual(stats.cleanupSampleCount, 1)
    }

    // MARK: - LatencyStats: population partitioning

    func testLatencyStats_mixedPopulation_correctlyPartitioned() {
        let entries = [
            entry(stopToPaste: 0.5, cleanup: 0),    // raw (sentinel)
            entry(stopToPaste: 0.9, cleanup: 0),    // raw (sentinel)
            entry(stopToPaste: 1.2, cleanup: 0.5),  // cleanup
            entry(stopToPaste: 1.8, cleanup: 0.9)   // cleanup
        ]
        let stats = LatencyStats(entries: entries)

        // Raw population: [0.5, 0.9], sorted median = 0.9 (n/2 = index 1 of 2-element)
        XCTAssertEqual(stats.rawSampleCount, 2)
        XCTAssertEqual(stats.rawMedian ?? 0, 0.9, accuracy: 0.001,
            "Median of [0.5, 0.9] at index 1 should be 0.9")

        // Cleanup population: [1.2, 1.8], sorted median = 1.8 (n/2 = index 1 of 2-element)
        XCTAssertEqual(stats.cleanupSampleCount, 2)
        XCTAssertEqual(stats.cleanupMedian ?? 0, 1.8, accuracy: 0.001,
            "Median of [1.2, 1.8] at index 1 should be 1.8")
    }

    func testLatencyStats_rawMedian_oddCount() {
        // Odd n=3: median is the middle element (index 1).
        let entries = [
            entry(stopToPaste: 0.3, cleanup: 0),
            entry(stopToPaste: 0.7, cleanup: 0),
            entry(stopToPaste: 1.1, cleanup: 0)
        ]
        let stats = LatencyStats(entries: entries)
        XCTAssertEqual(stats.rawMedian ?? 0, 0.7, accuracy: 0.001,
            "Median of [0.3, 0.7, 1.1] must be 0.7 (middle element)")
    }

    func testLatencyStats_rawMedian_evenCount_higherMiddle() {
        // Even n=4: index n/2 = 2 → third element (0-indexed) of sorted array.
        // [0.2, 0.5, 0.8, 1.0] → index 2 = 0.8
        let entries = [
            entry(stopToPaste: 0.5, cleanup: 0),
            entry(stopToPaste: 0.2, cleanup: 0),
            entry(stopToPaste: 1.0, cleanup: 0),
            entry(stopToPaste: 0.8, cleanup: 0)
        ]
        let stats = LatencyStats(entries: entries)
        XCTAssertEqual(stats.rawMedian ?? 0, 0.8, accuracy: 0.001,
            "Median of sorted [0.2, 0.5, 0.8, 1.0] at index 2 must be 0.8")
    }

    func testLatencyStats_p95_clampedOnSmallN() {
        // n=2: Int(2 * 0.95 rounded .up) - 1 = Int(2)-1 = 1 → index 1 (last).
        let entries = [
            entry(stopToPaste: 0.4, cleanup: 0),
            entry(stopToPaste: 0.9, cleanup: 0)
        ]
        let stats = LatencyStats(entries: entries)
        XCTAssertEqual(stats.rawP95 ?? 0, 0.9, accuracy: 0.001,
            "p95 of 2-element array must be clamped to last element (0.9)")
    }

    func testLatencyStats_p95_fiveElements() {
        // n=5: Int(5 * 0.95 rounded .up) - 1 = Int(5)-1 = 4 → index 4 (last).
        // Sorted: [0.1, 0.3, 0.6, 0.8, 0.95]
        let entries = [
            entry(stopToPaste: 0.6, cleanup: 0),
            entry(stopToPaste: 0.1, cleanup: 0),
            entry(stopToPaste: 0.95, cleanup: 0),
            entry(stopToPaste: 0.3, cleanup: 0),
            entry(stopToPaste: 0.8, cleanup: 0)
        ]
        let stats = LatencyStats(entries: entries)
        XCTAssertEqual(stats.rawMedian ?? 0, 0.6, accuracy: 0.001,
            "Median of sorted [0.1, 0.3, 0.6, 0.8, 0.95] at index 2 must be 0.6")
        XCTAssertEqual(stats.rawP95 ?? 0, 0.95, accuracy: 0.001,
            "p95 of 5-element array must be the last element (0.95)")
    }

    // MARK: - LatencyStats: budget thresholds (named constants, no magic numbers)

    func testLatencyStats_budgetConstantsMatchBenchmark() {
        // These constants are the single source of truth for all budget comparisons.
        // Derivation: benchmark.md §7 L_e2e. [verified: matches §7 table]
        XCTAssertEqual(latencyBudgetRawMedianSeconds, 1.0, accuracy: 0.000_01,
            "Raw median budget must be 1.0s [benchmark.md §7 L_e2e raw-only]")
        XCTAssertEqual(latencyBudgetCleanupMedianSeconds, 2.0, accuracy: 0.000_01,
            "Cleanup median budget must be 2.0s [benchmark.md §7 L_e2e incl. cleanup]")
    }

    // MARK: - Equatable (structural parity test)

    func testLatencyStats_equatable_sameEntries() {
        let entries = [entry(stopToPaste: 0.6, cleanup: 0), entry(stopToPaste: 1.2, cleanup: 0.4)]
        let statsA = LatencyStats(entries: entries)
        let statsB = LatencyStats(entries: entries)
        XCTAssertEqual(statsA, statsB, "LatencyStats from the same entries must be equal")
    }
}
