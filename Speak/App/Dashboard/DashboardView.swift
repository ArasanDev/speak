// App/Dashboard/DashboardView.swift
//
// The full-window dashboard: a NavigationSplitView with the sidebar IA from
// `DashboardSection`. This is the Phase-2 UI spine (acceleration-plan.md Wave A) — the
// daily-open home that every v1 feature plugs into as a sidebar item.
//
// ROUTING: the detail column switches on the selected `DashboardSection` and hands each
// pane the shared `DashboardContext`. Includes TopSegmentedBarView at top center for
// dual-mode toggling between Dictation Engine and Agent Workspace.

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

            NavigationSplitView {
                VStack(spacing: 0) {
                    List(DashboardSection.mainSections, selection: $selection) { section in
                        Label(section.title, systemImage: section.systemImage)
                            .tag(section)
                    }
                    .listStyle(.sidebar)

                    Divider()

                    List([DashboardSection.settings], selection: $selection) { section in
                        Label(section.title, systemImage: section.systemImage)
                            .tag(section)
                    }
                    .listStyle(.sidebar)
                    .frame(height: 40)
                    .scrollDisabled(true)
                }
                .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
            } detail: {
                detailContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .navigationTitle(appMode == .workspace ? "Agent Workspace" : selection.title)
            }
        }
        .frame(minWidth: 840, minHeight: 560)
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
    private var detailContent: some View {
        if appMode == .workspace {
            WorkspaceMainView()
        } else {
            detail(for: selection)
        }
    }

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
