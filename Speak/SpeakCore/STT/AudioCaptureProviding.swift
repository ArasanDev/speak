// SpeakCore/STT/AudioCaptureProviding.swift
//
// W2.1: A narrow protocol that lets `CaptureSession` access the live `AudioCapture`
// instance inside a transcriber — for the purpose of tapping its level stream only.
//
// DESIGN RATIONALE:
//   `Transcribing` deliberately has no audio channel (pluggability). The level
//   feed is a HUD-only side concern that should not pollute the STT protocol.
//   `AudioCaptureProviding` is the narrowest seam: only `AppleSpeechTranscriber`
//   conforms (it owns the live `AudioCapture`). `CaptureSession.levels()` checks
//   for this protocol via `as?` — no change to any other transcriber.
//
// [decision W2.1: narrow conformance over protocol widening; `as?` check keeps
//  the Transcribing protocol clean. Test transcrbers are unaffected.]

import Foundation

/// Implemented by transcrbibers that expose their underlying `AudioCapture`
/// so that `CaptureSession` can tap the live level stream (W2.1).
/// The `audioCapture` property is `nil` when a test fixture is in use.
public protocol AudioCaptureProviding: AnyObject {
    /// The live `AudioCapture` instance, if any. `nil` for fixture producers.
    var audioCapture: AudioCapture? { get }
}
