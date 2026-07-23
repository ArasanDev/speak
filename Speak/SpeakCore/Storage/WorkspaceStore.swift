// Speak/SpeakCore/Storage/WorkspaceStore.swift
//
// SQLite-backed persistence for Workspace Channels, Spoken Threads, and Evidence Cards.
// Uses raw SQLite3 C API (`import SQLite3`) for 100% local privacy without third-party dependencies.

import Foundation
import os
import SQLite3

private let sqliteTransientDestructor: sqlite3_destructor_type =
    unsafeBitCast(-1 as Int, to: sqlite3_destructor_type.self)

/// Workspace Channel domain model.
public struct Channel: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let topic: String?
    public let isPrivate: Bool
    public let createdAt: Date

    public init(id: String, name: String, topic: String? = nil, isPrivate: Bool = false, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.topic = topic
        self.isPrivate = isPrivate
        self.createdAt = createdAt
    }
}

/// Workspace Message / Thread Turn model.
public struct WorkspaceMessage: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let channelId: String
    public let threadId: UUID?
    public let senderTag: String
    public let text: String
    public let createdAt: Date

    public init(id: UUID = UUID(), channelId: String, threadId: UUID? = nil, senderTag: String, text: String, createdAt: Date = Date()) {
        self.id = id
        self.channelId = channelId
        self.threadId = threadId
        self.senderTag = senderTag
        self.text = text
        self.createdAt = createdAt
    }
}

