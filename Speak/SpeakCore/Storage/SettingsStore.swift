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

import AVFoundation
import CoreGraphics
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

/// Which border animation style to show on the recording HUD overlay.
/// Default = `.none` — zero regression risk for existing users.
public enum BorderAnimationStyle: String, Codable, Sendable, Equatable, CaseIterable {
    /// No border animation — plain panel edges. (default)
    case none
    /// Full-panel rotating conic gradient glow (style 2).
    case fullGlow
    /// Traveling color chaser that moves along the border edges only (style 3).
    case edgeFlow
}

/// Speed of the EdgeFlow border animation.
public enum BorderFlowSpeed: String, Codable, Sendable, Equatable, CaseIterable {
    case slow    // 6s per loop
    case medium  // 3s per loop
    case fast    // 1.5s per loop

    /// Cycle duration in seconds.
    public var cycleDuration: Double {
        switch self {
        case .slow: return 6.0
        case .medium: return 3.0
        case .fast: return 1.5
        }
    }
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
        static let borderAnimationStyle  = "speak.settings.borderAnimationStyle"
        static let borderFlowSpeed       = "speak.settings.borderFlowSpeed"
        static let borderFlowCount       = "speak.settings.borderFlowCount"
        static let voiceActionsEnabled   = "speak.settings.voiceActionsEnabled"
        static let voiceActionsPrefix    = "speak.settings.voiceActionsPrefix"
        static let petEnabled            = "speak.settings.petEnabled"
        static let petPositions          = "speak.settings.petPositions"
        static let readbackEnabled       = "speak.settings.readbackEnabled"
        static let revealTextWhileProcessing = "speak.settings.revealTextWhileProcessing"
        static let ttsVoiceIdentifier    = "speak.settings.ttsVoiceIdentifier"
        static let ttsSpeechRate         = "speak.settings.ttsSpeechRate"
        static let ttsPitchMultiplier    = "speak.settings.ttsPitchMultiplier"
        static let ttsVolume             = "speak.settings.ttsVolume"
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
            Keys.borderAnimationStyle: BorderAnimationStyle.none.rawValue,
            Keys.borderFlowSpeed: BorderFlowSpeed.medium.rawValue,
            Keys.borderFlowCount: 1,
            Keys.voiceActionsPrefix: "hey speak",
            // [decision H-2] Default true: the readback affordance is inert until the
            // user presses it (no audio plays unprompted), so there is no privacy/
            // surprise cost to shipping it on by default — the toggle exists purely
            // to let a user hide the button, not to gate a background behavior.
            Keys.readbackEnabled: true,
            // [decision input-felt-speed §3.2/§3.3] Default true: showing the raw
            // transcript in the HUD during cleanup is strictly additive to what the
            // user already sees while listening — no new capability, no privacy cost,
            // just not hiding text we already have. OFF reproduces the pre-slice
            // spinner-only `.processing` view exactly.
            Keys.revealTextWhileProcessing: true,
            Keys.petEnabled: false,
            Keys.ttsVoiceIdentifier: "",
            Keys.ttsSpeechRate: AVSpeechUtteranceDefaultSpeechRate,
            Keys.ttsPitchMultiplier: Float(1.0),
            Keys.ttsVolume: Float(1.0)
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

    // MARK: - Voice Actions (H-1) & VoiceOut (H-2) — see extension below ([lint] type_body_length)

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
        access(keyPath: \.borderAnimationStyle)
        access(keyPath: \.borderFlowSpeed)
        access(keyPath: \.borderFlowCount)
        access(keyPath: \.voiceActionsEnabled)
        access(keyPath: \.voiceActionsPrefix)
        access(keyPath: \.readbackEnabled)

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
        withMutation(keyPath: \.borderAnimationStyle) {
            defaults.set(BorderAnimationStyle.none.rawValue, forKey: Keys.borderAnimationStyle)
        }
        withMutation(keyPath: \.borderFlowSpeed) {
            defaults.set(BorderFlowSpeed.medium.rawValue, forKey: Keys.borderFlowSpeed)
        }
        withMutation(keyPath: \.borderFlowCount) {
            defaults.set(1, forKey: Keys.borderFlowCount)
        }
        withMutation(keyPath: \.voiceActionsEnabled) {
            defaults.set(false, forKey: Keys.voiceActionsEnabled)
        }
        withMutation(keyPath: \.voiceActionsPrefix) {
            defaults.set("hey speak", forKey: Keys.voiceActionsPrefix)
        }
        withMutation(keyPath: \.readbackEnabled) {
            defaults.set(true, forKey: Keys.readbackEnabled)
        }
        withMutation(keyPath: \.petEnabled) {
            defaults.set(true, forKey: Keys.petEnabled)
        }
        withMutation(keyPath: \.ttsVoiceIdentifier) {
            defaults.set("", forKey: Keys.ttsVoiceIdentifier)
        }
        withMutation(keyPath: \.ttsSpeechRate) {
            defaults.set(AVSpeechUtteranceDefaultSpeechRate, forKey: Keys.ttsSpeechRate)
        }
        withMutation(keyPath: \.ttsPitchMultiplier) {
            defaults.set(Float(1.0), forKey: Keys.ttsPitchMultiplier)
        }
        withMutation(keyPath: \.ttsVolume) {
            defaults.set(Float(1.0), forKey: Keys.ttsVolume)
        }

