// SpeakCore/AgentBridge/BridgeBackend.swift
//
// The seam between the MCP tool-call layer (AgentBridgeServer) and however a
// tool is actually fulfilled. `AgentBridgeServer` depends only on this
// protocol, never on a concrete transport, so the JSON-RPC/MCP protocol layer
// stays unit-testable with an in-memory stub — the same seam pattern as
// `Transcribing` / `LLMCleaning` elsewhere in SpeakCore.
//
// Agent bridge scope (specs/agent-voice-bridge.md): all five tools are wired to
// a real running app instance, reusing the existing CFMessagePort CLI IPC
// (Speak/SpeakCore/CLI/CLIContract.swift) — no new transport (XPC/UNIX-socket) was
// needed. `say`/`ask`/`confirm` ride the same wire the `--start`/`--stop`/`--status`
// CLI verbs already use, extended with `.say`/`.ask`/`.confirm` `CLICommand` cases.
// `BridgeUnavailable.appNotRunning` remains the one "not available" case every tool
// can still report — the horizon spec's "every pillar has an off switch" — for when
// speak.app simply isn't running.

import Foundation

/// The result of `speak_status`.
public struct BridgeStatusReport: Sendable, Equatable {
    public let appRunning: Bool
    /// "idle" | "listening" | "processing" when `appRunning`; `nil` otherwise.
    public let engineState: String?
    /// The active hotkey binding's display string, when available.
    public let hotkeyBinding: String?
    /// Human-readable detail — e.g. why the app isn't reachable, or an extra
    /// note appended to an otherwise-successful report.
    public let detail: String?

    public init(appRunning: Bool, engineState: String?, hotkeyBinding: String?, detail: String?) {
        self.appRunning = appRunning
        self.engineState = engineState
        self.hotkeyBinding = hotkeyBinding
        self.detail = detail
    }
}

/// Why a bridge operation could not complete. Distinct from a thrown `Error`:
/// these are expected, user-facing conditions (a missing seam or transport),
/// never a bug — `AgentBridgeServer` turns one into a tool execution error
/// (`MCPToolCallResult.error(_:)`), not a JSON-RPC protocol error.
public struct BridgeUnavailable: Error, Sendable, Equatable, CustomStringConvertible {
    public let reason: String

    public init(_ reason: String) { self.reason = reason }

    public var description: String { reason }

    public static let appNotRunning = BridgeUnavailable("speak is not running. Open speak.app first.")

    /// `speak_ask` / `speak_confirm`: the round-trip started but no answer arrived
    /// within the requested (or default) timeout — see
    /// `CLIContract.askConfirmDefaultTimeoutSeconds`. [decision: H-3]
    public static func timedOut(_ tool: String) -> BridgeUnavailable {
        BridgeUnavailable("\(tool) timed out waiting for a spoken answer.")
    }

    /// `speak_confirm`: an answer arrived but didn't match any yes/no/cancel phrase
    /// (`YesNoCancelExtractor` returned `.unclear`/`.cancel`). Reported as
    /// "unavailable" rather than defaulting to `false`, so a caller never mistakes
    /// an ambiguous answer for a deliberate "no". [decision: H-3]
    public static func unclearAnswer(_ tool: String) -> BridgeUnavailable {
        BridgeUnavailable("\(tool) got an answer that wasn't a recognizable yes/no/cancel.")
    }

    /// Any other transport-level failure translating a CLI reply (malformed JSON,
    /// an `ok == false` reply with no more specific mapping, etc).
    public static func transportError(_ tool: String, _ detail: String) -> BridgeUnavailable {
        BridgeUnavailable("\(tool) transport error: \(detail)")
    }
}

/// AVB-6 (specs/agent-voice-bridge.md §7.1): wraps a tool's normal return
/// value with an optional note attached when a caller-supplied `sessionId`
/// was not found in the registry. The call still proceeds normally
/// (compatibility first — enforcement is a later policy slice); this is
/// informational only, never a failure. `nil` when no `sessionId` was
/// supplied, or when it was supplied and recognized.
public struct BridgeOutcome<Value: Sendable>: Sendable {
    public let value: Value
    public let sessionNote: String?

    public init(_ value: Value, sessionNote: String? = nil) {
        self.value = value
        self.sessionNote = sessionNote
    }

    /// The note shown when `sessionId` was supplied but not recognized.
    /// [decision: AVB-6]
    public static func unregisteredSessionNote(_ sessionId: String) -> String {
        "note: sessionId '\(sessionId)' is not a registered session (call speak_register_session first) " +
            "— proceeded anyway."
    }
}

/// Bundles `speak_request_input`'s arguments so `BridgeBackend.requestInput`
/// stays under the project's function-parameter-count limit. One value type
/// shared by `AgentBridgeServer` (constructs it from tool-call arguments),
/// `CLIBridgeBackend` (translates it to a `CLIRequest`), and any test double.
/// [decision: AVB-6]
public struct RequestInputCall: Sendable {
    public let requestId: String
    public let idempotencyKey: String?
    public let prompt: String
    public let mode: RequestInputMode
    public let choices: [String]?
    public let timeoutSeconds: Double?
    public let consequence: String?
    public let spokenSummary: String?
    public let sessionId: String?

