// App/Settings/GeneralSettingsView.swift
//
// "General" — the application-frame category of the dedicated Settings
// experience: startup behavior and resetting preferences. Kept deliberately
// small — everything pipeline-shaped lives on the layer panes.

import AppKit
import Combine
import ServiceManagement
import SpeakCore
import SwiftUI

// MARK: - GeneralSettingsView

@MainActor
struct GeneralSettingsView: View {
    let context: DashboardContext

    private let launchAtLogin = LaunchAtLoginManager.shared
    @State private var showResetConfirmation = false

    /// Raw `SMAppService` status. `LaunchAtLoginManager` publishes only the
    /// derived `isEnabled` bool — the view needs the raw status to surface
    /// `.requiresApproval` (macOS holds the login item for review after
    /// `register()`, so the toggle silently snaps back without this note) and
    /// `.notFound` (unbundled dev/debug runs can never persist a login item).
    @State private var loginItemStatus: SMAppService.Status = .notRegistered

    var body: some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.lg) {
            startupCard
            resetCard
        }
        .onAppear { refreshLoginItemStatus() }
        .onChange(of: launchAtLogin.isEnabled) { refreshLoginItemStatus() }
        // Approving the login item happens in System Settings — TCC-style
        // changes don't notify the app, so refresh when we re-activate.
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification
        )) { _ in
            refreshLoginItemStatus()
        }
        .confirmationDialog(
            "Reset all settings to defaults?",
            isPresented: $showResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset Settings", role: .destructive) {
                context.settingsStore.resetToDefaults()
                // The hotkey bindings live in `UserDefaultsBindingStore`
                // (outside `SettingsStore.Keys`) — restore the primary binding
                // and clear the additive set so Reset really returns the
                // trigger to double-tap Right-Command. Routing through
                // `rebindHotkey`/`rebindExtraBindings` re-arms the live tap
                // without a relaunch.
                context.rebindHotkey?(.defaultBinding)
                context.rebindExtraBindings?(.empty)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "Engines, language, hotkeys, microphone selection, voice, and appearance "
                    + "return to defaults — including custom vocabulary and corrections. "
                    + "Dictation history, snippets, and your custom themes are kept."
            )
        }
    }

    // MARK: - Startup

    private var startupCard: some View {
        SettingsSectionCard(title: "Startup") {
            SettingsRow(
                "Launch at Login",
                description: "Start speak in the background when you log in."
            ) {
                Toggle("", isOn: Binding(
                    get: { launchAtLogin.isEnabled },
                    set: { launchAtLogin.setEnabled($0) }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
            }

            if loginItemStatus == .requiresApproval {
                SettingsRowSeparator()

                SettingsRow(
                    "Approval needed",
                    description: "macOS is holding the login item for review. Approve speak under General → Login Items & Extensions."
                ) {
                    Button("Open Login Items…") {
                        SMAppService.openSystemSettingsLoginItems()
                    }
                    .controlSize(.small)
                }
            } else if loginItemStatus == .notFound {
                SettingsRowSeparator()

                SettingsRow(
                    "Login item unavailable",
                    description: "This build isn't a registered app bundle, so macOS can't persist a login item for it."
                )
            }
        }
    }

    private func refreshLoginItemStatus() {
        launchAtLogin.refresh()
        loginItemStatus = SMAppService.mainApp.status
    }

    // MARK: - Reset

    private var resetCard: some View {
        SettingsSectionCard(title: "Reset") {
            SettingsRow(
                "Reset All Settings",
                description: "Returns every preference — hotkeys, microphone, theme included — to its default. History is not touched."
            ) {
                Button("Reset All Settings…", role: .destructive) {
                    showResetConfirmation = true
                }
                .buttonStyle(.borderless)
                .foregroundStyle(Color.speakError)
                .controlSize(.small)
            }
        }
    }
}
