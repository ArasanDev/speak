// SpeakCore/Storage/SettingsStore.swift
//
// Typed UserDefaults wrapper for all user-configurable `speak` settings.
//
// DESIGN:
//   - `@unchecked Sendable` (NOT `@MainActor`): properties are computed over an
//     injected `UserDefaults` instance, which is documented thread-safe by Apple.
//     This lets `SpeakEngine` (an actor) read `settings.cleanupEnabled` etc.
//     synchronously without a cross-actor `await`.
//   - `ObservableObject`: SwiftUI views bind to this directly via `@ObservedObject`
//     or `@EnvironmentObject`. Setters send `objectWillChange` before mutating so
//     Combine/SwiftUI re-renders on every property write.
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
import Combine
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

/// Which AI cleanup engine to use. v0 = `.foundationModels`. v0.1+ are placeholders.
public enum CleanupEngine: Codable, Sendable, Equatable, Hashable {
    /// Apple Foundation Models (macOS 26+, Apple Silicon + Neural Engine). **v0 default.**
    case foundationModels
    /// Ollama local server (Qwen 2.5, Gemma 3, Phi-4-mini…). **v0.1 placeholder (not built).**
    case ollama(model: String)
}

/// How finished text is delivered to the cursor. v0 = `.cmdV`.
public enum PasteMode: String, Codable, Sendable, Equatable {
    /// Simulate Cmd+V via `CGEventTap`. **v0 default.** Fast; works in most apps.
    case cmdV
    /// Accessibility API insertion (AXUIElement). **v1 placeholder** — avoids paste-provenance
    /// issues in Terminal on macOS 26.4+, but requires an extra Accessibility call.
    case accessibility
}

// MARK: - SettingsStore

/// The single source of truth for all persisted user preferences in `speak`.
///
/// Inject into the SwiftUI environment and read from `SpeakEngine` actors;
/// do not access `UserDefaults.standard` directly anywhere else.
public final class SettingsStore: ObservableObject, @unchecked Sendable {

    // MARK: - UserDefaults key namespace

    private enum Keys {
        // Prefix matches the bundle id convention; stable across versions.
        static let cleanupEnabled        = "speak.settings.cleanupEnabled"
        static let cleanupEngine         = "speak.settings.cleanupEngine"
        static let sttEngine             = "speak.settings.sttEngine"
        static let language              = "speak.settings.language"
        static let pasteMode             = "speak.settings.pasteMode"
        static let hasCompletedOnboarding = "speak.settings.hasCompletedOnboarding"
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
        get { defaults.bool(forKey: Keys.cleanupEnabled) }
        set {
            objectWillChange.send()
            defaults.set(newValue, forKey: Keys.cleanupEnabled)
        }
    }

    // MARK: - Cleanup engine

    /// Which LLM cleanup engine to use when `cleanupEnabled == true`.
    /// Default: `.foundationModels`.
    public var cleanupEngine: CleanupEngine {
        get {
            guard let data = defaults.data(forKey: Keys.cleanupEngine),
                  let decoded = try? JSONDecoder().decode(CleanupEngine.self, from: data) else {
                return .foundationModels   // v0 default
            }
            return decoded
        }
        set {
            objectWillChange.send()
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: Keys.cleanupEngine)
            } else {
                SpeakLog.storage.error("SettingsStore: failed to encode cleanupEngine — value not persisted.")
            }
        }
    }

    // MARK: - STT engine

    /// Which speech-to-text engine to use.
    /// Default: `.appleSpeech` (SpeechAnalyzer, zero-cost, on-device).
    public var sttEngine: STTEngine {
        get {
            guard let data = defaults.data(forKey: Keys.sttEngine),
                  let decoded = try? JSONDecoder().decode(STTEngine.self, from: data) else {
                return .appleSpeech   // v0 default
            }
            return decoded
        }
        set {
            objectWillChange.send()
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: Keys.sttEngine)
            } else {
                SpeakLog.storage.error("SettingsStore: failed to encode sttEngine — value not persisted.")
            }
        }
    }

    // MARK: - Language / locale

    /// The transcription locale. Default: `en-US`. `en-GB` is also surfaced in the UI.
    ///
    /// Stored as the locale's `identifier` string (e.g., `"en-US"`).
    public var language: Locale {
        get {
            let id = defaults.string(forKey: Keys.language) ?? "en-US"
            return Locale(identifier: id)
        }
        set {
            objectWillChange.send()
            defaults.set(newValue.identifier, forKey: Keys.language)
        }
    }

    // MARK: - Onboarding completion flag

    /// `true` once the user has completed (or deliberately skipped) the
    /// first-run onboarding flow. When `false`, the onboarding window is
    /// presented on launch. Defaults to `false` so a fresh install always shows
    /// onboarding. [decision: false default — new installs must onboard]
    public var hasCompletedOnboarding: Bool {
        get { defaults.bool(forKey: Keys.hasCompletedOnboarding) }
        set {
            objectWillChange.send()
            defaults.set(newValue, forKey: Keys.hasCompletedOnboarding)
            SpeakLog.storage.info(
                "SettingsStore: hasCompletedOnboarding → \(newValue, privacy: .public)"
            )
        }
    }

    // MARK: - Paste mode

    /// How finished text is inserted at the cursor.
    /// Default: `.cmdV` (simulate Cmd+V via CGEventTap).
    public var pasteMode: PasteMode {
        get {
            let raw = defaults.string(forKey: Keys.pasteMode) ?? PasteMode.cmdV.rawValue
            return PasteMode(rawValue: raw) ?? .cmdV
        }
        set {
            objectWillChange.send()
            defaults.set(newValue.rawValue, forKey: Keys.pasteMode)
        }
    }
}
