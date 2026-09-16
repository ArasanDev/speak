// SpeakCore/AgentBridge/AgentSessionRegistry.swift
//
// AVB-6 (specs/agent-voice-bridge.md §7.1): the in-memory registry backing
// `speak_register_session` and sessionId threading through the rest of the
// tool surface. `@MainActor`-isolated (not a separate `actor`) so every
// register/touch/list is still a single read-modify-write with no TOCTOU
// window — never check state outside the isolation domain then write inside
// it (the AVB-5 lesson this codebase already paid for) — but callers on the
// main thread (`CLIPortServer`'s CFMessagePort callback) can now call in
// synchronously via `MainActor.assumeIsolated`, matching the `--status` path,
// instead of bridging through a `Task{@MainActor}` + run-loop pump. That
// bridge was found to starve: the dispatched Task reliably did not run until
// `pumpUntilResult`'s timeout had already elapsed and given up, making
// `speak_register_session` fail every time despite the underlying work being
// trivial in-memory state (see AgentBridgeServerTests + live-log evidence,
// 2026-08-01). A separate `actor` adds a genuine cross-domain hop for work
// that never needed one; `@MainActor` keeps the same single-writer guarantee
// with none of the bridging risk. In-memory only this slice; durability
// arrives with AVB-7's inbox store — do not add SQLite/UserDefaults
// persistence here.

import Foundation

/// Outcome of `AgentSessionRegistry.register`. `.rejected` means the caller
/// asked to re-register a sessionId that is already held by a DIFFERENT
/// caller — the existing session (and its token) is left untouched. Rejecting
/// rather than rotating is the whole point of the token: silently rotating
/// the capability on re-register would let any local process that learns a
/// sessionId hijack the session. [decision: session-capability-token]
public enum AgentSessionRegistration: Sendable, Equatable {
    /// Registration accepted. `sessionToken` is the opaque capability the
    /// caller must present alongside `sessionId` on every session-scoped
    /// request (and on any later re-registration of the same sessionId).
    case registered(session: AgentSession, sessionToken: String)
    /// The supplied sessionId is already registered and the presented token
    /// was missing or did not match. No state changed.
    case rejected
}

@MainActor
public final class AgentSessionRegistry {

    /// A session not registered/touched within this window reads as `.stale`
    /// from `list()`. 30 minutes: long enough to survive a coffee break
    /// without a re-registration ping, short enough that a genuinely dead
    /// agent process doesn't linger as "active" indefinitely. [decision: AVB-6]
    public static nonisolated let staleThreshold: TimeInterval = 30 * 60

    /// The capability set `speak` actually supports this slice (spec §7.1).
    /// `speak_register_session`'s negotiated response is always a subset of
    /// this list, intersected with what the caller requested — unknown
    /// requested capabilities are dropped silently, never an error.
    public static let supportedCapabilities: [String] = [
        "notify", "say", "ask", "confirm", "request_input", "status"
    ]

    private var sessionsById: [String: AgentSession] = [:]
    /// Per-session capability tokens, keyed by sessionId. Kept OUT of
    /// `AgentSession` itself so the token never rides the Codable session
    /// record into `list()`/`Dashboard`/`sessionNote` surfaces — it is a
    /// bearer credential returned exactly once, at registration.
    /// [decision: session-capability-token]
    private var tokensById: [String: String] = [:]
    private let now: @Sendable () -> Date

    /// - Parameter now: injectable clock for staleness tests.
    public nonisolated init(now: @escaping @Sendable () -> Date = { Date() }) {
        self.now = now
    }

