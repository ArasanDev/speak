// App/Settings/CleanupEngineSheet.swift
//
// API key-entry sheet for the cloud OpenAI-compatible cleanup presets
// (Sarvam / OpenAI / Groq / OpenRouter). Ollama needs no key and never
// presents this sheet — it gets `OllamaSetupSheet` instead.
//
// Extracted into its own file (not folded into `AICleanupSettingsTab`) for the
// same reason as `OllamaSetupSheet.swift`: keeps `SettingsView.swift` under the
// swiftlint 1000-line file limit, and keeps the Keychain-facing logic testable
// in isolation via `CleanupEngineKeyViewModel`. [decision V01-2 follow-up]
//
// SECURITY:
//   Once a key is saved, it is never read back into the UI in plaintext — the
//   `SecureField` only ever shows a "Key set" placeholder state, never the
//   stored secret. Only `LLMKeychainStore` (Keychain-backed) ever holds the
//   value; this view model keeps it in memory only for the duration of a
//   save/clear operation.

import SpeakCore
import SpeakLLM
import SwiftUI

// MARK: - CleanupEngineKeyViewModel

/// Owns the Keychain read/save/delete round trip for one `ProviderPreset`'s
/// API key. Kept separate from the view so it can be unit-tested without
/// instantiating SwiftUI.
@Observable
@MainActor
final class CleanupEngineKeyViewModel {
    /// The preset this key belongs to (`Sarvam` / `OpenAI` / `Groq` / `OpenRouter`).
    let preset: ProviderPreset

    /// Live text field contents. Cleared after a successful save so the
    /// plaintext key never lingers in view state. [decision: never echo back]
    var keyText: String = ""

    /// Whether a key is currently stored in Keychain for this preset.
    private(set) var hasStoredKey: Bool = false

    /// Set after a failed save/clear so the sheet can surface it; cleared on
    /// the next attempt.
    private(set) var errorMessage: String?

    private let keychainStore: LLMKeychainStore

    init(preset: ProviderPreset, keychainStore: LLMKeychainStore = LLMKeychainStore()) {
        self.preset = preset
        self.keychainStore = keychainStore
    }

    /// Reads current Keychain state for `preset`. Call on sheet appear.
    func refresh() {
        errorMessage = nil
        do {
            hasStoredKey = try keychainStore.readKey(account: preset.id) != nil
        } catch {
            // A read failure (e.g. Keychain locked) is surfaced but does not
            // block key entry — the user can still attempt a save.
            hasStoredKey = false
            errorMessage = "Could not read Keychain status: \(error.localizedDescription)"
        }
    }

    /// Whether the Save button should be enabled.
    var canSave: Bool {
        !keyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Saves `keyText` to Keychain, replacing any existing value, then clears
    /// the field from memory.
    func save() {
        let trimmed = keyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        errorMessage = nil
        do {
            try keychainStore.save(key: trimmed, forAccount: preset.id)
            keyText = ""
            hasStoredKey = true
        } catch {
            errorMessage = "Could not save key: \(error.localizedDescription)"
        }
    }

    /// Removes any stored key for `preset`.
    func clear() {
        errorMessage = nil
        do {
            try keychainStore.deleteKey(account: preset.id)
            keyText = ""
            hasStoredKey = false
        } catch {
            errorMessage = "Could not remove key: \(error.localizedDescription)"
        }
    }
}

// MARK: - CleanupEngineSheet

/// Modal sheet for entering/clearing the API key for one cloud preset.
/// Presented from `AICleanupSettingsTab` when the user picks a preset whose
/// `ProviderPreset.requiresAPIKey` is true.
struct CleanupEngineSheet: View {
    @Binding var isPresented: Bool
    @State private var viewModel: CleanupEngineKeyViewModel

    init(isPresented: Binding<Bool>, preset: ProviderPreset, keychainStore: LLMKeychainStore = LLMKeychainStore()) {
        self._isPresented = isPresented
        self._viewModel = State(
            wrappedValue: CleanupEngineKeyViewModel(preset: preset, keychainStore: keychainStore)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.lg) {
            HStack(alignment: .top, spacing: SpeakSpacing.md) {
                Image(systemName: "key")
                    .font(.system(size: 32))
                    .foregroundStyle(Color.speakAccent)
                VStack(alignment: .leading, spacing: SpeakSpacing.xs) {
                    Text("\(viewModel.preset.displayName) API Key")
                        .font(.speakMonoTitle)
                    Text("Stored in Keychain \u{2014} never sent anywhere except \(viewModel.preset.displayName).")
                        .font(.speakMonoCaption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, SpeakSpacing.sm)

            Divider()

            statusRow

            SecureField(viewModel.hasStoredKey ? "Key set \u{2014} enter a new key to replace it" : "Enter API key",
                        text: $viewModel.keyText)
                .textFieldStyle(.roundedBorder)
                .font(.speakMonoBody)

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Spacer()

            HStack {
                if viewModel.hasStoredKey {
                    Button("Remove Key", role: .destructive) {
                        viewModel.clear()
                    }
                }
                Spacer()
                Button("Cancel") { isPresented = false }
                Button("Save") {
                    viewModel.save()
                    isPresented = false
                }
                .keyboardShortcut(.return, modifiers: [])
                .disabled(!viewModel.canSave)
            }
        }
        .padding(SpeakSpacing.lg)
        // [decision: 420×280 fits the header + field + actions without slack]
        .frame(minWidth: 420, minHeight: 280)
        .onAppear { viewModel.refresh() }
    }

    @ViewBuilder
    private var statusRow: some View {
        HStack(spacing: SpeakSpacing.xs) {
            Image(systemName: viewModel.hasStoredKey ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(viewModel.hasStoredKey ? Color.speakAccent : .secondary)
            Text(viewModel.hasStoredKey ? "A key is currently set for \(viewModel.preset.displayName)." :
                 "No key set \u{2014} cleanup falls back to raw transcript until one is entered.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Cleanup Engine Key Entry") {
    CleanupEngineSheet(
        isPresented: .constant(true),
        preset: .openAI,
        keychainStore: LLMKeychainStore(service: "com.speak.llm.apikeys.preview")
    )
}
#endif
