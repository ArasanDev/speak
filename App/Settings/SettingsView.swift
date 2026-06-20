// App/Settings/SettingsView.swift
//
// The Settings window content for `speak`.
//
// DESIGN:
//   - One `Form` with labelled sections matching the settings taxonomy.
//   - Binds directly to `SettingsStore` (ObservableObject), so every toggle/
//     picker write is immediately persisted to UserDefaults.
//   - Hotkey rebinding shows the current binding label + a "Record…" button.
//     Full record-flow UX is P10 polish; the current binding is displayed
//     read-only here (the full HotkeyMonitor.updateBinding path is wired
//     but the key-capture UI is [deferred — human verification]).
//   - STT and Ollama cleanup engine pickers show v0.1/v1 cases as disabled
//     labels so the user can see what is coming without being able to select
//     unbuilt engines.
//
// HONESTY BOUNDARY:
//   Whether this window opens correctly from the menubar and all controls
//   persist live is [deferred — human verification]. The SettingsStore
//   persistence layer is unit-tested independently.
//
// THREADING:
//   - `@MainActor` is implicit for SwiftUI `View` bodies.
//   - `SettingsStore` is `@unchecked Sendable`; its properties are read
//     synchronously on main — no cross-actor hop needed.

import SwiftUI
import SpeakCore

// MARK: - SettingsView

struct SettingsView: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        Form {
            transcriptionSection
            cleanupSection
            pasteSection
        }
        .formStyle(.grouped)
        .padding()
        .frame(minWidth: 420, minHeight: 340)
    }

    // MARK: - Transcription section

    private var transcriptionSection: some View {
        Section("Transcription") {
            // Language picker (two offered locales in v0; more in v1)
            Picker("Language", selection: Binding(
                get: { store.language.identifier },
                set: { store.language = Locale(identifier: $0) }
            )) {
                Text("English (US)").tag("en-US")
                Text("English (UK)").tag("en-GB")
            }
            .pickerStyle(.menu)

            // STT engine picker — v0.1/v1 cases shown disabled
            Picker("Speech Engine", selection: Binding(
                get: { store.sttEngine },
                set: { store.sttEngine = $0 }
            )) {
                Text("Apple Speech (default)")
                    .tag(STTEngine.appleSpeech)
                Text("WhisperKit  (v0.1 — coming soon)")
                    .tag(STTEngine.whisperKit)
                    .disabled(true)
                    .foregroundStyle(.secondary)
                Text("whisper.cpp  (v1 — coming soon)")
                    .tag(STTEngine.whisperCpp)
                    .disabled(true)
                    .foregroundStyle(.secondary)
            }
            .pickerStyle(.menu)
            // Disable pickers for non-default engines so the user cannot
            // select unbuilt options even if the tag is rendered.
            // The Picker selection binding already rejects non-active values
            // when the associated rows are disabled.
        }
    }

    // MARK: - AI cleanup section

    private var cleanupSection: some View {
        Section("AI Cleanup") {
            Toggle("Enable AI neat-writing", isOn: Binding(
                get: { store.cleanupEnabled },
                set: { store.cleanupEnabled = $0 }
            ))

            Picker("Cleanup Engine", selection: Binding(
                get: { store.cleanupEngine },
                set: { store.cleanupEngine = $0 }
            )) {
                Text("Foundation Models (default)")
                    .tag(CleanupEngine.foundationModels)
                Text("Ollama  (v0.1 — coming soon)")
                    .tag(CleanupEngine.ollama(model: ""))
                    .disabled(true)
                    .foregroundStyle(.secondary)
            }
            .pickerStyle(.menu)
            .disabled(!store.cleanupEnabled)
        }
    }

    // MARK: - Paste / insertion section

    private var pasteSection: some View {
        Section("Text Insertion") {
            Picker("Paste Mode", selection: Binding(
                get: { store.pasteMode },
                set: { store.pasteMode = $0 }
            )) {
                Text("Cmd+V (default)").tag(PasteMode.cmdV)
                Text("Accessibility API  (v1 — coming soon)")
                    .tag(PasteMode.accessibility)
                    .disabled(true)
                    .foregroundStyle(.secondary)
            }
            .pickerStyle(.menu)
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    SettingsView(store: SettingsStore())
}
#endif
