// SpeakCore/Engine/CaptureSession+Paste.swift
//
// Paste delivery step for CaptureSession. Extracted from CaptureSession.swift
// (pure reorganization — zero logic changes).
//
// runPaste(_:) is `internal` (not `private`) so stop() in CaptureSession.swift
// can call it across files within the same module.

import Foundation
import os

extension CaptureSession {

    /// Paste step (P6): deliver the final text to the cursor (if not streaming).
    ///
    /// Contract:
    /// - When `streamingInserter` is nil: call `inserter.insert(cleanedText ?? rawText)`
    ///   if an inserter was injected. This is the standard final-paste path.
    /// - When `streamingInserter` is non-nil: skip the final paste. Raw text has already
    ///   been streamed character-by-character via keystroke injection during listening
    ///   (the in-document deliverable). Cleaned text runs in the background (for history,
    ///   latency stats, quality) but is NOT re-pasted to avoid duplication. [decision P11-c]
    ///
    /// Text selection rule per architecture §11: `cleanedText ?? rawText`.
    /// (Cleanup-unavailable already produced cleanedText=nil, so the raw
    ///  transcript is used — the graceful-fallback contract is preserved.)
    ///
    /// If paste throws, the session transitions to `.error` (paste is the
    /// delivery; if it fails, the dictation has not landed at the cursor).
    ///
    /// No-op when `inserter == nil` or when `streamingInserter != nil`.
    func runPaste(_ result: TranscriptionResult) async throws {
        // When streaming is enabled, raw text has already been delivered via keystroke
        // injection. Skip the final paste to avoid duplication. [P11-c option D]
        if streamingInserter != nil {
            SpeakLog.engine.info(
                "CaptureSession: streaming enabled — skipping final paste (raw already streamed)."
            )
            return
        }

        guard let inserter = inserter else { return }
        let textToInsert = result.cleanedText ?? result.rawText
        do {
            try await inserter.insert(textToInsert)
        } catch {
            let speakError = (error as? SpeakError) ?? .pasteboardBusy
            SpeakLog.engine.error(
                "CaptureSession: paste failed — \(speakError.recoverySuggestion, privacy: .public)"
            )
            state = .error(speakError)
            partialsContinuation?.finish()
            partialsContinuation = nil
            streamTask = nil
            throw speakError
        }
    }
}
