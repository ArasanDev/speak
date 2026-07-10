// SpeakCore/AgentBridge/AgentSession.swift
//
// AVB-6 (specs/agent-voice-bridge.md §3 `AgentSession`, §7.1 session
// registration and capability negotiation): the MCP-independent domain type
// for a routable agent destination. Lives in SpeakCore, same posture as
// `HumanResponse.swift` — the CLI wire (CLIContract.swift) and the MCP tool
// layer (AgentBridgeServer/BridgeBackend) both translate to/from this type
// rather than inventing their own, and it must never import MCP types.

import Foundation

/// Whether an `AgentSession` is still considered live. `.stale` is derived
/// from `lastSeen` at read time (see `AgentSessionRegistry.staleThreshold`),
/// not a field an actor mutates directly — there is no timer; staleness is
/// computed on demand. [decision: AVB-6]
public enum AgentSessionState: String, Codable, Sendable, Equatable {
    case active
    case stale
}

/// A routable destination for agent-directed voice interaction (spec §3).
///
/// Registration identifies a routable destination and grants NO access to
/// files, screen contents, dictation history, or the microphone (spec §3 —
/// quoted verbatim in `speak_register_session`'s tool description so agents
/// reading the tool list see the same guarantee).
///
/// In-memory only this slice — no persistence. Durability arrives with the
/// AVB-7 inbox store. [decision: AVB-6]
public struct AgentSession: Sendable, Codable, Equatable {
    /// Stable identifier. Server-generated (UUID) unless the caller supplies
    /// one to register/re-register under an existing id.
    public let sessionId: String
    /// e.g. "codex", "claude-code". Caller-supplied, free-form.
    public let provider: String
    /// Human-readable label shown to the user (e.g. a task or terminal title).
    public let label: String
    /// The agent's working directory / repository, when known.
    public let workingDirectory: String?
    /// The capabilities this session was granted after negotiation — the
    /// intersection of what it requested with `AgentSessionRegistry
    /// .supportedCapabilities`. Never the caller's raw request verbatim.
    public let capabilities: [String]
    /// `.active` unless `lastSeen` is older than `AgentSessionRegistry
    /// .staleThreshold` — derived, not stored authoritatively; a caller reads
    /// it as of `AgentSessionRegistry.list()`'s snapshot time.
    public let state: AgentSessionState
    /// Last time this session was registered or touched.
    public let lastSeen: Date

    public init(
        sessionId: String,
        provider: String,
        label: String,
        workingDirectory: String?,
        capabilities: [String],
        state: AgentSessionState,
        lastSeen: Date
    ) {
        self.sessionId = sessionId
        self.provider = provider
        self.label = label
        self.workingDirectory = workingDirectory
        self.capabilities = capabilities
        self.state = state
        self.lastSeen = lastSeen
    }
}
