// SpeakCore/Storage/HistoryEntry.swift
//
// Verbatim struct from `docs/architecture.md` §6. A lightweight value type
// representing one completed dictation session stored in history.
//
// `Equatable` is additive to §6 (not in the spec) — included so tests can
// use `XCTAssertEqual` on round-tripped values without boilerplate.

import Foundation

public struct HistoryEntry: Sendable, Identifiable, Equatable {
    public let id: UUID
    public let rawText: String
    public let cleanedText: String?
    public let createdAt: Date
    public let engineId: String
    /// Wall-clock dictation duration in seconds (from `TranscriptionResult.duration`).
    /// Used to compute words-per-minute in Insights. Defaults to 0 for back-compat
    /// (rows migrated from the pre-duration schema, and call sites that don't supply it).
    public let duration: TimeInterval
    /// Stop→paste elapsed seconds (benchmark.md §7 `L_e2e`).
    /// 0 for rows created before this column existed (pre-P13 migration).
    /// The raw-path budget is < 1.0 s median; full-path (cleanup) < 2.0 s.
    public let stopToPasteSeconds: Double
    /// Seconds spent in the on-device cleanup pass (Foundation Models).
    /// 0 when cleanup did not run (cleaner nil, unavailable, or cleanupLevel==.none).
    /// Use `stopToPasteSeconds > 0 && cleanupSeconds > 0` to identify
    /// the "cleanup ran" population for the full-path median.
    public let cleanupSeconds: Double

    public init(
        id: UUID = UUID(),
        rawText: String,
        cleanedText: String?,
        createdAt: Date = Date(),
        engineId: String,
        duration: TimeInterval = 0,
        stopToPasteSeconds: Double = 0,
        cleanupSeconds: Double = 0
    ) {
        self.id = id
        self.rawText = rawText
        self.cleanedText = cleanedText
        self.createdAt = createdAt
        self.engineId = engineId
        self.duration = duration
        self.stopToPasteSeconds = stopToPasteSeconds
        self.cleanupSeconds = cleanupSeconds
    }
}
