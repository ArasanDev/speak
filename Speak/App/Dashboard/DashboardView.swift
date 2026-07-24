// App/Dashboard/DashboardView.swift
//
// The full-window dashboard: a NavigationSplitView with the sidebar IA from
// `DashboardSection`.

import SpeakCore
import SwiftUI

// MARK: - DashboardView

struct DashboardView: View {

    let context: DashboardContext

    enum SidebarDisplayMode: Equatable {
        case full, rail, hidden
    }

    /// The selected sidebar section. Seeded from `initialSection` (defaults to Home).
    @State private var selection: DashboardSection
    @State private var isSidebarManuallyToggled = false

    init(context: DashboardContext, initialSection: DashboardSection = .home) {
        self.context = context
        _selection = State(initialValue: initialSection)
    }
    
    private func effectiveSidebarMode(for width: CGFloat) -> SidebarDisplayMode {
        if width < 600 {
            return isSidebarManuallyToggled ? .full : .hidden
        } else if width < 720 {
            return isSidebarManuallyToggled ? .full : .rail
        } else {
            return isSidebarManuallyToggled ? .rail : .full
        }
    }

    private func toggleSidebar() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            isSidebarManuallyToggled.toggle()
        }
    }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let mode = effectiveSidebarMode(for: width)
            let isRail = mode == .rail
            let sidebarWidth: CGFloat = mode == .full ? 220 : (isRail ? 54 : 0)
            
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    HStack {
                        if mode == .full {
                            Button(action: toggleSidebar) {
                                Image(systemName: "sidebar.left")
                                    .font(.system(size: 16))
                                    .foregroundColor(.secondary)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .padding(.leading, 80) // Clear traffic lights
                        }
                        Spacer()
                    }
                    .frame(height: 28)
                    
                    List(selection: $selection) {
                        ForEach(DashboardSection.mainSections) { section in
                            if isRail {
                                Image(systemName: section.systemImage)
                                    .font(.system(size: 16))
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .help(section.title)
                                    .tag(section)
                            } else {
                                Label(section.title, systemImage: section.systemImage)
                                    .tag(section)
                            }
                        }
                    }
                    .listStyle(.sidebar)
                    .scrollContentBackground(.hidden)
                    
                    Spacer(minLength: 0)
                    
                    List(selection: $selection) {
                        if isRail {
                            Image(systemName: DashboardSection.settings.systemImage)
                                .font(.system(size: 16))
                                .frame(maxWidth: .infinity, alignment: .center)
                                .help(DashboardSection.settings.title)
                                .tag(DashboardSection.settings)
                        } else {
                            Label(DashboardSection.settings.title, systemImage: DashboardSection.settings.systemImage)
                                .tag(DashboardSection.settings)
                        }
                    }
                    .listStyle(.sidebar)
                    .scrollContentBackground(.hidden)
                    .frame(height: 52)
                    .scrollDisabled(true)
                }
                .frame(width: sidebarWidth)
                .opacity(mode == .hidden ? 0 : 1)
                .clipped()
                .tint(Color.speakSidebarSelection)
                
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        if mode != .full {
                            Button(action: toggleSidebar) {
                                Image(systemName: "sidebar.left")
                                    .font(.system(size: 14))
                                    .foregroundColor(.secondary)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .frame(width: 28, height: 28)
                            .background(Color.speakCardBorder)
                            .clipShape(Capsule())
                        }
                        
                        Text(selection.title)
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        Spacer()
                    }
                    .padding(.leading, mode == .hidden ? 80 : 16)
                    .frame(height: mode == .full ? 44 : 36)
                    
                    detail(for: selection)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 480, minHeight: 480)
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
