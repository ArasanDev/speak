// App/Dashboard/DashboardView.swift
//
// The full-window dashboard: a NavigationSplitView with the sidebar IA from
// `DashboardSection`.

import Combine
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
                    .foregroundStyle(Color.speakMica)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(Color.primary.opacity(isHovering ? 0.08 : 0))
            .clipShape(.rect(cornerRadius: 6))
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
    /// `.settings` is the sentinel for the dedicated two-panel Settings
    /// experience — it is not a `mainSections` row, so when it is selected the
    /// whole window swaps to `SettingsExperienceView` instead of a desk pane.
    @State private var selection: DashboardSection
    /// The desk section to return to when leaving Settings. Updated each time a
    /// real desk section is selected so "‹ Dashboard" restores where you were.
    @State private var lastDeskSection: DashboardSection = .home
    @State private var isSidebarManuallyToggled = false
    @State private var selfHealRotation: Double = 0
    @State private var isSelfHealed: Bool = false
    @State private var isSettingsHovered: Bool = false
    @State private var isSelfHealHovered: Bool = false
    @State private var showUpdateNotification: Bool = false
    /// Pending resets for the transient badges — cancelled and replaced on
    /// re-trigger so rapid clicks restart the clock instead of an older
    /// timer dismissing a badge that was just re-shown.
    @State private var selfHealResetTask: Task<Void, Never>?
    @State private var updateToastTask: Task<Void, Never>?

    /// How long the self-heal "re-armed" confirmation stays lit.
    /// [decision: 2.5s — long enough to register as a confirmation, short
    ///  enough not to read as a stuck state]
    private static let selfHealConfirmationSeconds: Double = 2.5
    /// How long the update-check badge stays visible.
    /// [decision: 3.0s — transient toast convention]
    private static let updateToastSeconds: Double = 3.0

    /// Which Settings category Mode B opens on — seeded by the debug
    /// deep-link (`--debug-open dashboard:settings:<category>`); the normal
    /// gear path leaves it at .pipeline.
    private let initialSettingsCategory: SettingsCategory

    init(
        context: DashboardContext,
        initialSection: DashboardSection = .home,
        initialSettingsCategory: SettingsCategory = .pipeline
    ) {
        self.context = context
        self.initialSettingsCategory = initialSettingsCategory
        _selection = State(initialValue: initialSection)
        if initialSection != .settings {
            _lastDeskSection = State(initialValue: initialSection)
        }
    }

    /// Enter the dedicated Settings experience, remembering the desk section.
    private func openSettings() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            lastDeskSection = selection
            selection = .settings
        }
    }

    /// Leave Settings and restore the desk section the user came from.
    private func closeSettings() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            selection = lastDeskSection
        }
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
        Group {
            if selection == .settings {
                // Mode B — the dedicated two-panel Settings experience.
                SettingsExperienceView(
                    context: context,
                    initialCategory: initialSettingsCategory,
                    onBack: closeSettings,
                    onOpenSection: { section in
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                            selection = section
                        }
                    }
                )
            } else {
                // Mode A — the main application desk.
                desk
            }
        }
        .frame(minWidth: 480, minHeight: 480)
        .background(Color.speakWindowCanvas)
        .ignoresSafeArea(.all, edges: .top)
        .onChange(of: selection) { _, newValue in
            if newValue != .settings { lastDeskSection = newValue }
        }
        .onReceive(context.navigateToSectionPublisher ?? Empty().eraseToAnyPublisher()) { target in
            if target == .settings {
                openSettings()
            } else {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                    selection = target
                    lastDeskSection = target
                }
            }
        }
        .background(
            Button(action: toggleSidebar) { EmptyView() }
                .keyboardShortcut("s", modifiers: [.command, .control])
                .opacity(0)
        )
    }

    /// Mode A layout: sidebar + detail canvas (the pre-Settings desk).
    private var desk: some View {
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
                        if isRail {
                            // Icon-only rail: no group headers, flat list.
                            ForEach(DashboardSection.mainSections) { section in
                                Image(systemName: section.systemImage)
                                    .font(.system(size: 16))
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .help(section.title)
                                    .tag(section)
                            }
                        } else {
                            // Grouped like the Settings rail — ACTIVITY is what
                            // the pipeline did, AGENT COCKPIT is the bridge,
                            // STUDIOS is where work gets shaped.
                            ForEach(DashboardGroup.allCases) { group in
                                Section {
                                    ForEach(group.sections) { section in
                                        Label(section.title, systemImage: section.systemImage)
                                            .tag(section)
                                    }
                                } header: {
                                    if let title = group.title {
                                        Text(title)
                                    }
                                }
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
                            .foregroundStyle(Color.speakBone)

                        // The pane's "why am I here" line — carried by the
                        // section, not a duplicate in-pane hero title.
                        Text(selection.subtitle)
                            .font(.speakBody(.caption))
                            .foregroundStyle(Color.speakMica)
                            .lineLimit(1)

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
    }

    // MARK: - Sidebar Bottom Toolbars

    private var sidebarBottomToolbar: some View {
        HStack(spacing: 0) {
            // Settings Icon Button (bottom left) — enters the dedicated
            // two-panel Settings experience (Mode B).
            Button(action: openSettings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(selection == .settings ? Color.speakUIAccent : Color.speakMica)
                    .frame(width: 32, height: 32)
                    .background(
                        selection == .settings
                            ? Color.speakSidebarSelection
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
                        .foregroundStyle(isSelfHealed ? Color.speakDelivered : Color.speakMica)
                        .rotationEffect(.degrees(selfHealRotation))
                        .frame(width: 32, height: 32)
                        .background(
                            isSelfHealed
                                ? Color.speakDelivered.opacity(0.15)
                                : (isSelfHealHovered ? Color.primary.opacity(0.06) : Color.clear)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    // Future version update indicator on top of the circle
                    Circle()
                        .fill(Color.speakUIAccent)
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
                    updateToastTask?.cancel()
                    updateToastTask = Task {
                        try? await Task.sleep(for: .seconds(Self.updateToastSeconds))
                        guard !Task.isCancelled else { return }
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
            Button(action: openSettings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(selection == .settings ? Color.speakUIAccent : Color.speakMica)
                    .frame(width: 32, height: 32)
                    .background(selection == .settings ? Color.speakSidebarSelection : Color.clear)
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
                        .foregroundStyle(isSelfHealed ? Color.speakDelivered : Color.speakMica)
                        .rotationEffect(.degrees(selfHealRotation))
                        .frame(width: 32, height: 32)
                        .background(isSelfHealed ? Color.speakDelivered.opacity(0.15) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    Circle()
                        .fill(Color.speakUIAccent)
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
        selfHealResetTask?.cancel()
        selfHealResetTask = Task {
            try? await Task.sleep(for: .seconds(Self.selfHealConfirmationSeconds))
            guard !Task.isCancelled else { return }
            isSelfHealed = false
        }
    }

    private func restartApp() {
        let bundleURL = Bundle.main.bundleURL
        let config = NSWorkspace.OpenConfiguration()
        config.arguments = ["--replace"]
        NSWorkspace.shared.openApplication(at: bundleURL, configuration: config) { _, error in
            if error == nil {
                Task { @MainActor in
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
        case .transforms: TransformsPaneView(context: context)
        case .scratchpad: ScratchpadPaneView(context: context)
        case .inference:  InferencePaneView(context: context)
        case .playground: AgentPlaygroundView(context: context)
        case .history:    HistoryPaneView(context: context)
        case .agentInbox: AgentInboxPaneView(context: context)
        case .mcpAgents:  MCPAgentPaneView(context: context)

        // `.settings` never reaches the desk detail — `body` swaps the whole
        // window to `SettingsExperienceView` before `detail(for:)` is called.
        case .settings:   EmptyView()
        }
    }
}
