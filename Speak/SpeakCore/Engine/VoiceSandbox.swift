// SpeakCore/Engine/VoiceSandbox.swift
//
// The "Test My Voice" sandbox backing Settings ▸ AI Models: a real
// `CaptureSession` wired exactly like a live dictation (settings-derived
// locale, cleanup mode, vocabulary + acoustic-correction expander chain) but
// with `inserter: nil`, so `runPaste` is a no-op and the session settles to
// `.done` returning a paste-free `TranscriptionResult`.
//
// Why a factory and not a SpeakEngine path: `SpeakEngine`'s inserter is fixed
// at init and `newSession()` always wires it; the sandbox needs the same
// settings-driven session shape minus delivery. Composing `CaptureSession`
// directly reuses the verified state machine instead of forking it.
//
// Levels: when the resolved transcriber is `AppleSpeechTranscriber`, its
// `AudioCapture` level feed is unconsumed in a sandbox session (no HUD is
// attached) — `levelStream()` exposes it for the sandbox card's live meter.

import Foundation

public final class VoiceSandbox: Sendable {

    private let settings: SettingsStore
    private let snippetStore: SnippetStore?
    private let transcriber: any Transcribing
    private let cleaner: (any LLMCleaning)?

    /// Production wiring — resolves the transcriber and cleaner from
    /// `settings` via the same `defaultTranscriber`/`defaultCleaner` factories
    /// `SpeakEngine` uses, so the sandbox measures the real pipeline.
    public init(settings: SettingsStore, snippetStore: SnippetStore? = nil) {
        self.settings = settings
        self.snippetStore = snippetStore
        self.transcriber = defaultTranscriber(for: settings)
        self.cleaner = defaultCleaner(for: settings)
    }

    /// Test seam — explicit engines, same session wiring.
    public init(
        settings: SettingsStore,
        transcriber: any Transcribing,
        cleaner: (any LLMCleaning)?
    ) {
        self.settings = settings
        self.snippetStore = nil
        self.transcriber = transcriber
        self.cleaner = cleaner
    }

    /// Build a configured, unstarted session. Mirror of `SpeakEngine.newSession`
    /// for the global (non-profile) path: cleanup gated on
    /// `cleanupEnabled && cleanupLevel != .none`; expander = corrections then
    /// snippets; no voice-command preprocessor, no voice actions, no agent
    /// prefix — a sandbox run is a measurement, not a delivery.
    public func makeSession() -> CaptureSession {
        let levelIsNone = settings.cleanupLevel == .none
        let activeCleaner: (any LLMCleaning)? =
            (settings.cleanupEnabled && !levelIsNone) ? cleaner : nil
        return CaptureSession(
            transcriber: transcriber,
            cleaner: activeCleaner,
            inserter: nil,
            locale: settings.language,
            cleanupMode: .styled(
                settings.cleanupStyle,
                settings.cleanupLevel,
                customVocabulary: settings.effectiveVocabulary
            ),
            expander: defaultExpander(for: settings, snippetStore: snippetStore)
        )
    }

    /// The resolved transcriber's live mic-level stream (0…1 raw RMS), when it
    /// exposes one. Must be called after the session has started — the level
    /// stream is created by `AudioCapture.start()`, which runs inside
    /// `Transcribing.startStream`. Single-consumer: take it once.
    public func levelStream() -> AsyncStream<Double>? {
        (transcriber as? AppleSpeechTranscriber)?.audioCapture?.startLevelStream()
    }
}