/// Actor managing the workspace database (`workspace.sqlite`).
public actor WorkspaceStore {
    nonisolated(unsafe) private var db: OpaquePointer?

    public init(databaseURL: URL) throws {
        var dbHandle: OpaquePointer?
        let openResult = sqlite3_open_v2(
            databaseURL.path,
            &dbHandle,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX,
            nil
        )
        guard openResult == SQLITE_OK, let db = dbHandle else {
            let errmsg = dbHandle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            sqlite3_close(dbHandle)
            throw SpeakError.unknown("Failed to open WorkspaceStore at \(databaseURL.path): \(errmsg)")
        }
        self.db = db
        try Self.setupSchema(db: db)
        try Self.createDefaultChannelIfNeeded(db: db)
    }

    deinit {
        if let db {
            sqlite3_close_v2(db)
        }
    }

    public static func makeProductionStore() throws -> WorkspaceStore {
        guard let appSupportBase = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw SpeakError.unknown("Could not locate Application Support directory")
        }
        let appSupport = appSupportBase.appendingPathComponent("speak", isDirectory: true)
        try FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        let dbURL = appSupport.appendingPathComponent("workspace.sqlite")
        return try WorkspaceStore(databaseURL: dbURL)
    }

    private static func setupSchema(db: OpaquePointer?) throws {
        let sql = """
        CREATE TABLE IF NOT EXISTS channels (
            id TEXT PRIMARY KEY NOT NULL,
            name TEXT NOT NULL,
            topic TEXT,
            isPrivate INTEGER NOT NULL,
            createdAt REAL NOT NULL
        );
        CREATE TABLE IF NOT EXISTS messages (
            id TEXT PRIMARY KEY NOT NULL,
            channelId TEXT NOT NULL,
            threadId TEXT,
            senderTag TEXT NOT NULL,
            text TEXT NOT NULL,
            createdAt REAL NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_messages_channel ON messages (channelId, createdAt DESC);
        CREATE INDEX IF NOT EXISTS idx_messages_thread ON messages (threadId, createdAt ASC);
        """
        var errmsg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &errmsg) != SQLITE_OK {
            let msg = errmsg.map { String(cString: $0) } ?? "unknown error"
            sqlite3_free(errmsg)
            throw SpeakError.unknown("WorkspaceStore schema setup failed: \(msg)")
        }
    }

    private static func createDefaultChannelIfNeeded(db: OpaquePointer?) throws {
        let channels = try fetchChannels(db: db)
        if channels.isEmpty {
            let general = Channel(id: "general", name: "general", topic: "Default workspace channel", isPrivate: false)
            try createChannel(general, db: db)
        }
    }

    // MARK: - Channels API

    public func createChannel(_ channel: Channel) throws {
        try Self.createChannel(channel, db: db)
    }

    private static func createChannel(_ channel: Channel, db: OpaquePointer?) throws {
        let sql = "INSERT OR REPLACE INTO channels (id, name, topic, isPrivate, createdAt) VALUES (?, ?, ?, ?, ?);"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SpeakError.unknown("Failed to prepare createChannel statement")
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, channel.id, -1, sqliteTransientDestructor)
        sqlite3_bind_text(stmt, 2, channel.name, -1, sqliteTransientDestructor)
        if let topic = channel.topic {
            sqlite3_bind_text(stmt, 3, topic, -1, sqliteTransientDestructor)
        } else {
            sqlite3_bind_null(stmt, 3)
        }
        sqlite3_bind_int(stmt, 4, channel.isPrivate ? 1 : 0)
        sqlite3_bind_double(stmt, 5, channel.createdAt.timeIntervalSince1970)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw SpeakError.unknown("Failed to execute createChannel: \(msg)")
        }
    }

    public func fetchChannels() throws -> [Channel] {
        try Self.fetchChannels(db: db)
    }

    private static func fetchChannels(db: OpaquePointer?) throws -> [Channel] {
        let sql = "SELECT id, name, topic, isPrivate, createdAt FROM channels ORDER BY name ASC;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SpeakError.unknown("Failed to prepare fetchChannels statement")
        }
        defer { sqlite3_finalize(stmt) }

        var results: [Channel] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = String(cString: sqlite3_column_text(stmt, 0))
            let name = String(cString: sqlite3_column_text(stmt, 1))
            let topic = sqlite3_column_type(stmt, 2) == SQLITE_NULL ? nil : String(cString: sqlite3_column_text(stmt, 2))
            let isPrivate = sqlite3_column_int(stmt, 3) != 0
            let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 4))
            results.append(Channel(id: id, name: name, topic: topic, isPrivate: isPrivate, createdAt: createdAt))
        }
        return results
    }

    // MARK: - Messages API & Search

    public func postMessage(_ msg: WorkspaceMessage) throws {
        let sql = "INSERT OR REPLACE INTO messages (id, channelId, threadId, senderTag, text, createdAt) VALUES (?, ?, ?, ?, ?, ?);"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SpeakError.unknown("Failed to prepare postMessage statement")
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, msg.id.uuidString, -1, sqliteTransientDestructor)
        sqlite3_bind_text(stmt, 2, msg.channelId, -1, sqliteTransientDestructor)
        if let threadId = msg.threadId {
            sqlite3_bind_text(stmt, 3, threadId.uuidString, -1, sqliteTransientDestructor)
        } else {
            sqlite3_bind_null(stmt, 3)
        }
        sqlite3_bind_text(stmt, 4, msg.senderTag, -1, sqliteTransientDestructor)
        sqlite3_bind_text(stmt, 5, msg.text, -1, sqliteTransientDestructor)
        sqlite3_bind_double(stmt, 6, msg.createdAt.timeIntervalSince1970)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw SpeakError.unknown("Failed to execute postMessage: \(msg)")
        }
    }

    public func fetchMessages(channelId: String, threadId: UUID? = nil) throws -> [WorkspaceMessage] {
        let sql: String
        if threadId != nil {
            sql = "SELECT id, channelId, threadId, senderTag, text, createdAt FROM messages WHERE channelId = ? AND threadId = ? ORDER BY createdAt ASC;"
        } else {
            sql = "SELECT id, channelId, threadId, senderTag, text, createdAt FROM messages WHERE channelId = ? AND threadId IS NULL ORDER BY createdAt ASC;"
        }

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SpeakError.unknown("Failed to prepare fetchMessages statement")
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, channelId, -1, sqliteTransientDestructor)
        if let targetThreadId = threadId {
            sqlite3_bind_text(stmt, 2, targetThreadId.uuidString, -1, sqliteTransientDestructor)
        }

        var results: [WorkspaceMessage] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let id = UUID(uuidString: String(cString: sqlite3_column_text(stmt, 0))) else { continue }
            let chanId = String(cString: sqlite3_column_text(stmt, 1))
            let thId = sqlite3_column_type(stmt, 2) == SQLITE_NULL ? nil : UUID(uuidString: String(cString: sqlite3_column_text(stmt, 2)))
            let sender = String(cString: sqlite3_column_text(stmt, 3))
            let text = String(cString: sqlite3_column_text(stmt, 4))
            let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 5))
            results.append(WorkspaceMessage(id: id, channelId: chanId, threadId: thId, senderTag: sender, text: text, createdAt: createdAt))
        }
        return results
    }

    public func searchMessagesFTS(query: String) throws -> [WorkspaceMessage] {
        let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanQuery.isEmpty else { return [] }
        let sql = "SELECT id, channelId, threadId, senderTag, text, createdAt FROM messages WHERE text LIKE ? ORDER BY createdAt DESC LIMIT 20;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SpeakError.unknown("Failed to prepare searchMessagesFTS statement")
        }
        defer { sqlite3_finalize(stmt) }
        let pattern = "%\(cleanQuery)%"
        sqlite3_bind_text(stmt, 1, pattern, -1, sqliteTransientDestructor)

        var results: [WorkspaceMessage] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let id = UUID(uuidString: String(cString: sqlite3_column_text(stmt, 0))) else { continue }
            let chanId = String(cString: sqlite3_column_text(stmt, 1))
            let thId = sqlite3_column_type(stmt, 2) == SQLITE_NULL ? nil : UUID(uuidString: String(cString: sqlite3_column_text(stmt, 2)))
            let sender = String(cString: sqlite3_column_text(stmt, 3))
            let text = String(cString: sqlite3_column_text(stmt, 4))
            let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 5))
            results.append(WorkspaceMessage(id: id, channelId: chanId, threadId: thId, senderTag: sender, text: text, createdAt: createdAt))
        }
        return results
    }
}
