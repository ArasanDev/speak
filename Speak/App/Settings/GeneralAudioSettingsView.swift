// App/Settings/GeneralAudioSettingsView.swift
//
// "General & Audio" — the first category of the dedicated Settings experience.
// Startup, speech language, live microphone status, text insertion, and
// voice-out readback. Rows use the SettingsChrome card/row primitives
// (title + description left, control right).

import SpeakCore
import SwiftUI

// MARK: - GeneralAudioSettingsView

@MainActor
struct GeneralAudioSettingsView: View {
    let context: DashboardContext

    @ObservedObject private var launchAtLogin = LaunchAtLoginManager.shared

    private var store: SettingsStore { context.settingsStore }

    var body: some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.lg) {
            startupCard
            LanguageCard(store: store)
            MicrophoneCard()
            insertionCard
            voiceOutCard
        }
    }

    // MARK: - Startup

    private var startupCard: some View {
        SettingsSectionCard(title: "Startup", systemImage: "power") {
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

    // MARK: - Text insertion

    private var insertionCard: some View {
        SettingsSectionCard(title: "Text Insertion", systemImage: "text.insert") {
            SettingsRow(
                "Paste Mode",
                description: "Cmd+V works in almost every app."
            ) {
                Picker("", selection: Binding(
                    get: { store.pasteMode },
                    set: { guard $0 != .accessibility else { return }; store.pasteMode = $0 }
                )) {
                    Text("Cmd+V").tag(PasteMode.cmdV)
                    Text("Accessibility (v1)").tag(PasteMode.accessibility)
                }
                .pickerStyle(.menu)
                .fixedSize()
            }

            SettingsRowSeparator()

            SettingsRow(
                "Streaming",
                description: "Type cleaned text live as you speak, instead of pasting at the end."
            ) {
                Picker("", selection: Binding(
                    get: { store.streamingMode },
                    set: { store.streamingMode = $0 }
                )) {
                    Text("Live keystrokes").tag(StreamingMode.keystrokeInjection)
                    Text("Off").tag(StreamingMode.off)
                }
                .pickerStyle(.menu)
                .fixedSize()
            }

            SettingsRowSeparator()

            SettingsRow(
                "Reveal words while cleaning",
                description: "Keep the raw transcript visible in the HUD while AI cleanup runs."
            ) {
                Toggle("", isOn: Binding(
                    get: { store.revealTextWhileProcessing },
                    set: { store.revealTextWhileProcessing = $0 }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
            }
        }
    }

    // MARK: - Voice out

    private var voiceOutCard: some View {
        SettingsSectionCard(title: "Voice Out", systemImage: "speaker.wave.2") {
            SettingsRow(
                "Read back finished transcripts",
                description: "Adds a speaker button after each dictation to hear it read aloud on-device."
            ) {
                Toggle("", isOn: Binding(
                    get: { store.readbackEnabled },
                    set: { store.readbackEnabled = $0 }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
            }
        }
    }
}

// MARK: - LanguageCard

/// Speech language picker. Locales load async from `SpeechTranscriberLocaleSource`;
/// rows marked "(download)" are supported but not yet installed on-device.
private struct LanguageCard: View {
    let store: SettingsStore

    @State private var supportedLocales: [Locale] = []
    @State private var installedLocaleIDs: Set<String> = []
    @State private var localesLoaded = false
    @State private var showLanguageResetAlert = false
    @State private var pendingResetLocale: Locale?

    var body: some View {
        SettingsSectionCard(title: "Language", systemImage: "globe") {
            SettingsRow(
                "Dictation Language",
                description: "Applied to the next dictation — no restart needed."
            ) {
                if !localesLoaded {
                    ProgressView().controlSize(.small)
                } else {
                    Picker("", selection: Binding(
                        get: { store.language.identifier },
                        set: { store.language = Locale(identifier: $0) }
                    )) {
                        ForEach(supportedLocales, id: \.identifier) { locale in
                            Text(localeLabel(for: locale))
                                .tag(locale.identifier)
                        }
                    }
                    .pickerStyle(.menu)
                    .fixedSize()
                }
            }
        }
        .task {
            async let supported = SpeechTranscriberLocaleSource.supportedLocales()
            async let installed = SpeechTranscriberLocaleSource.installedLocales()
            let (s, i) = await (supported, installed)
            supportedLocales = s
            installedLocaleIDs = Set(i.map(\.identifier))
            localesLoaded = true

            if !s.isEmpty && !s.contains(where: { $0.identifier == store.language.identifier }) {
                let fallback = s[0]
                store.language = fallback
                pendingResetLocale = fallback
                showLanguageResetAlert = true
            }
        }
        .alert(
            "Language Reset",
            isPresented: $showLanguageResetAlert,
            actions: {
                Button("OK", role: .cancel) { pendingResetLocale = nil }
            },
            message: {
                let name = pendingResetLocale.flatMap {
                    $0.localizedString(forIdentifier: $0.identifier)
                } ?? pendingResetLocale?.identifier ?? "the first supported language"
                Text("Your previously selected language is no longer available. " +
                     "Language has been reset to \(name).")
            }
        )
    }

    private func localeLabel(for locale: Locale) -> String {
        let name = SpeechTranscriberLocaleSource.displayName(for: locale)
        return installedLocaleIDs.contains(locale.identifier) ? name : "\(name) (download)"
    }
}

// MARK: - MicrophoneCard

/// Live readout of the current default input device, driven by
/// `CoreAudioDeviceMonitor` — same source the old Transcription tab used.
private struct MicrophoneCard: View {
    @State private var currentDevice: CoreAudioDeviceMonitor.DeviceInfo?
    @State private var monitorToken: UUID?

    var body: some View {
        SettingsSectionCard(title: "Microphone", systemImage: "mic") {
            if let dev = currentDevice {
                SettingsRow(
                    dev.name,
                    description: "\(Int(dev.sampleRate)) Hz · \(dev.channelCount) channel\(dev.channelCount == 1 ? "" : "s") — follows the system default input."
                ) {
                    SettingsStatusPill(text: "Active")
                }
            } else {
                SettingsRow(
                    "System Default Microphone",
                    description: "Automatically follows connected headphones, AirPods, or external mics."
                )
            }
        }
        .onAppear {
            currentDevice = CoreAudioDeviceMonitor.shared.currentDefaultInputDevice()
            if monitorToken == nil {
                monitorToken = CoreAudioDeviceMonitor.shared.registerCallback { dev in
                    Task { @MainActor in
                        currentDevice = dev
                    }
                }
            }
        }
        .onDisappear {
            if let token = monitorToken {
                CoreAudioDeviceMonitor.shared.unregisterCallback(token)
                monitorToken = nil
            }
        }
    }
}
