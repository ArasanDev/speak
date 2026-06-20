// SpeakCore/Paste/PasteboardWriter.swift
//
// Concrete `TextInserting` conformer. Implements architecture §11 verbatim:
//   1. `NSPasteboard.general.clearContents()` → `setString(_:forType:.string)`
//      WRITE only — never read the pasteboard (hard rule: AGENTS.md §2.6,
//      architecture §13; macOS 26.4 paste-protection triggers on reads).
//   2. Simulate Cmd+V via two `CGEvent` keyboard events (key-down + key-up)
//      posted to `.cghidEventTap`.
//
// SDK verifications (swiftc -typecheck against macOS 26 SDK, 2026-06-20):
//   • `NSPasteboard.general.clearContents()` → `Int` [verified]
//   • `NSPasteboard.general.setString(_:forType:.string)` → `Bool` [verified]
//   • `CGEventSource(stateID: .hidSystemState)` → `CGEventSource?` [verified]
//   • `CGEvent(keyboardEventSource:virtualKey:keyDown:)` → `CGEvent?` [verified]
//   • `CGEvent.flags: CGEventFlags` (settable) [verified]
//   • `CGEvent.post(tap: .cghidEventTap)` — Swift instance method [verified]
//     (NOTE: the free functions `CGEventPost`/`CGEventTapPostEvent` are
//      obsoleted in Swift 3; use the instance method `.post(tap:)` instead.)
//   • `kVK_ANSI_V == 9 == 0x09` [verified: swiftc + runtime print, 2026-06-20]
//     (Virtual key constant from Carbon/HIToolbox — preferred over the bare
//      literal so the intent is self-documenting.)
//   • `CGEventFlags.maskCommand` [verified]
//
// Unverified / deferred (requires live human test — P6 done-when):
//   [unverified] Write+Cmd+V avoids macOS 26.4 Terminal paste-provenance prompt
//   [deferred]   Paste into Slack (rich text), Terminal, password fields
//   See specs/verification-ledger.md §P6 for the test matrix.

import AppKit
import Carbon.HIToolbox
import os

/// Writes text to `NSPasteboard.general` and simulates Cmd+V to paste it into
/// the frontmost application. Requires Accessibility permission to post synthetic
/// keyboard events.
///
/// This type is stateless (only a `Logger`) so it is `Sendable` without
/// `@unchecked`.
public final class PasteboardWriter: TextInserting {

    // kVK_ANSI_V = 9 = 0x09 [verified: Carbon/HIToolbox, runtime 2026-06-20].
    // Using the Carbon constant rather than the raw literal makes the intent
    // explicit and the trace auditable.
    private static let vKeyCode: CGKeyCode = CGKeyCode(kVK_ANSI_V)

    private let log = SpeakLog.paste

    public init() {}

    /// Write `text` to the system pasteboard and fire a synthetic Cmd+V.
    ///
    /// - Throws: `SpeakError.pasteboardBusy` when either `CGEventSource` or
    ///   `CGEvent` cannot be constructed (the only failure mode detectable
    ///   without reading the pasteboard).
    public func insert(_ text: String) async throws {
        log.info(
            "PasteboardWriter: writing \(text.count, privacy: .public) chars to pasteboard"
        )

        // --- Step 1: write to pasteboard (WRITE only, never read) ---------------
        let pb = NSPasteboard.general
        _ = pb.clearContents()             // returns Int (change count); result unused
        _ = pb.setString(text, forType: .string)  // returns Bool; not checked here because
                                                   // a false result is observable only by
                                                   // reading, which is prohibited.

        // --- Step 2: simulate Cmd+V ---------------------------------------------
        try simulateCmdV()
    }

    // MARK: - Private

    private func simulateCmdV() throws {
        // `CGEventSource(stateID:)` returns nil when the event infrastructure is
        // unavailable (rare; occurs in headless CI or when Accessibility is denied).
        // Architecture §11 uses `source` as an optional — nil is valid; CGEvent
        // still constructs with a nil source on most platforms.
        let source = CGEventSource(stateID: .hidSystemState)

        guard
            let vDown = CGEvent(keyboardEventSource: source,
                                virtualKey: Self.vKeyCode,
                                keyDown: true),
            let vUp   = CGEvent(keyboardEventSource: source,
                                virtualKey: Self.vKeyCode,
                                keyDown: false)
        else {
            // CGEvent construction failed — system is too constrained to fire
            // synthetic events. Surface as pasteboardBusy (the canonical paste
            // error case in SpeakError).
            log.error("PasteboardWriter: CGEvent construction failed — cannot simulate Cmd+V")
            throw SpeakError.pasteboardBusy
        }

        vDown.flags = .maskCommand
        vDown.post(tap: .cghidEventTap)  // [verified] Swift instance method, not free fn

        vUp.flags = .maskCommand
        vUp.post(tap: .cghidEventTap)

        log.info("PasteboardWriter: Cmd+V posted to .cghidEventTap")
    }
}
