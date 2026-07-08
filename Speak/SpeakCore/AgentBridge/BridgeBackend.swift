// SpeakCore/AgentBridge/BridgeBackend.swift
//
// The seam between the MCP tool-call layer (AgentBridgeServer) and however a
// tool is actually fulfilled. `AgentBridgeServer` depends only on this
// protocol, never on a concrete transport, so the JSON-RPC/MCP protocol layer
// stays unit-testable with an in-memory stub — the same seam pattern as
// `Transcribing` / `LLMCleaning` elsewhere in SpeakCore.
//
// H-3 scope (specs/horizon-voice-os.md Pillar 3): all four tools are now wired to
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

/// Backs the four Pillar-3 tools. Every method reports what happened as a
/// value (never throws) so `AgentBridgeServer` can turn "not available" into
/// a tool execution error instead of a protocol error.
public protocol BridgeBackend: Sendable {
    func status() async -> BridgeStatusReport
    func say(text: String, interrupt: Bool) async -> Result<Void, BridgeUnavailable>
    func ask(question: String, timeoutSeconds: Double?) async -> Result<String, BridgeUnavailable>
    func confirm(question: String) async -> Result<Bool, BridgeUnavailable>
}
