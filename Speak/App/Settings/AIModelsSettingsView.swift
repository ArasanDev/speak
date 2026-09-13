// App/Settings/AIModelsSettingsView.swift
//
// "AI Models & Neat-Writing" — the third Settings category. Cleanup intensity
// (unified `effectiveCleanupLevel` picker), a live diff preview of what each
// level changes, voice/style, the cleanup engine picker (Foundation Models /
// Ollama / OpenAI-compatible presets / MLX stub), and per-app context.
//
// Ported from the legacy `AICleanupSettingsTab` into SettingsChrome cards —
// same bindings, same guided-setup sheets, same canned diff preview.
// [decision W4.1: canned sample in Settings preview; live diffs are in History]

import SpeakCore
import SwiftUI

// MARK: - AIModelsSettingsView

@MainActor
struct AIModelsSettingsView: View {
    let context: DashboardContext

    private var store: SettingsStore { context.settingsStore }

    /// Cleanup is active when effectiveCleanupLevel != .none.
    private var cleanupActive: Bool { store.effectiveCleanupLevel != .none }

    @State private var showOllamaSetup = false
    @State private var showKeyEntry = false
    @State private var sandbox = VoiceSandboxModel()

    var body: some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.lg) {
            intensityCard
            sandboxCard
            voiceCard
            engineCard
            contextCard
        }
        .sheet(isPresented: $showOllamaSetup) {
            OllamaSetupSheet(isPresented: $showOllamaSetup)
        }
        .sheet(isPresented: $showKeyEntry) {
            if case .openAICompatible(let preset, _) = store.cleanupEngine {
                CleanupEngineSheet(isPresented: $showKeyEntry, preset: preset)
            }
        }
        .onDisappear {
            Task { await sandbox.cancel() }
        }
    }

    // MARK: - Intensity

    private var intensityCard: some View {
        SettingsSectionCard(title: "Intensity") {
            VStack(alignment: .leading, spacing: SpeakSpacing.sm) {
                Picker("", selection: Binding(
                    get: { store.effectiveCleanupLevel },
                    set: { store.effectiveCleanupLevel = $0 }
                )) {
                    ForEach(CleanupLevel.allCases, id: \.self) { level in
                        Text(level.displayName).tag(level)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Text(store.effectiveCleanupLevel.levelDescription + " None pastes the raw transcript untouched.")
                    .font(.speakBody(.caption))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, SpeakSpacing.md)
            .padding(.vertical, SpeakSpacing.sm + 4)
        }
    }

    // MARK: - Test My Voice sandbox

    /// Live sandbox: a real `CaptureSession` (settings-derived locale, vocab +
    /// corrections, snippets, cleanup mode) with `inserter: nil` — nothing is
    /// pasted; the diff shows exactly what the current engine/level does.
    private var sandboxCard: some View {
        SettingsSectionCard(title: "Test My Voice") {
            VStack(alignment: .leading, spacing: SpeakSpacing.sm) {
                HStack(spacing: SpeakSpacing.md) {
                    HoldToTalkPill(
                        model: sandbox,
                        isEnabled: context.permissionManager?.status(.microphone) == .granted
                    ) {
                        await sandbox.begin(settings: store, snippetStore: context.snippetStore)
                    } onEnd: {
                        await sandbox.end()
                    }

                    VUMeterView(level: sandbox.level)
                        .opacity(sandbox.phase == .listening ? 1 : 0.35)

                    Spacer()

                    if sandbox.phase == .listening {
                        Text(String(format: "%.1fs", sandbox.elapsed))
                            .font(.speakMonoFace(.caption))
                            .foregroundStyle(.secondary)
                    }
                }

                sandboxContent
            }
            .padding(.horizontal, SpeakSpacing.md)
            .padding(.vertical, SpeakSpacing.sm + 4)
        }
    }

    @ViewBuilder
    private var sandboxContent: some View {
        switch sandbox.phase {
        case .idle:
            if context.permissionManager?.status(.microphone) != .granted {
                Label("Microphone permission is required to test your voice.", systemImage: "mic.slash")
                    .font(.speakBody(.caption))
                    .foregroundStyle(.secondary)
            } else {
                Text("Hold the pill (or tap once) and say a sentence — e.g. “um open the rippo and run cubectl get pods”. The on-device model cleans it; nothing is pasted.")
                    .font(.speakBody(.caption))
                    .foregroundStyle(.secondary)
            }

        case .listening, .processing:
            VStack(alignment: .leading, spacing: SpeakSpacing.xs) {
                ScrollView {
                    Text(sandbox.transcriptText.isEmpty ? "Listening…" : sandbox.transcriptText)
                        .font(.speakMonoFace(.base))
                        .foregroundStyle(sandbox.transcriptText.isEmpty ? .tertiary : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 44, maxHeight: 96)

                if sandbox.phase == .processing {
                    HStack(spacing: SpeakSpacing.xs) {
                        ProgressView().controlSize(.small)
                        Text("Cleaning on-device…")
                            .font(.speakBody(.caption))
                            .foregroundStyle(.secondary)
                    }
                }
            }

        case .done:
            if let result = sandbox.result {
                VStack(alignment: .leading, spacing: SpeakSpacing.xs) {
                    CleanupDiffView(rawText: result.rawText, cleanedText: result.cleanedText)
                        .frame(minHeight: 120)

                    HStack(spacing: SpeakSpacing.xs) {
                        if let ms = sandbox.processingMilliseconds {
                            Text(result.cleanedText == nil
                                 ? "delivered raw — cleanup off or engine unavailable"
                                 : "cleaned in \(ms) ms by \(result.engineId)")
                                .font(.speakMonoFace(.caption))
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        Button("Test again") { sandbox.reset() }
                            .font(.speakBody(.caption))
                            .buttonStyle(.borderless)
                    }
                }
            }

        case .failed(let message):
            HStack(spacing: SpeakSpacing.xs) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                Text(message)
                    .font(.speakBody(.caption))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Try again") { sandbox.reset() }
                    .font(.speakBody(.caption))
                    .buttonStyle(.borderless)
            }
        }
    }

    // MARK: - Voice

    private var voiceCard: some View {
        SettingsSectionCard(title: "Voice") {
            SettingsRow(
                "Neat-writing style",
                description: cleanupActive
                    ? "The register the cleaner rewrites into."
                    : "Set a cleanup level above to enable voice selection."
            ) {
                Picker("", selection: Binding(
                    get: { store.cleanupStyle },
                    set: { store.cleanupStyle = $0 }
                )) {
                    ForEach(CleanupStyle.allCases, id: \.self) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .pickerStyle(.menu)
                .fixedSize()
                .disabled(!cleanupActive)
            }
        }
    }

    // MARK: - Engine

    private var engineCard: some View {
        SettingsSectionCard(title: "Engine") {
            VStack(alignment: .leading, spacing: SpeakSpacing.sm) {
                SettingsRow(
                    "Cleanup engine",
                    description: engineFootnoteText
                ) {
                    Picker("", selection: engineBinding) {
                        Text("Foundation Models").tag(CleanupEngine.foundationModels)
                        Text("Ollama (local server)").tag(CleanupEngine.ollama(model: "qwen2.5:3b"))
                        ForEach([ProviderPreset.sarvamLLM, .openAI, .groq, .openRouter], id: \.self) { preset in
                            Text(preset.displayName)
                                .tag(CleanupEngine.openAICompatible(preset: preset, model: preset.defaultModel))
                        }
                        Text("MLX (v0.1+)")
                            .tag(CleanupEngine.mlx(model: "Qwen2.5-3B-Instruct-4bit"))
                    }
                    .pickerStyle(.menu)
                    .fixedSize()
                    .disabled(!cleanupActive)
                }

                if let note = engineStatusNote {
                    HStack(spacing: SpeakSpacing.xs) {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.secondary)
                        Text(note)
                            .font(.speakBody(.caption))
                            .foregroundStyle(.secondary)
                        Spacer()
                        engineStatusAction
                    }
                    .padding(.horizontal, SpeakSpacing.md)
                    .padding(.bottom, SpeakSpacing.sm)
                }
            }
        }
    }

    /// Picker binding that surfaces the Ollama guided-setup sheet on selection.
    private var engineBinding: Binding<CleanupEngine> {
        Binding(
            get: { store.cleanupEngine },
            set: { newEngine in
                store.cleanupEngine = newEngine
                if case .ollama = newEngine {
                    showOllamaSetup = true
                }
            }
        )
    }

    private var engineStatusNote: String? {
        switch store.cleanupEngine {
        case .foundationModels:
            return "Runs on-device — no network, no account. Requires Apple Intelligence."

        case .ollama:
            return "Requires a local Ollama server at 127.0.0.1:11434."

        case .openAICompatible(let preset, _):
            return "\(preset.displayName) requires an API key, stored in Keychain. " +
                   "Cloud cleanup is strictly opt-in — text only, never audio."

        case .mlx:
            return "MLX support arrives in v0.1 — falls back to raw transcript."
        }
    }

    @ViewBuilder
    private var engineStatusAction: some View {
        switch store.cleanupEngine {
        case .ollama:
            Button("Setup guide…") { showOllamaSetup = true }
                .font(.speakBody(.caption))
                .buttonStyle(.borderless)

        case .openAICompatible:
            Button("Enter API key…") { showKeyEntry = true }
                .font(.speakBody(.caption))
                .buttonStyle(.borderless)

        case .foundationModels, .mlx:
            EmptyView()
        }
    }

    private var engineFootnoteText: String {
        switch store.cleanupEngine {
        case .foundationModels:
            return "Falls back to raw transcript when unavailable."

        case .ollama:
            return "Never a remote host. Falls back to raw transcript when Ollama is not running."

        case .openAICompatible:
            return "Transcript text is sent only after you configure an API key."

        case .mlx:
            return "Requires third-party Swift packages; available from v0.1."
        }
    }

    // MARK: - Per-app context

    private var contextCard: some View {
        SettingsSectionCard(title: "Context") {
            SettingsRow(
                "Per-app profiles",
                description: "The frontmost app picks the profile (Xcode/Terminal → Agent, "
                    + "Slack/Messages → Chat, Mail/browsers → Write). Off = every dictation "
                    + "uses your global default."
            ) {
                Toggle("", isOn: Binding(
                    get: { store.perAppContextEnabled },
                    set: { store.perAppContextEnabled = $0 }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
            }
        }
    }
}
