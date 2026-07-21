// Speak/SpeakCore/AgentBridge/PluginTagAdapter.swift
//
// Protocol for any agent, tool, or plugin registered as a Spoken Tag (@tag).
// Allows local sub-processes, MCP servers, and channel adapters to be invoked via voice or text mentions.

import Foundation

/// Classification of tag targets.
public enum TagKind: String, Codable, Sendable, Equatable {
    case agent     // Specialized AI Agent (@Claude, @codex, @builder-audio)
    case plugin    // Tool / System Plugin (@github, @terminal, @xcode, @datadog)
    case team      // Multi-Agent Group (@engine-team, @qa-team)
    case scope     // Workspace Scope (@channel, @here)
}

/// Operational capability granted to a tag conformer.
public enum TagCapability: String, Codable, Sendable, Equatable {
    case read
    case execute
    case notify
    case requestApproval
}

/// Outcome of invoking a tag.
public enum TagTurnOutcome: Sendable, Equatable {
    case completed(summary: String, evidence: EvidencePayload?)
    case inProgress(summary: String, checklist: [TaskChecklistItem])
    case needsApproval(prompt: String, callId: UUID)
    case failed(error: String)
}

/// Protocol for all tag-invokable plugins and agents.
public protocol PluginTagAdapter: Sendable {
    var tagName: String { get }
    var tagKind: TagKind { get }
    var description: String { get }
    var capabilities: [TagCapability] { get }

    func handleTurn(prompt: String, sessionId: String?) async throws -> TagTurnOutcome
}
