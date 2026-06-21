// SpeakTests/InsightsStatsTests.swift
//
// Unit tests for `InsightsStats`. All tests inject `now` and use
// `Calendar.current` + `DateComponents` to build deterministic dates so
// they remain correct across time zones and across days.
//
// COVERAGE:
//   - Empty input → all zeros / empty bar data.
//   - Word counting: cleaned text preferred; raw text fallback; mixed.
//   - Average rounding: floor/ceil boundary.
//   - Streak: 0 (stale), 1 (today only), 1 (yesterday only), multi-day,
//     broken streak, today-vs-yesterday boundary.
//   - dictationsPerDay: correct bucket assignment and 7-day window.
//
// HONESTY BOUNDARY: `InsightsStats` is a pure value type; these tests are
// [verified] by the test suite. UI rendering is [deferred — human verification].

import XCTest
@testable import SpeakCore

@available(macOS 26.0, *)
final class InsightsStatsTests: XCTestCase {

    // MARK: - Helpers

    private let calendar = Calendar.current

    /// Builds a midnight Date for the given components, failing the test if
    /// `Calendar` returns nil (should be impossible for well-formed components).
    private func makeDay(year: Int, month: Int, day: Int) throws -> Date {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = 0
        comps.minute = 0
        comps.second = 0
        return try XCTUnwrap(
            calendar.date(from: comps),
            "Calendar.date(from:) returned nil for \(year)-\(month)-\(day) — check DateComponents."
        )
    }

    /// Makes a `HistoryEntry` at `offset` seconds past midnight of `day`.
    private func entry(
        rawText: String,
        cleanedText: String? = nil,
        on day: Date,
        secondsOffset: TimeInterval = 0,
        engineId: String = "test",
        duration: TimeInterval = 0
    ) -> HistoryEntry {
        HistoryEntry(
            rawText: rawText,
            cleanedText: cleanedText,
            createdAt: day.addingTimeInterval(secondsOffset),
            engineId: engineId,
            duration: duration
        )
    }

    // MARK: - Empty input

    func testEmpty_allZeros() throws {
        let now = try makeDay(year: 2026, month: 6, day: 21)
        let stats = InsightsStats(entries: [], now: now, calendar: calendar)

        XCTAssertEqual(stats.totalDictations, 0)
        XCTAssertEqual(stats.totalWords, 0)
        XCTAssertEqual(stats.averageWordsPerDictation, 0)
        XCTAssertEqual(stats.currentStreakDays, 0)
        XCTAssertEqual(stats.dictationsPerDay.count, 7)
        XCTAssertTrue(stats.dictationsPerDay.allSatisfy { point in point.count == .zero })
    }

    // MARK: - Word counting

    func testWordCount_usesCleanedTextWhenAvailable() throws {
        let now = try makeDay(year: 2026, month: 6, day: 21)
        let item = entry(
            rawText: "one two three four",       // 4 words
            cleanedText: "alpha beta gamma",      // 3 words — should win
            on: now
        )
        let stats = InsightsStats(entries: [item], now: now, calendar: calendar)
        XCTAssertEqual(stats.totalWords, 3)
    }

    func testWordCount_fallsBackToRawWhenNoCleanedText() throws {
        let now = try makeDay(year: 2026, month: 6, day: 21)
        let item = entry(rawText: "hello world", cleanedText: nil, on: now)
        let stats = InsightsStats(entries: [item], now: now, calendar: calendar)
        XCTAssertEqual(stats.totalWords, 2)
    }

    func testWordCount_ignoresLeadingTrailingWhitespace() throws {
        let now = try makeDay(year: 2026, month: 6, day: 21)
        let item = entry(rawText: "  word one  two  ", cleanedText: nil, on: now)
        let stats = InsightsStats(entries: [item], now: now, calendar: calendar)
        // split(whereSeparator:) on whitespace returns ["word","one","two"]
        XCTAssertEqual(stats.totalWords, 3)
    }

    func testWordCount_emptyText_isZeroWords() throws {
        let now = try makeDay(year: 2026, month: 6, day: 21)
        let item = entry(rawText: "", cleanedText: nil, on: now)
        let stats = InsightsStats(entries: [item], now: now, calendar: calendar)
        XCTAssertEqual(stats.totalWords, 0)
        XCTAssertEqual(stats.totalDictations, 1)
    }

    func testWordCount_multipleEntries_summed() throws {
        let now = try makeDay(year: 2026, month: 6, day: 21)
        let entries = [
            entry(rawText: "a b c", on: now),           // 3 words (raw)
            entry(rawText: "ignored", cleanedText: "x y", on: now)  // 2 words (cleaned)
        ]
        let stats = InsightsStats(entries: entries, now: now, calendar: calendar)
        XCTAssertEqual(stats.totalWords, 5)
    }

