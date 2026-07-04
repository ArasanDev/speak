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
}
