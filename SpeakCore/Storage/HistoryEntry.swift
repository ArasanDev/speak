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

    public init(
        id: UUID = UUID(),
        rawText: String,
        cleanedText: String?,
        createdAt: Date = Date(),
        engineId: String
    ) {
        self.id = id
        self.rawText = rawText
        self.cleanedText = cleanedText
        self.createdAt = createdAt
        self.engineId = engineId
    }
}
