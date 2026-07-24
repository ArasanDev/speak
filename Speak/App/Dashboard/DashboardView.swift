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
    @State private var isSidebarCollapsed = false

    init(context: DashboardContext, initialSection: DashboardSection = .home) {
        self.context = context
        _selection = State(initialValue: initialSection)
    }

    private func toggleSidebar() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            isSidebarCollapsed.toggle()
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                HStack {
                    Button(action: toggleSidebar) {
                        Image(systemName: "sidebar.left")
                            .font(.system(size: 16))
                            .foregroundColor(.secondary)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 80) // Clear traffic lights
                    Spacer()
                }
                .frame(height: 28)
                
                List(selection: $selection) {
                    ForEach(DashboardSection.mainSections) { section in
                        Label(section.title, systemImage: section.systemImage)
                            .tag(section)
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
                
                Spacer(minLength: 0)
                
                List(selection: $selection) {
                    Label(DashboardSection.settings.title, systemImage: DashboardSection.settings.systemImage)
                        .tag(DashboardSection.settings)
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
                .frame(height: 52)
                .scrollDisabled(true)
            }
            .frame(width: isSidebarCollapsed ? 0 : 220)
            .opacity(isSidebarCollapsed ? 0 : 1)
            .clipped()
            .tint(Color.speakSidebarSelection)
            
            ZStack(alignment: .topLeading) {
                detail(for: selection)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                if isSidebarCollapsed {
                    Button(action: toggleSidebar) {
                        Image(systemName: "sidebar.left")
                            .font(.system(size: 16))
                            .foregroundColor(.secondary)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(24)
                }
            }
            .background(Color.speakCardCanvas)
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(Color.speakCardBorder, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.05), radius: 12, y: 4)
            .padding(16)
        }
        .frame(minWidth: 860, minHeight: 580)
        .background(Color.speakWindowCanvas)
        .ignoresSafeArea(.all, edges: .top)
        .background(
            Button(action: toggleSidebar) { EmptyView() }
                .keyboardShortcut("s", modifiers: [.command, .control])
                .opacity(0)
        )
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
        case .mcpAgents:  MCPAgentPaneView(context: context)
        case .privacy:    PrivacyPaneView(context: context)
        case .settings:   SettingsPaneView(context: context)
        }
    }
}
