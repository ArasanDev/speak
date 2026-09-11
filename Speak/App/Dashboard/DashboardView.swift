// App/Dashboard/DashboardView.swift
//
// The full-window dashboard: a NavigationSplitView with the sidebar IA from
// `DashboardSection`.

import SpeakCore
import SwiftUI

// MARK: - DashboardView

struct DashboardView: View {

    private struct SidebarToggleButton: View {
        let action: () -> Void
        @State private var isHovering = false
        
        var body: some View {
            Button(action: action) {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 15))
                    .foregroundColor(.secondary)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(Color.primary.opacity(isHovering ? 0.08 : 0))
            .cornerRadius(6)
            .onHover { hovering in
                isHovering = hovering
            }
        }
    }

    let context: DashboardContext

    enum SidebarDisplayMode: Equatable {
        case full, rail, hidden
    }

    /// The selected sidebar section. Seeded from `initialSection` (defaults to Home).
    @State private var selection: DashboardSection
    @State private var isSidebarManuallyToggled = false
    @State private var selfHealRotation: Double = 0
    @State private var isSelfHealed: Bool = false
    @State private var isSettingsHovered: Bool = false
    @State private var isSelfHealHovered: Bool = false
    @State private var showUpdateNotification: Bool = false

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
                            SidebarToggleButton(action: toggleSidebar)
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
                    
                    Divider()
                        .padding(.horizontal, isRail ? 8 : 16)
                        .opacity(0.4)
                    
                    if isRail {
                        sidebarRailBottomToolbar
                    } else {
                        sidebarBottomToolbar
                    }
                }
                .frame(width: sidebarWidth)
                .opacity(mode == .hidden ? 0 : 1)
                .clipped()
                .tint(Color.speakSidebarSelection)
                
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        if mode != .full {
                            SidebarToggleButton(action: toggleSidebar)
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

    // MARK: - Sidebar Bottom Toolbars
    
    private var sidebarBottomToolbar: some View {
        HStack(spacing: 0) {
            // Settings Icon Button (bottom left)
            Button(action: {
                selection = .settings
            }) {
                Image(systemName: "gearshape")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(selection == .settings ? Color.speakAccent : .secondary)
                    .frame(width: 32, height: 32)
                    .background(
                        selection == .settings
                            ? Color.primary.opacity(0.12)
                            : (isSettingsHovered ? Color.primary.opacity(0.06) : Color.clear)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .help("Settings")
            .onHover { isSettingsHovered = $0 }

            Spacer()

            // Self-Healing & Quick Repair Circle Button (bottom right of left panel)
            // Icon: "arrow.2.circlepath" (circle divided by half with arrows following each other)
            Button(action: {
                triggerSelfHeal()
            }) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "arrow.2.circlepath")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(isSelfHealed ? Color.speakStateDone : .secondary)
                        .rotationEffect(.degrees(selfHealRotation))
                        .frame(width: 32, height: 32)
                        .background(
                            isSelfHealed
                                ? Color.speakStateDone.opacity(0.15)
                                : (isSelfHealHovered ? Color.primary.opacity(0.06) : Color.clear)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    // Future version update indicator on top of the circle
                    Circle()
                        .fill(Color.speakAccent)
                        .frame(width: 6, height: 6)
                        .offset(x: -2, y: 2)
                        .opacity(showUpdateNotification ? 1 : 0)
                }
            }
            .buttonStyle(.plain)
            .help(isSelfHealed ? "Application Re-armed & Configured Properly" : "Self-Heal & Re-arm: reset hotkey tap & restore healthy state")
            .onHover { isSelfHealHovered = $0 }
            .contextMenu {
                Button("Self-Heal & Re-arm Hotkey") {
                    triggerSelfHeal()
                }
                Button("Restart speak") {
                    restartApp()
                }
                Divider()
                Button("Check for Updates (v0.0.1)") {
                    showUpdateNotification = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                        showUpdateNotification = false
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var sidebarRailBottomToolbar: some View {
        VStack(spacing: 8) {
            Button(action: {
                selection = .settings
            }) {
                Image(systemName: "gearshape")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(selection == .settings ? Color.speakAccent : .secondary)
                    .frame(width: 32, height: 32)
                    .background(selection == .settings ? Color.primary.opacity(0.12) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .help("Settings")

            Button(action: {
                triggerSelfHeal()
            }) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "arrow.2.circlepath")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(isSelfHealed ? Color.speakStateDone : .secondary)
                        .rotationEffect(.degrees(selfHealRotation))
                        .frame(width: 32, height: 32)
                        .background(isSelfHealed ? Color.speakStateDone.opacity(0.15) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    Circle()
                        .fill(Color.speakAccent)
                        .frame(width: 6, height: 6)
                        .offset(x: -2, y: 2)
                        .opacity(showUpdateNotification ? 1 : 0)
                }
            }
            .buttonStyle(.plain)
            .help("Self-Heal & Re-arm")
            .contextMenu {
                Button("Self-Heal & Re-arm Hotkey") {
                    triggerSelfHeal()
                }
                Button("Restart speak") {
                    restartApp()
                }
            }
        }
        .padding(.vertical, 8)
    }

    private func triggerSelfHeal() {
        withAnimation(.easeInOut(duration: 0.6)) {
            selfHealRotation += 360
        }
        context.onSelfHeal?()
        isSelfHealed = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            isSelfHealed = false
        }
    }

    private func restartApp() {
        let bundleURL = Bundle.main.bundleURL
        let config = NSWorkspace.OpenConfiguration()
        config.arguments = ["--replace"]
        NSWorkspace.shared.openApplication(at: bundleURL, configuration: config) { _, error in
            if error == nil {
                DispatchQueue.main.async {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
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
        case .inference:  InferencePaneView(context: context)
        case .playground: AgentPlaygroundView(context: context)
        case .history:    HistoryPaneView(context: context)
        case .agentInbox: AgentInboxPaneView(context: context)
        case .mcpAgents:  MCPAgentPaneView(context: context)
        case .privacy:    PrivacyPaneView(context: context)
        case .settings:   SettingsPaneView(context: context)
        }
    }
}
