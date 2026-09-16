// App/DictationController+NullStores.swift
//
// No-op persistence fallbacks for `DictationController`. Extracted from
// DictationController.swift to keep that file under SwiftLint's
// `file_length` cap — pure code motion, no behavior change. These types are
// module-internal (previously file-private) for exactly that reason.

import Foundation
import SpeakCore

// MARK: - NullHistoryStore

/// A no-op `HistoryStoring` used when the production SQLite store fails to open.
/// Every method succeeds silently — the dictation flow is unaffected.
final class NullHistoryStore: HistoryStoring, @unchecked Sendable {
    func save(_ entry: HistoryEntry) throws {}
    func recent(limit: Int) throws -> [HistoryEntry] { [] }
    func search(_ substring: String) throws -> [HistoryEntry] { [] }
    func clear() throws {}
    func export() throws -> String { "[]" }
}

// MARK: - NullAgentCallStore

/// AVB-7: a no-op `AgentCallStoring` used when `AgentCallStore`'s SQLite open
/// fails. Mirrors `NullHistoryStore`'s degradation shape — the durable-call
/// surface is silently disabled for the session rather than crashing the app;
/// `speak_request_input`'s own round-trip is entirely unaffected (its durable
/// side effect is a best-effort write that swallows errors already).
actor NullAgentCallStore: AgentCallStoring {
    func submit(_ submission: AgentCallSubmission) async throws -> AgentCallSubmitResult {
        throw SpeakError.unknown("AgentCallStore unavailable")
    }
    func get(id: UUID, requestingSessionId: String?) async throws -> AgentCall? { nil }
    func pendingAndPresented() async throws -> [AgentCall] { [] }
    func markPresented(id: UUID) async throws {}
    @discardableResult
    func resolve(id: UUID, outcome: HumanResponseOutcome) async throws -> Bool { false }
    func expireOverdue(now: Date) async throws {}
}

/// Open the production `AgentCallStore`, falling back to `NullAgentCallStore`
/// on failure. A free function (not a method) so `DictationController`'s own
/// class body stays under SwiftLint's `type_body_length` cap — pure code
/// motion, no behavior change, matching the existing precedent
/// (`applyAppearance`/`rebindExtraBindings` moved to an extension for the
/// same reason).
func makeAgentCallStore() -> any AgentCallStoring {
    do {
        return try AgentCallStore.makeProductionStore()
    } catch {
        SpeakLog.storage.error(
            "DictationController: AgentCallStore open failed — durable calls disabled. \(error.localizedDescription, privacy: .public)"
        )
        return NullAgentCallStore()
    }
}
