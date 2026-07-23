// SpeakCore/AgentBridge/AgentSessionRegistry.swift
//
// AVB-6 (specs/agent-voice-bridge.md §7.1): the in-memory registry backing
// `speak_register_session` and sessionId threading through the rest of the
// tool surface. An actor so every register/touch/list is a single
// read-modify-write with no TOCTOU window — never check state outside the
// actor then write inside it (the AVB-5 lesson this codebase already paid
// for). In-memory only this slice; durability arrives with AVB-7's inbox
// store — do not add SQLite/UserDefaults persistence here.

import Foundation

public actor AgentSessionRegistry {

    /// A session not registered/touched within this window reads as `.stale`
    /// from `list()`. 30 minutes: long enough to survive a coffee break
    /// without a re-registration ping, short enough that a genuinely dead
    /// agent process doesn't linger as "active" indefinitely. [decision: AVB-6]
    public static let staleThreshold: TimeInterval = 30 * 60

    /// The capability set `speak` actually supports this slice (spec §7.1).
    /// `speak_register_session`'s negotiated response is always a subset of
    /// this list, intersected with what the caller requested — unknown
    /// requested capabilities are dropped silently, never an error.
    public static let supportedCapabilities: [String] = [
        "notify", "say", "ask", "confirm", "request_input", "status"
    ]

    private var sessionsById: [String: AgentSession] = [:]
    private let now: @Sendable () -> Date

    /// - Parameter now: injectable clock for staleness tests.
    public init(now: @escaping @Sendable () -> Date = { Date() }) {
        self.now = now
    }

    /// Register a new session, or re-register an existing one when
    /// `sessionId` is supplied and already known (updates fields + `lastSeen`
    /// rather than creating a duplicate entry).
    ///
    /// Returns the negotiated capabilities — the intersection of `requested`
    /// with `Self.supportedCapabilities`, in `supportedCapabilities`' order so
    /// the response is deterministic regardless of request order.
    @discardableResult
    public func register(
        sessionId: String?,
        provider: String,
        label: String,
        workingDirectory: String?,
        requestedCapabilities: [String]
    ) -> AgentSession {
        let id = sessionId ?? UUID().uuidString
        let negotiated = Self.supportedCapabilities.filter { requestedCapabilities.contains($0) }
        let session = AgentSession(
            sessionId: id,
            provider: provider,
            label: label,
            workingDirectory: workingDirectory,
            capabilities: negotiated,
            state: .active,
            lastSeen: now()
        )
        sessionsById[id] = session
        return session
    }

    /// Update `lastSeen` for a known session. No-op (returns `false`) when
    /// `sessionId` is not registered — the caller decides how to react
    /// (compatibility first: proceed anyway, note the session is unregistered).
    @discardableResult
    public func touch(sessionId: String) -> Bool {
        guard let existing = sessionsById[sessionId] else { return false }
        sessionsById[sessionId] = AgentSession(
            sessionId: existing.sessionId,
            provider: existing.provider,
            label: existing.label,
            workingDirectory: existing.workingDirectory,
            capabilities: existing.capabilities,
            state: .active,
            lastSeen: now()
        )
        return true
    }

    /// `true` iff `sessionId` is a currently-known session (regardless of
    /// staleness) — used to decide whether to attach the "unregistered
    /// session" note to a tool result.
    public func isKnown(sessionId: String) -> Bool {
        sessionsById[sessionId] != nil
    }

    /// All registered sessions, with `state` derived against `now()` at this
    /// snapshot instant.
    public func list() -> [AgentSession] {
        let cutoff = now().addingTimeInterval(-Self.staleThreshold)
        return sessionsById.values.map { session in
            let state: AgentSessionState = session.lastSeen < cutoff ? .stale : .active
            return AgentSession(
                sessionId: session.sessionId,
                provider: session.provider,
                label: session.label,
                workingDirectory: session.workingDirectory,
                capabilities: session.capabilities,
                state: state,
                lastSeen: session.lastSeen
            )
        }
    }
}
