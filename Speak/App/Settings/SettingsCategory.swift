// App/Settings/SettingsCategory.swift
//
// The information architecture for the dedicated two-panel Settings experience
// (SettingsExperienceView). One case per rail destination; `group` defines the
// sidebar layout — grouped like macOS System Settings, so related categories
// sit under a shared section header.
//
// THE DISTRIBUTION PRINCIPLE [decision]: the dashboard is where the product
// works (runtime workspaces — dictate, history, inbox, playground, inference);
// Settings is where the product is built (parameters — engines, devices,
// voices, keys, hotkeys). The product IS a pipeline — `speech → text →
// intelligence → speech` — so the rail exposes it directly: one pane per layer
// plus `pipeline`, the assembled "final layer" that shows all three composed
// with live status. One home per capability: vocabulary/style/dictionary live
// ONLY here, never duplicated on the desk.
//
// Each category carries a `tileColor` — the System-Settings-style colored icon
// tile. Layer categories reuse the FE-1 channel hues (STT = human amber,
// Intelligence = agent violet) so color stays semantic, not decorative.
//
// Adding a category = adding a case here + a view in the detail-canvas switch.

import SwiftUI

// MARK: - SettingsCategory

/// One destination in the Settings rail. `CaseIterable` order == display order
/// within each `group`.
enum SettingsCategory: String, CaseIterable, Identifiable, Hashable {
    case pipeline
    case speechToText
    case textToSpeech
    case intelligence
    case hotkeys
    case vocabulary
    case agentBridge
    case appearance
    case privacy
    case general
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pipeline:     return "Voice Pipeline"
        case .speechToText: return "Speech to Text"
        case .textToSpeech: return "Text to Speech"
        case .intelligence: return "Intelligence"
        case .hotkeys:      return "Hotkeys"
        case .vocabulary:   return "Vocabulary"
        case .agentBridge:  return "Agent Bridge"
        case .appearance:   return "Appearance"
        case .privacy:      return "Privacy"
        case .general:      return "General"
        case .about:        return "About"
        }
    }

    /// One-line canvas subtitle — the "why am I here" line under the title.
    var subtitle: String {
        switch self {
        case .pipeline:
            return "The assembled voice loop — how the three layers connect."

        case .speechToText:
            return "Recognition engine, language, microphone, and text delivery."

        case .textToSpeech:
            return "The voice that speaks back — voice, rate, pitch, and readback."

        case .intelligence:
            return "Neat-writing engine, intensity, and inference providers."

        case .hotkeys:
            return "Global activation, push-to-talk, and extra shortcuts."

        case .vocabulary:
            return "Names, jargon, corrections, and trigger → expansion snippets."

        case .agentBridge:
            return "speak-mcp stdio server, agent sessions, and prompt tags."

        case .appearance:
            return "Theme, recording HUD, and border animations."

        case .privacy:
            return "On-device moat, OS permissions, and data controls."

        case .general:
            return "Startup behavior and resetting preferences."

        case .about:
            return "Version, license, and project links."
        }
    }

    var systemImage: String {
        switch self {
        case .pipeline:     return "point.3.connected.trianglepath.dotted"
        case .speechToText: return "waveform.and.mic"
        case .textToSpeech: return "speaker.wave.2"
        case .intelligence: return "brain.head.profile"
        case .hotkeys:      return "keyboard"
        case .vocabulary:   return "character.book.closed"
        case .agentBridge:  return "server.rack"
        case .appearance:   return "paintpalette"
        case .privacy:      return "lock.shield"
        case .general:      return "gearshape"
        case .about:        return "info.circle"
        }
    }

    /// The System-Settings-style colored icon tile. Layer categories reuse the
    /// FE-1 channel hues so color stays semantic: STT is the human channel
    /// (amber), Intelligence is the agent channel (violet); Text→Speech is the
    /// machine's voice (teal). Remaining categories get muted system hues.
    var tileColor: Color {
        switch self {
        case .pipeline:     return .indigo
        case .speechToText: return .speakHumanAmber
        case .textToSpeech: return .teal
        case .intelligence: return .speakAgentViolet
        case .hotkeys:      return .gray
        case .vocabulary:   return .orange
        case .agentBridge:  return .mint
        case .appearance:   return .pink
        case .privacy:      return .blue
        case .general:      return .gray
        case .about:        return .gray
        }
    }

    /// The rail section this category belongs to. CaseIterable order inside a
    /// group == display order. [decision: the rail IS the pipeline — the three
    /// layers sit under LAYERS in speech-order; PIPELINE leads as the assembled
    /// map; CONTROL holds input surfaces; APP holds the application frame.]
    var group: SettingsCategoryGroup {
        switch self {
        case .pipeline:
            return .pipeline

        case .speechToText, .textToSpeech, .intelligence:
            return .layers

        case .hotkeys, .vocabulary, .agentBridge:
            return .control

        case .appearance, .privacy, .general, .about:
            return .app
        }
    }
}

// MARK: - SettingsCategoryGroup

/// A rail section header. Order of cases == display order.
enum SettingsCategoryGroup: String, CaseIterable, Identifiable {
    case pipeline
    case layers
    case control
    case app

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pipeline: return "Pipeline"
        case .layers:   return "Layers"
        case .control:  return "Control"
        case .app:      return "App"
        }
    }

    /// The categories in this group, in display order.
    var categories: [SettingsCategory] {
        SettingsCategory.allCases.filter { $0.group == self }
    }
}
