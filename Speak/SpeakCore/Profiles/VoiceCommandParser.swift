// SpeakCore/Profiles/VoiceCommandParser.swift
//
// Pure, stateless voice-command detector (PE-3.1).
// Matches trigger phrases anchored at the START of a transcript (case-insensitive),
// strips the trigger prefix, and returns the destination/category to apply before the
// cleanup pass. Returns nil when no trigger is present.
//
// PURITY CONSTRAINTS (PE-3.1 spec):
//   - No I/O, no Date/random, no global state — deterministic for every input.
//   - Profile IDs accepted as parameters so the parser stays independently testable.
//   - Destination triggers change the cleanup destination (note: / write: / agent:).
//   - Category triggers change the AgentCategory only; destination stays Agent.
//   - Patterns are matched longest-first so a short prefix cannot shadow a longer one.

import Foundation

// MARK: - VoiceCommand

/// The result of a successful voice-command match at the start of a transcript.
public struct VoiceCommand: Sendable {
    /// Destination profile ID to apply (nil for category-only triggers).
    public let destination: UUID?
    /// Agent sub-category to apply (nil for destination-only triggers).
    public let category: AgentCategory?
    /// The transcript with the trigger phrase stripped and whitespace-trimmed.
    public let strippedTranscript: String
}

// MARK: - VoiceCommandParser

/// Detects spoken trigger phrases anchored at the start of a transcript.
public enum VoiceCommandParser {

    /// Detect a voice command trigger in `transcript`.
    ///
    /// Returns nil when no known trigger is present at the start of the text.
    ///
    /// - Parameters:
    ///   - transcript: The raw transcript from the STT engine.
    ///   - agentProfileID: Stable UUID for the Agent destination.
    ///   - writeProfileID: Stable UUID for the Write destination.
    ///   - noteProfileID: Stable UUID for the Note destination.
    public static func detect(
        _ transcript: String,
        agentProfileID: UUID,
        writeProfileID: UUID,
        noteProfileID: UUID
    ) -> VoiceCommand? {
        let trimmed = transcript.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let lower = trimmed.lowercased()

        struct Trigger {
            let prefix: String      // lowercased, may include trailing ":"
            let destination: UUID?
            let category: AgentCategory?
        }

        // All patterns longest-first so no short prefix shadows a longer one.
        // Colon variants end with ":" so remainder needs no extra colon-strip.
        let triggers: [Trigger] = [
            Trigger(prefix: "switch to write:", destination: writeProfileID, category: nil),
            Trigger(prefix: "switch to write", destination: writeProfileID, category: nil),
            Trigger(prefix: "switch to agent:", destination: agentProfileID, category: nil),
            Trigger(prefix: "switch to agent", destination: agentProfileID, category: nil),
            Trigger(prefix: "for the agent:", destination: agentProfileID, category: nil),
            Trigger(prefix: "for the agent", destination: agentProfileID, category: nil),
            Trigger(prefix: "i have a question:", destination: nil, category: .ask),
            Trigger(prefix: "i have a question", destination: nil, category: .ask),
            Trigger(prefix: "as a question:", destination: nil, category: .ask),
            Trigger(prefix: "as a question", destination: nil, category: .ask),
            Trigger(prefix: "commit message:", destination: nil, category: .commit),
            Trigger(prefix: "as a commit:", destination: nil, category: .commit),
            Trigger(prefix: "as a commit", destination: nil, category: .commit),
            Trigger(prefix: "as a command:", destination: nil, category: .shell),
            Trigger(prefix: "as a command", destination: nil, category: .shell),
            Trigger(prefix: "as a note:", destination: noteProfileID, category: nil),
            Trigger(prefix: "as a note", destination: noteProfileID, category: nil),
            Trigger(prefix: "as code:", destination: nil, category: .code),
            Trigger(prefix: "as code", destination: nil, category: .code),
            Trigger(prefix: "as a fix:", destination: nil, category: .fix),
            Trigger(prefix: "as a fix", destination: nil, category: .fix),
            Trigger(prefix: "as prose:", destination: writeProfileID, category: nil),
            Trigger(prefix: "as prose", destination: writeProfileID, category: nil),
            Trigger(prefix: "commit:", destination: nil, category: .commit),
            Trigger(prefix: "write:", destination: writeProfileID, category: nil),
            Trigger(prefix: "agent:", destination: agentProfileID, category: nil),
            Trigger(prefix: "shell:", destination: nil, category: .shell),
            Trigger(prefix: "note:", destination: noteProfileID, category: nil),
            Trigger(prefix: "code:", destination: nil, category: .code),
            Trigger(prefix: "ask:", destination: nil, category: .ask),
            Trigger(prefix: "fix:", destination: nil, category: .fix),
            Trigger(prefix: "run:", destination: nil, category: .shell),
            Trigger(prefix: "fix this", destination: nil, category: .fix),
            Trigger(prefix: "fix bug", destination: nil, category: .fix)
        ]

        for t in triggers {
            guard lower.hasPrefix(t.prefix) else { continue }
            // Strip the matched prefix from the ORIGINAL-cased transcript.
            var remainder = String(trimmed.dropFirst(t.prefix.count))
            // Strip a leading colon not already consumed by the prefix
            // (handles "as a commit: text" when matched by "as a commit").
            if remainder.hasPrefix(":") {
                remainder = String(remainder.dropFirst())
            }
            return VoiceCommand(
                destination: t.destination,
                category: t.category,
                strippedTranscript: remainder.trimmingCharacters(in: .whitespaces)
            )
        }
        return nil
    }
}