        SpeakLog.storage.info("SettingsStore reset to defaults")
    }
}

// MARK: - Voice Actions (H-1) + VoiceOut readback (H-2)
// Computed properties moved out of the class body to hold SwiftLint's
// type_body_length cap — pure code motion, same file so the @Observable
// macro's access/withMutation members remain reachable.
extension SettingsStore {
    // MARK: - Streaming settings (keystroke injection)

    /// Whether raw (unprocessed) text is streamed character-by-character during dictation
    /// when `streamingMode == .keystrokeInjection`.
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

    /// Whether keystroke injection (real-time text delivery) is active. Default: `.keystrokeInjection`.
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

    // MARK: - Border animation settings

    /// Border animation style for the overlay panel. Default: `.none`.
    public var borderAnimationStyle: BorderAnimationStyle {
        get {
            access(keyPath: \.borderAnimationStyle)
            let raw = defaults.string(forKey: Keys.borderAnimationStyle) ?? BorderAnimationStyle.none.rawValue
            return BorderAnimationStyle(rawValue: raw) ?? .none
        }
        set {
            withMutation(keyPath: \.borderAnimationStyle) {
                defaults.set(newValue.rawValue, forKey: Keys.borderAnimationStyle)
            }
        }
    }

    /// Speed of the EdgeFlow border animation. Default: `.medium`.
    public var borderFlowSpeed: BorderFlowSpeed {
        get {
            access(keyPath: \.borderFlowSpeed)
            let raw = defaults.string(forKey: Keys.borderFlowSpeed) ?? BorderFlowSpeed.medium.rawValue
            return BorderFlowSpeed(rawValue: raw) ?? .medium
        }
        set {
            withMutation(keyPath: \.borderFlowSpeed) {
                defaults.set(newValue.rawValue, forKey: Keys.borderFlowSpeed)
            }
        }
    }

    /// Number of flowing light blobs in EdgeFlow animation (1...3). Default: `1`.
    public var borderFlowCount: Int {
        get {
            access(keyPath: \.borderFlowCount)
            let val = defaults.integer(forKey: Keys.borderFlowCount)
            return (1...3).contains(val) ? val : 1
        }
        set {
            withMutation(keyPath: \.borderFlowCount) {
                let clamped = min(max(newValue, 1), 3)
                defaults.set(clamped, forKey: Keys.borderFlowCount)
            }
        }
    }

    // MARK: - Per-app context awareness (V01-3, profile-native)

    /// Whether the frontmost app influences which profile runs the cleanup pass
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

    // MARK: - VoiceOut readback (H-2)

    /// Whether the "Read back" (speaker.wave.2) affordance appears in the `.done`
    /// overlay state. Default `true`. The button itself is inert until pressed —
    /// this toggle only controls whether it's shown, not a background behavior.
    /// `false` hides the button entirely (no `SpeechSynthesizing` call is ever made).
    public var readbackEnabled: Bool {
        get {
            access(keyPath: \.readbackEnabled)
            return defaults.bool(forKey: Keys.readbackEnabled)
        }
        set {
            withMutation(keyPath: \.readbackEnabled) {
                defaults.set(newValue, forKey: Keys.readbackEnabled)
            }
        }
    }

