// App/Dashboard/Panes/SettingsPaneView.swift
//
// The Settings pane — all app preferences in one Dashboard surface.
// Routes: menubar "Settings…" → Dashboard .settings pane (via WindowPresenter.showSettings).
//
// Sections: Hotkey & Activation · Language & Transcription · Text Insertion · AI Cleanup · About.
// Reads/writes SettingsStore. Hotkey rebinding calls context.rebindHotkey (wired to
// DictationController.rebindHotkey by WindowPresenter).

import SpeakCore
import SwiftUI

// MARK: - SettingsPaneView

@MainActor
struct SettingsPaneView: View {
    let context: DashboardContext

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaneHeader(
                title: "Settings",
                subtitle: "Hotkey, language, AI cleanup, and general preferences."
            )
            ScrollView {
                VStack(alignment: .leading, spacing: SpeakSpacing.lg) {
                    HotkeySection(context: context)
                    Divider()
                    LanguageSection(store: context.settingsStore)
                    Divider()
                    TextInsertionSection(store: context.settingsStore)
                    Divider()
                    AICleanupSection(store: context.settingsStore)
                    Divider()
                    AppearanceSection(store: context.settingsStore)
                    Divider()
                    AboutSection()
                }
                .padding(SpeakSpacing.lg)
            }
        }
    }
}

// MARK: - Hotkey & Activation

private struct HotkeySection: View {
    let context: DashboardContext
    @State private var showingRecorder = false

    var body: some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.sm) {
            Text("Hotkey & Activation")
                .font(.speakMonoBody)
                .foregroundStyle(.primary)

            Form {
                Section {
                    Picker("Activation Mode", selection: Binding(
                        get: { context.settingsStore.triggerMode },
                        set: { context.settingsStore.triggerMode = $0 }
                    )) {
                        Text("Double-tap (toggle)").tag(HotkeyBinding.Trigger.doubleTap)
                        Text("Hold (push-to-talk)").tag(HotkeyBinding.Trigger.hold)
                    }
                    .pickerStyle(.inline)

                    HStack {
                        Text("Current hotkey")
                        Spacer()
                        HStack(spacing: SpeakSpacing.xs) {
                            ForEach(context.hotkeyCombo, id: \.self) { key in
                                KeyCapView(label: key)
                            }
                        }
                        Button("Change…") { showingRecorder = true }
                            .disabled(context.rebindHotkey == nil)
                    }
                }
            }
            .formStyle(.grouped)
            .frame(minHeight: 120)
        }
        .sheet(isPresented: $showingRecorder) {
            HotkeyRecorderView(
                initialBinding: context.activeBinding,
                onSave: { newBinding in
                    context.rebindHotkey?(newBinding)
                    showingRecorder = false
                },
                onCancel: { showingRecorder = false }
            )
        }
    }
}

// MARK: - Language & Transcription

private struct LanguageSection: View {
    let store: SettingsStore
    @State private var supportedLocales: [Locale] = []
    @State private var installedLocaleIDs: Set<String> = []
    @State private var localesLoaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.sm) {
            Text("Language & Transcription")
                .font(.speakMonoBody)
                .foregroundStyle(.primary)

            Form {
                Section {
                    if !localesLoaded {
                        HStack {
                            Text("Language")
                            Spacer()
                            ProgressView().controlSize(.small)
                        }
                    } else {
                        Picker("Language", selection: Binding(
                            get: { store.language.identifier },
                            set: { store.language = Locale(identifier: $0) }
                        )) {
                            ForEach(supportedLocales, id: \.identifier) { locale in
                                Text(SpeechTranscriberLocaleSource.displayName(for: locale))
                                    .tag(locale.identifier)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }
            }
            .formStyle(.grouped)
            .frame(minHeight: 60)
            .task {
                async let supported = SpeechTranscriberLocaleSource.supportedLocales()
                async let installed = SpeechTranscriberLocaleSource.installedLocales()
                let (s, i) = await (supported, installed)
                supportedLocales = s
                installedLocaleIDs = Set(i.map(\.identifier))
                localesLoaded = true
            }
        }
    }
}

// MARK: - Text Insertion

private struct TextInsertionSection: View {
    let store: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.sm) {
            Text("Text Insertion")
                .font(.speakMonoBody)
                .foregroundStyle(.primary)

            Form {
                Section {
                    Picker("Paste Mode", selection: Binding(
                        get: { store.pasteMode },
                        set: { guard $0 != .accessibility else { return }; store.pasteMode = $0 }
                    )) {
                        Text("Cmd+V (default)").tag(PasteMode.cmdV)
                        Text("Accessibility API  (v1 — coming soon)")
                            .tag(PasteMode.accessibility)
                            .disabled(true)
                    }
                    .pickerStyle(.menu)
                } footer: {
                    Text("Cmd+V works in almost every app. [unverified: Terminal paste-provenance — test at P13]")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .frame(minHeight: 80)
        }
    }
}

// MARK: - AI Cleanup

private struct AICleanupSection: View {
    let store: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.sm) {
            Text("AI Cleanup")
                .font(.speakMonoBody)
                .foregroundStyle(.primary)

            Form {
                Section {
                    Toggle("AI cleanup enabled", isOn: Binding(
                        get: { store.cleanupEnabled },
                        set: { store.cleanupEnabled = $0 }
                    ))
                    .font(.speakMonoBody)
                } footer: {
                    Text("Off = raw transcript pastes untouched. Full profile configuration: AI Studio.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .frame(minHeight: 70)
        }
    }
}

// MARK: - Appearance

private struct AppearanceSection: View {
    let store: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.sm) {
            Text("Appearance")
                .font(.speakMonoBody)
                .foregroundStyle(.primary)

            Form {
                Section {
                    Picker("Theme", selection: Binding(
                        get: { store.appTheme },
                        set: { store.appTheme = $0 }
                    )) {
                        Text("System (default)").tag(AppTheme.system)
                        Text("Light").tag(AppTheme.light)
                        Text("Dark").tag(AppTheme.dark)
                    }
                    .pickerStyle(.menu)
                }
            }
            .formStyle(.grouped)
            .frame(minHeight: 60)
        }
    }
}

// MARK: - About

private struct AboutSection: View {
    private let version: String = {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.1"
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.sm) {
            Text("About")
                .font(.speakMonoBody)
                .foregroundStyle(.primary)

            HStack(spacing: SpeakSpacing.md) {
                VStack(alignment: .leading, spacing: SpeakSpacing.xs) {
                    Text("speak v\(version)")
                        .font(.speakMonoBody)
                    Text("Local-first, free, open-source AI voice dictation.")
                        .font(.speakMonoCaption)
                        .foregroundStyle(.secondary)
                    Text("MIT License · macOS 26+ · Apple Silicon")
                        .font(.speakMonoCaption)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
            }
            .padding(SpeakSpacing.md)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.speakSurface))
        }
    }
}
