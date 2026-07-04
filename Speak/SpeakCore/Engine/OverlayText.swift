// SpeakCore/Engine/OverlayText.swift
//
// Pure, headlessly-testable accumulation logic for the partial-transcript overlay.
//
// The overlay rule: display the *newest non-empty* partial text received from the
// live STT stream. An empty chunk (the transcriber momentarily returns "") is
// treated as "no update" — the last non-empty text stays displayed. This prevents
// a blank flash when the transcriber resets its hypothesis mid-utterance.
//
// Why a named type?  The rule is tiny today (two branches), but it is the tested
// seam between `CaptureSession.partials()` and the overlay view. Naming it lets
// `OverlayTextTests.swift` exercise it without any AppKit or SwiftUI dependency.
//
// Threading: all callers are @MainActor (DictationController drives the task that
// calls `next`); the function itself is pure / stateless.

import Foundation

/// Maintains the overlay's displayed partial text.
///
/// Semantics:
/// - Start: display text is `""` (the view shows a "Listening…" placeholder).
/// - Each chunk: if `chunk.text` is non-empty, it becomes the displayed text;
///   empty chunks are ignored (newest-non-empty-wins rule).
/// - On end/error: caller resets to `""`.
///
/// The type is a lightweight value struct so it is trivially `Sendable` and
/// safe to copy in tests.
public struct OverlayTextAccumulator: Sendable {

    /// The text currently shown in the overlay. Empty = "no speech yet".
    public private(set) var displayText: String = ""

    public init() {}

    /// Incorporate the next chunk from the partial stream.
    ///
    /// - Parameter chunk: A `TranscriptChunk` from `CaptureSession.partials()`.
    /// - Returns: `self` after applying the newest-non-empty rule.
    @discardableResult
    public mutating func next(_ chunk: TranscriptChunk) -> String {
        // Newest-non-empty rule: if the incoming text is empty, keep the
        // current display text unchanged to avoid a blank flash.
        if !chunk.text.isEmpty {
            displayText = chunk.text
        }
        return displayText
    }

    /// Reset to the initial (empty) state. Called when dictation ends or errors.
    public mutating func reset() {
        displayText = ""
    }
}
