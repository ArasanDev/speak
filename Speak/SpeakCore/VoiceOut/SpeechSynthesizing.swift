// SpeakCore/VoiceOut/SpeechSynthesizing.swift
//
// The text-to-speech seam (Pillar 2 — "the conversational loop", H-2 in
// specs/horizon-voice-os.md). Conformers turn text into on-device speech.
//
// v0 conformer: `AppleSpeechSynthesizer` (AVSpeechSynthesizer). Mirrors the
// shape of the other engine seams (`Transcribing`, `LLMCleaning`, `TextInserting`):
// a narrow protocol so higher layers (`DictationController`) depend on behavior,
// not on AVFoundation directly — keeping `SpeakCore` the portability seam.
//
// [decision H-2] `speak(_:locale:)` takes a `Locale` parameter rather than baking
// one in at init — mirrors `Transcribing.startStream(locale:)`. The locale is
// read from `SettingsStore.language` at call time by the caller (the same
// "settings-at-call-time" pattern `SpeakEngine.newSession()` already uses), so a
// language change takes effect on the next readback without recreating the
// synthesizer.
//
// [decision H-2] `speak(_:locale:)` suspends until speech completes (naturally,
// or via `stop()`). This lets a caller `await` a readback the same way it awaits
// `LLMCleaning.clean(_:mode:)` — no separate "is it done yet" polling — while
// `stop()` remains the interruption entry point per the horizon spec's
// "any hotkey press cuts TTS instantly" requirement.

import Foundation

public protocol SpeechSynthesizing: Sendable {
    /// Speak `text` aloud in `locale`. Returns once speech has finished — either
    /// it played to completion, or `stop()` cut it short. A caller that only
    /// wants to fire-and-forget can ignore the `await`'s completion; a caller
    /// that wants to serialize (e.g. don't start a new dictation while a
    /// previous readback's audio is still draining) can `await` it directly.
    ///
    /// If speech is already in progress when this is called, the conformer
    /// stops the current utterance first — utterances never overlap.
    /// A `text` that trims to empty is a no-op (returns immediately).
    func speak(_ text: String, locale: Locale) async

    /// Stop any in-progress speech immediately. Safe to call when not
    /// speaking (no-op). Any `speak(_:locale:)` call currently awaiting
    /// completion returns promptly once stopped.
    func stop() async

    /// Whether speech is currently in progress.
    var isSpeaking: Bool { get async }
}
