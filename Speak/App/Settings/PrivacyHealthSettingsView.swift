// App/Settings/PrivacyHealthSettingsView.swift
//
// "Privacy" — the operational privacy category in the dedicated Settings
// experience. Three cards:
//   - System Health: microphone + accessibility permission status and the
//     "fix it" paths (guided onboarding re-run, per-pane System Settings
//     deep links for denied grants).
//   - On-Device Moat: the four structural guarantees + the live audit button.
//   - Data Management: reset settings, clear history, export history.
//
// The dashboard Privacy pane stays the marketing surface; this category is the
// operational one — status, audit, and data controls.

import AppKit
import SpeakCore
import SwiftUI

// MARK: - PrivacyHealthSettingsView

@MainActor
struct PrivacyHealthSettingsView: View {
    let context: DashboardContext

    @State private var showMoatResults = false
    @State private var moatResults: [MoatCheckResult] = []
    @State private var lastAuditAt: Date?
    @State private var micStatus: PermissionState = .notDetermined
    @State private var axStatus: PermissionState = .notDetermined
    @State private var showResetConfirmation = false
    @State private var showClearHistoryConfirmation = false
    @State private var showClearedNotice = false
    @State private var showExportedNotice = false
    @State private var actionError: String?
    @State private var showActionError = false