    public init(
        requestId: String,
        idempotencyKey: String? = nil,
        prompt: String,
        mode: RequestInputMode,
        choices: [String]? = nil,
        timeoutSeconds: Double? = nil,
        consequence: String? = nil,
        spokenSummary: String? = nil,
        sessionId: String? = nil
    ) {
        self.requestId = requestId
        self.idempotencyKey = idempotencyKey
        self.prompt = prompt
        self.mode = mode
        self.choices = choices
        self.timeoutSeconds = timeoutSeconds
        self.consequence = consequence
        self.spokenSummary = spokenSummary
        self.sessionId = sessionId
    }
}

/// Bundles `speak_submit_call`'s arguments so `BridgeBackend.submitCall` stays
/// under the project's function-parameter-count limit, mirroring
/// `RequestInputCall`. [decision: AVB-7]
public struct SubmitCallArguments: Sendable {
    public let requestId: String
    public let idempotencyKey: String?
    public let prompt: String
    public let mode: RequestInputMode
    public let choices: [String]
    public let consequence: String?
    public let spokenSummary: String?
    public let urgency: AgentCallUrgency
    /// Always concrete by the time this reaches `BridgeBackend` — the MCP tool
    /// layer (`AgentBridgeServer`) applies `AgentCallDefaults.defaultExpirySeconds`
    /// when the caller omits it. [decision: AVB-7 orchestrator amendment 1]
    public let expiresInSeconds: Double
    public let sessionId: String?

    public init(
        requestId: String, idempotencyKey: String? = nil, prompt: String, mode: RequestInputMode,
        choices: [String] = [], consequence: String? = nil, spokenSummary: String? = nil,
        urgency: AgentCallUrgency = .normal, expiresInSeconds: Double, sessionId: String? = nil
    ) {
        self.requestId = requestId
        self.idempotencyKey = idempotencyKey
        self.prompt = prompt
        self.mode = mode
        self.choices = choices
        self.consequence = consequence
        self.spokenSummary = spokenSummary
        self.urgency = urgency
        self.expiresInSeconds = expiresInSeconds
        self.sessionId = sessionId
    }
}

/// `speak_submit_call`'s success payload — the created (or, on a duplicate
/// submission, existing) `AgentCall`, plus whether it was a duplicate.
/// [decision: AVB-7]
public struct AgentCallSubmitOutcome: Sendable, Equatable {
    public let call: AgentCall
    public let duplicate: Bool

    public init(call: AgentCall, duplicate: Bool) {
        self.call = call
        self.duplicate = duplicate
    }
}

/// Backs the current tool catalog. `speak_notify` composes the same `say`
/// backend as `speak_say`. Every method reports what happened as a
/// value (never throws) so `AgentBridgeServer` can turn "not available" into
/// a tool execution error instead of a protocol error.
public protocol BridgeBackend: Sendable {
    func status(sessionId: String?) async -> BridgeOutcome<BridgeStatusReport>
    func say(text: String, interrupt: Bool, sessionId: String?) async -> Result<BridgeOutcome<Void>, BridgeUnavailable>
    func ask(
        question: String, timeoutSeconds: Double?, sessionId: String?
    ) async -> Result<BridgeOutcome<String>, BridgeUnavailable>
    func confirm(question: String, sessionId: String?) async -> Result<BridgeOutcome<Bool>, BridgeUnavailable>

    /// AVB-5 (specs/agent-voice-bridge.md §6): `speak_request_input`. Reuses the
    /// CFMessagePort CLI IPC's new `.requestInput` command — no new transport.
    /// Arguments are bundled into `RequestInputCall` (AVB-6) to stay under the
    /// project's function-parameter-count limit now that `sessionId` is threaded
    /// through as well.
    func requestInput(
        _ call: RequestInputCall
    ) async -> Result<BridgeOutcome<HumanResponseOutcome>, BridgeUnavailable>

    /// AVB-6 (specs/agent-voice-bridge.md §7.1): `speak_register_session`.
    /// Reuses the CFMessagePort CLI IPC's new `.registerSession` command — no
    /// new transport. Returns the negotiated capabilities alongside the
    /// (possibly server-generated) sessionId.
    func registerSession(
        sessionId: String?,
        provider: String,
        label: String,
        workingDirectory: String?,
        requestedCapabilities: [String]
    ) async -> Result<(sessionId: String, capabilities: [String]), BridgeUnavailable>

    // MARK: - AVB-7 (specs/avb7-durable-calls-design.md) durable calls

    /// `speak_submit_call`. No mic, no pump — a fast durable write. Fails with
    /// `BridgeUnavailable` when the caller has no registered session (never
    /// silently proceeds, unlike the advisory `sessionNote` other tools attach).
    func submitCall(_ args: SubmitCallArguments) async -> Result<BridgeOutcome<AgentCallSubmitOutcome>, BridgeUnavailable>

    /// `speak_get_call`. `nil` inside the outcome means "not found or not yours"
    /// — isolation, never an error. [decision: AVB-7]
    func getCall(callId: UUID, sessionId: String?) async -> Result<BridgeOutcome<AgentCall?>, BridgeUnavailable>

    // MARK: - Layer 4

    func askUser(
        prompt: String, mode: String?, sessionId: String?
    ) async -> Result<BridgeOutcome<String>, BridgeUnavailable>

    func streamSpeech(
        text: String, isFinal: Bool, sessionId: String?
    ) async -> Result<BridgeOutcome<String>, BridgeUnavailable>
}
