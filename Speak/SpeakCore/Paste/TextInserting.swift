// SpeakCore/Paste/TextInserting.swift
//
// The paste-seam abstraction (architecture.md §11, roadmap P6).
// `CaptureSession` calls this after the cleanup pass; the real AppKit
// implementation (`PasteboardWriter`) lives in the same module. Tests inject
// a mock conformer so the session can be exercised without real NSPasteboard /
// CGEvent calls.
//
// Hard rule: conformers WRITE to the pasteboard and simulate Cmd+V.
// They NEVER read the pasteboard. macOS 26.4 paste-protection (architecture §11)
// triggers a permission prompt on pasteboard reads; writes are exempt.

import Foundation

/// A pasteboard-write + Cmd+V paste pipeline, abstracted for testability.
///
/// `CaptureSession` holds an optional `(any TextInserting)?`; when non-nil,
/// `insert(_:)` is called just before the session reaches `.done`.
///
/// Thread safety: `Sendable` so the session actor can store and call it
/// across suspension points without isolation warnings.
public protocol TextInserting: Sendable {
    /// Write `text` to the system pasteboard and simulate Cmd+V to paste it
    /// into the frontmost application at the current cursor position.
    ///
    /// - Parameter text: The final text to paste (`cleanedText ?? rawText` per
    ///   architecture §11 line 341).
    /// - Throws: `SpeakError.pasteboardBusy` if the CGEvent machinery cannot
    ///   be constructed (nil `CGEventSource` or nil `CGEvent`). A successful
    ///   write+Cmd+V that lands silently in a password field does **not** throw
    ///   — that case cannot be detected without reading the pasteboard (hard
    ///   rule violation), so it is a `[deferred — needs human verification]` row.
    func insert(_ text: String) async throws

    /// Cancellation-aware variant of `insert(_:)`.
    ///
    /// `shouldContinue` is consulted at the points where proceeding would
    /// commit a user-visible paste — in `PasteboardWriter`, after the settle
    /// delay, before the Cmd+V sequence starts, and between its events.
    /// Returning `false`
    /// throws `SpeakError.sessionCancelled` (never `.pasteboardBusy`); the
    /// clipboard floor write may already have run, which is by design — the
    /// text stays recoverable from the clipboard even when the keystroke is
    /// suppressed. [fix: audit — cancel-during-paste]
    ///
    /// - Parameter shouldContinue: Called on the insert path; must return
    ///   `false` when the owning session was cancelled.
    /// - Throws: `SpeakError.sessionCancelled` when `shouldContinue()` is false.
    func insert(_ text: String, shouldContinue: @Sendable () -> Bool) async throws
}

public extension TextInserting {
    /// Default: consult the predicate once, up front, then run the plain insert.
    /// Conformers with internal suspension points (settle delays, event gaps)
    /// should override and re-check `shouldContinue` there — the front check
    /// alone cannot catch a cancel that lands mid-insert.
    func insert(_ text: String, shouldContinue: @Sendable () -> Bool) async throws {
        guard shouldContinue() else { throw SpeakError.sessionCancelled }
        try await insert(text)
    }
}
