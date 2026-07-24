// App/Dashboard/DashboardView.swift
//
// The full-window dashboard: a NavigationSplitView with the sidebar IA from
// `DashboardSection`.

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
                List(selection: $selection) {
                    ForEach(DashboardSection.mainSections) { section in
                        Label(section.title, systemImage: section.systemImage)
                            .tag(section)
                    }
                }
                .listStyle(.sidebar)

                Spacer(minLength: 0)

                List(selection: $selection) {
                    Label(DashboardSection.settings.title, systemImage: DashboardSection.settings.systemImage)
                        .tag(DashboardSection.settings)
                }
                .listStyle(.sidebar)
                .frame(height: 52)
                .scrollDisabled(true)
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
        } detail: {
            detail(for: selection)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.speakInk)
                .navigationTitle(selection.title)
        }
        .frame(minWidth: 860, minHeight: 580)
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
