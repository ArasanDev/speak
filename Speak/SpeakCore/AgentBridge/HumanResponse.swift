// SpeakCore/AgentBridge/HumanResponse.swift
//
// AVB-5 (specs/agent-voice-bridge.md §3 `HumanResponse`, §6 `speak_request_input`):
// the MCP-independent domain types behind the structured-input workflow. These
// live in SpeakCore, not AgentBridge's MCP-facing layer, and must never import
// MCP types — the CLI wire (CLIContract.swift) and the MCP tool layer
// (AgentBridgeServer/BridgeBackend) both translate to/from this type rather
// than inventing their own.

import Foundation

/// `speak_request_input`'s three interaction shapes (spec §6). `.freeform` never
/// yields `.declined` — refusal detection only applies to `.choice`/`.approval`.
public enum RequestInputMode: String, Codable, Sendable, Equatable {
    case freeform
    case choice
    case approval
}

/// The typed outcome of a durable human-input request (spec §3 `HumanResponse`).
/// Exactly one of these five is returned — cancellation and ambiguity must never
/// silently become `false` or an empty string.
///
/// - `answered`: `text` is the raw spoken transcript; `choice` is set only when
///   the mode matched a specific option (`.approval`'s "approved", or one of
///   `.choice`'s `choices`). `choice == nil` for `.freeform`, and for `.choice`/
///   `.approval` when the spoken answer didn't unambiguously match anything —
///   callers one layer up (the MCP tool) treat that ambiguity as a tool
///   execution error, never as a false success. [decision: AVB-5]
/// - `declined`: an explicit verbal refusal in `.choice`/`.approval` mode only.
/// - `cancelled`: the human stopped the capture (Escape/hotkey/user stop)
///   without answering.
/// - `timedOut`: the request's deadline elapsed with no answer.
/// - `busy`: another agent-initiated capture (or a duplicate in-flight request)
///   was already open; this request was refused, not queued.
public enum HumanResponseOutcome: Sendable, Equatable {
    case answered(text: String?, choice: String?)
    case declined
    case cancelled
    case timedOut
    case busy
}

// MARK: - Codable (CLI wire + any future persistence)

extension HumanResponseOutcome: Codable {
    private enum CodingKeys: String, CodingKey {
        case outcome, text, choice
    }

    private enum Kind: String, Codable {
        case answered, declined, cancelled, timedOut, busy
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .outcome)
        switch kind {
        case .answered:
            let text = try container.decodeIfPresent(String.self, forKey: .text)
            let choice = try container.decodeIfPresent(String.self, forKey: .choice)
            self = .answered(text: text, choice: choice)
        case .declined:
            self = .declined
        case .cancelled:
            self = .cancelled
        case .timedOut:
            self = .timedOut
        case .busy:
            self = .busy
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .answered(let text, let choice):
            try container.encode(Kind.answered, forKey: .outcome)
            try container.encodeIfPresent(text, forKey: .text)
            try container.encodeIfPresent(choice, forKey: .choice)
        case .declined:
            try container.encode(Kind.declined, forKey: .outcome)
        case .cancelled:
            try container.encode(Kind.cancelled, forKey: .outcome)
        case .timedOut:
            try container.encode(Kind.timedOut, forKey: .outcome)
        case .busy:
            try container.encode(Kind.busy, forKey: .outcome)
        }
    }
}
