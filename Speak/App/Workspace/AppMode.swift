// Speak/App/Workspace/AppMode.swift
//
// Dual-mode state for speak's primary interface:
// Mode 1: Dictation Engine (Focused quick global assistant / overlay)
// Mode 2: Agent Workspace (Slack replacement canvas for multi-agent human teams)

import Foundation

public enum AppMode: String, Codable, Sendable, CaseIterable, Identifiable {
    case dictation = "Dictation Engine"
    case workspace = "Agent Workspace"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .dictation: return "bolt.fill"
        case .workspace: return "bubble.left.and.bubble.right.fill"
        }
    }
}
