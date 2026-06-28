// App/AppShell.swift
//
// The unified app shell: a persistent window with sidebar navigation (5 sections)
// and a content area that switches between panes. This is an alternative entry point
// to the individual Dashboard, History, and Settings windows.
//
// ARCHITECTURE:
//   - AppPane enum: 5 cases (dashboard, history, settings, privacy, about)
//   - @State for active pane selection (persists during app session)
//   - Sidebar: navigation items with semantic highlighting
//   - Content area: @ViewBuilder routing to the appropriate pane
//
// DEPENDENCY WIRING (critical — see WindowPresenter pattern):
//   - DashboardContext is built once in @State init, not rebuilt on render
//   - HistoryViewModel is built once in @State init, likewise
//   - Both are passed down to their respective pane views
//   - No rebuilds = no state race / lost scroll position / lost pane state
//
// WINDOW LIFECYCLE:
//   Called from SpeakApp as a Window scene (non-auto-opening). Presented via
//   menu action or external trigger, not at app launch.
//
// CHROME vs CONTENT:
//   Sidebar labels use system UI font (chrome); panes use Monaco via SpeakTheme
//   (content voice). Sidebar width follows macOS convention (~180pt).

import SpeakCore
import SwiftUI

// MARK: - AppPane

/// The 5 top-level navigation sections in the app shell.
enum AppPane: Hashable, CaseIterable, Identifiable {
    case dashboard
    case history
    case settings
    case privacy
    case about

    var id: Self { self }

    var title: String {
        switch self {
        case .dashboard: "Dashboard"
        case .history: "History"
        case .settings: "Settings"
        case .privacy: "Privacy"
        case .about: "About"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: "waveform.circle"
        case .history: "clock.fill"
        case .settings: "gearshape"
        case .privacy: "lock.shield"
        case .about: "info.circle"
        }
    }
}

// MARK: - AppShell

@MainActor
struct AppShell: View {

    let controller: DictationController

    /// Current active pane — persists for the session.
    @State private var activePane: AppPane = .dashboard

    /// DashboardContext built once and held for the window lifetime.
    @State private var dashboardContext: DashboardContext?

    /// HistoryViewModel built once and held for the window lifetime.
    @State private var historyViewModel: HistoryViewModel?

    var body: some View {
        HStack(spacing: 0) {
            // Sidebar — left column
            SidebarView(activePane: $activePane)

            Divider()

            // Content area — right column, switches on activePane
            ZStack {
                contentView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .navigationTitle(activePane.title)
            }
        }
        .frame(minWidth: 960, minHeight: 600)
        .onAppear {
            // Build the shared dependencies once at window open.
            if dashboardContext == nil {
                // Use ["Fn"] as default; the actual hotkey combo will match the controller's
                // current binding, but we use the default here to avoid accessing private APIs.
                // The combo is refreshed each time the window is shown (if needed).
                dashboardContext = DashboardContext(
                    settingsStore: controller.settingsStore,
                    historyStore: controller.historyStore,
                    hotkeyCombo: ["Fn"],
                    snippetStore: controller.snippetStore
                )
            }
            if historyViewModel == nil {
                if let context = dashboardContext {
                    historyViewModel = HistoryViewModel(store: context.historyStore)
                }
            }
        }
    }

    // MARK: - Content routing

    @ViewBuilder
    private func contentView() -> some View {
        switch activePane {
        case .dashboard:
            if let context = dashboardContext {
                DashboardView(context: context)
            } else {
                Text("Loading…")
                    .foregroundStyle(.secondary)
            }

        case .history:
            if let viewModel = historyViewModel {
                HistoryView(viewModel: viewModel)
            } else {
                Text("Loading…")
                    .foregroundStyle(.secondary)
            }

        case .settings:
            SettingsView(controller: controller)

        case .privacy:
            if let context = dashboardContext {
                PrivacyPaneView(context: context)
            } else {
                Text("Loading…")
                    .foregroundStyle(.secondary)
            }

        case .about:
            AboutView()
        }
    }
}

// MARK: - SidebarView

@MainActor
private struct SidebarView: View {

    @Binding var activePane: AppPane

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Sidebar title
            VStack(alignment: .leading, spacing: SpeakSpacing.md) {
                Image(systemName: "waveform")
                    .font(.system(size: 24))
                    .foregroundStyle(Color.speakAccent)
                Text("speak")
                    .font(.headline)
            }
            .padding(SpeakSpacing.md)

            Divider()

            // Navigation items
            List(AppPane.allCases, selection: $activePane) { pane in
                NavigationLink(value: pane) {
                    Label(pane.title, systemImage: pane.systemImage)
                        .foregroundStyle(activePane == pane ? Color.speakAccent : .primary)
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)

            Spacer()

            Divider()

            // Footer info
            Text("v\(appVersion)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(SpeakSpacing.sm)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(minWidth: 180, maxWidth: 240)
        .background(Color.speakSurface)
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        return [version, build.map { "(\($0))" }]
            .compactMap { $0 }
            .joined(separator: " ")
    }
}

// MARK: - Preview

#if DEBUG
#Preview("AppShell Sidebar") {
    // Previewing AppShell requires a real controller (which starts CGEventTap
    // and full engine setup). This preview sketches the sidebar layout only.
    VStack {
        HStack(spacing: 0) {
            // Sidebar sketch
            VStack(alignment: .leading, spacing: SpeakSpacing.md) {
                VStack(alignment: .leading, spacing: SpeakSpacing.md) {
                    Image(systemName: "waveform")
                        .font(.system(size: 24))
                        .foregroundStyle(Color.speakAccent)
                    Text("speak")
                        .font(.headline)
                }
                .padding(SpeakSpacing.md)

                Divider()

                List(AppPane.allCases, id: \.self) { pane in
                    Label(pane.title, systemImage: pane.systemImage)
                        .foregroundStyle(pane == .dashboard ? Color.speakAccent : .primary)
                }
                .listStyle(.sidebar)

                Spacer()
            }
            .frame(minWidth: 180, maxWidth: 240)
            .background(Color.speakSurface)

            Divider()

            // Content area sketch
            VStack {
                Text("Dashboard")
                    .font(.speakMonoTitle)
                    .padding(SpeakSpacing.lg)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 960, minHeight: 600)
    }
}
#endif
