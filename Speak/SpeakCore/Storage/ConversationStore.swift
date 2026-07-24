// SpeakCore/Storage/ConversationStore.swift
//
// SQLite-backed persistence for Agent Playground conversations and messages.
// Own file (conversations.sqlite), own connection, own actor — follows the
// established HistoryStore/AgentCallStore pattern: raw SQLite3 C API, actor
// isolation, protocol-first for testability.

import Foundation
import os
import SQLite3

// MARK: - SQLITE_TRANSIENT shim

private let conversationSqliteTransientDestructor: sqlite3_destructor_type =
    unsafeBitCast(-1 as Int, to: sqlite3_destructor_type.self)

// MARK: - Models

/// A conversation thread in the Agent Playground.
public struct Conversation: Sendable, Identifiable, Equatable {
    public let id: String
    public let title: String
    public let model: String
    public let systemPrompt: String?
    public let createdAt: Date

    public init(id: String, title: String, model: String, systemPrompt: String?, createdAt: Date) {
        self.id = id
        self.title = title
        self.model = model
        self.systemPrompt = systemPrompt
        self.createdAt = createdAt
    }
}

/// A single message within a conversation.
public struct ChatMessage: Sendable, Identifiable, Equatable {
    public let id: String
    public let conversationId: String
    public let role: String
    public let content: String
    public let createdAt: Date

    public init(id: String, conversationId: String, role: String, content: String, createdAt: Date) {
        self.id = id
        self.conversationId = conversationId
        self.role = role
        self.content = content
        self.createdAt = createdAt
    }
}

// MARK: - ConversationStoring protocol

/// Protocol for conversation persistence, enabling test doubles.
public protocol ConversationStoring: Sendable {
    func createConversation(title: String, model: String, systemPrompt: String?) async throws -> Conversation
    func listConversations(limit: Int) async throws -> [Conversation]
    func deleteConversation(id: String) async throws
    func appendMessage(conversationId: String, role: String, content: String) async throws -> ChatMessage
    func messages(conversationId: String) async throws -> [ChatMessage]
}

// MARK: - ConversationStore