    /// Register a new session, or re-register an existing one when
    /// `sessionId` is supplied and already known AND the presented
    /// `sessionToken` matches the token issued at first registration
    /// (updates fields + `lastSeen` rather than creating a duplicate entry).
    ///
    /// Token semantics [decision: session-capability-token]:
    ///   - New/unknown sessionId → a fresh opaque token is minted
    ///     (`UUID().uuidString` — a local capability, not crypto-bearing) and
    ///     returned in `.registered`. The caller presents it alongside
    ///     `sessionId` on every session-scoped request.
    ///   - Re-register a known sessionId with the SAME token → allowed;
    ///     idempotent reconnect (e.g. an agent that restarted). The stored
    ///     token is NOT rotated — the same token is returned again.
    ///   - Re-register a known sessionId with a missing or DIFFERENT token →
    ///     `.rejected`; the existing session and token are untouched. Never
    ///     silently rotate: that was the session-hijack vector.
    ///   - A session only stops being "known" if a future cleanup/eviction
    ///     removes it (see the TODO below — sessions currently persist for
    ///     the app lifetime). After eviction the sessionId is unknown again,
    ///     so re-registering with a stale token becomes a FRESH registration
    ///     and is allowed.
    ///
    /// `negotiated` capabilities are the intersection of `requested`
    /// with `Self.supportedCapabilities`, in `supportedCapabilities`' order so
    /// the response is deterministic regardless of request order.
    @discardableResult
    public func register(
        sessionId: String?,
        provider: String,
        label: String,
        workingDirectory: String?,
        requestedCapabilities: [String],
        sessionToken: String?
    ) -> AgentSessionRegistration {
        let id = sessionId ?? UUID().uuidString
        let existingToken = tokensById[id]
        if sessionsById[id] != nil, existingToken != sessionToken {
            return .rejected
        }
        let token = existingToken ?? UUID().uuidString
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
        // TODO(agentbridge-protocol-edges survey, critical, left unfixed):
        // `sessionsById` only ever grows — sessions become `.stale` after
        // `staleThreshold` inactivity (see `list()` below) but are never
        // actually removed from storage, so a long-running app with many
        // short-lived agent sessions accumulates entries forever. Two
        // candidate fixes, neither applied here because the choice affects
        // in-flight lookups and needs a deliberate decision:
        //   1. Evict-on-register: before inserting `session` here, sweep
        //      `sessionsById` for entries past some hard eviction threshold
        //      (longer than `staleThreshold`, e.g. 24h) and remove them —
        //      zero extra scheduling, but only reclaims memory on the next
        //      registration, not while the app sits idle.
        //   2. Periodic sweep task: a `Task` (owned by whoever constructs
        //      this actor) that wakes on an interval and calls a new
        //      `evictStale(olderThan:)` method — reclaims memory even with
        //      no new registrations, but adds another long-lived task whose
        //      lifecycle must be managed (see the lifecycle-leaks survey
        //      findings in DictationController/StatusBarController/
        //      HistoryViewModel for why that bookkeeping matters here).
        // Either way, `isKnown(sessionId:)`/`touch`/`list()` must
        // keep working for any session not yet evicted — no TOCTOU window.
        sessionsById[id] = session
        tokensById[id] = token
        return .registered(session: session, sessionToken: token)
    }

    /// `true` iff `sessionId` is a currently-known session AND `sessionToken`
    /// matches the token issued at registration. This is the session-scoped
    /// auth check: a wrong/missing token is indistinguishable from an
    /// unregistered session — callers must never leak "exists but wrong
    /// token" upstream. [decision: session-capability-token]
    public func isAuthenticated(sessionId: String, sessionToken: String?) -> Bool {
        guard let sessionToken else { return false }
        return tokensById[sessionId] == sessionToken
    }

    /// Update `lastSeen` for an authenticated session. No-op (returns
    /// `false`) when `sessionId` is not registered OR the token doesn't
    /// match — an unauthenticated caller must not be able to refresh another
    /// session's liveness. [decision: session-capability-token]
    @discardableResult
    public func touch(sessionId: String, sessionToken: String?) -> Bool {
        guard isAuthenticated(sessionId: sessionId, sessionToken: sessionToken),
              let existing = sessionsById[sessionId] else { return false }
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
