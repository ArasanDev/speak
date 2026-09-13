// App/Settings/PrivacyHealthSettingsView.swift
//
// "Privacy & System Health" — the seventh Settings category. Three cards:
//   - System Health: microphone + accessibility permission status and the
//     "fix it" paths (onboarding flow / System Settings).
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
            "Reset Settings?",
            isPresented: $showResetConfirmation,
            actions: {
                Button("Cancel", role: .cancel) { }
                Button("Reset", role: .destructive) {
                    context.settingsStore.resetToDefaults()
                }
            },
            message: {
                Text("This will reset all settings to their defaults. History is not affected.")
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
                permissionPill(for: micStatus)
            }

            SettingsRowSeparator()

            SettingsRow(
                "Accessibility",
                description: "Powers the global hotkey tap and Cmd+V paste simulation."
            ) {
                permissionPill(for: axStatus)
            }

            SettingsRowSeparator()

            SettingsRow(
                "Resolve permissions",
                description: "Re-runs the guided onboarding steps for anything missing."
            ) {
                Button("Fix via Onboarding…") { context.showOnboarding?() }
                    .disabled(context.showOnboarding == nil)
            }
        }
    }

    private func permissionPill(for state: PermissionState) -> some View {
        let granted = state == .granted
        return SettingsStatusPill(
            text: granted ? "Granted" : "Missing",
            tint: granted ? .speakDelivered : .orange
        )
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
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, SpeakSpacing.sm)
                    }
                )
                .buttonStyle(.borderedProminent)
                .tint(.speakDelivered)

                if let lastAuditAt, !moatResults.isEmpty {
                    let passed = moatResults.filter { $0.status == .pass }.count
                    HStack(spacing: SpeakSpacing.xs) {
                        Image(systemName: passed == moatResults.count
                              ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(passed == moatResults.count
                                             ? Color.speakDelivered : .orange)
                        Text("\(passed)/\(moatResults.count) guarantees verified · \(lastAuditAt.formatted(date: .omitted, time: .standard))")
                            .font(.speakBody(.caption))
                            .foregroundStyle(.secondary)
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
                description: "Restores every preference to its default. History is not affected."
            ) {
                Button("Reset…") { showResetConfirmation = true }
            }

            SettingsRowSeparator()

            SettingsRow(
                "Clear all history",
                description: "Deletes the local dictation archive stored on this Mac."
            ) {
                Button("Clear…") { clearHistory() }
            }

            SettingsRowSeparator()

            SettingsRow(
                "Export history",
                description: "Writes a JSON backup of your history onto the clipboard."
            ) {
                Button("Export…") { exportHistory() }
            }
        }
    }

    private func clearHistory() {
        Task {
            do {
                try await context.historyStore.clear()
                SpeakLog.app.info("History cleared via Settings")
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
            } catch {
                actionError = error.localizedDescription
                showActionError = true
            }
        }
    }
}
