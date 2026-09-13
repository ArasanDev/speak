// App/Settings/IntelligenceSettingsView.swift
//
// "Intelligence" — the second pipeline layer of the dedicated Settings
// experience. What happens to the words between ears and voice: neat-writing
// intensity + style (the unified `effectiveCleanupLevel` picker), the cleanup
// engine picker (Foundation Models / Ollama / OpenAI-compatible presets / MLX
// stub) with each engine's own config nested underneath it, a live
// availability check through the same `defaultCleaner(for:)` factory the
// dictation path uses, and the per-app profile routing table.
//
// The end-to-end "Test the Loop" sandbox lives on the Pipeline page — this
// pane is the layer's configuration surface. The Inference dashboard pane is
// its runtime counterpart (server + model registry); this is the config side.
//
// Ported from the legacy `AICleanupSettingsTab` into SettingsChrome cards —
// same bindings, same guided-setup sheets.
// [decision W4.1: canned sample in Settings preview; live diffs are in History]

import AppKit
import SpeakCore
import SpeakLLM
import SwiftUI

// MARK: - IntelligenceSettingsView

@MainActor
struct IntelligenceSettingsView: View {
    let context: DashboardContext

    private var store: SettingsStore { context.settingsStore }

    /// Cleanup is active when effectiveCleanupLevel != .none.
    private var cleanupActive: Bool { store.effectiveCleanupLevel != .none }

    @State private var showOllamaSetup = false
    @State private var showKeyEntry = false
    @State private var availability: EngineAvailability = .idle
    /// The editable model tag for engines that take one (Ollama, cloud
    /// presets). Committed on Return or focus-out — never per keystroke, so a
    /// half-typed model can never reach a live dictation. [decision]
    @State private var modelDraft = ""
    @FocusState private var modelFieldFocused: Bool

    /// Keychain read for the "does this cloud preset already have a key?"
    /// check that decides whether picking a preset opens the key sheet.
    /// `SpeakLLM` is the allowlisted module — the raw `SecItem*` symbols the
    /// moat greps for never appear in this file. [decision V01-2]
    private let keychainStore = LLMKeychainStore()

    /// The model the MLX menu item tags — kept as one constant so the tag and
    /// the normalizer can never drift apart.
    private static let mlxMenuModel = "Qwen2.5-3B-Instruct-4bit"