    // MARK: - Average rounding

    func testAverage_roundsCorrectly() throws {
        let now = try makeDay(year: 2026, month: 6, day: 21)
        // 7 words / 3 entries = 2.333… → rounds to 2
        let entries = [
            entry(rawText: "a b c", on: now),    // 3
            entry(rawText: "d e", on: now),       // 2
            entry(rawText: "f g", on: now)        // 2
        ]
        let stats = InsightsStats(entries: entries, now: now, calendar: calendar)
        XCTAssertEqual(stats.averageWordsPerDictation, 2)
    }

    func testAverage_roundsUp() throws {
        let now = try makeDay(year: 2026, month: 6, day: 21)
        // 5 words / 2 entries = 2.5 → rounds to 3
        let entries = [
            entry(rawText: "a b c", on: now),    // 3
            entry(rawText: "d e", on: now)        // 2
        ]
        let stats = InsightsStats(entries: entries, now: now, calendar: calendar)
        XCTAssertEqual(stats.averageWordsPerDictation, 3)
    }

    func testAverage_zeroOnNoEntries() throws {
        let now = try makeDay(year: 2026, month: 6, day: 21)
        let stats = InsightsStats(entries: [], now: now, calendar: calendar)
        XCTAssertEqual(stats.averageWordsPerDictation, 0)
    }

    // MARK: - Words per minute

    func testWPM_computedFromTimedEntries() throws {
        let now = try makeDay(year: 2026, month: 6, day: 21)
        // 30 words over 60 seconds total → 30 wpm.
        let entries = [
            entry(rawText: "one two three four five six seven eight nine ten", on: now,
                  secondsOffset: 0, duration: 20),   // 10 words / 20s
            entry(rawText: "one two three four five six seven eight nine ten "
                  + "one two three four five six seven eight nine ten", on: now,
                  secondsOffset: 100, duration: 40)  // 20 words / 40s
        ]
        let stats = InsightsStats(entries: entries, now: now, calendar: calendar)
        // 30 words / (60s = 1 min) = 30 wpm
        XCTAssertEqual(stats.wordsPerMinute, 30)
    }

    func testWPM_excludesZeroDurationEntries() throws {
        let now = try makeDay(year: 2026, month: 6, day: 21)
        let entries = [
            entry(rawText: "ten words here a b c d e f g", on: now, duration: 0),   // excluded
            entry(rawText: "one two three four", on: now, secondsOffset: 10, duration: 60) // 4 words / 1 min
        ]
        let stats = InsightsStats(entries: entries, now: now, calendar: calendar)
        XCTAssertEqual(stats.wordsPerMinute, 4, "Zero-duration rows must be excluded from WPM.")
    }

    func testWPM_zeroWhenNoTimedEntries() throws {
        let now = try makeDay(year: 2026, month: 6, day: 21)
        let stats = InsightsStats(entries: [entry(rawText: "a b c", on: now)], now: now, calendar: calendar)
        XCTAssertEqual(stats.wordsPerMinute, 0)
    }

    // MARK: - Streak: zero cases

    func testStreak_noEntries_isZero() throws {
        let now = try makeDay(year: 2026, month: 6, day: 21)
        let stats = InsightsStats(entries: [], now: now, calendar: calendar)
        XCTAssertEqual(stats.currentStreakDays, 0)
    }

    func testStreak_latestEntryTwoDaysAgo_isZero() throws {
        let now   = try makeDay(year: 2026, month: 6, day: 21)
        let twoDaysAgo = try makeDay(year: 2026, month: 6, day: 19)
        let item = entry(rawText: "hello", on: twoDaysAgo)
        let stats = InsightsStats(entries: [item], now: now, calendar: calendar)
        XCTAssertEqual(stats.currentStreakDays, 0)
    }

    // MARK: - Streak: today only

    func testStreak_todayOnly_isOne() throws {
        let now = try makeDay(year: 2026, month: 6, day: 21)
        let item = entry(rawText: "hello", on: now, secondsOffset: 3600)
        let stats = InsightsStats(entries: [item], now: now, calendar: calendar)
        XCTAssertEqual(stats.currentStreakDays, 1)
    }

    // MARK: - Streak: yesterday only (no entry today)

    func testStreak_yesterdayOnly_isOne() throws {
        let now       = try makeDay(year: 2026, month: 6, day: 21)
        let yesterday = try makeDay(year: 2026, month: 6, day: 20)
        let item = entry(rawText: "hello", on: yesterday)
        let stats = InsightsStats(entries: [item], now: now, calendar: calendar)
        XCTAssertEqual(stats.currentStreakDays, 1)
    }

