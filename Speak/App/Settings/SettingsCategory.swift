// App/Settings/SettingsCategory.swift
//
// The information architecture for the dedicated two-panel Settings experience
// (SettingsExperienceView). One case per rail destination; `groupedSections`
// defines the sidebar layout — grouped like t3code's settings nav and macOS
// System Settings, so related categories sit under a shared section header.
//
// Adding a category = adding a case here + a view in the detail-canvas switch.

import SwiftUI

// MARK: - SettingsCategory

/// One destination in the Settings rail. `CaseIterable` order == display order
/// within each `group`.
enum SettingsCategory: String, CaseIterable, Identifiable, Hashable {
    case generalAudio
    case hotkeys
    case aiModels
    case vocabulary
    case agentBridge
    case appearance
    case privacy
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .generalAudio: return "General & Audio"
        case .hotkeys:      return "Hotkeys & Activation"
        case .aiModels:     return "AI Models & Neat-Writing"
        case .vocabulary:   return "Vocabulary & Jargon"
        case .agentBridge:  return "Agent Bridge & MCP"
        case .appearance:   return "Appearance & HUD"
        case .privacy:      return "Privacy & System Health"
        case .about:        return "About"
        }
    }

    /// One-line canvas subtitle — the "why am I here" line under the title.
    var subtitle: String {
        switch self {
        case .generalAudio:
            return "Language, microphone, text insertion, and voice readback."

        case .hotkeys:
            return "Global activation, push-to-talk, and extra shortcuts."

        case .aiModels:
            return "On-device neat-writing engine, intensity, and voice."

        case .vocabulary:
            return "Names, jargon, and trigger → expansion snippets."

        case .agentBridge:
            return "speak-mcp stdio server, agent sessions, and prompt tags."

        case .appearance:
            return "Theme, recording HUD, and border animations."

        case .privacy:
            return "On-device moat, OS permissions, and data controls."

        case .about:
            return "Version, license, and project links."
        }
    }

    var systemImage: String {
        switch self {
        case .generalAudio: return "waveform.and.mic"
        case .hotkeys:      return "keyboard"
        case .aiModels:     return "brain.head.profile"
        case .vocabulary:   return "character.book.closed"
        case .agentBridge:  return "server.rack"
        case .appearance:   return "paintpalette"
        case .privacy:      return "lock.shield"
        case .about:        return "info.circle"
        }
    }

    /// The rail section this category belongs to. CaseIterable order inside a
    /// group == display order. [decision: three groups — System owns the capture
    ///  pipeline, Intelligence owns what happens to the words, Experience owns
    ///  how the app looks and what it guarantees.]
    var group: SettingsCategoryGroup {
        switch self {
        case .generalAudio, .hotkeys:
            return .system

        case .aiModels, .vocabulary, .agentBridge:
            return .intelligence

        case .appearance, .privacy, .about:
            return .experience
        }
    }
}

// MARK: - SettingsCategoryGroup

/// A rail section header. Order of cases == display order.
enum SettingsCategoryGroup: String, CaseIterable, Identifiable {
    case system
    case intelligence
    case experience

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system:       return "System"
        case .intelligence: return "Intelligence"
        case .experience:   return "Experience"
        }
    }

    /// The categories in this group, in display order.
    var categories: [SettingsCategory] {
        SettingsCategory.allCases.filter { $0.group == self }
    }
}
