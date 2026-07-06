// SpeakCore/AgentBridge/BridgeBackend.swift
//
// The seam between the MCP tool-call layer (AgentBridgeServer) and however a
// tool is actually fulfilled. `AgentBridgeServer` depends only on this
// protocol, never on a concrete transport, so the JSON-RPC/MCP protocol layer
// stays unit-testable with an in-memory stub — the same seam pattern as
// `Transcribing` / `LLMCleaning` elsewhere in SpeakCore.
//
// H-3 scope (specs/horizon-voice-os.md Pillar 3): the menubar-app link
// (XPC/UNIX-socket) is explicitly a later task. In this slice:
//   - `speak_status` gets a REAL backend (`CLIBridgeBackend`) by reusing the
//     existing CFMessagePort CLI IPC (Speak/SpeakCore/CLI/CLIContract.swift)
//     that already answers "is the app running, what state is it in" for
//     `speak --status`. No new transport is introduced.
//   - `speak_say` has no synthesizer seam to call yet (VoiceOut / Pillar 2 is
//     unbuilt).
//   - `speak_ask` / `speak_confirm` need a live mic round-trip through the
//     running app (the XPC link).
// All three report a clean, structured "not available" result rather than a
// JSON-RPC protocol error, so a connected agent can degrade gracefully — the
// horizon spec's "every pillar has an off switch."

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

    /// `speak_say`: no TTS seam exists yet (VoiceOut / Pillar 2 is a separate,
    /// unbuilt horizon item — see specs/horizon-voice-os.md).
    public static func noSynthesizer(_ tool: String) -> BridgeUnavailable {
        BridgeUnavailable(
            "\(tool) has no synthesizer wired yet — VoiceOut (Pillar 2, specs/horizon-voice-os.md) " +
            "is not built in this slice."
        )
    }

    /// `speak_ask` / `speak_confirm`: both need a live mic round-trip through
    /// the running app, which requires the menubar-app link that is out of
    /// scope for H-3.
    public static func needsTransport(_ tool: String) -> BridgeUnavailable {
        BridgeUnavailable(
            "\(tool) needs a live round-trip through the running speak.app (mic + STT) — the " +
            "menubar-app link (XPC/socket transport, specs/horizon-voice-os.md Pillar 3) is a later task."
        )
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
