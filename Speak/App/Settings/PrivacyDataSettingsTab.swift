// App/Settings/PrivacyDataSettingsTab.swift
//
// Privacy & Data: the structural moat (four on-device guarantees) + data controls.
// This is marketing AND trust: a local-first app's clearest differentiator.
// Extracted from SettingsView.swift to respect SwiftLint file_length cap.

import AppKit
import SpeakCore
import SwiftUI

struct PrivacyDataSettingsTab: View {
    let store: SettingsStore
    let controller: DictationController

    @State private var showResetConfirmation = false
    @State private var resetError: String?
    @State private var showResetError = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SpeakSpacing.lg) {

                // Badge block — lock icon + headline
                HStack(alignment: .top, spacing: SpeakSpacing.md) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: SpeakSpacing.xs) {
                        Text("100% On-Device")
                            .font(.speakMonoTitle)
                        Text("speak never sends your voice, your words, or your clipboard anywhere.")
                            .font(.speakMonoCaption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(SpeakSpacing.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.speakSurface)
                )

                // Four guarantee rows
                VStack(alignment: .leading, spacing: SpeakSpacing.md) {
                    PrivacyGuaranteeRow(
                        icon: "mic.slash.fill",
                        title: "No cloud audio",
                        detail: "Speech is processed by Apple SpeechAnalyzer entirely on your Mac. Audio never leaves the device."
                    )
                    Divider()
                    PrivacyGuaranteeRow(
                        icon: "brain.head.profile",
                        title: "No cloud AI",
                        detail: "Neat-writing uses Apple Foundation Models — the neural engine on your chip. No API call, no account, no quota."
                    )
                    Divider()
                    PrivacyGuaranteeRow(
                        icon: "person.slash",
                        title: "No account required",
                        detail: "speak is free, open-source, and MIT-licensed. There is no sign-in, no subscription, and no usage metering."
                    )
                    Divider()
                    PrivacyGuaranteeRow(
                        icon: "clipboard.fill",
                        title: "Never reads your clipboard",
                        detail: "speak only writes to the clipboard to paste your dictation. It never reads what is already there."
                    )
                }
                .padding(SpeakSpacing.lg)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.speakSurface)
                )

                // Data controls — reset settings, clear history, export data.
                VStack(alignment: .leading, spacing: SpeakSpacing.md) {
                    Text("Data Management")
                        .font(.headline)

                    Button(action: { showResetConfirmation = true }) {
                        HStack {
                            Image(systemName: "arrow.counterclockwise")
                            Text("Reset All Settings to Defaults")
                            Spacer()
                        }
                        .foregroundStyle(.primary)
                    }
                    .padding(.vertical, SpeakSpacing.sm)
                    .padding(.horizontal, SpeakSpacing.md)
                    .background(Color.speakSurface)
                    .cornerRadius(6)

                    Button(action: {
                        Task {
                            do {
                                try await controller.historyStore.clear()
                                SpeakLog.app.info("History cleared via Settings")
                            } catch {
                                resetError = error.localizedDescription
                                showResetError = true
                            }
                        }
                    }) {
                        HStack {
                            Image(systemName: "trash")
                            Text("Clear All History")
                            Spacer()
                        }
                        .foregroundStyle(.primary)
                    }
                    .padding(.vertical, SpeakSpacing.sm)
                    .padding(.horizontal, SpeakSpacing.md)
                    .background(Color.speakSurface)
                    .cornerRadius(6)

                    Button(action: {
                        Task {
                            do {
                                let exported = try await controller.historyStore.export()
                                let pasteboard = NSPasteboard.general
                                pasteboard.clearContents()
                                pasteboard.setString(exported, forType: .string)
                                SpeakLog.app.info("History exported via Settings")
                            } catch {
                                resetError = error.localizedDescription
                                showResetError = true
                            }
                        }
                    }) {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                            Text("Export History as JSON")
                            Spacer()
                        }
                        .foregroundStyle(.primary)
                    }
                    .padding(.vertical, SpeakSpacing.sm)
                    .padding(.horizontal, SpeakSpacing.md)
                    .background(Color.speakSurface)
                    .cornerRadius(6)

                    Text("History is stored locally on your Mac. Export creates a JSON backup on your clipboard.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(SpeakSpacing.lg)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.speakSurface)
                )
            }
            .padding(SpeakSpacing.lg)
        }
        .alert(
            "Reset Settings?",
            isPresented: $showResetConfirmation,
            actions: {
                Button("Cancel", role: .cancel) { }
                Button("Reset", role: .destructive) {
                    store.resetToDefaults()
                }
            },
            message: {
                Text("This will reset all settings to their defaults. History is not affected.")
            }
        )
        .alert(
            "Error",
            isPresented: $showResetError,
            actions: {
                Button("OK", role: .cancel) { resetError = nil }
            },
            message: {
                if let error = resetError {
                    Text(error)
                }
            }
        )
    }
}
