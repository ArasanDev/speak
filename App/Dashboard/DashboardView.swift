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

import SwiftUI
import SpeakCore

// MARK: - DashboardView

struct DashboardView: View {

    let context: DashboardContext

    /// Persisted last-selected section so re-opening the window restores the user's place.
    @State private var selection: DashboardSection = .home

    var body: some View {
        NavigationSplitView {
            List(DashboardSection.allCases, selection: $selection) { section in
                NavigationLink(value: section) {
                    Label(section.title, systemImage: section.systemImage)
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
            .listStyle(.sidebar)
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
        case .history:    HistoryPaneView(context: context)
        case .dictionary: DictionaryPaneView(context: context)
        case .snippets:   SnippetsPaneView(context: context)
        case .style:      StylePaneView(context: context)
        case .insights:   InsightsPaneView(context: context)
        }
    }
}
