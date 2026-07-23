// SpeakCore/Storage/AgentCallStore.swift
//
// AVB-7 (specs/avb7-durable-calls-design.md): SQLite-backed `AgentCallStoring`.
// Own file (`agent-calls.sqlite`), own connection, own actor — deliberately NOT
// folded into `HistoryStore`: access pattern differs fundamentally (mutated in
// place pending → presented → terminal, queried by state for the inbox badge,
// own expiry unrelated to dictation-history retention). Copies HistoryStore's
// raw-SQLite3-C-API pattern, error handling, and schema-migration precedent.
//
// Concurrency model: `actor`. Every read-modify-write (submit/resolve/expire) is
// a single non-suspending body — no `await` between a check and its mutation —
// so actor isolation alone closes the TOCTOU window the design doc calls out.
// CAS transitions (`resolve`, `expireOverdue`) additionally guard with a SQL
// `WHERE state IN (...)` so two concurrent callers racing the SAME row (which
// actor isolation serializes, but whose LOGICAL race — e.g. a human answering as
// the expiry sweep fires — is still real) have a well-defined, at-most-one-winner
// outcome expressed at the SQL layer, matching the design doc's CAS section.

import Foundation
import os
import SQLite3

// MARK: - SQLITE_TRANSIENT shim (mirrors HistoryStore.swift)

private let agentCallSqliteTransientDestructor: sqlite3_destructor_type =
    unsafeBitCast(-1 as Int, to: sqlite3_destructor_type.self)

// MARK: - nil-session sentinel
//
// SQL NULL is never equal to itself, so a partial unique index on
// `(sessionId, idempotencyKey) WHERE idempotencyKey IS NOT NULL` never fires
// when `sessionId IS NULL` — exactly the case the `speak_request_input`
// durable side effect always submits (it never carries a sessionId). Two
// concurrent request_input calls with the same idempotencyKey would both
// insert successfully, defeating the dedupe the design doc requires. Fix:
// map `nil` to a fixed, never-user-suppliable sentinel string on write and
// back to `nil` on read — ONE mapping point, so the SQL layer sees a
// concrete, self-equal value and the unique index actually bites. The
// public `AgentCallSubmission`/`AgentCall` types are untouched — this is a
// storage-internal detail. [decision: AVB-7]
// U+E000 (Private Use Area) as a leading marker — NOT a literal NUL byte:
// `sqlite3_column_text` returns a NUL-terminated C string, so embedding an
// actual `\u{0}` would silently truncate on read-back (verified the hard way —
// this exact bug shipped once and broke nil-session isolation; the fixed test
// is `AgentCallStoreTests.nilSessionIsolation`). [decision: AVB-7]
private let agentCallNoSessionSentinel = "\u{E000}avb7-no-session\u{E000}"

private func agentCallStoreDBSessionId(_ sessionId: String?) -> String {
    sessionId ?? agentCallNoSessionSentinel
}

private func agentCallStoreSessionId(fromDB value: String) -> String? {
    value == agentCallNoSessionSentinel ? nil : value
}

// MARK: - AgentCallStore

