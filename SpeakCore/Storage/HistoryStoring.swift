// SpeakCore/Storage/HistoryStoring.swift
//
// Protocol that SpeakEngine depends on (architecture.md §6).
// All methods are async because the conformer does file I/O on a background
// actor; callers never need to know whether the backing store is SQLite,
// in-memory, or a mock.

import Foundation

/// Persistence contract for dictation history. Conformers must be `Sendable`
/// so they can be safely passed across actor boundaries in `SpeakEngine`.
public protocol HistoryStoring: Sendable {
    /// Persist a completed dictation entry.
    func save(_ entry: HistoryEntry) async throws

    /// Return the most-recently-created entries, newest first.
    /// - Parameter limit: Maximum number of entries to return.
    func recent(limit: Int) async throws -> [HistoryEntry]

    /// Return all entries whose `rawText` OR `cleanedText` contains
    /// `substring` (case-sensitive, exact substring match).
    func search(_ substring: String) async throws -> [HistoryEntry]

    /// Permanently delete all stored entries.
    func clear() async throws

    /// Produce a human-readable export of all entries (JSON, ISO-8601 dates).
    func export() async throws -> String
}
