// App/Settings/GeneralSettingsView.swift
//
// "General" — the application-frame category of the dedicated Settings
// experience: startup behavior and resetting preferences. Kept deliberately
// small — everything pipeline-shaped lives on the layer panes.

import SpeakCore
import SwiftUI

// MARK: - GeneralSettingsView

@MainActor
struct GeneralSettingsView: View {
    let context: DashboardContext

    @ObservedObject private var launchAtLogin = LaunchAtLoginManager.shared
    @State private var showResetConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.lg) {
            startupCard
            resetCard
        }
        .confirmationDialog(
            "Reset all settings to defaults?",
            isPresented: $showResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset Settings", role: .destructive) {
                context.settingsStore.resetToDefaults()
                // The primary hotkey binding lives in `UserDefaultsBindingStore`
                // (outside `SettingsStore.Keys`) — restore it too so Reset really
                // returns the trigger to double-tap Right-Command. Routes through
                // `rebindHotkey` so the live tap re-arms without a relaunch.
                context.rebindHotkey?(.defaultBinding)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Language, hotkeys, engines, voices, and appearance return to defaults. Dictation history is kept.")
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
        }
    }

    // MARK: - Reset

    private var resetCard: some View {
        SettingsSectionCard(title: "Reset") {
            SettingsRow(
                "Reset All Settings",
                description: "Restores every preference to its default. History is not touched."
            ) {
                Button("Reset…", role: .destructive) {
                    showResetConfirmation = true
                }
                .controlSize(.small)
            }
        }
    }
}