    /// [input-felt-speed §3.2/§3.3] Whether the `.processing` HUD state shows the raw
    /// transcript (dimmed, marked as settling) instead of only a spinner + "Cleaning
    /// up…"/"Pasting…" label. Read directly by `TranscriptOverlayView` on every render
    /// (not cached), so a Settings change takes effect on the very next dictation.
    ///
    /// This is progressive reveal, NOT the two-phase optimistic-paste design from
    /// `specs/input-felt-speed.md` §3 — the paste itself is untouched and still
    /// happens exactly once, after cleanup returns, inside `SpeakEngine.endDictation()`.
    /// Default `true`. `false` reproduces the exact pre-slice spinner-only view.
    public var revealTextWhileProcessing: Bool {
        get {
            access(keyPath: \.revealTextWhileProcessing)
            return defaults.bool(forKey: Keys.revealTextWhileProcessing)
        }
        set {
            withMutation(keyPath: \.revealTextWhileProcessing) {
                defaults.set(newValue, forKey: Keys.revealTextWhileProcessing)
            }
        }
    }

    /// FE-1: Voice Desktop Pet the pet enabled state. Controls whether the floating 56x36pt
    /// edge-snapping mascot lozenge (`PetPanelController`) is visible.
    /// Defaults to `true` (always-on companion).
    public var petEnabled: Bool {
        get {
            access(keyPath: \.petEnabled)
            return defaults.object(forKey: Keys.petEnabled) as? Bool ?? false
        }
        set {
            withMutation(keyPath: \.petEnabled) {
                defaults.set(newValue, forKey: Keys.petEnabled)
            }
        }
    }

    /// Voice Desktop Pet's last dragged-to position, keyed by display UUID (spec §5:
    /// "position persisted per display UUID in SettingsStore"). JSON-encoded,
    /// same pattern as `cleanupEngine`/`sttEngine` — `CGPoint` is `Codable` on
    /// Apple platforms so no custom coding is needed.
    public var petPositions: [String: CGPoint] {
        get {
            access(keyPath: \.petPositions)
            guard let data = defaults.data(forKey: Keys.petPositions),
                  let decoded = try? JSONDecoder().decode([String: CGPoint].self, from: data) else {
                return [:]
            }
            return decoded
        }
        set {
            withMutation(keyPath: \.petPositions) {
                if let data = try? JSONEncoder().encode(newValue) {
                    defaults.set(data, forKey: Keys.petPositions)
                } else {
                    SpeakLog.storage.error("SettingsStore: failed to encode petPositions — value not persisted.")
                }
            }
        }
    }

    // MARK: - TTS Voice Settings

    /// Selected TTS voice identifier (e.g. `com.apple.speech.synthesis.voice.samantha`). Empty string = system default.
    public var ttsVoiceIdentifier: String {
        get {
            access(keyPath: \.ttsVoiceIdentifier)
            return defaults.string(forKey: Keys.ttsVoiceIdentifier) ?? ""
        }
        set {
            withMutation(keyPath: \.ttsVoiceIdentifier) {
                defaults.set(newValue, forKey: Keys.ttsVoiceIdentifier)
            }
        }
    }

    /// TTS speech rate multiplier (0.1 to 1.0, default: `AVSpeechUtteranceDefaultSpeechRate` ~0.5).
    public var ttsSpeechRate: Float {
        get {
            access(keyPath: \.ttsSpeechRate)
            let val = defaults.float(forKey: Keys.ttsSpeechRate)
            return val > 0 ? val : AVSpeechUtteranceDefaultSpeechRate
        }
        set {
            withMutation(keyPath: \.ttsSpeechRate) {
                defaults.set(newValue, forKey: Keys.ttsSpeechRate)
            }
        }
    }

    /// TTS pitch multiplier (0.5 to 2.0, default: 1.0).
    public var ttsPitchMultiplier: Float {
        get {
            access(keyPath: \.ttsPitchMultiplier)
            let val = defaults.float(forKey: Keys.ttsPitchMultiplier)
            return val > 0 ? val : 1.0
        }
        set {
            withMutation(keyPath: \.ttsPitchMultiplier) {
                defaults.set(newValue, forKey: Keys.ttsPitchMultiplier)
            }
        }
    }

    /// TTS volume (0.0 to 1.0, default: 1.0).
    public var ttsVolume: Float {
        get {
            access(keyPath: \.ttsVolume)
            if defaults.object(forKey: Keys.ttsVolume) == nil {
                return 1.0
            }
            return defaults.float(forKey: Keys.ttsVolume)
        }
        set {
            withMutation(keyPath: \.ttsVolume) {
                defaults.set(newValue, forKey: Keys.ttsVolume)
            }
        }
    }
}
