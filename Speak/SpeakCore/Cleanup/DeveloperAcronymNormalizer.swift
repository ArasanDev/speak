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
        ("whisper flow", "Wispr Flow"),
        ("sub egypt", "subagent"),
        ("some egypt", "subagent"),
        ("gate work tree", "Git worktree"),
        ("get work trees", "Git worktrees"),
        ("git work trees", "Git worktrees"),
        ("gift repository", "Git repository"),
        ("gift repo", "Git repo"),
        ("gate repository", "Git repository"),
        ("gate repo", "Git repo"),
        ("landing beach", "landing page"),
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
        ("Delhi guitar", "delegator"),
        ("teeth record", "T3 code"),
        ("8 under lines of code", "800 lines of code"),
        ("shift standard", "Swift standard"),
        ("fable model", "Apple model"),
        ("gear project", "Git project"),
        ("get repose", "Git repos"),
        ("workries", "worktrees"),
        ("workways", "worktrees"),
        ("one king properly", "one thing properly"),
        ("processing foster", "processing faster"),
        ("3000000000", "3B"),
        ("3 billion", "3B"),
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

    /// Collapses immediate repeated word stutters (e.g. "I will I will" -> "I will", "For, for" -> "For", "you, you" -> "you").
    public static func collapseStutters(_ text: String) -> String {
        var result = text
        let pattern = "\\b([A-Za-z0-9_'-]+(?:\\s+[A-Za-z0-9_'-]+){0,2})(?:,\\s*|\\s+)\\1\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return result
        }
        for _ in 0..<3 {
            let range = NSRange(result.startIndex..., in: result)
            let replaced = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "$1")
            if replaced == result { break }
            result = replaced
        }
        return result
    }

    /// Prunes conversational throat-clearing preambles and confirmation questions.
    public static func pruneConversationalPaddings(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let original = result

        let tailPatterns = [
            "(?i)\\s*[,;]?\\s*(and\\s+)?\\b(do you understand my point|can you relate this|do you understand|can you understand this|is it clear|got it)\\b[?.!]*\\s*$"
        ]
        let headPatterns = [
            "^(?i)(So\\s+)?(Now\\s+)?what I (want to tell you|am telling|feel) is like[,:]?\\s*",
            "^(?i)Here is the information I want to give you[:.]?\\s*",
            "^(?i)Okay,\\s*correct[.]\\s*",
            "^(?i)Now\\s+what I am going to do is like[,:]?\\s*"
        ]

        for _ in 0..<3 {
            let before = result
            for pattern in tailPatterns {
                if let regex = try? NSRegularExpression(pattern: pattern) {
                    let range = NSRange(result.startIndex..., in: result)
                    result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
            for pattern in headPatterns {
                if let regex = try? NSRegularExpression(pattern: pattern) {
                    let range = NSRange(result.startIndex..., in: result)
                    result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
            if result == before { break }
        }

        if result != original, let first = result.first, first.isLowercase {
            result = first.uppercased() + result.dropFirst()
        }

        return result
    }

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
        result = collapseStutters(result)
        result = pruneConversationalPaddings(result)
        return result
    }
}
