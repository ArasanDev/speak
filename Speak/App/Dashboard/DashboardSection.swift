// App/Dashboard/DashboardSection.swift
//
// The sidebar information architecture for the full-window dashboard.
// Adding a feature = adding a case here + its pane view. CaseIterable order == display order.

import SwiftUI

// MARK: - DashboardSection

/// One destination in the dashboard sidebar. `CaseIterable` order == display order.
enum DashboardSection: String, CaseIterable, Identifiable, Hashable {
    case home
    case aiStudio
    case insights
    case dictionary
    case snippets
    case style
    case transforms
    case scratchpad
    case inference
    case playground
    case history
    /// AVB-7 (specs/avb7-durable-calls-design.md): non-terminal `AgentCall`s
    /// (prompt, urgency, elapsed time, mode) — the local inbox. [decision: AVB-7]
    case agentInbox
    case mcpAgents
    case privacy
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home:       return "Home"
        case .aiStudio:   return "AI Studio"
        case .insights:   return "Insights"
        case .dictionary: return "Dictionary"
        case .snippets:   return "Snippets"
        case .style:      return "Style"
        case .transforms: return "Transforms"
        case .scratchpad: return "Scratchpad"
        case .inference:  return "Inference"
        case .playground: return "Playground"
        case .history:    return "History"
        case .agentInbox: return "Agent Inbox"
        case .mcpAgents:  return "MCP & Agents"
        case .privacy:    return "Privacy"
        case .settings:   return "Settings"
        }
    }

    /// Sidebar sections shown in the main scrollable nav list, in display order.
    /// [decision: Settings is pinned to the bottom of the sidebar, separate from this
    ///  list — the common macOS pattern (System Settings, Slack, VS Code) of anchoring
    ///  the gear icon below a divider so it never scrolls away as sections are added.]
    static var mainSections: [DashboardSection] {
        allCases.filter { $0 != .settings }
    }

    var systemImage: String {
        switch self {
        case .home:       return "house"
        case .aiStudio:   return "brain.head.profile"
        case .insights:   return "chart.bar"
        case .dictionary: return "character.book.closed"
        case .snippets:   return "text.append"
        case .style:      return "wand.and.stars"
        case .transforms: return "arrow.triangle.2.circlepath"
        case .scratchpad: return "note.text"
        case .inference:  return "cpu"
        case .playground: return "bubble.left.and.text.bubble.right"
        case .history:    return "clock.arrow.circlepath"
        case .agentInbox: return "tray.and.arrow.down"
        case .mcpAgents:  return "server.rack"
        case .privacy:    return "lock.fill"
        case .settings:   return "gearshape"
        }
    }
}
