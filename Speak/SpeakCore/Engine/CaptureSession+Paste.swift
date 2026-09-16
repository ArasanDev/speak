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

    /// Paste step (P6): deliver the final text to the cursor.
    ///
    /// Contract: The final AI text (cleanedText ?? rawText) is ALWAYS pasted when an
    /// inserter is wired. Raw text is never inserted into the document — only the final
    /// AI text is the delivery. [P0.1 / task #29]
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
        let baseText = result.cleanedText ?? result.rawText
        guard !baseText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let isCleaned = result.cleanedText != nil
        let prefixToUse: String
        if agentPrefixStyle != .none {
            prefixToUse = agentPrefixStyle.formattedPrefix(isCleaned: isCleaned, includeState: agentPrefixIncludeState)
        } else {
            prefixToUse = agentPrefix
        }
        let textToInsert = prefixToUse.isEmpty ? baseText : "\(prefixToUse)\(baseText)"
        // [fix: audit — C2/H1 cancel-during-paste] Hand the inserter the session's
        // off-actor cancel flag as a continuation predicate. `PasteboardWriter`
        // consults it after the settle delay and before posting Cmd+V, so a
        // cancel() that lands mid-paste suppresses the keystroke instead of
        // pasting against the user's intent.
        let flag = cancelRequestedFlag
        do {
            try await inserter.insert(textToInsert) {
                !flag.withLock { $0 }
            }
        } catch {
            // Never overwrite an existing terminal error — a `.sessionCancelled`
            // set by cancel() while the inserter was suspended wins over whatever
            // the inserter threw (including its own .sessionCancelled on the
            // predicate path above).
            if case .error(let existing) = state {
                throw existing
            }
            // [fix: audit — error mapping] CancellationError is a cancellation
            // signal, not a busy pasteboard; map it to .sessionCancelled so the
            // app shell treats it as a user-intent abort, not a transient fault.
            let speakError: SpeakError
            if let speakErr = error as? SpeakError {
                speakError = speakErr
            } else if error is CancellationError {
                speakError = .sessionCancelled
            } else {
                speakError = .pasteboardBusy
            }
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
