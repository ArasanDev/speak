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
        _ = try await beginDictation()
        // Suppress before any text can be produced. A conversation turn is heard,
        // not pasted; without this the human's answer to an agent would be typed
        // into whatever window happens to be frontmost.
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
