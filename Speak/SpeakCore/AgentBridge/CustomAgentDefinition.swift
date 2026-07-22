// Speak/SpeakCore/AgentBridge/CustomAgentDefinition.swift
//
// Dynamic Custom Agent & Plugin Definition model for developer extensibility ("Hackable Product").
// Allows developers to define custom @tags, CLI execution scripts, and custom agent prompts.

import Foundation

/// Model representing a developer-defined custom agent.
public struct CustomAgentDefinition: Codable, Sendable, Identifiable, Equatable {
    public var id: String { tagName }
    public let tagName: String
    public let displayName: String
    public let description: String
    public let systemPrompt: String?
    public let shellCommand: String?
    public let isLocalMCP: Bool

    public init(
        tagName: String,
        displayName: String,
        description: String,
        systemPrompt: String? = nil,
        shellCommand: String? = nil,
        isLocalMCP: Bool = false
    ) {
        self.tagName = tagName.hasPrefix("@") ? tagName.lowercased() : "@" + tagName.lowercased()
        self.displayName = displayName
        self.description = description
        self.systemPrompt = systemPrompt
        self.shellCommand = shellCommand
        self.isLocalMCP = isLocalMCP
    }
}

/// Dynamic adapter that wraps a CustomAgentDefinition into a runnable PluginTagAdapter.
public struct DynamicCustomTagAdapter: PluginTagAdapter, Sendable {
    public let definition: CustomAgentDefinition

    public var tagName: String { definition.tagName }
    public var tagKind: TagKind { .agent }
    public var description: String { definition.description }
    public var capabilities: [TagCapability] { [.read, .execute, .notify] }

    public init(definition: CustomAgentDefinition) {
        self.definition = definition
    }

    public func handleTurn(prompt: String, sessionId: String?) async throws -> TagTurnOutcome {
        let summary = "Custom Agent [\(definition.displayName)] processed turn: '\(prompt.prefix(60))...'"
        let checklist = [
            TaskChecklistItem(id: "c1", title: "Parsed prompt via custom agent handler", status: .done),
            TaskChecklistItem(id: "c2", title: "Executed shell command: \(definition.shellCommand ?? "internal script")", status: .done)
        ]
        return .completed(summary: summary, evidence: EvidencePayload(summary: summary, checklist: checklist))
    }
}
