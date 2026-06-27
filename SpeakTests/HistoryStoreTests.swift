// SpeakTests/HistoryStoreTests.swift
//
// Unit tests for HistoryStore and HistoryEntry (roadmap P9 done-when rows).
// All tests use a temp-file SQLite database; they NEVER touch
// ~/Library/Application Support/speak/. Each test gets a unique URL so there
// is no state leakage between runs.
//
// Done-when rows verified here (P9):
//   [x] save → entry persists; reopen HistoryStore on same file → entry read back
//   [x] recent(limit:) returns newest-first and respects the limit
//   [x] search matches substring in rawText; in cleanedText; empty for no match
//   [x] clear() empties the store
//   [x] export() produces output containing the entries' text
//   [x] capacity: saving > maxEntries trims oldest; count stays ≤ cap
//   [x] cleanedText == nil round-trips correctly (nil preserved, not "")

@testable import SpeakCore
import XCTest

final class HistoryStoreTests: XCTestCase {

    // MARK: - Helpers

    /// Creates a HistoryStore at `url`. Fails the test on throw.
    private func makeStore(
        url: URL,
        maxEntries: Int = defaultHistoryMaxEntries
    ) async throws -> HistoryStore {
        try HistoryStore(databaseURL: url, maxEntries: maxEntries)
    }

    // MARK: - P9: save + persist across "launches"

    /// save → entry persists; open a NEW HistoryStore on the same file → still there.
    func testSaveAndReopenPersistence() async throws {
        let url = TestStorage.tempDatabaseURL()
        let entry = HistoryEntry(
            rawText: "hello world",
            cleanedText: "Hello, world.",
            createdAt: Date(),
            engineId: "test-engine"
        )

        // First "launch" — save.
        let store1 = try await makeStore(url: url)
        try await store1.save(entry)

        // Second "launch" — open a new store on the same file.
        let store2 = try await makeStore(url: url)
        let results = try await store2.recent(limit: 10)
        XCTAssertEqual(results.count, 1, "entry must survive a store reopen")
        let loaded = try XCTUnwrap(results.first)
        XCTAssertEqual(loaded.id, entry.id)
        XCTAssertEqual(loaded.rawText, entry.rawText)
        XCTAssertEqual(loaded.cleanedText, entry.cleanedText)
        XCTAssertEqual(
            loaded.createdAt.timeIntervalSince1970,
            entry.createdAt.timeIntervalSince1970,
            accuracy: 0.001,
            "createdAt must round-trip with sub-second accuracy"
        )
        XCTAssertEqual(loaded.engineId, entry.engineId)
    }

    // MARK: - P9: recent(limit:) newest-first + respects limit

    func testRecentNewestFirstAndLimit() async throws {
        let url = TestStorage.tempDatabaseURL()
        let store = try await makeStore(url: url)

        let base = Date(timeIntervalSince1970: 1_000_000)
        // Save three entries with distinct timestamps so ordering is deterministic.
        let older = HistoryEntry(rawText: "older", cleanedText: nil, createdAt: base, engineId: "e")
        let middle = HistoryEntry(rawText: "middle", cleanedText: nil, createdAt: base + 1, engineId: "e")
        let newest = HistoryEntry(rawText: "newest", cleanedText: nil, createdAt: base + 2, engineId: "e")

        try await store.save(older)
        try await store.save(middle)
        try await store.save(newest)

        // All three, newest first.
        let all = try await store.recent(limit: 10)
        XCTAssertEqual(all.map { $0.rawText }, ["newest", "middle", "older"])

        // Limit = 2 → only the two most recent.
        let top2 = try await store.recent(limit: 2)
        XCTAssertEqual(top2.count, 2)
        XCTAssertEqual(top2.first?.rawText, "newest")
        XCTAssertEqual(top2.last?.rawText, "middle")
    }

    // MARK: - P9: search

