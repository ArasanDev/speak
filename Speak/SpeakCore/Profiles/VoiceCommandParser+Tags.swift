// SpeakCore/Profiles/VoiceCommandParser+Tags.swift
//
// Extension to VoiceCommandParser for detecting and extracting spoken/typed @tag mentions.
// Supports both literal handles (@Claude, @terminal) and spoken tag phrases ("tag claude", "tag terminal").

import Foundation

/// Represents a parsed tag handle within a spoken or typed turn.
public struct SpokenTagMention: Sendable, Equatable {
    public let tag: String          // e.g. "@claude"
    public let rawToken: String     // original matched phrase or handle
    public let kind: TagKind

    public init(tag: String, rawToken: String, kind: TagKind = .agent) {
        self.tag = TagRegistry.normalizeTagName(tag)
        self.rawToken = rawToken
        self.kind = kind
    }
}

extension VoiceCommandParser {

    /// Extracts all tag mentions (@tag, "tag agent_name", "tag team_name") from a transcript.
    public static func extractTags(from transcript: String) -> [SpokenTagMention] {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var results: [SpokenTagMention] = []
        var seenTags: Set<String> = []

        // 1. Match literal @mentions (e.g. @Claude, @terminal, @qa-team, @channel)
        let literalPattern = #"@([A-Za-z0-9_\-]+)"#
        if let regex = try? NSRegularExpression(pattern: literalPattern) {
            let nsString = trimmed as NSString
            let matches = regex.matches(in: trimmed, range: NSRange(location: 0, length: nsString.length))

            for match in matches {
                guard match.numberOfRanges > 1 else { continue }
                let handle = nsString.substring(with: match.range(at: 1))
                let canonical = TagRegistry.normalizeTagName(handle)
                if !seenTags.contains(canonical) {
                    seenTags.insert(canonical)
                    let kind = inferTagKind(canonical)
                    results.append(SpokenTagMention(tag: canonical, rawToken: "@" + handle, kind: kind))
                }
            }
        }

        // 2. Match spoken tag triggers (e.g. "tag claude", "tag terminal", "tag qa team")
        let spokenPattern = #"(?i)\btag\s+([A-Za-z0-9_\-]+(?:\s+team)?)\b"#
        if let regex = try? NSRegularExpression(pattern: spokenPattern) {
            let nsString = trimmed as NSString
            let matches = regex.matches(in: trimmed, range: NSRange(location: 0, length: nsString.length))

            for match in matches {
                guard match.numberOfRanges > 1 else { continue }
                let target = nsString.substring(with: match.range(at: 1)).replacingOccurrences(of: " ", with: "-")
                let canonical = TagRegistry.normalizeTagName(target)
                if !seenTags.contains(canonical) {
                    seenTags.insert(canonical)
                    let kind = inferTagKind(canonical)
                    results.append(SpokenTagMention(tag: canonical, rawToken: nsString.substring(with: match.range), kind: kind))
                }
            }
        }

        return results
    }

    private static func inferTagKind(_ canonicalTag: String) -> TagKind {
        let lower = canonicalTag.lowercased()
        if lower == "@channel" || lower == "@here" {
            return .scope
        } else if lower.contains("team") {
            return .team
        } else if lower == "@terminal" || lower == "@github" || lower == "@xcode" || lower == "@datadog" || lower == "@browser" {
            return .plugin
        } else {
            return .agent
        }
    }
}
