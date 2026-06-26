// SpeakCore/Storage/HistoryStore.swift
//
// SQLite-backed implementation of `HistoryStoring`. Uses the raw SQLite3 C API
// (`import SQLite3`) — no third-party wrappers — to satisfy the v0 "Apple
// frameworks only" hard constraint (AGENTS.md §2).
//
// Concurrency model: `actor`. The actor's isolation guarantee means that
// `db` (the `OpaquePointer` SQLite handle) is only ever touched inside
// serialized actor methods. Swift 6's actor isolation is therefore the entire
// data-race-safety story: no lock, no serial DispatchQueue, and the main
// thread is never blocked because every call site `await`s.
//
// Capacity default — `benchmark.md` §7 "history size" [decision]:
//   Default = 10,000 entries. Derivation: at an average entry of ~400 bytes
//   (UUID 36B + timestamps 30B + typical text 300B + engineId 30B + overhead),
//   10 k entries ≈ 4 MB on disk — negligible on modern hardware and well under
//   macOS App Support storage norms. The value is an init parameter so the
//   user can change it via Settings (P10). [decision]
//
// Statement lifecycle: `sqlite3_prepare_v2` → bind → `sqlite3_step` →
// `sqlite3_finalize` in a `defer` block. Every SQLite return code is checked;
// failures throw `SpeakError.unknown(String)` with the sqlite3_errmsg detail.

import Foundation
import SQLite3
import os

// MARK: - SQLITE_TRANSIENT shim
// `SQLITE_TRANSIENT` is a C macro that evaluates to `(sqlite3_destructor_type)(-1)`.
// Swift does not import C macros, so we reproduce it here. [verified: standard practice]
// Named with camelCase to satisfy SwiftLint identifier_name; semantically identical
// to the C macro SQLITE_TRANSIENT.
private let sqliteTransientDestructor: sqlite3_destructor_type =
    unsafeBitCast(-1 as Int, to: sqlite3_destructor_type.self)

// MARK: - HistoryStore

/// Default max entries when none is specified at init.
/// Traces to `benchmark.md` §7 "history size" [decision]:
/// 10,000 entries ≈ 4 MB — negligible, makes a reasonable default setting.
public let defaultHistoryMaxEntries: Int = 10_000

