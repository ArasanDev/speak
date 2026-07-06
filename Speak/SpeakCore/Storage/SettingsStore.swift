// SpeakCore/Storage/SettingsStore.swift
//
// Typed UserDefaults wrapper for all user-configurable `speak` settings.
//
// DESIGN:
//   - `@unchecked Sendable` (NOT `@MainActor`): properties are computed over an
//     injected `UserDefaults` instance, which is documented thread-safe by Apple.
//     This lets `SpeakEngine` (an actor) read `settings.cleanupEnabled` etc.
//     synchronously without a cross-actor `await`.
//   - `@Observable`: SwiftUI views bind to this directly via plain `let` (no
//     `@ObservedObject` needed). Computed properties over UserDefaults are manually
//     instrumented with `access(keyPath:)` / `withMutation(keyPath:)` so the
//     observation registrar tracks reads and writes correctly.
//   - Testable via injection: `init(defaults:)` accepts any `UserDefaults` instance.
//     Tests pass `UserDefaults(suiteName: UUID().uuidString)!` to avoid `.standard`
//     pollution. Production uses `.standard`.
//   - Enums include v0.1/v1 cases as placeholders so `switch` is exhaustive.
//
// HOTKEY BINDING PERSISTENCE:
//   The P5 `UserDefaultsBindingStore` already owns hotkey-binding persistence
//   under its own key ("speak.hotkeyBinding"). `SettingsStore` does NOT duplicate
//   that: the Settings UI reads/writes the binding through the injected
//   `BindingStoring` (the same `UserDefaultsBindingStore` the `HotkeyMonitor`
//   uses). This avoids two sources of truth for the same value.
//
// KEY CONSTANTS:
//   All UserDefaults keys live in `Keys` to avoid typos and make the key
//   namespace discoverable. There are no magic strings elsewhere in this file.

import Foundation
import Observation
import os

// MARK: - Engine enums

/// Which STT engine to use. v0 = `.appleSpeech`. v0.1+ cases are placeholders.
public enum STTEngine: Codable, Sendable, Equatable, Hashable {
    /// Apple SpeechAnalyzer (macOS 26+, Apple Silicon). **v0 default.**
    case appleSpeech
    /// WhisperKit — accurate, 99 languages. **v0.1 placeholder (not built).**
    case whisperKit
    /// whisper.cpp — Intel Mac support. **v1 placeholder (not built).**
    case whisperCpp
}

/// Which AI cleanup engine to use. v0 = `.foundationModels`. v0.1+ are opt-in alternatives.
///
/// **Persistence:** encoded as JSON in `UserDefaults` (same pattern as `STTEngine`).
/// **Default:** `.foundationModels` — the only production-ready engine in v0.
/// **Fallback:** `EngineFactories.defaultCleaner(for:)` always falls back to
/// `FoundationModelsCleaner` when an opt-in engine's stub returns `isAvailable == false`.
///
/// Wave 2.1 registered `.ollama`/`.mlx` as stub placeholders (`isAvailable == false`
/// always). V01-2 makes `.ollama` real: `EngineFactories.defaultCleaner` now routes it
/// to `OpenAICompatibleCleaner(preset: .ollama, model:)`, backed by the `SpeakLLM`
/// module. `.openAICompatible` is the general form covering the remaining five
/// presets (Sarvam/OpenAI/Groq/OpenRouter/custom) from `ProviderPreset`
/// (`SpeakCore/Cleanup/OpenAICompatibleCleaner.swift`). `.mlx` remains a stub —
/// MLX is a third-party dep, forbidden until its own v0.1+ approval. [decision V01-2]
public enum CleanupEngine: Codable, Sendable, Equatable, Hashable {
    /// Apple Foundation Models (macOS 26+, Apple Silicon + Neural Engine). **v0 default.**
    /// Runs entirely on-device; no network, no account, no server required.
    case foundationModels
    /// Ollama local server (Qwen2.5-3B / Gemma3-4B / Phi-4-mini…), talked to via the
    /// universal `OpenAICompatibleCleaner` with `ProviderPreset.ollama`. Loopback-only,
    /// no API key. **v0.1 — real implementation as of V01-2.**
    case ollama(model: String)
    /// The universal OpenAI-compatible engine for a specific non-Ollama preset
    /// (Sarvam LLM / OpenAI / Groq / OpenRouter / a fully custom endpoint). Cloud
    /// presets are strictly opt-in: nothing here runs unless the user picks this
    /// case AND supplies an API key via Settings → AI Cleanup. **v0.1 (V01-2).**
    case openAICompatible(preset: ProviderPreset, model: String)
    /// MLX on-device inference (Apple Silicon, github.com/ml-explore/mlx).
    /// Requires MLX Swift packages (third-party dep — forbidden in v0). **v0.1+ stub.**
    case mlx(model: String)
}

