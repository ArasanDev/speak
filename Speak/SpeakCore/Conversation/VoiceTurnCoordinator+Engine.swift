// SpeakCore/Conversation/VoiceTurnCoordinator+Engine.swift
//
// Conforms the real engine to the four verbs a voice turn needs.
//
// Kept apart from `VoiceTurnCoordinator` so the coordinator's tests never link
// against a microphone, a speech model, or a TCC grant — the seam is the point.
//
// Note what is NOT here: no new capture mode, no format renegotiation, no change
// to how dictation starts or stops. Every call below is a verb the daily
// dictation path already exercises. A conversation turn is the same capture with
// paste suppressed and a detector attached.

import Foundation

extension SpeakEngine: VoiceTurnCapturing {

    public func beginTurnCapture() async throws {
        // `beginDictation()` RETURNS FALSE — it does not throw — when a session is
        // already in flight (SpeakEngine.swift:570, the [A3] re-entrancy guard).
        // Discarding that would be the one regression this whole path must not
        // have: the coordinator would attach its detector to the *human's* live
        // dictation, and `finalizeTurnCapture()` would then end that dictation and
        // consume its transcript with paste suppressed — the user's words would
        // vanish mid-sentence. An agent turn must never adopt a session it did not
        // open, so a refusal is an error here even though it is benign at the CLI.
        guard try await beginDictation() else {
            throw SpeakError.unknown("a dictation session is already in flight; agent turn refused")
        }
        // Suppression follows `beginDictation()`, matching the two existing
        // production call sites (DictationController+CLI.swift:174, :410). Text can
        // only be produced once audio has been transcribed, which is far downstream
        // of the actor hop above — a conversation turn is heard, not pasted.
        await suppressPasteForAgentResponse()
    }

    @discardableResult
    public func attachTurnDetector(_ detector: VoiceActivityDetector?) async -> Bool {
        await attachVoiceActivityDetector(detector)
    }

    public func finalizeTurnCapture() async throws -> String {
        // `endDictation()` is the flush: it drives `session.stop()`, which
        // finalizes the STT stream and returns the completed transcript. Reusing
        // it rather than adding a finalize path means the mechanism the turn
        // depends on is the one exercised by every dictation, every day.
        let result = try await endDictation()
        // Raw, not cleaned. Cleanup rewrites text for a human reader — it is the
        // wrong transformation for a prompt that a model is about to act on, and
        // it would add its own latency to a turn measured in hundreds of ms.
        return result.rawText
    }

    public func cancelTurnCapture() async {
        await cancelDictation()
    }
}
