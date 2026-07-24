// App/Dashboard/DashboardView.swift
//
// The full-window dashboard: a NavigationSplitView with the sidebar IA from
// `DashboardSection`.
//
// DUAL-MODE SIDEBAR ISOLATION RULE:
// When in Agent Workspace Mode (appMode == .workspace), the Dictation NavigationSplitView
// sidebar is hidden, allowing WorkspaceMainView to fill the entire window with its single
// Slack Channel Sidebar. When in Dictation Engine Mode (appMode == .dictation),
// NavigationSplitView renders the Dictation Engine Sidebar.

import SpeakCore
import SwiftUI

// MARK: - DashboardView

struct DashboardView: View {

    let context: DashboardContext

    /// The selected sidebar section. Seeded from `initialSection` (defaults to Home).
    @State private var selection: DashboardSection

    init(context: DashboardContext, initialSection: DashboardSection = .home) {
        self.context = context
        _selection = State(initialValue: initialSection)
    }

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                List(DashboardSection.mainSections, selection: $selection) { section in
                    Label(section.title, systemImage: section.systemImage)
                        .tag(section)
                }
                .listStyle(.sidebar)

                // Premium Glassmorphic Settings Footer Button
                VStack(spacing: 0) {
                    Divider()
                        .overlay(Color.speakCardBorder.opacity(0.6))
                    
                    Button {
                        selection = .settings
                    } label: {
                        HStack(spacing: SpeakSpacing.sm) {
                            Image(systemName: DashboardSection.settings.systemImage)
                                .font(.system(size: 14, weight: selection == .settings ? .bold : .medium))
                                .foregroundStyle(selection == .settings ? Color.white : Color.secondary)
                            Text(DashboardSection.settings.title)
                                .font(.system(size: 13, weight: selection == .settings ? .semibold : .medium))
                                .foregroundStyle(selection == .settings ? Color.white : Color.primary)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, SpeakSpacing.md)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(selection == .settings ? Color.accentColor : Color.white.opacity(0.06))
                                .shadow(color: Color.black.opacity(selection == .settings ? 0.2 : 0.05), radius: selection == .settings ? 4 : 2, x: 0, y: 1)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.white.opacity(selection == .settings ? 0.3 : 0.1), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, SpeakSpacing.xs + 2)
                    .padding(.vertical, SpeakSpacing.xs + 2)
                }
                .background(.ultraThinMaterial)
            }
            .background(Color.speakSidebarBg)
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 250)
        } detail: {
            detail(for: selection)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.speakInk)
                .navigationTitle(selection.title)
        }
        .frame(minWidth: 840, minHeight: 560)
        .background(Color.speakInk)
    }

    // MARK: - Detail routing

    @ViewBuilder
    private func detail(for section: DashboardSection) -> some View {
        switch section {
        case .home:       HomePaneView(context: context)
        case .aiStudio:   AIStudioPaneView(context: context)
        case .insights:   InsightsPaneView(context: context)
        case .dictionary: DictionaryPaneView(context: context)
        case .snippets:   SnippetsPaneView(context: context)
        case .style:      StylePaneView(context: context)
        case .transforms: TransformsPaneView(context: context)
        case .scratchpad: ScratchpadPaneView(context: context)
        case .history:    HistoryPaneView(context: context)
        case .agentInbox: AgentInboxPaneView(context: context)
        case .privacy:    PrivacyPaneView(context: context)
        case .settings:   SettingsPaneView(context: context)
        }
    }
}
