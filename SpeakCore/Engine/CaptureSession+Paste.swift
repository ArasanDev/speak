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

    /// Paste step (P6): if an inserter was injected, deliver the final text.
    ///
    /// Text selection rule per architecture §11: `cleanedText ?? rawText`.
    /// (Cleanup-unavailable already produced cleanedText=nil, so the raw
    ///  transcript is used — the graceful-fallback contract is preserved.)
    ///
    /// If paste throws, the session transitions to `.error` (paste is the
    /// delivery; if it fails, the dictation has not landed at the cursor).
    ///
    /// No-op when `inserter == nil`.
    func runPaste(_ result: TranscriptionResult) async throws {
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
