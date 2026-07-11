// SpeakCore/AgentBridge/AgentCall.swift
//
// AVB-7 (specs/avb7-durable-calls-design.md): durable Agent Calls + local inbox.
// Domain types only — no SQLite, no MCP types. `AgentCallStore` (Storage/) is the
// concrete `AgentCallStoring` conformer; `speak_submit_call`/`speak_get_call` (MCP
// tool layer) and `speak_request_input`'s adapter path both go through this
// protocol, never around it.

import Foundation

/// Caller-supplied hint only — never authority over presentation (spec §3:
/// "urgency is input, never authority"). This slice's inbox never branches on it.
public enum AgentCallUrgency: String, Codable, Sendable, Equatable {
    case low, normal, high
}

/// spec §3 `AgentCall` state machine:
///   pending --present()--> presented --resolve()--> {answered, declined, cancelled, timedOut}
///   pending/presented --expire()--> expired   (deadline elapsed, human never engaged)
/// `expired` is distinct from `timedOut`: `timedOut` means a live capture round-trip's own
/// deadline elapsed (AVB-5 semantics, still used by the adapter path); `expired` means the
/// call sat in the inbox past `expiresAt` with no human action at all.
public enum AgentCallState: String, Codable, Sendable, Equatable {
    case pending, presented, answered, declined, cancelled, timedOut, expired

    public var isTerminal: Bool {
        switch self {
        case .pending, .presented: return false
        case .answered, .declined, .cancelled, .timedOut, .expired: return true
        }
    }
}

/// Durable request record (spec §3 `AgentCall`). `response` is populated only once `state`
/// reaches a terminal value — it is exactly a `HumanResponseOutcome`, never a re-encoding of
/// one, so `speak_get_call`'s reply and `speak_request_input`'s reply share one shape.
///
/// `Codable` so this type can also be the CLI wire payload for `.submitCall`/`.getCall`
/// (`CLIReply.agentCall`) — shared, not re-encoded, across the MCP-process ↔ app-process
/// boundary. [decision: AVB-7]
public struct AgentCall: Sendable, Equatable, Identifiable, Codable {
    public let id: UUID
    /// AVB-6 `AgentSession.sessionId` that submitted this call. Required for
    /// `speak_submit_call`/`speak_get_call`; `nil` only for the `speak_request_input`
    /// legacy adapter path, which never leaves the requesting call stack (§ Isolation below).
    public let sessionId: String?
    public let requestId: String
    public let idempotencyKey: String?
    public let prompt: String
    public let mode: RequestInputMode
    public let choices: [String]
    public let consequence: String?
    public let spokenSummary: String?
    public let urgency: AgentCallUrgency
    public var state: AgentCallState
    public let createdAt: Date
    public let expiresAt: Date?
    public var presentedAt: Date?
    public var resolvedAt: Date?
    public var response: HumanResponseOutcome?

    public init(
        id: UUID,
        sessionId: String?,
        requestId: String,
        idempotencyKey: String?,
        prompt: String,
        mode: RequestInputMode,
        choices: [String],
        consequence: String?,
        spokenSummary: String?,
        urgency: AgentCallUrgency,
        state: AgentCallState,
        createdAt: Date,
        expiresAt: Date?,
        presentedAt: Date? = nil,
        resolvedAt: Date? = nil,
        response: HumanResponseOutcome? = nil
    ) {
        self.id = id
        self.sessionId = sessionId
        self.requestId = requestId
        self.idempotencyKey = idempotencyKey
        self.prompt = prompt
        self.mode = mode
        self.choices = choices
        self.consequence = consequence
        self.spokenSummary = spokenSummary
        self.urgency = urgency
        self.state = state
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.presentedAt = presentedAt
        self.resolvedAt = resolvedAt
        self.response = response
    }
}

public enum AgentCallSubmitResult: Sendable, Equatable {
    case created(AgentCall)
    /// Same (sessionId, idempotencyKey) already has a live (non-terminal) call.
    /// Distinct from `.busy` (AVB-5: "a synchronous capture is in flight") — this is
    /// "you already asked this", a different cause, never collapsed into the same signal.
    case duplicateSubmission(existingCallId: UUID)
}

/// Default `expiresAt` window applied by `speak_submit_call` when the caller omits
/// `expiresInSeconds` — an abandoned agent must not leave an immortal pending call in
/// the inbox. `expiresAt` is never `nil` for a durable call submitted through the tool
/// surface. The `speak_request_input` legacy adapter path is exempt (may pass `nil`) —
/// it resolves within its own call stack and never lingers in the inbox.
/// [decision: AVB-7 orchestrator amendment 1]
public enum AgentCallDefaults {
    public static let defaultExpirySeconds: TimeInterval = 24 * 60 * 60
}

/// Bundles `AgentCallStoring.submit`'s arguments so the function stays under
/// the project's function-parameter-count limit, mirroring `RequestInputCall`
/// / `SubmitCallArguments`. [decision: AVB-7]
public struct AgentCallSubmission: Sendable {
    public let sessionId: String?
    public let requestId: String
    public let idempotencyKey: String?
    public let prompt: String
    public let mode: RequestInputMode
    public let choices: [String]
    public let consequence: String?
    public let spokenSummary: String?
    public let urgency: AgentCallUrgency
    public let expiresAt: Date?

    public init(
        sessionId: String?, requestId: String, idempotencyKey: String?, prompt: String,
        mode: RequestInputMode, choices: [String] = [], consequence: String? = nil,
        spokenSummary: String? = nil, urgency: AgentCallUrgency = .normal, expiresAt: Date?
    ) {
        self.sessionId = sessionId
        self.requestId = requestId
        self.idempotencyKey = idempotencyKey
        self.prompt = prompt
        self.mode = mode
        self.choices = choices
        self.consequence = consequence
        self.spokenSummary = spokenSummary
        self.urgency = urgency
        self.expiresAt = expiresAt
    }
}

/// Backs `speak_submit_call` / `speak_get_call` and the durable side effect of
/// `speak_request_input`. Conformed by `AgentCallStore` (Storage/), an actor —
/// every method is a single non-suspending body from the actor's point of view
/// (no `await` between a check and its mutation), closing the TOCTOU window.
public protocol AgentCallStoring: Sendable {
    func submit(_ submission: AgentCallSubmission) async throws -> AgentCallSubmitResult

    /// `nil` when `id` doesn't exist, OR when it exists but `call.sessionId != requestingSessionId`
    /// — a session mismatch never reveals existence (spec §8: "only the originating
    /// call/session receives its response").
    func get(id: UUID, requestingSessionId: String?) async throws -> AgentCall?

    /// Non-terminal calls, newest first — backs the inbox list + badge count.
    func pendingAndPresented() async throws -> [AgentCall]

    func markPresented(id: UUID) async throws

    /// CAS: only transitions if current state is non-terminal. Returns `false` if the
    /// call already resolved (race lost) — caller logs and discards, never overwrites.
    @discardableResult
    func resolve(id: UUID, outcome: HumanResponseOutcome) async throws -> Bool

    /// Sweep: transitions any non-terminal call past `expiresAt` to `.expired`. Called on
    /// store open (recovery) and periodically (e.g. inbox refresh).
    func expireOverdue(now: Date) async throws
}
