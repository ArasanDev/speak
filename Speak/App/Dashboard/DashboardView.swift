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

    /// Top-center mode selection (Dictation Engine vs Agent Workspace).
    @State private var appMode: AppMode = .workspace

    init(context: DashboardContext, initialSection: DashboardSection = .home) {
        self.context = context
        _selection = State(initialValue: initialSection)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top-center segmented bar for dual-mode switching
            TopSegmentedBarView(currentMode: $appMode)

            if appMode == .workspace {
                // Workspace Mode: WorkspaceMainView fills the entire window with its single Slack Channel Sidebar!
                WorkspaceMainView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Dictation Engine Mode: NavigationSplitView renders the Dictation Engine Sidebar
                NavigationSplitView {
                    VStack(spacing: 0) {
                        List(DashboardSection.mainSections.filter { $0 != .workspace }, selection: $selection) { section in
                            Label(section.title, systemImage: section.systemImage)
                                .tag(section)
                        }
                        .listStyle(.sidebar)

                        Divider()
                            .overlay(Color.speakCardBorder)

                        List([DashboardSection.settings], selection: $selection) { section in
                            Label(section.title, systemImage: section.systemImage)
                                .tag(section)
                        }
                        .listStyle(.sidebar)
                        .frame(height: 40)
                        .scrollDisabled(true)
                    }
                    .background(Color.speakSidebarBg)
                    .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
                } detail: {
                    detail(for: selection)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.speakInk)
                        .navigationTitle(selection.title)
                }
            }
        }
        .frame(minWidth: 840, minHeight: 560)
        .background(Color.speakInk)
        .onChange(of: appMode) { newMode in
            if newMode == .workspace {
                selection = .workspace
            } else if selection == .workspace {
                selection = .home
            }
        }
        .onChange(of: selection) { newSelection in
            if newSelection == .workspace {
                appMode = .workspace
            } else {
                appMode = .dictation
            }
        }
    }

    // MARK: - Detail routing

    @ViewBuilder
    private func detail(for section: DashboardSection) -> some View {
        switch section {
        case .home:       HomePaneView(context: context)
        case .workspace:  WorkspaceMainView()
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