/// How finished text is delivered to the cursor. v0 = `.cmdV`.
public enum PasteMode: String, Codable, Sendable, Equatable {
    /// Simulate Cmd+V via `CGEventTap`. **v0 default.** Fast; works in most apps.
    case cmdV
    /// Accessibility API insertion (AXUIElement). **v1 placeholder** — avoids paste-provenance
    /// issues in Terminal on macOS 26.4+, but requires an extra Accessibility call.
    case accessibility
}

/// Whether to stream cleaned text as keystrokes during active dictation. v0 = `.off`.
public enum StreamingMode: String, Codable, Sendable, Equatable {
    /// Streaming disabled. Cleaned text is pasted all at once after dictation ends.
    case off = "off"
    /// Real-time keystroke injection. Cleaned text is delivered character-by-character
    /// as dictation progresses, creating a live-typing effect in the target app.
    case keystrokeInjection = "keystroke"
}

/// Application appearance theme. v0 default = `.system` (follow macOS setting).
public enum AppTheme: String, Codable, Sendable, Equatable {
    /// Light mode always.
    case light
    /// Dark mode always.
    case dark
    /// Follow system setting (default).
    case system
}

/// Visual style for the floating recording HUD (overlay). v0 default = `.classic`
/// — **zero regression risk**: existing behavior is unchanged unless the user
/// opts in via Settings. [decision H-UI]
public enum HUDStyle: String, Codable, Sendable, Equatable {
    /// The original 15-bar waveform HUD (W2.2). **v0 default.**
    case classic
    /// The ambient orb + materializing-words HUD (H-UI "Aurora"). Opt-in.
    case aurora
}

// MARK: - SettingsStore

/// The single source of truth for all persisted user preferences in `speak`.
///
/// Inject into the SwiftUI environment and read from `SpeakEngine` actors;
/// do not access `UserDefaults.standard` directly anywhere else.
@Observable
public final class SettingsStore: @unchecked Sendable {

    // MARK: - UserDefaults key namespace

    private enum Keys {
        // Prefix matches the bundle id convention; stable across versions.
        static let cleanupEnabled        = "speak.settings.cleanupEnabled"
        static let cleanupEngine         = "speak.settings.cleanupEngine"
        static let sttEngine             = "speak.settings.sttEngine"
        static let language              = "speak.settings.language"
        static let pasteMode             = "speak.settings.pasteMode"
        static let hasCompletedOnboarding = "speak.settings.hasCompletedOnboarding"
        static let triggerMode           = "speak.settings.triggerMode"
        static let customVocabulary      = "speak.settings.customVocabulary"
        static let cleanupStyle          = "speak.settings.cleanupStyle"
        static let cleanupLevel          = "speak.settings.cleanupLevel"
        static let streamingRawTextEnabled = "speak.settings.streamingRawTextEnabled"
        static let streamingMode         = "speak.settings.streamingMode"
        static let appTheme              = "speak.settings.appTheme"
        static let perAppContextEnabled  = "speak.settings.perAppContextEnabled"
        static let extraBindings         = "speak.settings.extraHotkeyBindings"
        static let hudStyle              = "speak.settings.hudStyle"
        static let voiceActionsEnabled   = "speak.settings.voiceActionsEnabled"
        static let voiceActionsPrefix    = "speak.settings.voiceActionsPrefix"
    }

    // MARK: - Injected defaults (the testability seam)

    /// The backing `UserDefaults` instance. Production uses `.standard`;
    /// tests inject a named suite so `.standard` is never polluted.
    private let defaults: UserDefaults

    // MARK: - Init

