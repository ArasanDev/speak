// SpeakCore/VoiceOut/AppleSpeechSynthesizer.swift
//
// The v0 conformer of `SpeechSynthesizing`: on-device text-to-speech via
// `AVSpeechSynthesizer` (Apple, zero network — consistent with the 100%-local
// contract). H-2 in specs/horizon-voice-os.md.
//
// API surface (`AVSpeechSynthesizer`/`AVSpeechUtterance`/`AVSpeechSynthesisVoice`,
// `stopSpeaking(at:)`, the delegate's `didFinish`/`didCancel`) is
// [verified via swiftc -typecheck against the local macOS 26 SDK, 2026-07-06] —
// also independently typecheck-confirmed by the horizon validator
// (specs/horizon-voice-os.md "Validation results").
//
// DESIGN:
//   - `actor` (matches the `Transcribing`/`LLMCleaning` conformers' concurrency
//     model — actor-isolated state, no manual locking).
//   - Swift actors cannot subclass `NSObject`, and `AVSpeechSynthesizerDelegate`
//     requires an `NSObject` conformer, so a small plain-class bridge
//     (`SpeechSynthesizerDelegateBridge`) forwards delegate callbacks back onto
//     the actor via a `Task`.
//   - `speak(_:locale:)` suspends on a `CheckedContinuation` that the bridge
//     resumes on `didFinish` OR `didCancel` — both mean "this utterance is
//     over," which is exactly what `stop()`'s interruption contract needs:
//     an awaiting caller returns promptly either way.
//   - Personal Voice / voice-quality fallback chain (personal → premium →
//     enhanced → default, per the horizon spec) is deferred past this slice:
//     `AVSpeechSynthesisVoice(language:)` already resolves the best installed
//     voice for the locale. [decision H-2: keep the first vertical slice small
//     — the seam + instant-interruption contract is the deliverable; richer
//     voice selection is a follow-up, not required by the "read that back"
//     demo.]
//   - Live audio output/latency is [deferred — needs human verification],
//     matching the rest of the engine's honesty boundary (no CI runs real
//     audio hardware).

import AVFoundation
import Foundation

// MARK: - SpeechSynthesizerDelegateBridge

/// Forwards `AVSpeechSynthesizerDelegate` callbacks (which arrive off the
/// `AppleSpeechSynthesizer` actor, on whatever thread AVFoundation chooses)
/// into the actor via a `@Sendable` closure captured at init.
private final class SpeechSynthesizerDelegateBridge: NSObject, AVSpeechSynthesizerDelegate {
    /// Fired on `didFinish` (utterance played to completion) or `didCancel`
    /// (cut short by `stopSpeaking(at:)`) — both mean "this utterance is over."
    var onUtteranceEnded: (@Sendable () -> Void)?

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        onUtteranceEnded?()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        onUtteranceEnded?()
    }
}

// MARK: - AppleSpeechSynthesizer

/// On-device TTS readback. One instance can be shared for the app's lifetime —
/// `speak(_:locale:)` calls never overlap (a new call stops whatever is
/// currently playing first).
public actor AppleSpeechSynthesizer: SpeechSynthesizing {

    public static let id = "apple-speech-synthesizer"

    private let synthesizer = AVSpeechSynthesizer()
    private let delegateBridge = SpeechSynthesizerDelegateBridge()

    /// Resumed by `finishSpeaking()` when the current utterance ends (naturally
    /// or via `stop()`). `nil` when idle.
    private var continuation: CheckedContinuation<Void, Never>?

    private var speaking = false

    public init() {
        synthesizer.delegate = delegateBridge
        // The bridge's callback arrives off-actor; hop back on via `Task`.
        // `[weak self]` avoids a retain cycle through
        // bridge → closure → actor → delegateBridge.
        delegateBridge.onUtteranceEnded = { [weak self] in
            Task { await self?.finishSpeaking() }
        }
    }

    // MARK: - SpeechSynthesizing

    public var isSpeaking: Bool { speaking }

    public func speak(_ text: String, locale: Locale) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            SpeakLog.voiceOut.info("AppleSpeechSynthesizer: speak() skipped — empty text.")
            return
        }
        // Never overlap utterances: interrupt whatever is currently playing.
        // (H-2: "any hotkey press cuts TTS instantly" — the same stop path a
        // new readback request takes.)
        if speaking {
            await stop()
        }

        let utterance = AVSpeechUtterance(string: trimmed)
        // Fall back to en-US if the requested locale has no installed voice
        // (e.g. a language pack the user hasn't downloaded) rather than
        // silently producing no audio.
        utterance.voice = AVSpeechSynthesisVoice(language: locale.identifier)
            ?? AVSpeechSynthesisVoice(language: "en-US")

        speaking = true
        SpeakLog.voiceOut.info("AppleSpeechSynthesizer: speak() — \(trimmed.count, privacy: .public) chars, locale=\(locale.identifier, privacy: .public).")
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            self.continuation = continuation
            synthesizer.speak(utterance)
        }
    }

    public func stop() async {
        guard speaking else { return }
        // `stopSpeaking(at: .immediate)` fires the delegate's `didCancel`
        // [verified via swiftc], which routes through `finishSpeaking()` below
        // and resumes any awaiting `speak(_:locale:)` caller.
        synthesizer.stopSpeaking(at: .immediate)
        SpeakLog.voiceOut.info("AppleSpeechSynthesizer: stop() — interrupted in-flight speech.")
    }

    // MARK: - Delegate bridge target

    /// Called when the current utterance ends, whether it finished naturally
    /// or was cut short by `stop()`. Resumes the continuation exactly once;
    /// guarded by `speaking` so a stray extra callback is a no-op, not a
    /// double-resume crash.
    private func finishSpeaking() {
        guard speaking else { return }
        speaking = false
        continuation?.resume()
        continuation = nil
    }
}
