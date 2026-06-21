// SpeakCore/Insights/InsightsStats.swift
//
// A pure, fully unit-testable value type that derives usage statistics from a
// slice of dictation history. No I/O, no singletons, no `Date()` inside the
// compute — the caller injects `now` and `calendar` so tests are deterministic.
//
// THREADING: `Sendable` struct — safe to create on any actor and publish to main.

import Foundation

// MARK: - InsightsStats

/// Aggregated usage statistics derived from a slice of `HistoryEntry` values.
public struct InsightsStats: Sendable, Equatable {

    // MARK: - Computed fields

    /// Total number of dictation sessions in the provided entries.
    public let totalDictations: Int

    /// Total word count across all entries, using `cleanedText` when available,
    /// falling back to `rawText`. Words are whitespace-separated non-empty tokens.
    public let totalWords: Int

    /// Rounded average words per dictation session. 0 when there are no dictations.
    public let averageWordsPerDictation: Int

    /// Consecutive calendar days ending today (or yesterday if none today) that each
    /// have at least one dictation. 0 when the most-recent activity is ≥2 days stale.
    public let currentStreakDays: Int

    /// Per-day dictation counts for the last 7 calendar days, oldest first.
    /// The `day` value is midnight (start of day) in the current calendar.
    public let dictationsPerDay: [(day: Date, count: Int)]

    // MARK: - Init

    /// Creates an `InsightsStats` from a flat list of entries.
    ///
    /// - Parameters:
    ///   - entries: All entries to aggregate — caller decides the fetch window.
    ///   - now: The reference "now" date. Pass `Date()` at the view layer.
    ///   - calendar: The calendar used for day arithmetic. Defaults to `.current`.
    public init(
        entries: [HistoryEntry],
        now: Date,
        calendar: Calendar = .current
    ) {
        // --- Total dictations ---
        let total = entries.count
        totalDictations = total

        // --- Word counts (cleaned preferred, raw fallback) ---
        let words = entries.map { entry in
            (entry.cleanedText ?? entry.rawText)
                .split(whereSeparator: \.isWhitespace)
                .count
        }
        let wordTotal = words.reduce(0, +)
        totalWords = wordTotal

        // --- Average (rounded, 0 on empty) ---
        averageWordsPerDictation = total == 0 ? 0 : Int((Double(wordTotal) / Double(total)).rounded())

        // --- Streak ---
        // Build a set of start-of-day dates that have ≥1 dictation entry.
        let activeDays = Set(entries.map { calendar.startOfDay(for: $0.createdAt) })

        if activeDays.isEmpty {
            currentStreakDays = 0
        } else {
            let today = calendar.startOfDay(for: now)
            // [decision] Anchor on today if active, else yesterday if active,
            // else streak is broken (≥2 days stale → 0).
            let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
            let anchor: Date?
            if activeDays.contains(today) {
                anchor = today
            } else if activeDays.contains(yesterday) {
                anchor = yesterday
            } else {
                anchor = nil
            }

            if let anchor {
                var streak = 0
                var cursor = anchor
                while activeDays.contains(cursor) {
                    streak += 1
                    // Walk back one calendar day at a time — avoids DST-unsafe 86400s math.
                    guard let prev = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
                    cursor = prev
                }
                currentStreakDays = streak
            } else {
                currentStreakDays = 0
            }
        }

        // --- 7-day activity bar data (oldest first) ---
        // [decision] 7 days gives one week of activity at a glance.
        let today = calendar.startOfDay(for: now)
        var perDay: [(day: Date, count: Int)] = []
        for offset in (0..<7).reversed() {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let count = entries.filter { calendar.startOfDay(for: $0.createdAt) == day }.count
            perDay.append((day: day, count: count))
        }
        dictationsPerDay = perDay
    }
}

// MARK: - Equatable for dictationsPerDay

// `dictationsPerDay` is `[(day: Date, count: Int)]` — tuples are not `Equatable`
// by default, so we synthesise a custom implementation comparing element-by-element.
extension InsightsStats {
    public static func == (lhs: InsightsStats, rhs: InsightsStats) -> Bool {
        guard lhs.totalDictations == rhs.totalDictations,
              lhs.totalWords == rhs.totalWords,
              lhs.averageWordsPerDictation == rhs.averageWordsPerDictation,
              lhs.currentStreakDays == rhs.currentStreakDays,
              lhs.dictationsPerDay.count == rhs.dictationsPerDay.count else { return false }
        for (left, right) in zip(lhs.dictationsPerDay, rhs.dictationsPerDay) {
            guard left.day == right.day, left.count == right.count else { return false }
        }
        return true
    }
}