public actor AgentCallStore: AgentCallStoring {

    // MARK: - State (actor-isolated)

    nonisolated(unsafe) private var db: OpaquePointer?
    private let now: @Sendable () -> Date

    // MARK: - Init / deinit

    /// - Parameters:
    ///   - databaseURL: File URL for the SQLite database. The parent directory must
    ///     already exist (use `makeProductionStore()` for the production path).
    ///   - now: injectable clock — recovery/expiry tests plant a past `expiresAt`
    ///     and drive `expireOverdue(now:)` with an explicit instant; `submit`'s
    ///     `createdAt` uses this clock too so a single fake-clock test double
    ///     controls both. Defaults to `Date.init`.
    public init(databaseURL: URL, now: @escaping @Sendable () -> Date = { Date() }) throws {
        self.now = now
        let path = databaseURL.path
        guard sqlite3_open_v2(
            path, &db,
            SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        ) == SQLITE_OK else {
            let msg = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unable to open database"
            SpeakLog.storage.error("AgentCallStore open failed: \(msg, privacy: .public)")
            if let handle = db { sqlite3_close_v2(handle) }
            throw SpeakError.unknown("SQLite open failed: \(msg)")
        }
        SpeakLog.storage.info("AgentCallStore opened at \(path, privacy: .sensitive)")
        do {
            try AgentCallStore.setupSchema(db: db)
        } catch {
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

    /// `~/Library/Application Support/speak/agent-calls.sqlite` — a file distinct
    /// from `history.sqlite`, matching the design doc's "separate store, separate
    /// file" decision.
    public static func makeProductionStore() throws -> AgentCallStore {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        let dir = appSupport.appendingPathComponent("speak", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dbURL = dir.appendingPathComponent("agent-calls.sqlite")
        return try AgentCallStore(databaseURL: dbURL)
    }

    // MARK: - AgentCallStoring

    public func submit(_ submission: AgentCallSubmission) throws -> AgentCallSubmitResult {
        let sessionId = submission.sessionId
        let requestId = submission.requestId
        let idempotencyKey = submission.idempotencyKey
        let prompt = submission.prompt
        let mode = submission.mode
        let choices = submission.choices
        let consequence = submission.consequence
        let spokenSummary = submission.spokenSummary
        let urgency = submission.urgency
        let expiresAt = submission.expiresAt

        let id = UUID()
        let createdAt = now()
        let choicesJSON = try? Self.encodeJSON(choices)

        // Plain INSERT (never INSERT OR REPLACE — a REPLACE would silently
        // overwrite an idempotency-key collision instead of raising
        // SQLITE_CONSTRAINT, which is the only signal `.duplicateSubmission`
        // has to fire on). [decision: AVB-7]
        let sql = """
            INSERT INTO agent_calls
            (id, sessionId, requestId, idempotencyKey, prompt, mode, choicesJSON, consequence,
             spokenSummary, urgency, state, createdAt, expiresAt)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'pending', ?, ?)
            """
        do {
            try execute(sql: sql) { stmt in
                try bind(stmt, index: 1, text: id.uuidString)
                try bind(stmt, index: 2, text: agentCallStoreDBSessionId(sessionId))
                try bind(stmt, index: 3, text: requestId)
                try bindOptional(stmt, index: 4, text: idempotencyKey)
                try bind(stmt, index: 5, text: prompt)
                try bind(stmt, index: 6, text: mode.rawValue)
                try bindOptional(stmt, index: 7, text: choicesJSON)
                try bindOptional(stmt, index: 8, text: consequence)
                try bindOptional(stmt, index: 9, text: spokenSummary)
                try bind(stmt, index: 10, text: urgency.rawValue)
                try bindDouble(stmt, index: 11, value: createdAt.timeIntervalSince1970)
                try bindOptionalDouble(stmt, index: 12, value: expiresAt?.timeIntervalSince1970)
            }
        } catch let error as SpeakError {
            if isConstraintViolation(error), let idempotencyKey {
                // Loser of the idempotency race: look up the winner's row and
                // report its id — never the same `.busy` signal AVB-5 uses;
                // this is a causally different "you already asked this."
                if let existing = try findByIdempotencyKey(sessionId: sessionId, idempotencyKey: idempotencyKey) {
                    return .duplicateSubmission(existingCallId: existing.id)
                }
            }
            throw error
        }

        let call = AgentCall(
            id: id, sessionId: sessionId, requestId: requestId, idempotencyKey: idempotencyKey,
            prompt: prompt, mode: mode, choices: choices, consequence: consequence,
            spokenSummary: spokenSummary, urgency: urgency, state: .pending,
            createdAt: createdAt, expiresAt: expiresAt
        )
        SpeakLog.storage.debug("AgentCallStore submitted call \(id.uuidString, privacy: .private)")
        return .created(call)
    }

    public func get(id: UUID, requestingSessionId: String?) throws -> AgentCall? {
        // Lazy expiry: an always-running menubar app calls `expireOverdue` once
        // at launch (recovery), but a call's `expiresAt` can pass hours later
        // mid-session with nothing else driving a sweep. Every read path must
        // see the CAS-expired state, not a stale `pending`/`presented` row, or
        // an agent's poll (and the inbox) would see an immortal call — the
        // exact bug the design doc's `expiresAt` promise forbids. Same
        // non-suspending actor body, same CAS shape as `resolve`. [decision: AVB-7]
        try expireOverdue(now: now())
        guard let call = try findByID(id) else { return nil }
        // Isolation: a session mismatch is indistinguishable from "not found" —
        // never reveals that the id exists for another session. Single
        // non-suspending body, no TOCTOU window. [decision: AVB-7]
        guard call.sessionId == requestingSessionId else { return nil }
        return call
    }

    public func pendingAndPresented() throws -> [AgentCall] {
        // Lazy expiry — see `get(id:requestingSessionId:)` above for the full
        // rationale. Without this, a call that overstays its `expiresAt`
        // mid-session (no restart in between) would sit in the inbox forever.
        try expireOverdue(now: now())
        let sql = """
            SELECT \(Self.columns) FROM agent_calls
            WHERE state IN ('pending','presented')
            ORDER BY createdAt DESC
            """
        return try query(sql: sql) { _ in }
    }

    public func markPresented(id: UUID) throws {
        let sql = "UPDATE agent_calls SET state = 'presented', presentedAt = ? WHERE id = ? AND state = 'pending'"
        try execute(sql: sql) { stmt in
            try bindDouble(stmt, index: 1, value: now().timeIntervalSince1970)
            try bind(stmt, index: 2, text: id.uuidString)
        }
    }

    @discardableResult
    public func resolve(id: UUID, outcome: HumanResponseOutcome) throws -> Bool {
        // `.busy` has no dedicated `AgentCallState` case (it never reaches a
        // presented capture) — treated as `.cancelled` ("no answer given"),
        // the closest existing terminal semantics. [decision: AVB-7]
        let state: AgentCallState
        switch outcome {
        case .answered: state = .answered
        case .declined: state = .declined
        case .cancelled, .busy: state = .cancelled
        case .timedOut: state = .timedOut
        }
        let responseJSON = try? Self.encodeJSON(outcome)
        let sql = """
            UPDATE agent_calls SET state = ?, resolvedAt = ?, responseJSON = ?
            WHERE id = ? AND state IN ('pending','presented')
            """
        var changed = 0
        try execute(sql: sql) { stmt in
            try bind(stmt, index: 1, text: state.rawValue)
            try bindDouble(stmt, index: 2, value: now().timeIntervalSince1970)
            try bindOptional(stmt, index: 3, text: responseJSON)
            try bind(stmt, index: 4, text: id.uuidString)
        }
        changed = Int(sqlite3_changes(db))
        if changed != 1 {
            SpeakLog.storage.info(
                "AgentCallStore.resolve: id \(id.uuidString, privacy: .private) already terminal — race lost, discarded."
            )
        }
        return changed == 1
    }

    public func expireOverdue(now expiryNow: Date) throws {
        let sql = """
            UPDATE agent_calls SET state = 'expired'
            WHERE state IN ('pending','presented') AND expiresAt IS NOT NULL AND expiresAt < ?
            """
        try execute(sql: sql) { stmt in
            try bindDouble(stmt, index: 1, value: expiryNow.timeIntervalSince1970)
        }
    }

    // MARK: - Schema

    private static let columns = """
        id, sessionId, requestId, idempotencyKey, prompt, mode, choicesJSON, consequence,
        spokenSummary, urgency, state, createdAt, expiresAt, presentedAt, resolvedAt, responseJSON
        """

    private static func setupSchema(db: OpaquePointer?) throws {
        let sql = """
            CREATE TABLE IF NOT EXISTS agent_calls (
                id             TEXT PRIMARY KEY NOT NULL,
                sessionId      TEXT,
                requestId      TEXT NOT NULL,
                idempotencyKey TEXT,
                prompt         TEXT NOT NULL,
                mode           TEXT NOT NULL,
                choicesJSON    TEXT,
                consequence    TEXT,
                spokenSummary  TEXT,
                urgency        TEXT NOT NULL DEFAULT 'normal',
                state          TEXT NOT NULL,
                createdAt      REAL NOT NULL,
                expiresAt      REAL,
                presentedAt    REAL,
                resolvedAt     REAL,
                responseJSON   TEXT
            );
            CREATE INDEX IF NOT EXISTS idx_agent_calls_state ON agent_calls (state, createdAt DESC);
            CREATE INDEX IF NOT EXISTS idx_agent_calls_session ON agent_calls (sessionId, createdAt DESC);
            CREATE UNIQUE INDEX IF NOT EXISTS idx_agent_calls_idempotency
                ON agent_calls (sessionId, idempotencyKey) WHERE idempotencyKey IS NOT NULL;
            """
        var errMsg: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(db, sql, nil, nil, &errMsg) == SQLITE_OK else {
            let msg = errMsg.map { String(cString: $0) } ?? "schema setup failed"
            sqlite3_free(errMsg)
            SpeakLog.storage.error("AgentCallStore schema error: \(msg, privacy: .public)")
            throw SpeakError.unknown("SQLite schema: \(msg)")
        }
        // No additive-column migrations yet — mirrors HistoryStore's precedent
        // (idempotent `ALTER TABLE ... ADD COLUMN`) for when one is needed.
    }

    // MARK: - Row lookups

    private func findByID(_ id: UUID) throws -> AgentCall? {
        let sql = "SELECT \(Self.columns) FROM agent_calls WHERE id = ?"
        let rows = try query(sql: sql) { stmt in
            try bind(stmt, index: 1, text: id.uuidString)
        }
        return rows.first
    }

    private func findByIdempotencyKey(sessionId: String?, idempotencyKey: String) throws -> AgentCall? {
        // The nil-session sentinel (see top of file) means this is always a
        // concrete equality match — no more IS NULL branch needed.
        let sql = "SELECT \(Self.columns) FROM agent_calls WHERE sessionId = ? AND idempotencyKey = ?"
        let rows = try query(sql: sql) { stmt in
            try bind(stmt, index: 1, text: agentCallStoreDBSessionId(sessionId))
            try bind(stmt, index: 2, text: idempotencyKey)
        }
        return rows.first
    }

    // MARK: - Helpers

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

    private func query(sql: String, binder: (OpaquePointer) throws -> Void) throws -> [AgentCall] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw dbError("prepare: \(sql)")
        }
        defer { sqlite3_finalize(stmt) }
        try binder(stmt)

        var results: [AgentCall] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let call = Self.decodeRow(stmt) else {
                SpeakLog.storage.warning("AgentCallStore: skipping malformed row")
                continue
            }
            results.append(call)
        }
        return results
    }

    private static func decodeRow(_ stmt: OpaquePointer) -> AgentCall? {
        guard
            let idCStr = sqlite3_column_text(stmt, 0),
            let id = UUID(uuidString: String(cString: idCStr)),
            let requestIdCStr = sqlite3_column_text(stmt, 2),
            let promptCStr = sqlite3_column_text(stmt, 4),
            let modeCStr = sqlite3_column_text(stmt, 5),
            let mode = RequestInputMode(rawValue: String(cString: modeCStr)),
            let urgencyCStr = sqlite3_column_text(stmt, 9),
            let urgency = AgentCallUrgency(rawValue: String(cString: urgencyCStr)),
            let stateCStr = sqlite3_column_text(stmt, 10),
            let state = AgentCallState(rawValue: String(cString: stateCStr))
        else { return nil }

        // Unmap the nil-session sentinel back to `nil` (also tolerates an
        // actual SQL NULL, for any row written before this mapping existed).
        let sessionId: String? = sqlite3_column_type(stmt, 1) == SQLITE_NULL ? nil :
            sqlite3_column_text(stmt, 1).flatMap { agentCallStoreSessionId(fromDB: String(cString: $0)) }
        let idempotencyKey = sqlite3_column_type(stmt, 3) == SQLITE_NULL ? nil :
            sqlite3_column_text(stmt, 3).map { String(cString: $0) }
        let choicesJSON = sqlite3_column_type(stmt, 6) == SQLITE_NULL ? nil :
            sqlite3_column_text(stmt, 6).map { String(cString: $0) }
        let choices: [String] = choicesJSON.flatMap { try? decodeJSON([String].self, from: $0) } ?? []
        let consequence = sqlite3_column_type(stmt, 7) == SQLITE_NULL ? nil :
            sqlite3_column_text(stmt, 7).map { String(cString: $0) }
        let spokenSummary = sqlite3_column_type(stmt, 8) == SQLITE_NULL ? nil :
            sqlite3_column_text(stmt, 8).map { String(cString: $0) }
        let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 11))
        let expiresAt = sqlite3_column_type(stmt, 12) == SQLITE_NULL ? nil :
            Date(timeIntervalSince1970: sqlite3_column_double(stmt, 12))
        let presentedAt = sqlite3_column_type(stmt, 13) == SQLITE_NULL ? nil :
            Date(timeIntervalSince1970: sqlite3_column_double(stmt, 13))
        let resolvedAt = sqlite3_column_type(stmt, 14) == SQLITE_NULL ? nil :
            Date(timeIntervalSince1970: sqlite3_column_double(stmt, 14))
        let responseJSON = sqlite3_column_type(stmt, 15) == SQLITE_NULL ? nil :
            sqlite3_column_text(stmt, 15).map { String(cString: $0) }
        let response = responseJSON.flatMap { try? decodeJSON(HumanResponseOutcome.self, from: $0) }

        return AgentCall(
            id: id, sessionId: sessionId, requestId: String(cString: requestIdCStr),
            idempotencyKey: idempotencyKey, prompt: String(cString: promptCStr), mode: mode,
            choices: choices, consequence: consequence, spokenSummary: spokenSummary,
            urgency: urgency, state: state, createdAt: createdAt, expiresAt: expiresAt,
            presentedAt: presentedAt, resolvedAt: resolvedAt, response: response
        )
    }

    private func bind(_ stmt: OpaquePointer, index: Int32, text: String) throws {
        guard sqlite3_bind_text(stmt, index, text, -1, agentCallSqliteTransientDestructor) == SQLITE_OK else {
            throw dbError("bind text at index \(index)")
        }
    }

    private func bindOptional(_ stmt: OpaquePointer, index: Int32, text: String?) throws {
        if let text {
            try bind(stmt, index: index, text: text)
        } else {
            guard sqlite3_bind_null(stmt, index) == SQLITE_OK else {
                throw dbError("bind null at index \(index)")
            }
        }
    }

    private func bindDouble(_ stmt: OpaquePointer, index: Int32, value: Double) throws {
        guard sqlite3_bind_double(stmt, index, value) == SQLITE_OK else {
            throw dbError("bind double at index \(index)")
        }
    }

    private func bindOptionalDouble(_ stmt: OpaquePointer, index: Int32, value: Double?) throws {
        if let value {
            try bindDouble(stmt, index: index, value: value)
        } else {
            guard sqlite3_bind_null(stmt, index) == SQLITE_OK else {
                throw dbError("bind null at index \(index)")
            }
        }
    }

    private func isConstraintViolation(_ error: SpeakError) -> Bool {
        if case .unknown(let message) = error {
            return message.contains("UNIQUE constraint failed") || message.contains("constraint failed")
        }
        return false
    }

    private static func encodeJSON<T: Encodable>(_ value: T) throws -> String {
        let data = try JSONEncoder().encode(value)
        guard let string = String(data: data, encoding: .utf8) else {
            throw SpeakError.unknown("AgentCallStore: JSON encoding produced non-UTF8 data")
        }
        return string
    }

    private static func decodeJSON<T: Decodable>(_ type: T.Type, from string: String) throws -> T {
        guard let data = string.data(using: .utf8) else {
            throw SpeakError.unknown("AgentCallStore: JSON decoding got non-UTF8 string")
        }
        return try JSONDecoder().decode(type, from: data)
    }

    private func dbError(_ context: String) -> SpeakError {
        let msg = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown SQLite error"
        SpeakLog.storage.error("AgentCallStore error [\(context, privacy: .public)]: \(msg, privacy: .public)")
        return .unknown("SQLite [\(context)]: \(msg)")
    }
}
