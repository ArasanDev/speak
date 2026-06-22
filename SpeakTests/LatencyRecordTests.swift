// SpeakTests/LatencyRecordTests.swift
//
// Unit tests for `LatencyRecord` derivation math and `LatencyStats` aggregation.
//
// All tests are PURE: no I/O, no actors, no clock calls — timestamps are
// injected directly. This matches the InsightsStats pattern (injectable `now`).
//
// COVERAGE:
//   LatencyRecord:
//     - Normal derivation from well-ordered timestamps.
//     - stopToPasteSeconds spans the full t_stop→t_pasted range.
//     - cleanupSeconds is the transcriptReady→cleanupDone gap only.
//     - Defensive: out-of-order timestamps → 0 (no crash).
//     - No cleanup: cleanupSeconds == 0 when tCleanupDone == tTranscriptReady.
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
//
// HONESTY BOUNDARY:
//   These tests verify pure arithmetic derivation. Live wall-clock accuracy
//   (real mic + paste + FM) requires human verification [deferred — human-verification.md].

import XCTest
@testable import SpeakCore

@available(macOS 26.0, *)
final class LatencyRecordTests: XCTestCase {

    // MARK: - Helpers

    /// Nanoseconds-per-second constant. Avoids bare literals in test arithmetic.
    private let nsPerSecond: UInt64 = 1_000_000_000

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

    func testLatencyRecord_normalDerivation() {
        // Exact nanosecond values to avoid integer-arithmetic surprises:
        //   t_stop            =         0 ns  →  0.0 s
        //   t_transcript_ready = 500_000_000 ns  →  0.5 s
        //   t_cleanup_done    = 1_400_000_000 ns  →  1.4 s   (cleanup took 0.9 s)
        //   t_pasted          = 1_600_000_000 ns  →  1.6 s   (paste took 0.2 s)
        //
        // Expected derivations:
        //   stopToPasteSeconds     = 1.6 - 0.0 = 1.6 s
        //   transcriptReadySeconds = 0.5 - 0.0 = 0.5 s
        //   cleanupSeconds         = 1.4 - 0.5 = 0.9 s
        let record = LatencyRecord(
            tStop:            0,
            tTranscriptReady: 500_000_000,
            tCleanupDone:     1_400_000_000,
            tPasted:          1_600_000_000
        )
        XCTAssertEqual(record.stopToPasteSeconds, 1.6, accuracy: 0.001,
            "stopToPasteSeconds must span t_stop to t_pasted")
        XCTAssertEqual(record.transcriptReadySeconds, 0.5, accuracy: 0.001,
            "transcriptReadySeconds must span t_stop to t_transcriptReady")
        XCTAssertEqual(record.cleanupSeconds, 0.9, accuracy: 0.001,
            "cleanupSeconds must span t_transcriptReady to t_cleanupDone")
    }

    func testLatencyRecord_noCleanup_cleanupSecondsIsZero() {
        // When tCleanupDone == tTranscriptReady, no time was spent in cleanup.
        let tBase: UInt64 = 1_000_000_000  // 1s uptime
        let record = LatencyRecord(
            tStop:            tBase,
            tTranscriptReady: tBase + 300_000_000,   // +300ms
            tCleanupDone:     tBase + 300_000_000,   // same as transcript ready
            tPasted:          tBase + 350_000_000    // +50ms paste
        )
        XCTAssertEqual(record.cleanupSeconds, 0, accuracy: 0.0001,
            "cleanupSeconds must be 0 when cleanup was not run")
        XCTAssertEqual(record.stopToPasteSeconds, 0.35, accuracy: 0.001,
            "stopToPasteSeconds still reflects the full stop→paste interval")
    }

    func testLatencyRecord_outOfOrderTimestamps_noCrash() {
        // t_pasted < t_stop → should not crash, should produce 0 not negative.
        let record = LatencyRecord(
            tStop:            1_000_000_000,
            tTranscriptReady: 900_000_000,    // out of order (< t_stop)
            tCleanupDone:     800_000_000,    // out of order
            tPasted:          700_000_000     // out of order
        )
        XCTAssertEqual(record.stopToPasteSeconds, 0,
            "Out-of-order timestamps must produce 0, not negative or crash")
        XCTAssertEqual(record.transcriptReadySeconds, 0,
            "Out-of-order tTranscriptReady must produce 0")
        XCTAssertEqual(record.cleanupSeconds, 0,
            "Out-of-order tCleanupDone must produce 0")
    }

    func testLatencyRecord_allZeroTimestamps_zeroResult() {
        let record = LatencyRecord(tStop: 0, tTranscriptReady: 0, tCleanupDone: 0, tPasted: 0)
        XCTAssertEqual(record.stopToPasteSeconds, 0)
        XCTAssertEqual(record.transcriptReadySeconds, 0)
        XCTAssertEqual(record.cleanupSeconds, 0)
    }

    func testLatencyRecord_exactOneSecond() {
        // Sanity check: exactly 1,000,000,000 ns → 1.0 s.
        let record = LatencyRecord(
            tStop:            0,
            tTranscriptReady: 1_000_000_000,
            tCleanupDone:     1_000_000_000,
            tPasted:          1_000_000_000
        )
        XCTAssertEqual(record.stopToPasteSeconds, 1.0, accuracy: 0.000_001,
            "1,000,000,000 ns must convert to exactly 1.0 s")
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
            entry(stopToPaste: 0.5, cleanup: 0),    // raw
            entry(stopToPaste: 0.9, cleanup: 0),    // raw
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
        let a = LatencyStats(entries: entries)
        let b = LatencyStats(entries: entries)
        XCTAssertEqual(a, b, "LatencyStats from the same entries must be equal")
    }
}