    var body: some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.lg) {
            healthCard
            moatCard
            dataCard
        }
        .task { await pollPermissions() }
        .sheet(isPresented: $showMoatResults) {
            MoatResultsSheet(results: moatResults)
        }
        .alert(
            "Reset all settings to defaults?",
            isPresented: $showResetConfirmation,
            actions: {
                Button("Cancel", role: .cancel) { }
                Button("Reset Settings", role: .destructive) {
                    resetAllSettings()
                }
            },
            message: {
                Text(
                    "Engines, language, hotkeys, microphone selection, voice, and appearance "
                        + "return to defaults — including custom vocabulary and corrections. "
                        + "Dictation history, snippets, and your custom themes are kept."
                )
            }
        )
        .alert(
            "Clear all dictation history?",
            isPresented: $showClearHistoryConfirmation,
            actions: {
                Button("Cancel", role: .cancel) { }
                Button("Clear History", role: .destructive) {
                    clearHistory()
                }
            },
            message: {
                Text("Every saved dictation on this Mac is permanently deleted. This can't be undone.")
            }
        )
        .alert(
            "Error",
            isPresented: $showActionError,
            actions: {
                Button("OK", role: .cancel) { actionError = nil }
            },
            message: {
                if let actionError {
                    Text(actionError)
                }
            }
        )
    }

    // MARK: - System health

    private var healthCard: some View {
        SettingsSectionCard(title: "System Health") {
            SettingsRow(
                "Microphone",
                description: "Needed to capture dictation audio."
            ) {
                permissionControl(for: micStatus, kind: .microphone)
            }

            SettingsRowSeparator()

            SettingsRow(
                "Accessibility",
                description: "Powers the global hotkey tap and Cmd+V paste simulation."
            ) {
                permissionControl(for: axStatus, kind: .accessibility)
            }

            SettingsRowSeparator()

            SettingsRow(
                "Resolve permissions",
                description: "Re-runs the guided onboarding steps for anything missing."
            ) {
                Button("Fix via Onboarding…") { context.showOnboarding?() }
                    .controlSize(.small)
                    .disabled(context.showOnboarding == nil)
            }
        }
    }

    /// Trailing control for a permission row: the status pill, plus a direct
    /// System Settings deep link when TCC has *denied* the grant — a denied
    /// permission can't be re-prompted in-app, so onboarding's request path
    /// alone can't fix it; the user must flip the switch themselves.
    @ViewBuilder
    private func permissionControl(for state: PermissionState, kind: PermissionKind) -> some View {
        HStack(spacing: SpeakSpacing.sm) {
            if state == .denied {
                Button("Open Settings…") { openSystemSettings(for: kind) }
                    .controlSize(.small)
            }
            permissionPill(for: state)
        }
    }

    private func permissionPill(for state: PermissionState) -> SettingsStatusPill {
        switch state {
        case .granted:
            return SettingsStatusPill(text: "Granted", tint: .speakOK)

        case .denied:
            return SettingsStatusPill(text: "Denied", tint: .speakError)

        case .restricted:
            return SettingsStatusPill(text: "Restricted", tint: .speakWarning)

        case .notDetermined, .requesting:
            return SettingsStatusPill(text: "Needed", tint: .speakWarning)
        }
    }

    private func openSystemSettings(for kind: PermissionKind) {
        let urlString: String
        switch kind {
        case .microphone:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"

        case .accessibility:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        }
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }

    /// Refresh the permission pills every 1.5 s while visible — TCC grants can
    /// change in System Settings without notifying the app. [decision: cheap
    /// poll over a NotificationCenter dependency that doesn't exist]
    private func pollPermissions() async {
        while !Task.isCancelled {
            micStatus = context.permissionManager?.status(.microphone) ?? .notDetermined
            axStatus = context.permissionManager?.status(.accessibility) ?? .notDetermined
            try? await Task.sleep(for: .milliseconds(1500))
        }
    }

    // MARK: - Moat

    private var moatCard: some View {
        SettingsSectionCard(title: "On-Device Moat") {
            VStack(alignment: .leading, spacing: SpeakSpacing.sm) {
                PrivacyGuaranteeRow(
                    icon: "mic.slash.fill",
                    title: "No cloud audio",
                    detail: "SpeechAnalyzer processes everything on your Mac — audio never leaves the device."
                )
                PrivacyGuaranteeRow(
                    icon: "brain.head.profile",
                    title: "No cloud AI",
                    detail: "Neat-writing uses Apple Foundation Models on the neural engine. No API call, no account."
                )
                PrivacyGuaranteeRow(
                    icon: "clipboard.fill",
                    title: "Write-only pasteboard",
                    detail: "speak writes your dictation to the clipboard and never reads what is already there."
                )
                PrivacyGuaranteeRow(
                    icon: "person.slash",
                    title: "No account, no telemetry",
                    detail: "Free, open-source, MIT-licensed. Zero sign-in, zero metering."
                )

                Button(
                    action: {
                        moatResults = MoatAuditor.runAudit()
                        lastAuditAt = Date()
                        showMoatResults = true
                    },
                    label: {
                        HStack(spacing: SpeakSpacing.xs) {
                            Image(systemName: "shield.checkmark.fill")
                            Text("Run Moat Verification")
                        }
                        .font(.speakBody(.base, semibold: true))
                        .foregroundStyle(Color.speakOnAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, SpeakSpacing.sm)
                    }
                )
                .buttonStyle(.borderedProminent)
                .tint(.speakUIAccent)

                if let lastAuditAt, !moatResults.isEmpty {
                    let passed = moatResults.filter { $0.status == .pass }.count
                    HStack(spacing: SpeakSpacing.xs) {
                        Image(systemName: passed == moatResults.count
                              ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(passed == moatResults.count
                                             ? Color.speakOK : Color.speakWarning)
                        Text("\(passed)/\(moatResults.count) guarantees verified · \(lastAuditAt.formatted(date: .omitted, time: .standard))")
                            .font(.speakBody(.caption))
                            .foregroundStyle(Color.speakMica)
                        Spacer()
                        Button("Details") { showMoatResults = true }
                            .font(.speakBody(.caption))
                            .buttonStyle(.borderless)
                    }
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, SpeakSpacing.md)
            .padding(.vertical, SpeakSpacing.sm + 4)
        }
    }

    // MARK: - Data management

    private var dataCard: some View {
        SettingsSectionCard(title: "Data Management") {
            SettingsRow(
                "Reset all settings",
                description: "Returns every preference — hotkeys, microphone, theme included — to its default. History is not affected."
            ) {
                Button("Reset…", role: .destructive) { showResetConfirmation = true }
                    .buttonStyle(.borderless)
                    .foregroundStyle(Color.speakError)
                    .controlSize(.small)
            }

            SettingsRowSeparator()

            SettingsRow(
                "Clear all history",
                description: "Deletes the local dictation archive stored on this Mac."
            ) {
                HStack(spacing: SpeakSpacing.sm) {
                    if showClearedNotice {
                        SettingsStatusPill(text: "Cleared", tint: .speakOK)
                            .transition(.opacity)
                    }
                    Button("Clear…", role: .destructive) { showClearHistoryConfirmation = true }
                        .buttonStyle(.borderless)
                        .foregroundStyle(Color.speakError)
                        .controlSize(.small)
                }
                .animation(.easeInOut(duration: 0.2), value: showClearedNotice)
            }

            SettingsRowSeparator()

            SettingsRow(
                "Export history",
                description: "Writes a JSON backup of your history onto the clipboard."
            ) {
                HStack(spacing: SpeakSpacing.sm) {
                    if showExportedNotice {
                        SettingsStatusPill(text: "Copied", tint: .speakDelivered)
                            .transition(.opacity)
                    }
                    Button("Export…") { exportHistory() }
                        .controlSize(.small)
                }
                .animation(.easeInOut(duration: 0.2), value: showExportedNotice)
            }
        }
    }

    /// Mirrors the General category's reset: `resetToDefaults` covers every
    /// `SettingsStore.Keys` preference (incl. mic pin + theme), while the
    /// hotkey bindings live in `UserDefaultsBindingStore` — restore them too
    /// and re-arm the live tap via the controller's rebind entry points.
    private func resetAllSettings() {
        context.settingsStore.resetToDefaults()
        context.rebindHotkey?(.defaultBinding)
        context.rebindExtraBindings?(.empty)
    }

    private func clearHistory() {
        Task {
            do {
                try await context.historyStore.clear()
                SpeakLog.app.info("History cleared via Settings")
                flashClearedNotice()
            } catch {
                actionError = error.localizedDescription
                showActionError = true
            }
        }
    }

    private func exportHistory() {
        Task {
            do {
                let exported = try await context.historyStore.export()
                // Write-only pasteboard — the moat forbids reads, not writes.
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(exported, forType: .string)
                SpeakLog.app.info("History exported via Settings")
                flashExportedNotice()
            } catch {
                actionError = error.localizedDescription
                showActionError = true
            }
        }
    }

    /// Transient status pills for ~2.5 s after a successful data action —
    /// silent success leaves the user guessing whether anything happened.
    private func flashClearedNotice() {
        showClearedNotice = true
        Task {
            try? await Task.sleep(for: .milliseconds(2500))
            showClearedNotice = false
        }
    }

    private func flashExportedNotice() {
        showExportedNotice = true
        Task {
            try? await Task.sleep(for: .milliseconds(2500))
            showExportedNotice = false
        }
    }
}
