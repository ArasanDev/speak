// App/DictationController+VoiceOut.swift
//
// H-2: VoiceOut readback (specs/horizon-voice-os.md Pillar 2 — "the conversational
// loop"). Wires the `.done` overlay's "Read back" button to `voiceOut`
// (`AppleSpeechSynthesizer`, SpeakCore/VoiceOut/) over the last finished transcript.
//
// `toggleReadback()` is intentionally the only entry point: a second press while
// speech is in flight stops it rather than restarting — the same "never overlap
// / interrupt instead" contract `beginDictation()` uses when a new dictation starts
// (see DictationController+ErrorHandling.swift).

import Foundation
import SpeakCore

extension DictationController {

    // MARK: - H-2 readback

    /// Speak `lastTranscript` aloud, or stop if a readback is already in flight.
    /// No-op when there is no transcript yet (before the first successful dictation).
    /// [decision H-2: toggle, not queue — matches the overlay button's single-affordance
    /// design; mirrors `recleanCurrentTranscript()`'s one-shot pattern in spirit, though
    /// this one is safely re-invocable (stop → speak again) rather than one-shot-only,
    /// since a stale press here has no cleanup side effect to double-fire.]
    func toggleReadback() {
        Task { [weak self] in
            guard let self else { return }
            if await self.voiceOut.isSpeaking {
                await self.voiceOut.stop()
                SpeakLog.voiceOut.info("DictationController: readback stopped (toggle).")
                return
            }
            let text = self.lastTranscript
            guard !text.isEmpty else {
                SpeakLog.voiceOut.info("DictationController: readback skipped — no transcript yet.")
                return
            }
            SpeakLog.voiceOut.info("DictationController: readback started — \(text.count, privacy: .public) chars.")
            await self.voiceOut.speak(text, locale: self.settingsStore.language)
        }
    }
}