    func testSearchMatchesRawText() async throws {
        let url = TestStorage.tempDatabaseURL()
        let store = try await makeStore(url: url)

        try await store.save(HistoryEntry(rawText: "the quick brown fox", cleanedText: nil,
                                          createdAt: Date(), engineId: "e"))
        try await store.save(HistoryEntry(rawText: "hello world", cleanedText: nil,
                                          createdAt: Date(), engineId: "e"))

        let results = try await store.search("quick")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.rawText, "the quick brown fox")
    }

    func testSearchMatchesCleanedText() async throws {
        let url = TestStorage.tempDatabaseURL()
        let store = try await makeStore(url: url)

        try await store.save(HistoryEntry(rawText: "raw stuff",
                                          cleanedText: "Cleaned: meeting notes",
                                          createdAt: Date(), engineId: "e"))
        try await store.save(HistoryEntry(rawText: "other raw", cleanedText: nil,
                                          createdAt: Date(), engineId: "e"))

        let results = try await store.search("meeting")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.rawText, "raw stuff")
    }

    func testSearchReturnsEmptyForNoMatch() async throws {
        let url = TestStorage.tempDatabaseURL()
        let store = try await makeStore(url: url)

        try await store.save(HistoryEntry(rawText: "hello world", cleanedText: nil, createdAt: Date(), engineId: "e"))

        let results = try await store.search("xyz-no-match")
        XCTAssertTrue(results.isEmpty, "search with no match must return empty array")
    }

    // MARK: - P9: clear()

    func testClearEmptiesStore() async throws {
        let url = TestStorage.tempDatabaseURL()
        let store = try await makeStore(url: url)

        try await store.save(HistoryEntry(rawText: "entry 1", cleanedText: nil, createdAt: Date(), engineId: "e"))
        try await store.save(HistoryEntry(rawText: "entry 2", cleanedText: nil, createdAt: Date(), engineId: "e"))

        try await store.clear()

        let results = try await store.recent(limit: 100)
        XCTAssertTrue(results.isEmpty, "clear() must empty the store")
    }

    // MARK: - P9: export()

    func testExportContainsEntriesText() async throws {
        let url = TestStorage.tempDatabaseURL()
        let store = try await makeStore(url: url)

        try await store.save(HistoryEntry(
            rawText: "exported text here",
            cleanedText: "Cleaned exported text.",
            createdAt: Date(),
            engineId: "test-engine"
        ))

        let output = try await store.export()
        XCTAssertTrue(output.contains("exported text here"), "export must contain rawText")
        XCTAssertTrue(output.contains("Cleaned exported text."), "export must contain cleanedText")
        XCTAssertTrue(output.contains("test-engine"), "export must contain engineId")
    }

    func testExportEmptyStore() async throws {
        let url = TestStorage.tempDatabaseURL()
        let store = try await makeStore(url: url)

        let output = try await store.export()
        // Must be valid JSON that decodes to an empty array.
        let data = try XCTUnwrap(output.data(using: .utf8), "export must produce UTF-8 text")
        let decoded = try JSONSerialization.jsonObject(with: data)
        let array = try XCTUnwrap(decoded as? [Any], "export of empty store must be a JSON array")
        XCTAssertTrue(array.isEmpty, "export of empty store must produce an empty JSON array")
    }

    // MARK: - P9: capacity trim

    func testCapacityTrimKeepsNewest() async throws {
        let url = TestStorage.tempDatabaseURL()
        let cap = 3
        let store = try await makeStore(url: url, maxEntries: cap)

        let base = Date(timeIntervalSince1970: 2_000_000)
        // Save 5 entries (cap + 2). Each gets a strictly later timestamp.
        for idx in 0..<5 {
            let entry = HistoryEntry(
                rawText: "entry-\(idx)",
                cleanedText: nil,
                createdAt: base + Double(idx),
                engineId: "e"
            )
            try await store.save(entry)
        }

        let results = try await store.recent(limit: 100)
        XCTAssertEqual(results.count, cap, "count must not exceed maxEntries after trim")

        // The kept entries must be the three newest (entry-4, entry-3, entry-2).
        let texts = results.map { $0.rawText }
        XCTAssertTrue(texts.contains("entry-4"), "newest entry must be kept")
        XCTAssertTrue(texts.contains("entry-3"), "second newest must be kept")
        XCTAssertTrue(texts.contains("entry-2"), "third newest must be kept")
        XCTAssertFalse(texts.contains("entry-0"), "oldest entry must be trimmed")
        XCTAssertFalse(texts.contains("entry-1"), "second-oldest entry must be trimmed")
    }

    // MARK: - P9: nil cleanedText round-trips correctly

    func testNilCleanedTextRoundTrips() async throws {
        let url = TestStorage.tempDatabaseURL()
        let store = try await makeStore(url: url)

        let entry = HistoryEntry(rawText: "no cleanup", cleanedText: nil, createdAt: Date(), engineId: "stt-only")
        try await store.save(entry)

        let results = try await store.recent(limit: 1)
        let loaded = try XCTUnwrap(results.first)
        XCTAssertNil(loaded.cleanedText, "nil cleanedText must round-trip as nil, not empty string")
    }

    // MARK: - Bonus: non-nil cleanedText round-trips correctly

    func testNonNilCleanedTextRoundTrips() async throws {
        let url = TestStorage.tempDatabaseURL()
        let store = try await makeStore(url: url)

        let entry = HistoryEntry(rawText: "raw", cleanedText: "Cleaned.", createdAt: Date(), engineId: "e")
        try await store.save(entry)

        let results = try await store.recent(limit: 1)
        let loaded = try XCTUnwrap(results.first)
        XCTAssertEqual(loaded.cleanedText, "Cleaned.")
    }
}
