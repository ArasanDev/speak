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
    case history
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
        case .history:    return "History"
        case .privacy:    return "Privacy"
        case .settings:   return "Settings"
        }
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
        case .history:    return "clock.arrow.circlepath"
        case .privacy:    return "lock.fill"
        case .settings:   return "gearshape"
        }
    }
}
