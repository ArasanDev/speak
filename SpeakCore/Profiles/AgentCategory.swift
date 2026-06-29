// SpeakCore/Profiles/AgentCategory.swift
//
// Profile taxonomy (PT-1): Agent-specific sub-categories that modify the Agent
// destination's system prompt. Modeled like CleanupLevel — a Sendable/Codable/
// CaseIterable enum where each case appends a prompt fragment in PromptBuilder.
//
// Categories apply ONLY when the destination is Agent; Write/Note/Raw ignore them.
// The category defaults to `.task` and is chosen per-dictation by the user (tap, voice,
// or pinned to a context). Auto-resolution from the app is NOT applied to categories —
// only destinations are auto-resolved from bundle ID.
//
// Specifications: specs/profile-taxonomy.md §2.

import Foundation

/// An Agent-specific sub-category that appends a prompt fragment to the Agent
/// system prompt. Only meaningful when the selected profile is the Agent destination.
///
/// `CaseIterable` order == picker order (primary → rare).
public enum AgentCategory: String, Codable, Sendable, CaseIterable, Equatable {
    /// Implement / refactor / add a feature. The default.
    case task
    /// Fix a broken thing — error symptom or bug report provided.
    case fix
    /// Explain / how / why — a question for an agent.
    case ask
    /// A commit or PR message in Conventional Commits format.
    case commit
    /// A single terminal command or terse instruction.
    case shell
    /// Literal code — convert spoken notation to proper syntax.
    case code

    /// The picker label (primary profiles come first).
    public var displayName: String {
        switch self {
        case .task:   return "Task"
        case .fix:    return "Fix"
        case .ask:    return "Ask"
        case .commit: return "Commit"
        case .shell:  return "Shell"
        case .code:   return "Code"
        }
    }

    /// A short description shown below the picker label in Settings.
    public var categoryDescription: String {
        switch self {
        case .task:   return "Implement / refactor / add a feature"
        case .fix:    return "Fix a broken thing"
        case .ask:    return "Explain / how / why"
        case .commit: return "Commit or PR message"
        case .shell:  return "Single terminal command"
        case .code:   return "Literal code — convert notation to syntax"
        }
    }
}
