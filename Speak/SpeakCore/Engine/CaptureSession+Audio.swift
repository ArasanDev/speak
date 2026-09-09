// SpeakCore/Engine/CaptureSession+Audio.swift
//
// Audio capture and stream side-channel access for CaptureSession.
// Extracted from CaptureSession.swift to maintain clean module boundaries
// and preserve strict file length limits (<800 lines).

import Foundation

extension CaptureSession {

    // MARK: - W2.1: Level stream (consumed by the overlay HUD waveform)

    /// The `AudioCapture` instance providing both the PCM buffer stream (to the
    /// transcriber) and the live level stream (to the HUD). Stored so we can
    /// call `startLevelStream()` after `start()` initiates capture.
    ///
    /// Injected via `levels()` — the transcriber owns the capture object but the
    /// level stream is a parallel read-only side channel. We hold a weak reference
    /// only if the transcriber exposes it; see the note in `levels()` below.
    ///
    /// [decision W2.1: level stream is threaded through the transcriber's AudioCapture.
    ///  We call `transcriber.audioCapture?.startLevelStream()` when available.
    ///  AppleSpeechTranscriber exposes its AudioCapture for this purpose.]
    public func levels() -> AsyncStream<Double>? {
        // The level stream is produced by AudioCapture inside the transcriber.
        // `Transcribing` does not expose `audioCapture` in the protocol — only
        // `AppleSpeechTranscriber` does. We use protocol-existential type checking
        // here, which is the narrowest possible coupling: this stays in CaptureSession
        // (the session's own start() already called transcriber.startStream), so the
        // AudioCapture is already running.
        if let sttTranscriber = transcriber as? AudioCaptureProviding {
            return sttTranscriber.audioCapture?.startLevelStream()
        }
        return nil
    }

    // MARK: - VAD attachment (output-conversation-reconnect)

    /// Attaches (or, passing `nil`, detaches) a `VoiceActivityDetector` to the
    /// live `AudioCapture` behind this session's transcriber, mirroring the
    /// `levels()` seam above: same `AudioCaptureProviding` cast, same narrow
    /// coupling, no change to `Transcribing` or any other transcriber.
    ///
    /// Returns `true` if an `AudioCapture` was found to attach to, `false`
    /// otherwise (e.g. a test fixture transcriber with no live capture).
    @discardableResult
    public func attachVoiceActivityDetector(_ vad: VoiceActivityDetector?) -> Bool {
        guard let sttTranscriber = transcriber as? AudioCaptureProviding,
              let audioCapture = sttTranscriber.audioCapture else {
            return false
        }
        audioCapture.attachVoiceActivityDetector(vad)
        return true
    }
}
