// SpeakCore/Cleanup/DeveloperAcronymNormalizer.swift
//
// Pure, deterministic spoken-form → written-form normalization for developer acronyms.
// Extracted from FoundationModelsCleaner to decouple lexical post-processing from
// the Foundation Models session lifecycle.
//
// Rules are:
// 1. Ordered — longer, more specific multi-word patterns come first so they resolve
//    deterministically and win over their single-token prefixes.
// 2. Word-boundary-anchored — uses `\b` so substring replacements do not corrupt
//    ordinary English words (e.g. `pr` inside "project", `ui` inside "build").

import Foundation

public struct DeveloperAcronymNormalizer: Sendable {

    /// Spoken-form → written-form rules for developer acronyms.
    /// Ordered array to ensure deterministic execution order.
    public static let rules: [(spoken: String, written: String)] = [
        // Multi-word spoken forms and acoustic mishearings first — they must win over their own prefixes.
        ("gift repository", "Git repository"),
        ("gift repo", "Git repo"),
        ("gid hup", "GitHub"),
        ("gidhup", "GitHub"),
        ("git hup", "GitHub"),
        ("work treat", "worktree"),
        ("work dream", "worktree"),
        ("what tree", "worktree"),
        ("lines of coke", "lines of code"),
        ("studio mcp", "stdio MCP"),
        ("stdio mcp", "stdio MCP"),
        ("project dogs", "project docs"),
        ("full rippo", "full repo"),
        ("port base", "codebase"),
        ("portbase", "codebase"),
        ("dog footing", "dogfooding"),
        ("qva testing", "QA testing"),
        ("sub agents", "subagents"),
        ("sql lite 3", "SQLite3"),
        ("sequel light", "SQLite"),
        ("sql lite", "SQLite"),
        ("CLA tools", "CLI tools"),
        ("CL line", "CLI"),
        ("A page", "API"),
        ("F T S 5", "FTS5"),
        ("FTS 5", "FTS5"),
        ("S D K", "SDK"),
        ("you I", "UI"),
        ("L L M", "LLM"),
        ("P R", "PR"),
        ("H D M L", "HTML"),
        ("A G I", "AGI"),
        // Single-token forms. `sqlite3` before `sqlite` so the digit is not orphaned.
        ("sqlite3", "SQLite3"),
        ("sqlite", "SQLite"),
        ("fts5", "FTS5"),
        ("cli", "CLI"),
        ("api", "API"),
        ("sdk", "SDK"),
        ("ui", "UI"),
        ("llm", "LLM"),
        ("pr", "PR"),
        ("hdml", "HTML"),
        ("html", "HTML"),
        ("agi", "AGI"),
        ("subagents", "subagents")
    ]

    /// Compiled regexes — compiled once for performance.
    private static let compiledRules: [(regex: NSRegularExpression, written: String)] = {
        rules.compactMap { rule in
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: rule.spoken))\\b"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                return nil
            }
            return (regex, rule.written)
        }
    }()

    /// Normalizes developer acronyms in the given text using word-boundary matching.
    ///
    /// - Parameter text: The text to normalize.
    /// - Returns: The normalized text with developer acronyms properly cased.
    public static func normalize(_ text: String) -> String {
        var result = text
        for (regex, written) in compiledRules {
            let template = NSRegularExpression.escapedTemplate(for: written)
            result = regex.stringByReplacingMatches(
                in: result,
                options: [],
                range: NSRange(result.startIndex..., in: result),
                withTemplate: template
            )
        }
        return result
    }
}
