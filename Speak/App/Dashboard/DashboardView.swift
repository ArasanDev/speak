// App/Dashboard/DashboardView.swift
//
// The full-window dashboard: a NavigationSplitView with the sidebar IA from
// `DashboardSection`. This is the Phase-2 UI spine (acceleration-plan.md Wave A) — the
// daily-open home that every v1 feature plugs into as a sidebar item.
//
// ROUTING: the detail column switches on the selected `DashboardSection` and hands each
// pane the shared `DashboardContext`. Pane bodies are owned by their specialists; this
// file owns only the frame + routing and is intentionally STABLE so per-pane work never
// collides here.
//
// CHROME vs CONTENT (design system): the sidebar/labels use the system UI font; panes
// render *content + data* in Monaco via the theme tokens. The split view itself is plain
// AppKit chrome.

import SpeakCore
import SwiftUI

// MARK: - DashboardView

struct DashboardView: View {

    let context: DashboardContext

    /// The selected sidebar section. Seeded from `initialSection` (defaults to Home);
    /// the debug dashboard target uses this to open straight to a pane for verification.
    @State private var selection: DashboardSection

    init(context: DashboardContext, initialSection: DashboardSection = .home) {
        self.context = context
        _selection = State(initialValue: initialSection)
    }

    var body: some View {
        NavigationSplitView {
            // [task #33] Selection-driven sidebar: the detail column switches on `selection`
            // (see `detail(for: selection)`). A `NavigationLink(value:)` row here has no
            // `.navigationDestination` and captures the tap, so `selection` never updated and
            // panes never switched. Plain `.tag`-ged rows let `List(selection:)` drive it.
            //
            // [decision: Settings pinned to the bottom] Two independent `List(selection:)`
            // instances share the same `$selection` binding — either can drive it. The main
            // list scrolls; the Settings row below the divider never does, matching the
            // System Settings / Slack / VS Code convention of anchoring Settings at the
            // bottom regardless of how many sections the main list grows to.
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
            detail(for: selection)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle(selection.title)
        }
        .frame(minWidth: 760, minHeight: 520)
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
