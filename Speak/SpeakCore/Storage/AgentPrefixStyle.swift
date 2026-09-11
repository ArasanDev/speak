// SpeakCore/Storage/AgentPrefixStyle.swift
//
// Defines explicit STT (Speech-to-Text) origin tags prepended to delivered text
// when pasting into applications or coding agents (Claude Code, Antigravity, Cursor)
// to signal that the input is a voice-dictated prompt.

import Foundation

/// Explicit STT origin prefix prepended to delivered text when pasting into applications or coding agents.
public enum AgentPrefixStyle: String, Codable, Sendable, CaseIterable, Equatable, Hashable {
    /// No prefix added (plain text delivery).
    case none = "none"
    /// Prepend "[speak-stt]" (Speak application + STT origin). Default.
    case speakSTT = "speak_stt"
    /// Prepend "[voice-stt]" (Universal voice-to-text prompt).
    case voiceSTT = "voice_stt"
    /// Prepend "[stt-input]" (Explicit speech-to-text user input).
    case sttInput = "stt_input"
    /// Prepend "[stt-prompt]" (Explicit speech-to-text developer prompt).
    case sttPrompt = "stt_prompt"

    // Custom decodable to seamlessly support legacy stored values ("speak", "voice")
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        switch raw {
        case "speak", "speak_stt": self = .speakSTT
        case "voice", "voice_stt": self = .voiceSTT
        case "stt_input": self = .sttInput
        case "stt_prompt": self = .sttPrompt
        case "none": self = .none
        default: self = .none
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    /// The base tag name without surrounding brackets or state modifiers.
    public var baseTag: String {
        switch self {
        case .none: return ""
        case .speakSTT: return "speak-stt"
        case .voiceSTT: return "voice-stt"
        case .sttInput: return "stt-input"
        case .sttPrompt: return "stt-prompt"
        }
    }

    /// User-facing label displayed in pickers and segmented controls.
    public var displayName: String {
        switch self {
        case .none: return "Off"
        case .speakSTT: return "[speak-stt]"
        case .voiceSTT: return "[voice-stt]"
        case .sttInput: return "[stt-input]"
        case .sttPrompt: return "[stt-prompt]"
        }
    }

    /// Formats the tag, optionally appending `:clean` or `:raw` state.
    public func formattedPrefix(isCleaned: Bool, includeState: Bool = false) -> String {
        guard self != .none else { return "" }
        if includeState {
            let stateTag = isCleaned ? "clean" : "raw"
            return "[\(baseTag):\(stateTag)] "
        } else {
            return "[\(baseTag)] "
        }
    }

    /// Default prefix without state modifier.
    public var prefix: String {
        formattedPrefix(isCleaned: true, includeState: false)
    }
}