    /// Create a `SettingsStore` backed by the given `UserDefaults` instance.
    ///
    /// - Parameter defaults: The store to read/write. Tests inject a named suite
    ///   (`UserDefaults(suiteName: UUID().uuidString)!`). Production passes `.standard`.
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Register v0 defaults so unset keys return the right value
        // (not the zero/false/empty value that UserDefaults returns by default).
        defaults.register(defaults: [
            Keys.cleanupEnabled: true,
            Keys.language: "en-US",
            Keys.pasteMode: PasteMode.cmdV.rawValue,
            Keys.cleanupStyle: CleanupStyle.default.rawValue,
            // W4.1: default is .medium (the "balanced" equivalent in the new 4-level scale).
            // Old stored rawValues (basic/balanced/thorough) will not decode after this
            // rename — the getter falls back to .medium. [decision: clean break, no shim]
            Keys.cleanupLevel: CleanupLevel.medium.rawValue,
            Keys.streamingRawTextEnabled: true,
            Keys.streamingMode: StreamingMode.keystrokeInjection.rawValue,
            Keys.appTheme: AppTheme.system.rawValue,
            Keys.perAppContextEnabled: true,
            Keys.hudStyle: HUDStyle.classic.rawValue,
            Keys.voiceActionsPrefix: "hey speak"
        ])
        // Enum defaults are handled via `?? fallback` at the getter level because
        // Codable JSON cannot be registered as a `[String: Any]` literal.
    }

    // MARK: - AI cleanup toggle

    /// Whether AI cleanup (Foundation Models) is applied after transcription.
    ///
    /// `true` (default): cleaned text is pasted.
    /// `false`: raw transcript is pasted without an LLM pass.
    public var cleanupEnabled: Bool {
        get {
            access(keyPath: \.cleanupEnabled)
            return defaults.bool(forKey: Keys.cleanupEnabled)
        }
        set {
            withMutation(keyPath: \.cleanupEnabled) {
                defaults.set(newValue, forKey: Keys.cleanupEnabled)
            }
        }
    }

    // MARK: - Cleanup engine

    /// Which LLM cleanup engine to use when `cleanupEnabled == true`.
    /// Default: `.foundationModels`.
    public var cleanupEngine: CleanupEngine {
        get {
            access(keyPath: \.cleanupEngine)
            guard let data = defaults.data(forKey: Keys.cleanupEngine),
                  let decoded = try? JSONDecoder().decode(CleanupEngine.self, from: data) else {
                return .foundationModels   // v0 default
            }
            return decoded
        }
        set {
            withMutation(keyPath: \.cleanupEngine) {
                if let data = try? JSONEncoder().encode(newValue) {
                    defaults.set(data, forKey: Keys.cleanupEngine)
                } else {
                    SpeakLog.storage.error("SettingsStore: failed to encode cleanupEngine — value not persisted.")
                }
            }
        }
    }

    // MARK: - STT engine

    /// Which speech-to-text engine to use.
    /// Default: `.appleSpeech` (SpeechAnalyzer, zero-cost, on-device).
    public var sttEngine: STTEngine {
        get {
            access(keyPath: \.sttEngine)
            guard let data = defaults.data(forKey: Keys.sttEngine),
                  let decoded = try? JSONDecoder().decode(STTEngine.self, from: data) else {
                return .appleSpeech   // v0 default
            }
            return decoded
        }
        set {
            withMutation(keyPath: \.sttEngine) {
                if let data = try? JSONEncoder().encode(newValue) {
                    defaults.set(data, forKey: Keys.sttEngine)
                } else {
                    SpeakLog.storage.error("SettingsStore: failed to encode sttEngine — value not persisted.")
                }
            }
        }
    }

    // MARK: - Language / locale

    /// The transcription locale. Default: `en-US`. `en-GB` is also surfaced in the UI.
    ///
    /// Stored as the locale's `identifier` string (e.g., `"en-US"`).
    public var language: Locale {
        get {
            access(keyPath: \.language)
            let id = defaults.string(forKey: Keys.language) ?? "en-US"
            return Locale(identifier: id)
        }
        set {
            withMutation(keyPath: \.language) {
                defaults.set(newValue.identifier, forKey: Keys.language)
            }
        }
    }

    // MARK: - Onboarding completion flag

    /// `true` once the user has completed (or deliberately skipped) the
    /// first-run onboarding flow. When `false`, the onboarding window is
    /// presented on launch. Defaults to `false` so a fresh install always shows
    /// onboarding. [decision: false default — new installs must onboard]
    public var hasCompletedOnboarding: Bool {
        get {
            access(keyPath: \.hasCompletedOnboarding)
            return defaults.bool(forKey: Keys.hasCompletedOnboarding)
        }
        set {
            withMutation(keyPath: \.hasCompletedOnboarding) {
                defaults.set(newValue, forKey: Keys.hasCompletedOnboarding)
                SpeakLog.storage.info(
                    "SettingsStore: hasCompletedOnboarding → \(newValue, privacy: .public)"
                )
            }
        }
    }

    // MARK: - Paste mode

    /// How finished text is inserted at the cursor.
    /// Default: `.cmdV` (simulate Cmd+V via CGEventTap).
    public var pasteMode: PasteMode {
        get {
            access(keyPath: \.pasteMode)
            let raw = defaults.string(forKey: Keys.pasteMode) ?? PasteMode.cmdV.rawValue
            return PasteMode(rawValue: raw) ?? .cmdV
        }
        set {
            withMutation(keyPath: \.pasteMode) {
                defaults.set(newValue.rawValue, forKey: Keys.pasteMode)
            }
        }
    }

    // MARK: - Hotkey trigger mode (Phase B)

    /// Which gesture activates dictation.
    ///
    /// - `.doubleTap` (default): double-tap Fn starts hands-free recording; next
    ///   single Fn tap stops. Toggle style — ideal for longer dictations.
    /// - `.hold`: press Fn to record, release to stop. Push-to-talk style — ideal
    ///   for short utterances and one-handed use.
    ///
    /// Persisted as the `Trigger.rawValue` String. An unset key returns `.doubleTap`.
    /// `DictationController` reads this on launch and on change, builds a
    /// `HotkeyBinding` from it, and calls `monitor.updateBinding(_:)` so the live
    /// monitor switches mode without restart.
    ///
    /// Note: the trigger is also stored inside the `HotkeyBinding` in
    /// `UserDefaultsBindingStore` (owned by P5 `HotkeyMonitor`). `DictationController`
    /// keeps them in sync — `SettingsStore.triggerMode` is the user-facing setting,
    /// `UserDefaultsBindingStore` is the monitor's runtime view of the same value.
    public var triggerMode: HotkeyBinding.Trigger {
        get {
            access(keyPath: \.triggerMode)
            let raw = defaults.string(forKey: Keys.triggerMode) ?? HotkeyBinding.Trigger.doubleTap.rawValue
            return HotkeyBinding.Trigger(rawValue: raw) ?? .doubleTap
        }
        set {
            withMutation(keyPath: \.triggerMode) {
                defaults.set(newValue.rawValue, forKey: Keys.triggerMode)
            }
        }
    }

    // MARK: - Extra hotkey bindings (V01-5 — multiple bindings per action)

    /// Up to `ExtraBindingSet.maxPerAction` (4) additional bindings per action
    /// (`.activate` / `.stop`), independent of the primary double-tap/hold toggle
    /// binding above. This is the user-facing setting the Shortcuts pane binds to.
    ///
    /// Same duplication pattern as `triggerMode`: `HotkeyMonitor` also persists
    /// its own runtime copy via the injected `BindingStoring`
    /// (`loadExtraBindings()`/`saveExtraBindings(_:)`). `DictationController`
    /// reconciles the two at launch and applies live changes via
    /// `monitor.updateExtraBindings(_:)` — same wiring as `triggerMode`.
    /// Default: `.empty` — a fresh install (or an old payload predating V01-5)
    /// has no extra bindings.
    public var extraBindings: ExtraBindingSet {
        get {
            access(keyPath: \.extraBindings)
            guard let data = defaults.data(forKey: Keys.extraBindings),
                  let decoded = try? JSONDecoder().decode(ExtraBindingSet.self, from: data) else {
                return .empty
            }
            return decoded
        }
        set {
            withMutation(keyPath: \.extraBindings) {
                if let data = try? JSONEncoder().encode(newValue) {
                    defaults.set(data, forKey: Keys.extraBindings)
                } else {
                    SpeakLog.storage.error("SettingsStore: failed to encode extraBindings — value not persisted.")
                }
            }
        }
    }

    // MARK: - Cleanup style + level (Wave B — neat-writing voice)

    /// The neat-writing *voice* applied during AI cleanup. Default: `.default`
    /// (behavior-neutral baseline). Read by `SpeakEngine.newSession()` at call time
    /// (H1 pattern), so a Style-pane change applies on the next dictation. Persisted
    /// as the enum's `rawValue` String — `defaults.register` seeds the default.
    public var cleanupStyle: CleanupStyle {
        get {
            access(keyPath: \.cleanupStyle)
            let raw = defaults.string(forKey: Keys.cleanupStyle) ?? CleanupStyle.default.rawValue
            return CleanupStyle(rawValue: raw) ?? .default
        }
        set {
            withMutation(keyPath: \.cleanupStyle) {
                defaults.set(newValue.rawValue, forKey: Keys.cleanupStyle)
            }
        }
    }

    /// The neat-writing *intensity* applied during AI cleanup. Default: `.medium`.
    ///
    /// **W4.1 4-level scale**: None / Light / Medium / High. When `.none`, the engine
    /// skips the LLM pass entirely (raw transcript pasted) even if `cleanupEnabled == true`.
    /// Read alongside `cleanupStyle` at `newSession()` time (H1 pattern).
    public var cleanupLevel: CleanupLevel {
        get {
            access(keyPath: \.cleanupLevel)
            let raw = defaults.string(forKey: Keys.cleanupLevel) ?? CleanupLevel.medium.rawValue
            return CleanupLevel(rawValue: raw) ?? .medium
        }
        set {
            withMutation(keyPath: \.cleanupLevel) {
                defaults.set(newValue.rawValue, forKey: Keys.cleanupLevel)
            }
        }
    }

    // MARK: - Effective cleanup level (W3.1 collapse seam)

    /// The single picker-facing cleanup control. Collapses the legacy
    /// `cleanupEnabled` boolean and the 4-level `cleanupLevel` into one value.
    ///
    /// **Getter:** returns `.none` when `cleanupEnabled == false` (preserves the
    /// legacy "off" state for users who toggled via the old boolean), otherwise
    /// returns the stored `cleanupLevel`.
    /// **Setter:** `.none` sets both `cleanupEnabled = false` and `cleanupLevel = .none`;
    /// any other level sets `cleanupEnabled = true` and `cleanupLevel = <value>`.
    ///
    /// `SpeakEngine.newSession()` already reads `cleanupEnabled` and `cleanupLevel`
    /// independently — those remain the authoritative values. This is purely a
    /// UI-facing convenience that keeps both in sync from one picker. [decision: W3.1]
    public var effectiveCleanupLevel: CleanupLevel {
        get {
            access(keyPath: \.effectiveCleanupLevel)
            return cleanupEnabled ? cleanupLevel : .none
        }
        set {
            if newValue == .none {
                cleanupEnabled = false
                cleanupLevel = .none
            } else {
                cleanupEnabled = true
                cleanupLevel = newValue
            }
        }
    }

    // MARK: - Custom vocabulary (H4 seam)

    /// User-supplied term list passed to the STT recognizer as contextual hints.
    ///
    /// Persisted as a `[String]` array in `UserDefaults` (native type — no JSON
    /// encoding needed). An empty array (the default) means no injection into
    /// `AnalysisContext.contextualStrings`; the transcriber behaves exactly as it
    /// did before H4. No UI in v0 — this property is the persistence seam only.
    /// The v1 dictionary UI will write here and the transcriber will pick it up
    /// on the next dictation session.
    ///
    /// [decision: stored as [String] because UserDefaults natively supports string
    ///  arrays; no codec needed; injection point is AnalysisContext.contextualStrings[.general]]
    public var customVocabulary: [String] {
        get {
            access(keyPath: \.customVocabulary)
            return defaults.stringArray(forKey: Keys.customVocabulary) ?? []
        }
        set {
            withMutation(keyPath: \.customVocabulary) {
                defaults.set(newValue, forKey: Keys.customVocabulary)
            }
        }
    }

    // MARK: - Streaming settings (keystroke injection)

    /// Whether raw (unprocessed) text is streamed character-by-character during dictation
    /// when `streamingMode == .keystrokeInjection`.
    ///
    /// `true` (default): raw transcript is delivered live as you speak.
    /// `false`: only cleaned text is streamed (after the LLM pass completes).
    ///
    /// Has no effect when `streamingMode == .off` (text is always delivered in a single paste).
    public var streamingRawTextEnabled: Bool {
        get {
            access(keyPath: \.streamingRawTextEnabled)
            return defaults.bool(forKey: Keys.streamingRawTextEnabled)
        }
        set {
            withMutation(keyPath: \.streamingRawTextEnabled) {
                defaults.set(newValue, forKey: Keys.streamingRawTextEnabled)
            }
        }
    }

    /// Whether keystroke injection (real-time text delivery) is active.
    /// Default: `.keystrokeInjection`.
    public var streamingMode: StreamingMode {
        get {
            access(keyPath: \.streamingMode)
            let raw = defaults.string(forKey: Keys.streamingMode) ?? StreamingMode.keystrokeInjection.rawValue
            return StreamingMode(rawValue: raw) ?? .keystrokeInjection
        }
        set {
            withMutation(keyPath: \.streamingMode) {
                defaults.set(newValue.rawValue, forKey: Keys.streamingMode)
            }
        }
    }

    // MARK: - Application theme (UI appearance)

    /// The application appearance theme. Default: `.system` (follow macOS setting).
    public var appTheme: AppTheme {
        get {
            access(keyPath: \.appTheme)
            let raw = defaults.string(forKey: Keys.appTheme) ?? AppTheme.system.rawValue
            return AppTheme(rawValue: raw) ?? .system
        }
        set {
            withMutation(keyPath: \.appTheme) {
                defaults.set(newValue.rawValue, forKey: Keys.appTheme)
            }
        }
    }

    // MARK: - HUD style (overlay visual style, H-UI)

    /// Visual style for the floating recording HUD. Default: `.classic`.
    ///
    /// Read live by `OverlayRootView` (via `@Observable` tracking) so toggling
    /// this in Settings swaps the HUD content immediately — no relaunch and no
    /// panel recreation. [decision H-UI: opt-in, classic stays the default]
    public var hudStyle: HUDStyle {
        get {
            access(keyPath: \.hudStyle)
            let raw = defaults.string(forKey: Keys.hudStyle) ?? HUDStyle.classic.rawValue
            return HUDStyle(rawValue: raw) ?? .classic
        }
        set {
            withMutation(keyPath: \.hudStyle) {
                defaults.set(newValue.rawValue, forKey: Keys.hudStyle)
            }
        }
    }

    // MARK: - Per-app context awareness (V01-3, profile-native)

    /// Whether the frontmost app influences which profile runs the cleanup pass
    /// (`ProfileResolver` matching against each profile's `targetApps`).
    ///
    /// `true` (default): dictating in Xcode/Terminal → `Agent`, Slack/Messages →
    /// `Chat`, Mail/browsers → `Write`, unmatched apps → the global default.
    /// `false`: `SpeakEngine.newSession()` ignores the frontmost app entirely and
    /// always resolves to the global default profile — reproducing the
    /// no-app-context baseline exactly, regardless of which app is frontmost.
    ///
    /// [decision V01-3] A toggle, not a removal: per-app matching is the shipped
    /// default (it has been live since PE-1), but users who find it surprising
    /// (e.g. dictating a code snippet's prose description in Xcode) can turn it off.
    public var perAppContextEnabled: Bool {
        get {
            access(keyPath: \.perAppContextEnabled)
            return defaults.bool(forKey: Keys.perAppContextEnabled)
        }
        set {
            withMutation(keyPath: \.perAppContextEnabled) {
                defaults.set(newValue, forKey: Keys.perAppContextEnabled)
            }
        }
    }

    // MARK: - Voice Actions (H-1, specs/horizon-voice-os.md Pillar 1)

    /// Master toggle for Voice Actions (the intent router: dictation vs command
    /// vs action, `SpeakCore/VoiceActions/`).
    ///
    /// `false` (default): the router is never consulted and `shortcuts run` is
    /// never invoked — behavior is byte-identical to `VoiceActions/` not existing.
    /// `true`: a spoken `voiceActionsPrefix` at the start of an utterance gates
    /// routing to `CommandModeService` (command) or `ShortcutsCLIExecutor`
    /// (action); everything else remains plain dictation.
    ///
    /// [decision H-1] Default `false` — this is a v-next opt-in extension
    /// (spec Sequencing #1, "no new perms"), not a v0 behavior change, so
    /// existing users see nothing different until they opt in.
    public var voiceActionsEnabled: Bool {
        get {
            access(keyPath: \.voiceActionsEnabled)
            return defaults.bool(forKey: Keys.voiceActionsEnabled)
        }
        set {
            withMutation(keyPath: \.voiceActionsEnabled) {
                defaults.set(newValue, forKey: Keys.voiceActionsEnabled)
            }
        }
    }

    /// The spoken trigger prefix that gates Voice Actions routing when
    /// `voiceActionsEnabled == true`. Matched case-insensitively against the
    /// start of the transcript by `PrefixActionRouter`. Default: `"hey speak"`.
    public var voiceActionsPrefix: String {
        get {
            access(keyPath: \.voiceActionsPrefix)
            return defaults.string(forKey: Keys.voiceActionsPrefix) ?? "hey speak"
        }
        set {
            withMutation(keyPath: \.voiceActionsPrefix) {
                defaults.set(newValue, forKey: Keys.voiceActionsPrefix)
            }
        }
    }

    // MARK: - Reset to defaults

    /// Resets all user settings to their default values. All preferences are wiped;
    /// history is NOT cleared (separate operation). [decision: reset != clear history]
    public func resetToDefaults() {
        access(keyPath: \.cleanupEnabled)
        access(keyPath: \.cleanupEngine)
        access(keyPath: \.sttEngine)
        access(keyPath: \.language)
        access(keyPath: \.pasteMode)
        access(keyPath: \.triggerMode)
        access(keyPath: \.customVocabulary)
        access(keyPath: \.cleanupStyle)
        access(keyPath: \.cleanupLevel)
        access(keyPath: \.streamingRawTextEnabled)
        access(keyPath: \.streamingMode)
        access(keyPath: \.appTheme)
        access(keyPath: \.perAppContextEnabled)
        access(keyPath: \.hudStyle)
        access(keyPath: \.voiceActionsEnabled)
        access(keyPath: \.voiceActionsPrefix)

        withMutation(keyPath: \.cleanupEnabled) {
            defaults.set(true, forKey: Keys.cleanupEnabled)
        }
        withMutation(keyPath: \.sttEngine) {
            defaults.removeObject(forKey: Keys.sttEngine)
        }
        withMutation(keyPath: \.language) {
            defaults.set("en-US", forKey: Keys.language)
        }
        withMutation(keyPath: \.pasteMode) {
            defaults.set(PasteMode.cmdV.rawValue, forKey: Keys.pasteMode)
        }
        withMutation(keyPath: \.triggerMode) {
            defaults.removeObject(forKey: Keys.triggerMode)
        }
        withMutation(keyPath: \.customVocabulary) {
            defaults.removeObject(forKey: Keys.customVocabulary)
        }
        withMutation(keyPath: \.cleanupStyle) {
            defaults.set(CleanupStyle.default.rawValue, forKey: Keys.cleanupStyle)
        }
        withMutation(keyPath: \.cleanupLevel) {
            defaults.set(CleanupLevel.medium.rawValue, forKey: Keys.cleanupLevel)
        }
        withMutation(keyPath: \.streamingRawTextEnabled) {
            defaults.set(true, forKey: Keys.streamingRawTextEnabled)
        }
        withMutation(keyPath: \.streamingMode) {
            defaults.set(StreamingMode.keystrokeInjection.rawValue, forKey: Keys.streamingMode)
        }
        withMutation(keyPath: \.appTheme) {
            defaults.set(AppTheme.system.rawValue, forKey: Keys.appTheme)
        }
        withMutation(keyPath: \.perAppContextEnabled) {
            defaults.set(true, forKey: Keys.perAppContextEnabled)
        }
        withMutation(keyPath: \.hudStyle) {
            defaults.set(HUDStyle.classic.rawValue, forKey: Keys.hudStyle)
        }
        withMutation(keyPath: \.voiceActionsEnabled) {
            defaults.set(false, forKey: Keys.voiceActionsEnabled)
        }
        withMutation(keyPath: \.voiceActionsPrefix) {
            defaults.set("hey speak", forKey: Keys.voiceActionsPrefix)
        }

        SpeakLog.storage.info("SettingsStore reset to defaults")
    }
}