    // MARK: - Streak: multi-day continuous

    func testStreak_threeDays_todayIncluded() throws {
        let now   = try makeDay(year: 2026, month: 6, day: 21)
        let day19 = try makeDay(year: 2026, month: 6, day: 19)
        let day20 = try makeDay(year: 2026, month: 6, day: 20)
        let entries = [
            entry(rawText: "a", on: now),
            entry(rawText: "b", on: day20),
            entry(rawText: "c", on: day19)
        ]
        let stats = InsightsStats(entries: entries, now: now, calendar: calendar)
        XCTAssertEqual(stats.currentStreakDays, 3)
    }

    func testStreak_threeDays_noEntryToday_anchoredYesterday() throws {
        let now   = try makeDay(year: 2026, month: 6, day: 21)
        let day18 = try makeDay(year: 2026, month: 6, day: 18)
        let day19 = try makeDay(year: 2026, month: 6, day: 19)
        let day20 = try makeDay(year: 2026, month: 6, day: 20)
        let entries = [
            entry(rawText: "a", on: day20),
            entry(rawText: "b", on: day19),
            entry(rawText: "c", on: day18)
        ]
        let stats = InsightsStats(entries: entries, now: now, calendar: calendar)
        XCTAssertEqual(stats.currentStreakDays, 3)
    }

    // MARK: - Streak: broken streak

    func testStreak_brokenStreak_countsFromAnchorOnly() throws {
        let now   = try makeDay(year: 2026, month: 6, day: 21)
        // gap at day20 — streak should be 1 (today only), not 2
        let day19 = try makeDay(year: 2026, month: 6, day: 19)
        let entries = [
            entry(rawText: "a", on: now),
            entry(rawText: "b", on: day19)    // day20 missing → break
        ]
        let stats = InsightsStats(entries: entries, now: now, calendar: calendar)
        XCTAssertEqual(stats.currentStreakDays, 1)
    }

    // MARK: - Streak: multiple entries on same day count once

    func testStreak_multipleEntriesSameDay_countAsOneDay() throws {
        let now = try makeDay(year: 2026, month: 6, day: 21)
        let entries = [
            entry(rawText: "morning", on: now, secondsOffset: 3600),
            entry(rawText: "afternoon", on: now, secondsOffset: 43200),
            entry(rawText: "evening", on: now, secondsOffset: 72000)
        ]
        let stats = InsightsStats(entries: entries, now: now, calendar: calendar)
        XCTAssertEqual(stats.currentStreakDays, 1)
    }

    // MARK: - dictationsPerDay (7-day window)

    func testDictationsPerDay_sevenBuckets() throws {
        let now = try makeDay(year: 2026, month: 6, day: 21)
        let stats = InsightsStats(entries: [], now: now, calendar: calendar)
        XCTAssertEqual(stats.dictationsPerDay.count, 7)
    }

    func testDictationsPerDay_correctCounts() throws {
        let now   = try makeDay(year: 2026, month: 6, day: 21)
        let day20 = try makeDay(year: 2026, month: 6, day: 20)
        let day18 = try makeDay(year: 2026, month: 6, day: 18)  // inside 7-day window
        let entries = [
            entry(rawText: "a", on: now),
            entry(rawText: "b", on: now, secondsOffset: 3600),
            entry(rawText: "c", on: day20),
            entry(rawText: "d", on: day18)
        ]
        let stats = InsightsStats(entries: entries, now: now, calendar: calendar)

        // Today bucket (last element, offset 0 from now)
        let todayBucket = try XCTUnwrap(stats.dictationsPerDay.last)
        XCTAssertEqual(todayBucket.count, 2, "Expected 2 entries on today")

        // day20 bucket (second-to-last)
        let day20Bucket = try XCTUnwrap(stats.dictationsPerDay.dropLast().last)
        XCTAssertEqual(day20Bucket.count, 1, "Expected 1 entry on day20")

        // day18 is 3 days back — index 3 from the end (index 4 from start of 7)
        let day18Bucket = stats.dictationsPerDay[stats.dictationsPerDay.count - 4]
        XCTAssertEqual(day18Bucket.count, 1, "Expected 1 entry on day18")
    }

    func testDictationsPerDay_entryOutsideWindow_notCounted() throws {
        let now     = try makeDay(year: 2026, month: 6, day: 21)
        let day14   = try makeDay(year: 2026, month: 6, day: 14) // 7 days before today → out of window
        let entries = [entry(rawText: "old", on: day14)]
        let stats = InsightsStats(entries: entries, now: now, calendar: calendar)
        XCTAssertTrue(stats.dictationsPerDay.allSatisfy { point in point.count == .zero })
    }
}
