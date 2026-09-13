// App/Dashboard/DashboardSection.swift
//
// The sidebar information architecture for the full-window dashboard.
// Adding a feature = adding a case here + its pane view. CaseIterable order == display order.
//
// THE DISTRIBUTION PRINCIPLE [decision]: the desk hosts RUNTIME workspaces —
// surfaces you visit while working (dictate, review history, answer agent
// calls, run inference). Configuration lives in Settings (Mode B). This is why
// Dictionary / Snippets / Style are NOT desk sections: they are pure config,
// owned by Settings ▸ Vocabulary / Intelligence. One home per capability.
//
// `group` clusters the rail like System Settings; `subtitle` feeds the slim
// desk header so panes no longer render their own duplicate hero titles.

import SwiftUI

// MARK: - DashboardSection

/// One destination in the dashboard sidebar. `CaseIterable` order == display order.
enum DashboardSection: String, CaseIterable, Identifiable, Hashable {
    case home
    case history
    case insights
    case agentInbox
    case playground
    case mcpAgents
    case aiStudio
    case inference
    case transforms
    case scratchpad
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home:       return "Home"
        case .history:    return "History"
        case .insights:   return "Insights"
        case .agentInbox: return "Agent Inbox"
        case .playground: return "Playground"
        case .mcpAgents:  return "MCP & Agents"
        case .aiStudio:   return "AI Studio"
        case .inference:  return "Inference"
        case .transforms: return "Transforms"
        case .scratchpad: return "Scratchpad"
        case .settings:   return "Settings"
        }
    }

    /// The one-line "why am I here" shown beside the title in the desk header —
    /// carries what pane-internal `PaneHeader` subtitles used to say, so panes
    /// render no title of their own (single title owner).
    var subtitle: String {
        switch self {
        case .home:       return "Dictate, glance at activity, jump back in."
        case .history:    return "Every dictation, searchable and exportable."
        case .insights:   return "Words, pace, and latency over time."
        case .agentInbox: return "Calls from agents waiting on you."
        case .playground: return "Talk to agents end-to-end."
        case .mcpAgents:  return "Live MCP sessions and the bridge."
        case .aiStudio:   return "Profiles and prompt design."
        case .inference:  return "The intelligence workbench."
        case .transforms: return "Reusable text transforms."
        case .scratchpad: return "An ephemeral capture buffer."
        case .settings:   return "How speak is built."
        }
    }

    /// The rail group this section belongs to. [decision: desk groups mirror
    /// the Settings rail's language — ACTIVITY is what the pipeline did, AGENTS
    /// is the cockpit pillar, STUDIOS is where work gets shaped.]
    var group: DashboardGroup {
        switch self {
        case .home:
            return .home
        case .history, .insights:
            return .activity
        case .agentInbox, .playground, .mcpAgents:
            return .agents
        case .aiStudio, .inference, .transforms, .scratchpad:
            return .studios
        case .settings:
            return .home // never rendered in the rail — pinned below the divider
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
        case .history:    return "clock.arrow.circlepath"
        case .insights:   return "chart.bar"
        case .agentInbox: return "tray.and.arrow.down"
        case .playground: return "bubble.left.and.text.bubble.right"
        case .mcpAgents:  return "server.rack"
        case .aiStudio:   return "brain.head.profile"
        case .inference:  return "cpu"
        case .transforms: return "arrow.triangle.2.circlepath"
        case .scratchpad: return "note.text"
        case .settings:   return "gearshape"
        }
    }
}

// MARK: - DashboardGroup

/// A sidebar section cluster. Order of cases == display order.
enum DashboardGroup: String, CaseIterable, Identifiable {
    case home
    case activity
    case agents
    case studios

    var id: String { rawValue }

    /// `nil` for the leading Home group — it renders unlabeled (like the
    /// top item in System Settings' sidebar).
    var title: String? {
        switch self {
        case .home:     return nil
        case .activity: return "Activity"
        case .agents:   return "Agent Cockpit"
        case .studios:  return "Studios"
        }
    }

    /// The sections in this group, in display order (excluding `.settings`,
    /// which is pinned to the sidebar bottom, not part of the rail list).
    var sections: [DashboardSection] {
        DashboardSection.mainSections.filter { $0.group == self }
    }
}
