// App/Dashboard/DashboardSection.swift
//
// The sidebar information architecture for the full-window dashboard.
//
// RESOLVED (user, 2026-06-21, acceleration-plan.md Wave A): the Phase-2 UI spine is a
// full-window dashboard with a sidebar IA — Home · History · Dictionary · Snippets ·
// Style · Insights. Every v1 feature lands as a sidebar item, not a stacked modal.
//
// This enum is the single ordered source of truth for the sidebar. Adding a future
// feature = adding a case here + its pane view; the split view and routing pick it up.

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
    case history
    case privacy

    var id: String { rawValue }

    /// The user-facing sidebar label. (Naming per acceleration-plan.md Wave A:
    /// user-facing Style/Dictionary/Snippets vocabulary.)
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
        case .history:    return "History"
        case .privacy:    return "Privacy"
        }
    }

    /// SF Symbol shown beside the label in the sidebar.
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
        case .history:    return "clock.arrow.circlepath"
        case .privacy:    return "lock.fill"
        }
    }
}