public actor HistoryStore: HistoryStoring {

    // MARK: - State (actor-isolated)

    private var db: OpaquePointer?

    // Capacity guard: the maximum number of entries to keep. Oldest are
    // trimmed on every `save`. Traces to benchmark.md §7 [decision].
    private let maxEntries: Int

    // MARK: - Init / deinit

    /// Designated initialiser.
    /// - Parameters:
    ///   - databaseURL: File URL for the SQLite database. The parent directory
    ///     must already exist (use `makeProductionStore()` for the production path,
    ///     which creates the directory). Pass a temp file URL in tests.
    ///   - maxEntries: Capacity cap. Traces to `benchmark.md` §7 [decision].
    ///     Default = `defaultHistoryMaxEntries` (10,000 entries ≈ 4 MB).
    public init(databaseURL: URL, maxEntries: Int = defaultHistoryMaxEntries) throws {
        self.maxEntries = maxEntries
        let path = databaseURL.path
        guard sqlite3_open_v2(
            path,
            &db,
            SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        ) == SQLITE_OK else {
            let msg = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unable to open database"
            SpeakLog.storage.error("HistoryStore open failed: \(msg, privacy: .public)")
            // [App-H1] sqlite3_open_v2 sets *ppDb to a non-nil error-reporting handle
            // even on failure (SQLite docs). Swift's `init` throws here so `deinit`
            // never runs — close the handle explicitly to avoid a file-descriptor leak.
            if let handle = db { sqlite3_close_v2(handle) }
            throw SpeakError.unknown("SQLite open failed: \(msg)")
        }
        SpeakLog.storage.info("HistoryStore opened at \(path, privacy: .sensitive)")
        do {
            try HistoryStore.setupSchema(db: db)
        } catch {
            // [App-H1] If schema setup throws after a successful open, close before
            // rethrowing — deinit won't run when init throws.
            if let handle = db { sqlite3_close_v2(handle) }
            throw error
        }
    }

    deinit {
        if let db {
            sqlite3_close_v2(db)
        }
    }

    // MARK: - Convenience factory (production path)

    /// Returns a `HistoryStore` pointing at
    /// `~/Library/Application Support/speak/history.sqlite`, creating the
    /// directory if it doesn't exist.
    public static func makeProductionStore(
        maxEntries: Int = defaultHistoryMaxEntries
    ) throws -> HistoryStore {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = appSupport.appendingPathComponent("speak", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dbURL = dir.appendingPathComponent("history.sqlite")
        return try HistoryStore(databaseURL: dbURL, maxEntries: maxEntries)
    }

    // MARK: - HistoryStoring

    public func save(_ entry: HistoryEntry) throws {
        let sql = """
            INSERT OR REPLACE INTO history \
            (id, rawText, cleanedText, createdAt, engineId, duration, stopToPasteSeconds, cleanupSeconds)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """
        try execute(sql: sql) { stmt in
            let idStr = entry.id.uuidString
            try bind(stmt, index: 1, text: idStr)
            try bind(stmt, index: 2, text: entry.rawText)
            if let cleaned = entry.cleanedText {
                try bind(stmt, index: 3, text: cleaned)
            } else {
                guard sqlite3_bind_null(stmt, 3) == SQLITE_OK else {
                    throw dbError("bind null cleanedText")
                }
            }
            // Store as REAL (Double) to preserve sub-second resolution.
            // Avoids ordering collisions when entries are saved in rapid succession.
            // Ordered by `createdAt DESC, rowid DESC` so rowid breaks timestamp ties.
            guard sqlite3_bind_double(stmt, 4, entry.createdAt.timeIntervalSince1970) == SQLITE_OK else {
                throw dbError("bind createdAt")
            }
            try bind(stmt, index: 5, text: entry.engineId)
            guard sqlite3_bind_double(stmt, 6, entry.duration) == SQLITE_OK else {
                throw dbError("bind duration")
            }
            guard sqlite3_bind_double(stmt, 7, entry.stopToPasteSeconds) == SQLITE_OK else {
                throw dbError("bind stopToPasteSeconds")
            }
            guard sqlite3_bind_double(stmt, 8, entry.cleanupSeconds) == SQLITE_OK else {
                throw dbError("bind cleanupSeconds")
            }
        }
        try trimToCapacity()
        SpeakLog.storage.debug("HistoryStore saved entry \(entry.id.uuidString, privacy: .private)")
    }

    public func recent(limit: Int) throws -> [HistoryEntry] {
        let sql = """
            SELECT id, rawText, cleanedText, createdAt, engineId, duration,
                   stopToPasteSeconds, cleanupSeconds
            FROM history
            ORDER BY createdAt DESC, rowid DESC
            LIMIT ?
            """
        // Use sqlite3_bind_int64 so callers can safely pass Int.max to mean
        // "no effective limit" — Int32 would overflow and crash.
        return try query(sql: sql) { stmt in
            guard sqlite3_bind_int64(stmt, 1, Int64(limit)) == SQLITE_OK else {
                throw dbError("bind limit")
            }
        }
    }

    public func search(_ substring: String) throws -> [HistoryEntry] {
        // `instr(col, ?) > 0` is a true substring match — no wildcard escaping
        // needed (unlike LIKE '%x%'). Default BINARY collation → case-sensitive.
        //
        // LIMIT 500: a common-word search over a large history would otherwise
        // decode every matching row before the caller can page/cap the results,
        // causing a heap spike proportional to the match count. 500 is well above
        // any visible page size (the History pane shows ≤ 100 rows) and provides
        // a deterministic worst-case allocation bound.
        // [decision: 500-row search cap — balances full-history coverage with heap
        //  safety; revisit if power-users report truncated results. benchmark.md §7]
        // [App-L4] Case-insensitive search: lower() + lower(?) so "Hello" matches "hello".
        // SQLite's instr() uses BINARY collation by default; lower() normalises both sides.
        let sql = """
            SELECT id, rawText, cleanedText, createdAt, engineId, duration,
                   stopToPasteSeconds, cleanupSeconds
            FROM history
            WHERE instr(lower(rawText), lower(?)) > 0 OR instr(lower(cleanedText), lower(?)) > 0
            ORDER BY createdAt DESC, rowid DESC
            LIMIT 500
            """
        return try query(sql: sql) { stmt in
            try bind(stmt, index: 1, text: substring)
            try bind(stmt, index: 2, text: substring)
        }
    }

    public func clear() throws {
        try execute(sql: "DELETE FROM history") { _ in }
        SpeakLog.storage.info("HistoryStore cleared")
    }

    public func export() throws -> String {
        let entries = try recent(limit: Int.max)

        // Use a private Encodable struct so JSONEncoder handles optional
        // cleanedText correctly (encodes as JSON null, or omits with .encodeIfPresent).
        struct ExportEntry: Encodable {
            let id: String
            let rawText: String
            let cleanedText: String?
            let createdAt: String   // ISO-8601 string for human readability
            let engineId: String
        }

        let isoFormatter = ISO8601DateFormatter()
        let exportEntries = entries.map { entry in
            ExportEntry(
                id: entry.id.uuidString,
                rawText: entry.rawText,
                cleanedText: entry.cleanedText,
                createdAt: isoFormatter.string(from: entry.createdAt),
                engineId: entry.engineId
            )
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(exportEntries)
        guard let result = String(data: data, encoding: .utf8) else {
            throw SpeakError.unknown("export: UTF-8 encoding failed")
        }
        SpeakLog.storage.info("HistoryStore exported \(entries.count) entries")
        return result
    }

    // MARK: - Schema

    /// Static, nonisolated helper so it can be called safely from `init`
    /// (where actor isolation is not yet established under Swift 5 language mode).
    private static func setupSchema(db: OpaquePointer?) throws {
        let sql = """
            CREATE TABLE IF NOT EXISTS history (
                id                 TEXT PRIMARY KEY NOT NULL,
                rawText            TEXT NOT NULL,
                cleanedText        TEXT,
                createdAt          REAL NOT NULL,
                engineId           TEXT NOT NULL,
                duration           REAL NOT NULL DEFAULT 0,
                stopToPasteSeconds REAL NOT NULL DEFAULT 0,
                cleanupSeconds     REAL NOT NULL DEFAULT 0
            );
            CREATE INDEX IF NOT EXISTS idx_history_createdAt ON history (createdAt DESC);
            """
        // sqlite3_exec is convenient for DDL (no column binding needed).
        var errMsg: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(db, sql, nil, nil, &errMsg) == SQLITE_OK else {
            let msg = errMsg.map { String(cString: $0) } ?? "schema setup failed"
            sqlite3_free(errMsg)
            SpeakLog.storage.error("HistoryStore schema error: \(msg, privacy: .public)")
            throw SpeakError.unknown("SQLite schema: \(msg)")
        }

        // Migrations: add columns to DBs created before they existed. ALTER errors with
        // "duplicate column name" on fresh DBs or after a prior migration — that is the
        // idempotent no-op case, so the result is ignored.
        // [decision: column-add migration over PRAGMA user_version — single additive columns]
        sqlite3_exec(db, "ALTER TABLE history ADD COLUMN duration REAL NOT NULL DEFAULT 0", nil, nil, nil)
        // P13 migration: stop→paste latency columns (benchmark.md §7).
        sqlite3_exec(db, "ALTER TABLE history ADD COLUMN stopToPasteSeconds REAL NOT NULL DEFAULT 0", nil, nil, nil)
        sqlite3_exec(db, "ALTER TABLE history ADD COLUMN cleanupSeconds REAL NOT NULL DEFAULT 0", nil, nil, nil)
    }

    // MARK: - Capacity trim

    /// Delete entries beyond `maxEntries`, keeping the newest (by createdAt DESC, rowid DESC).
    private func trimToCapacity() throws {
        let sql = """
            DELETE FROM history
            WHERE rowid NOT IN (
                SELECT rowid FROM history ORDER BY createdAt DESC, rowid DESC LIMIT ?
            )
            """
        try execute(sql: sql) { stmt in
            // Use int64 to match the `recent()` binding and avoid Int32 truncation
            // for maxEntries values above 2 147 483 647 (theoretical, but consistent).
            guard sqlite3_bind_int64(stmt, 1, Int64(maxEntries)) == SQLITE_OK else {
                throw dbError("bind maxEntries for trim")
            }
        }
    }

    // MARK: - Helpers

    /// Prepare a statement, call `binder` to bind parameters, step, then finalize.
    private func execute(sql: String, binder: (OpaquePointer) throws -> Void) throws {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw dbError("prepare: \(sql)")
        }
        defer { sqlite3_finalize(stmt) }
        try binder(stmt)
        let result = sqlite3_step(stmt)
        guard result == SQLITE_DONE || result == SQLITE_ROW else {
            throw dbError("step")
        }
    }

    /// Prepare, bind, step through all rows, finalize, return decoded entries.
    private func query(
        sql: String,
        binder: (OpaquePointer) throws -> Void
    ) throws -> [HistoryEntry] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw dbError("prepare: \(sql)")
        }
        defer { sqlite3_finalize(stmt) }
        try binder(stmt)

        var entries: [HistoryEntry] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard
                let idCStr = sqlite3_column_text(stmt, 0),
                let rawCStr = sqlite3_column_text(stmt, 1)
            else {
                SpeakLog.storage.warning("HistoryStore: skipping row with null id or rawText")
                continue
            }
            let idStr = String(cString: idCStr)
            let rawText = String(cString: rawCStr)
            guard let id = UUID(uuidString: idStr) else {
                SpeakLog.storage.warning("HistoryStore: skipping row with malformed UUID \(idStr, privacy: .private)")
                continue
            }
            let cleanedText: String? = sqlite3_column_type(stmt, 2) == SQLITE_NULL
                ? nil
                : sqlite3_column_text(stmt, 2).map { String(cString: $0) }
            let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 3))
            let engineId = sqlite3_column_text(stmt, 4).map { String(cString: $0) } ?? ""
            let duration = sqlite3_column_double(stmt, 5)
            let stopToPasteSeconds = sqlite3_column_double(stmt, 6)
            let cleanupSeconds = sqlite3_column_double(stmt, 7)
            entries.append(HistoryEntry(
                id: id,
                rawText: rawText,
                cleanedText: cleanedText,
                createdAt: createdAt,
                engineId: engineId,
                duration: duration,
                stopToPasteSeconds: stopToPasteSeconds,
                cleanupSeconds: cleanupSeconds
            ))
        }
        return entries
    }

    /// Bind a Swift `String` to a statement parameter, using `SQLITE_TRANSIENT`
    /// so SQLite copies the buffer before the Swift string is freed.
    private func bind(_ stmt: OpaquePointer, index: Int32, text: String) throws {
        guard sqlite3_bind_text(
            stmt, index, text, -1, sqliteTransientDestructor
        ) == SQLITE_OK else {
            throw dbError("bind text at index \(index)")
        }
    }

    /// Construct a `SpeakError.unknown` from the current SQLite error message.
    private func dbError(_ context: String) -> SpeakError {
        let msg = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown SQLite error"
        SpeakLog.storage.error("HistoryStore error [\(context, privacy: .public)]: \(msg, privacy: .public)")
        return .unknown("SQLite [\(context)]: \(msg)")
    }
}