public actor ConversationStore: ConversationStoring {

    // MARK: - State

    nonisolated(unsafe) private var db: OpaquePointer?

    // MARK: - Init / deinit

    public init(databaseURL: URL) throws {
        let path = databaseURL.path
        guard sqlite3_open_v2(
            path, &db,
            SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        ) == SQLITE_OK else {
            let msg = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unable to open database"
            SpeakLog.storage.error("ConversationStore open failed: \(msg, privacy: .public)")
            if let handle = db { sqlite3_close_v2(handle) }
            throw SpeakError.unknown("SQLite open failed: \(msg)")
        }
        SpeakLog.storage.info("ConversationStore opened at \(path, privacy: .sensitive)")
        do {
            try ConversationStore.setupSchema(db: db)
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

    // MARK: - Factory

    /// ~/Library/Application Support/speak/conversations.sqlite
    public static func makeProductionStore() throws -> ConversationStore {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        let dir = appSupport.appendingPathComponent("speak", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dbURL = dir.appendingPathComponent("conversations.sqlite")
        return try ConversationStore(databaseURL: dbURL)
    }

    // MARK: - Schema

    private static func setupSchema(db: OpaquePointer?) throws {
        let conversationsDDL = """
            CREATE TABLE IF NOT EXISTS conversations (
                id TEXT PRIMARY KEY NOT NULL,
                title TEXT NOT NULL,
                model TEXT NOT NULL,
                systemPrompt TEXT,
                createdAt REAL NOT NULL
            );
            CREATE INDEX IF NOT EXISTS idx_conversations_createdAt
                ON conversations (createdAt DESC);
            """

        let messagesDDL = """
            CREATE TABLE IF NOT EXISTS messages (
                id TEXT PRIMARY KEY NOT NULL,
                conversationId TEXT NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
                role TEXT NOT NULL,
                content TEXT NOT NULL,
                createdAt REAL NOT NULL
            );
            CREATE INDEX IF NOT EXISTS idx_messages_conversation
                ON messages (conversationId, createdAt ASC);
            """

        var errMsg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, conversationsDDL, nil, nil, &errMsg) != SQLITE_OK {
            let msg = errMsg.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(errMsg)
            throw SpeakError.unknown("Schema setup (conversations) failed: \(msg)")
        }
        if sqlite3_exec(db, messagesDDL, nil, nil, &errMsg) != SQLITE_OK {
            let msg = errMsg.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(errMsg)
            throw SpeakError.unknown("Schema setup (messages) failed: \(msg)")
        }

        sqlite3_exec(db, "PRAGMA foreign_keys = ON;", nil, nil, nil)
    }

    // MARK: - ConversationStoring

    public func createConversation(title: String, model: String, systemPrompt: String?) async throws -> Conversation {
        let conversation = Conversation(
            id: UUID().uuidString,
            title: title,
            model: model,
            systemPrompt: systemPrompt,
            createdAt: Date()
        )

        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(
            db,
            "INSERT INTO conversations (id, title, model, systemPrompt, createdAt) VALUES (?, ?, ?, ?, ?)",
            -1, &stmt, nil
        ) == SQLITE_OK else {
            throw dbError("prepare createConversation")
        }

        sqlite3_bind_text(stmt, 1, (conversation.id as NSString).utf8String, -1, conversationSqliteTransientDestructor)
        sqlite3_bind_text(stmt, 2, (title as NSString).utf8String, -1, conversationSqliteTransientDestructor)
        sqlite3_bind_text(stmt, 3, (model as NSString).utf8String, -1, conversationSqliteTransientDestructor)
        if let systemPrompt {
            sqlite3_bind_text(stmt, 4, (systemPrompt as NSString).utf8String, -1, conversationSqliteTransientDestructor)
        } else {
            sqlite3_bind_null(stmt, 4)
        }
        sqlite3_bind_double(stmt, 5, conversation.createdAt.timeIntervalSince1970)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw dbError("insert createConversation")
        }

        return conversation
    }

    public func listConversations(limit: Int) async throws -> [Conversation] {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(
            db,
            "SELECT id, title, model, systemPrompt, createdAt FROM conversations ORDER BY createdAt DESC LIMIT ?",
            -1, &stmt, nil
        ) == SQLITE_OK else {
            throw dbError("prepare listConversations")
        }

        sqlite3_bind_int(stmt, 1, Int32(limit))

        var results: [Conversation] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = columnText(stmt, 0)
            let title = columnText(stmt, 1)
            let model = columnText(stmt, 2)
            let systemPrompt = columnTextOrNil(stmt, 3)
            let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 4))
            results.append(Conversation(id: id, title: title, model: model, systemPrompt: systemPrompt, createdAt: createdAt))
        }

        return results
    }

    public func deleteConversation(id: String) async throws {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(
            db,
            "DELETE FROM conversations WHERE id = ?",
            -1, &stmt, nil
        ) == SQLITE_OK else {
            throw dbError("prepare deleteConversation")
        }

        sqlite3_bind_text(stmt, 1, (id as NSString).utf8String, -1, conversationSqliteTransientDestructor)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw dbError("delete conversation")
        }
    }

    public func appendMessage(conversationId: String, role: String, content: String) async throws -> ChatMessage {
        let message = ChatMessage(
            id: UUID().uuidString,
            conversationId: conversationId,
            role: role,
            content: content,
            createdAt: Date()
        )

        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(
            db,
            "INSERT INTO messages (id, conversationId, role, content, createdAt) VALUES (?, ?, ?, ?, ?)",
            -1, &stmt, nil
        ) == SQLITE_OK else {
            throw dbError("prepare appendMessage")
        }

        sqlite3_bind_text(stmt, 1, (message.id as NSString).utf8String, -1, conversationSqliteTransientDestructor)
        sqlite3_bind_text(stmt, 2, (conversationId as NSString).utf8String, -1, conversationSqliteTransientDestructor)
        sqlite3_bind_text(stmt, 3, (role as NSString).utf8String, -1, conversationSqliteTransientDestructor)
        sqlite3_bind_text(stmt, 4, (content as NSString).utf8String, -1, conversationSqliteTransientDestructor)
        sqlite3_bind_double(stmt, 5, message.createdAt.timeIntervalSince1970)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw dbError("insert appendMessage")
        }

        return message
    }

    public func messages(conversationId: String) async throws -> [ChatMessage] {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(
            db,
            "SELECT id, conversationId, role, content, createdAt FROM messages WHERE conversationId = ? ORDER BY createdAt ASC",
            -1, &stmt, nil
        ) == SQLITE_OK else {
            throw dbError("prepare messages")
        }

        sqlite3_bind_text(stmt, 1, (conversationId as NSString).utf8String, -1, conversationSqliteTransientDestructor)

        var results: [ChatMessage] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = columnText(stmt, 0)
            let convId = columnText(stmt, 1)
            let role = columnText(stmt, 2)
            let content = columnText(stmt, 3)
            let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 4))
            results.append(ChatMessage(id: id, conversationId: convId, role: role, content: content, createdAt: createdAt))
        }

        return results
    }

    // MARK: - Helpers

    private func columnText(_ stmt: OpaquePointer?, _ index: Int32) -> String {
        guard let cString = sqlite3_column_text(stmt, index) else { return "" }
        return String(cString: cString)
    }

    private func columnTextOrNil(_ stmt: OpaquePointer?, _ index: Int32) -> String? {
        guard sqlite3_column_type(stmt, index) != SQLITE_NULL,
              let cString = sqlite3_column_text(stmt, index) else { return nil }
        return String(cString: cString)
    }

    private func dbError(_ context: String) -> SpeakError {
        let msg = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
        SpeakLog.storage.error("ConversationStore \(context, privacy: .public): \(msg, privacy: .public)")
        return SpeakError.unknown("ConversationStore \(context): \(msg)")
    }
}

// MARK: - NullConversationStore (preview/test double)

/// No-op conformer for previews and tests that don't need persistence.
public struct NullConversationStore: ConversationStoring {
    public init() {}

    public func createConversation(title: String, model: String, systemPrompt: String?) async throws -> Conversation {
        Conversation(id: UUID().uuidString, title: title, model: model, systemPrompt: systemPrompt, createdAt: Date())
    }

    public func listConversations(limit: Int) async throws -> [Conversation] { [] }

    public func deleteConversation(id: String) async throws {}

    public func appendMessage(conversationId: String, role: String, content: String) async throws -> ChatMessage {
        ChatMessage(id: UUID().uuidString, conversationId: conversationId, role: role, content: content, createdAt: Date())
    }

    public func messages(conversationId: String) async throws -> [ChatMessage] { [] }
}
