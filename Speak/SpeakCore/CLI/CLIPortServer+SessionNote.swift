// SpeakCore/CLI/CLIPortServer+SessionNote.swift
//
// Shared AVB-6 session-note helper for CLIPortServer pump paths.

import Foundation

extension CLIPortServer {
    /// Resolve the optional "unregistered session" note for a request that
    /// carries `sessionId`. `nil` when no `sessionId` was supplied (today's
    /// behavior, unchanged) or when it was supplied and is a known session.
    ///
    /// Previously bridged through a `Task{@MainActor}` + run-loop pump on the
    /// theory that `AgentSessionRegistry` (a separate `actor`) needed an
    /// `await` unreachable from this synchronous call site. That bridge
    /// starved in practice — live-log evidence (2026-08-01) showed the
    /// dispatched Task did not run until the pump's timeout had already
    /// elapsed, so every call carrying a `sessionId` silently ate 5 seconds
    /// and then omitted the note. `AgentSessionRegistry` is now
    /// `@MainActor`-isolated, so `cliTouchSession` is synchronous and this
    /// call is direct — no Task, no pump. [decision: AVB-6-pump-fix]
    static func pumpedSessionNote(sessionId: String?, handler: any CLICommandHandler) -> String? {
        guard let sessionId else { return nil }
        let known = handler.cliTouchSession(sessionId)
        return known ? nil : BridgeOutcome<Void>.unregisteredSessionNote(sessionId)
    }
}