    var body: some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.lg) {
            cleanupCard
            engineCard
            profilesCard
        }
        .task(id: availabilityKey) { await refreshAvailability() }
        .onAppear { modelDraft = storedModel }
        .onChange(of: store.cleanupEngine) { _, _ in modelDraft = storedModel }
        .onChange(of: modelFieldFocused) { _, focused in
            if !focused { commitModelDraft() }
        }
        .sheet(isPresented: $showOllamaSetup) {
            OllamaSetupSheet(isPresented: $showOllamaSetup)
        }
        .sheet(isPresented: $showKeyEntry) {
            if case .openAICompatible(let preset, _) = store.cleanupEngine {
                CleanupEngineSheet(isPresented: $showKeyEntry, preset: preset)
            }
        }
    }

    // MARK: - AI Cleanup (level + style)

    private var cleanupCard: some View {
        SettingsSectionCard(title: "AI Cleanup") {
            SettingsRow(
                "Level",
                description: store.effectiveCleanupLevel.levelDescription
            ) {
                Picker("", selection: Binding(
                    get: { store.effectiveCleanupLevel },
                    set: { store.effectiveCleanupLevel = $0 }
                )) {
                    ForEach(CleanupLevel.allCases, id: \.self) { level in
                        Text(level.displayName).tag(level)
                    }
                }
                .pickerStyle(.segmented)
                .tint(.speakUIAccent)
            }

            SettingsRowSeparator()

            SettingsRow(
                "Style",
                description: cleanupActive
                    ? "The register AI cleanup rewrites into — Default keeps your voice."
                    : "Set a level above None to choose a style."
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

    /// The picker row, then the selected engine's own configuration (model,
    /// endpoint, API key) and live status nested inside a recessed well — so
    /// "which engine" and "how that engine is set up" read as one unit.
    private var engineCard: some View {
        SettingsSectionCard(title: "Engine") {
            VStack(spacing: 0) {
                SettingsRow(
                    "Cleanup engine",
                    description: engineRowDescription
                ) {
                    Picker("", selection: engineBinding) {
                        Text("Foundation Models").tag(CleanupEngine.foundationModels)
                        Text("Ollama (local server)")
                            .tag(CleanupEngine.ollama(model: ProviderPreset.ollama.defaultModel))
                        ForEach([ProviderPreset.sarvamLLM, .openAI, .groq, .openRouter], id: \.self) { preset in
                            Text(preset.displayName)
                                .tag(CleanupEngine.openAICompatible(preset: preset, model: preset.defaultModel))
                        }
                        // A persisted `.custom` preset can't be picked from this
                        // menu, but if one is stored it still needs a tag to
                        // select — otherwise the menu renders blank.
                        if case .openAICompatible(let preset, _) = store.cleanupEngine,
                           case .custom = preset {
                            Text(preset.displayName)
                                .tag(CleanupEngine.openAICompatible(preset: preset, model: preset.defaultModel))
                        }
                        Text("MLX (v0.1+)")
                            .tag(CleanupEngine.mlx(model: Self.mlxMenuModel))
                    }
                    .pickerStyle(.menu)
                    .fixedSize()
                    .disabled(!cleanupActive)
                }

                if cleanupActive {
                    SettingsRowSeparator()

                    engineConfigBlock
                        .padding(.horizontal, SpeakSpacing.md)
                        .padding(.vertical, SpeakSpacing.sm + 4)
                }
            }
        }
    }

    /// The recessed per-engine config well — model + endpoint where the engine
    /// has them, then a live status line everywhere. `displayedAvailability`
    /// (not raw `availability`) drives the pill so "key set but no model
    /// chosen" still flags correctly.
    @ViewBuilder
    private var engineConfigBlock: some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.sm) {
            switch store.cleanupEngine {
            case .foundationModels:
                statusHeader
                statusDetail

            case .ollama:
                labeledField("Model", text: $modelDraft, placeholder: ProviderPreset.ollama.defaultModel)
                endpointRow(url: ProviderPreset.ollama.baseURL, note: "loopback only")
                insetHairline
                statusHeader
                statusDetail
                Button("Setup guide…") { showOllamaSetup = true }
                    .font(.speakBody(.caption))
                    .buttonStyle(.borderless)
                    .tint(.speakUIAccent)

            case .openAICompatible(let preset, _):
                labeledField("Model", text: $modelDraft, placeholder: modelPlaceholder(for: preset))
                endpointRow(
                    url: preset.baseURL,
                    note: preset.requiresAPIKey ? "key in Keychain" : "no key required"
                )
                insetHairline
                statusHeader
                statusDetail
                if preset.requiresAPIKey {
                    keyAction
                }

            case .mlx:
                statusHeader
                statusDetail
            }
        }
        .padding(SpeakSpacing.sm + 2)
        .speakInset(cornerRadius: 10)
    }

    /// Label column + plain text field, mono for the data (a model tag is
    /// something the user would copy or verify against the provider's list).
    private func labeledField(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        HStack(spacing: SpeakSpacing.sm) {
            Text(label)
                .font(.speakBody(.caption, semibold: true))
                .foregroundStyle(Color.speakMica)
                .frame(width: 56, alignment: .leading)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.speakMonoFace(.caption))
                .foregroundStyle(Color.speakBone)
                .tint(.speakUIAccent)
                .focused($modelFieldFocused)
                .onSubmit(commitModelDraft)
        }
    }

    /// Endpoint label + the mono URL (data voice — copyable) + a one-word
    /// provenance note ("loopback only" / "key in Keychain").
    private func endpointRow(url: URL?, note: String) -> some View {
        HStack(spacing: SpeakSpacing.sm) {
            Text("Endpoint")
                .font(.speakBody(.caption, semibold: true))
                .foregroundStyle(Color.speakMica)
                .frame(width: 56, alignment: .leading)
            if let url {
                Text(url.absoluteString)
                    .font(.speakMonoFace(.caption))
                    .foregroundStyle(Color.speakBone)
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                Text("Invalid URL")
                    .font(.speakMonoFace(.caption))
                    .foregroundStyle(Color.speakError)
            }
            Spacer(minLength: SpeakSpacing.sm)
            Text(note)
                .font(.speakBody(.caption))
                .foregroundStyle(Color.speakMica)
        }
    }

    /// Status dot + headline + trailing pill — the same dot/pill idiom the
    /// Agent Bridge card uses for its server heartbeat.
    private var statusHeader: some View {
        HStack(spacing: SpeakSpacing.sm) {
            Circle()
                .fill(statusTint)
                .frame(width: 7, height: 7)
            Text(statusHeadline)
                .font(.speakBody(.caption, semibold: true))
                .foregroundStyle(Color.speakBone)
            Spacer(minLength: 0)
            statusAccessory
        }
    }

    @ViewBuilder
    private var statusAccessory: some View {
        switch displayedAvailability {
        case .checking:
            ProgressView().controlSize(.small)

        case .ready:
            SettingsStatusPill(text: "Ready", tint: .speakOK)

        case .needsAttention:
            SettingsStatusPill(text: attentionPill, tint: .speakWarning)

        case .unsupported:
            SettingsStatusPill(text: "v0.1", tint: .speakMica)

        case .idle:
            EmptyView()
        }
    }

    private var statusDetail: some View {
        Text(statusDetailText)
            .font(.speakBody(.caption))
            .foregroundStyle(Color.speakMica)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// The primary fix affordance for a cloud preset — prominent when the key
    /// is genuinely the missing piece (raw `availability`, not the displayed
    /// value — a missing *model* doesn't want a key button), quiet once one
    /// is stored.
    @ViewBuilder
    private var keyAction: some View {
        if availability == .needsAttention {
            Button("Enter API key…") { showKeyEntry = true }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(.speakUIAccent)
        } else {
            Button("Manage API key…") { showKeyEntry = true }
                .font(.speakBody(.caption))
                .buttonStyle(.borderless)
                .tint(.speakUIAccent)
        }
    }

    private var insetHairline: some View {
        Divider().overlay(Color.speakCardBorder.opacity(0.6))
    }

    // MARK: - Engine status derivation

    /// Live availability of the selected engine, checked through
    /// `defaultCleaner(for:)` — the same factory the dictation path uses, so
    /// the pill reports what a real dictation would hit. `idle` = cleanup off
    /// (nothing to check); `unsupported` = the factory declined to build a
    /// cleaner (the `.mlx` stub); `needsAttention` = `isAvailable == false`
    /// (Apple Intelligence off, Ollama down, or no API key saved).
    private enum EngineAvailability {
        case idle, checking, ready, needsAttention, unsupported
    }

    /// What the pill actually shows — identical to `availability` except that
    /// a cloud preset with a key but no usable model still flags.
    private var displayedAvailability: EngineAvailability {
        if availability == .ready,
           case .openAICompatible(let preset, let model) = store.cleanupEngine,
           model.isEmpty, preset.defaultModel.isEmpty {
            return .needsAttention
        }
        return availability
    }

    /// Re-check triggers: engine choice, cleanup on/off, and guided-setup
    /// sheets closing (a saved key or a started Ollama changes the answer).
    private struct AvailabilityKey: Equatable {
        let engine: CleanupEngine
        let active: Bool
        let sheetsClosed: Bool
    }

    private var availabilityKey: AvailabilityKey {
        AvailabilityKey(
            engine: store.cleanupEngine,
            active: cleanupActive,
            sheetsClosed: !showOllamaSetup && !showKeyEntry
        )
    }

    private func refreshAvailability() async {
        guard cleanupActive else {
            availability = .idle
            return
        }
        // A sheet being up means the user is mid-fix — keep the last status.
        guard !showOllamaSetup, !showKeyEntry else { return }
        availability = .checking
        guard let cleaner = defaultCleaner(for: store) else {
            availability = .unsupported
            return
        }
        availability = await cleaner.isAvailable ? .ready : .needsAttention
    }

    private var statusTint: Color {
        switch displayedAvailability {
        case .ready: return .speakOK
        case .needsAttention: return .speakWarning
        case .idle, .checking, .unsupported: return .speakMica
        }
    }

    private var statusHeadline: String {
        switch displayedAvailability {
        case .checking:
            return "Checking…"

        case .ready:
            switch store.cleanupEngine {
            case .foundationModels: return "Runs on-device"
            case .ollama: return "Ollama is responding"
            case .openAICompatible(let preset, _): return "\(preset.displayName) is configured"
            case .mlx: return "Ready"
            }

        case .needsAttention:
            switch store.cleanupEngine {
            case .foundationModels: return "Apple Intelligence unavailable"
            case .ollama: return "Ollama isn't responding"
            case .openAICompatible: return "Setup needed"
            case .mlx: return "Unavailable"
            }

        case .unsupported:
            return "Arrives in v0.1"

        case .idle:
            return "Off"
        }
    }

    private var attentionPill: String {
        switch store.cleanupEngine {
        case .foundationModels: return "Unavailable"
        case .ollama: return "Not running"

        case .openAICompatible(let preset, let model):
            return model.isEmpty && preset.defaultModel.isEmpty ? "Set model" : "Needs key"

        case .mlx: return "Unavailable"
        }
    }

    private var statusDetailText: String {
        switch store.cleanupEngine {
        case .foundationModels:
            switch displayedAvailability {
            case .checking:
                return "Checking Apple Intelligence…"

            case .needsAttention:
                return "Apple Intelligence is off or unsupported on this Mac — the raw transcript is pasted until it's back."

            default:
                return "No network, no account — cleanup runs entirely on this Mac."
            }

        case .ollama(let model):
            switch displayedAvailability {
            case .checking:
                return "Pinging 127.0.0.1:11434…"

            case .needsAttention:
                return "Nothing is answering on 127.0.0.1:11434 — start Ollama or open the setup guide. The raw transcript is pasted meanwhile."

            default:
                return "Serving \(model.isEmpty ? ProviderPreset.ollama.defaultModel : model) on loopback — transcript text only, never audio."
            }

        case .openAICompatible(let preset, let model):
            if preset.baseURL == nil {
                return "The endpoint URL is invalid — the raw transcript is pasted until it's fixed."
            }
            if model.isEmpty && preset.defaultModel.isEmpty {
                return "\(preset.displayName) has no default model — set one above before dictating."
            }
            switch displayedAvailability {
            case .checking:
                return "Checking Keychain for a saved key…"

            case .needsAttention:
                return "No API key saved for \(preset.displayName) — the raw transcript is pasted until you add one. Text only, never audio."

            default:
                return "Only transcript text is sent to \(preset.displayName) — never audio."
            }

        case .mlx:
            return "MLX needs third-party Swift packages that ship in v0.1 — the raw transcript is pasted until then."
        }
    }

    // MARK: - Engine picker binding + model editing

    /// Canonical menu tag for the stored engine — the payload is normalized to
    /// the tag the menu uses, so a stored `.ollama(model: "gemma3:4b")` still
    /// selects the Ollama item instead of rendering a blank picker.
    private var engineTag: CleanupEngine {
        switch store.cleanupEngine {
        case .foundationModels:
            return .foundationModels

        case .ollama:
            return .ollama(model: ProviderPreset.ollama.defaultModel)

        case .openAICompatible(let preset, _):
            return .openAICompatible(preset: preset, model: preset.defaultModel)

        case .mlx:
            return .mlx(model: Self.mlxMenuModel)
        }
    }

    /// Picker binding: normalizes on read (tag match), preserves stored
    /// payloads on write (re-selecting the same family keeps the user's model),
    /// and surfaces the guided-setup sheet the engine needs.
    private var engineBinding: Binding<CleanupEngine> {
        Binding(
            get: { engineTag },
            set: { tag in
                let previous = store.cleanupEngine
                let merged: CleanupEngine
                switch (tag, previous) {
                case (.ollama, .ollama(let model)):
                    merged = .ollama(model: model.isEmpty ? ProviderPreset.ollama.defaultModel : model)

                case (.openAICompatible(let preset, _), .openAICompatible(let stored, let model)) where preset == stored:
                    merged = .openAICompatible(preset: preset, model: model)

                case (.mlx, .mlx(let model)):
                    merged = .mlx(model: model)

                default:
                    merged = tag
                }
                store.cleanupEngine = merged
                presentSetupIfNeeded(for: merged, replacing: previous)
            }
        )
    }

    /// Selecting Ollama walks the user through install + pull (only on a real
    /// switch — re-picking the selected item shouldn't re-pop the guide);
    /// selecting a cloud preset with no saved key opens key entry directly —
    /// the status row covers every other case.
    private func presentSetupIfNeeded(for engine: CleanupEngine, replacing previous: CleanupEngine) {
        switch engine {
        case .ollama:
            if case .ollama = previous { return }
            showOllamaSetup = true

        case .openAICompatible(let preset, _):
            guard preset.requiresAPIKey else { return }
            let hasKey = (try? keychainStore.readKey(account: preset.id))?.isEmpty == false
            if !hasKey { showKeyEntry = true }

        case .foundationModels, .mlx:
            break
        }
    }

    /// The model stored on the current engine case ("" for Foundation Models).
    private var storedModel: String {
        switch store.cleanupEngine {
        case .foundationModels: return ""
        case .ollama(let model): return model
        case .openAICompatible(_, let model): return model
        case .mlx(let model): return model
        }
    }

    private func modelPlaceholder(for preset: ProviderPreset) -> String {
        preset.defaultModel.isEmpty ? "model required" : preset.defaultModel
    }

    /// Commit the model field on Return / focus-out. Blank restores the
    /// engine's default tag (which may itself be blank for OpenRouter/custom —
    /// the status row flags that case).
    private func commitModelDraft() {
        let trimmed = modelDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        switch store.cleanupEngine {
        case .ollama:
            let model = trimmed.isEmpty ? ProviderPreset.ollama.defaultModel : trimmed
            store.cleanupEngine = .ollama(model: model)
            modelDraft = model

        case .openAICompatible(let preset, _):
            store.cleanupEngine = .openAICompatible(preset: preset, model: trimmed)
            modelDraft = trimmed

        case .foundationModels, .mlx:
            break
        }
    }

    private var engineRowDescription: String {
        guard cleanupActive else {
            return "Set a level above None to choose an engine."
        }
        switch store.cleanupEngine {
        case .foundationModels:
            return "On-device Apple Intelligence — no network, no account."

        case .ollama:
            return "A local model on your Mac via Ollama — no key, no cloud."

        case .openAICompatible(let preset, _):
            return "\(preset.displayName) — strictly opt-in; transcript text only, never audio."

        case .mlx:
            return "On-device MLX models — lands in v0.1."
        }
    }

    // MARK: - Per-app profiles

    /// The routing table the Profile Engine resolves against: the frontmost
    /// app picks the profile, everything unmatched runs the global style +
    /// level above (`SpeakEngine.newSession` — `.styled` stays the default
    /// path; only a non-default, non-raw profile match switches to `.profile`).
    private var profilesCard: some View {
        SettingsSectionCard(title: "Per-App Profiles") {
            VStack(spacing: 0) {
                SettingsRow(
                    "Route by frontmost app",
                    description: store.perAppContextEnabled
                        ? "The app you dictate into picks the profile AI cleanup runs. Unmatched apps use your global style and level."
                        : "Off — every dictation uses your global style and level, regardless of the app."
                ) {
                    Toggle("", isOn: Binding(
                        get: { store.perAppContextEnabled },
                        set: { store.perAppContextEnabled = $0 }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .tint(.speakUIAccent)
                }

                if store.perAppContextEnabled {
                    SettingsRowSeparator()

                    VStack(spacing: 0) {
                        ForEach(Array(context.profileStore.profiles.enumerated()), id: \.element.id) { index, profile in
                            if index > 0 { SettingsRowSeparator() }
                            profileRouteRow(profile)
                        }
                    }

                    SettingsRowSeparator()

                    Text("Profiles and their app lists are edited in AI Studio on the dashboard.")
                        .font(.speakBody(.caption))
                        .foregroundStyle(Color.speakMica)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, SpeakSpacing.md)
                        .padding(.vertical, SpeakSpacing.sm + 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    /// One routing row: profile glyph tile (agent channel — this is the
    /// intelligence layer), name, and the resolved app list. A profile with
    /// no `targetApps` reads honestly as "No apps assigned" rather than a
    /// blank. [decision: icon tiles tinted agentViolet — the intelligence
    /// channel, same as the Pipeline pane's layer status]
    private func profileRouteRow(_ profile: Profile) -> some View {
        HStack(alignment: .top, spacing: SpeakSpacing.sm) {
            Image(systemName: profile.icon)
                .font(.system(size: 13))
                .foregroundStyle(Color.speakAgentViolet)
                .frame(width: 22, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.speakAgentViolet.opacity(0.12))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(profile.name)
                    .font(.speakBody(.base, semibold: true))
                    .foregroundStyle(Color.speakBone)
                Text(appsLine(for: profile))
                    .font(.speakBody(.caption))
                    .foregroundStyle(Color.speakMica)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: SpeakSpacing.sm)

            if profile.model == .raw {
                SettingsStatusPill(text: "Passthrough", tint: .speakMica)
            }
        }
        .padding(.horizontal, SpeakSpacing.md)
        .padding(.vertical, SpeakSpacing.xs + 2)
    }

    /// The resolved app list for a profile, or the honest no-match caption.
    private func appsLine(for profile: Profile) -> String {
        guard !profile.targetApps.isEmpty else {
            return "No apps assigned — never auto-activates"
        }
        return profile.targetApps.map(appDisplayName).joined(separator: " · ")
    }

    /// Bundle ID → installed app name ("com.apple.Terminal" → "Terminal").
    /// Uninstalled IDs and host strings fall back to the last dotted component
    /// when it reads like a name ("…obsidian" → "Obsidian"), else the raw id.
    private func appDisplayName(_ identifier: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) {
            return url.deletingPathExtension().lastPathComponent
        }
        if let last = identifier.split(separator: ".").last,
           last.count > 2, last.allSatisfy({ $0.isLetter || $0 == "-" }) {
            return String(last).capitalized
        }
        return identifier
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Intelligence") {
    IntelligenceSettingsView(context: DashboardContext(
        settingsStore: SettingsStore(),
        historyStore: PreviewNullHistoryStore(),
        hotkeyCombo: ["Fn", "Fn"]
    ))
    .padding(SpeakSpacing.lg)
    .frame(width: 720)
    .background(Color.speakWindowCanvas)
}
#endif
