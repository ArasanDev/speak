// SpeakCore/Paste/PasteboardWriter.swift
//
// Concrete `TextInserting` conformer. Implements architecture §11 + spec
// dictation-flow.md §5 (Phase D: robust paste).
//
// Order of operations in `insert(_:)`:
//   1. Clipboard floor: `clearContents()` + `setString(_:forType:.string)`
//      WRITE only — never read the pasteboard (hard rule: AGENTS.md §2.6,
//      architecture §13; macOS 26.4 paste-protection triggers on reads).
//      This step runs unconditionally so text is always recoverable from
//      the clipboard, even if the subsequent steps fail.
//   2. AX-trust gate: if `AXIsProcessTrusted()` returns false → log + throw
//      `SpeakError.pasteRequiresAccessibility`. Synthetic keyboard events are
//      silently dropped without AX; posting them would be a no-op with no
//      signal. The caller (DictationController.endDictation) treats this as a
//      soft outcome, not a crash: it sets `permissionsNeeded = true` and stays
//      `.idle` (text is on the clipboard for manual paste).
//   3. Settle delay: `Task.sleep` for `settle` duration (default 100 ms) before
//      posting events. [decision] provenance: VoiceInk + Hex post a short delay
//      so the clipboard write commits and the target's first responder is ready
//      after focus returns from the hotkey. Spec dictation-flow.md §5. Tests
//      inject `.zero` to avoid real sleeps.
//   4. Explicit modifier sequence: Cmd-down → V-down → V-up → Cmd-up posted to
//      `.cghidEventTap`. [decision] VoiceInk/Hex post the modifier key events
//      explicitly rather than relying on `.maskCommand` alone on the V events;
//      this matches what the system expects for a synthetic keyboard chord.
//
// Pure testable plan:
//   `pasteEventPlan()` returns the 4-entry sequence as `[PasteKeyEvent]` structs.
//   `simulateCmdV()` maps each entry to a `CGEvent` and posts it. This mirrors
//   the project's `holdEdge`/`LevelMath` pure-function style.
//
// SDK verifications (swiftc -typecheck against macOS 26 SDK):
//   • `NSPasteboard.general.clearContents()` → `Int` [verified]
//   • `NSPasteboard.general.setString(_:forType:.string)` → `Bool` [verified]
//   • `AXIsProcessTrusted()` from `ApplicationServices` (via AppKit re-export) [verified]
//   • `CGEventSource(stateID: .hidSystemState)` → `CGEventSource?` [verified]
//   • `CGEvent(keyboardEventSource:virtualKey:keyDown:)` → `CGEvent?` [verified]
//   • `CGEvent.flags: CGEventFlags` (settable) [verified]
//   • `CGEvent.post(tap: .cghidEventTap)` — Swift instance method [verified]
//     (NOTE: the free functions `CGEventPost`/`CGEventTapPostEvent` are
//      obsoleted in Swift 3; use the instance method `.post(tap:)` instead.)
//   • `kVK_ANSI_V == 9 == 0x09` [verified: Carbon/HIToolbox, runtime 2026-06-20]
//   • `kVK_Command == 0x37 == 55` [verified: Carbon/HIToolbox, swiftc 2026-06-21]
//   • `CGEventFlags.maskCommand` [verified]
//
// Unverified / deferred (requires live human test — P6 done-when):
//   [unverified] Write+Cmd+V avoids macOS 26.4 Terminal paste-provenance prompt
//   [deferred]   Paste into Slack (rich text), Terminal, password fields
//   See specs/verification-ledger.md §P6 for the test matrix.

import AppKit
import ApplicationServices
import Carbon.HIToolbox
import os

// MARK: - PasteKeyEvent

/// One entry in the Cmd+V synthetic keyboard sequence.
///
/// Used by `pasteEventPlan()` — a pure function that returns the ordered plan.
/// `simulateCmdV()` maps each entry to a `CGEvent` and posts it.
/// This struct is `internal` so `@testable import SpeakCore` can reach it
/// in tests without widening the public surface of `PasteboardWriter`.
struct PasteKeyEvent: Sendable {
    let keyCode: CGKeyCode
    let keyDown: Bool
    let flags: CGEventFlags
}

// MARK: - PasteboardWriter

/// Writes text to `NSPasteboard.general` and simulates Cmd+V to paste it into
/// the frontmost application. Requires Accessibility permission to post synthetic
/// keyboard events.
///
/// This type is `Sendable`: it holds no mutable state (only an immutable Logger
/// and two injected closures that are themselves `@Sendable`).
public final class PasteboardWriter: TextInserting, Sendable {

    // kVK_ANSI_V = 9 = 0x09 [verified: Carbon/HIToolbox, runtime 2026-06-20].
    // kVK_Command = 0x37 = 55 [verified: Carbon/HIToolbox, swiftc 2026-06-21].
    // Using Carbon constants rather than raw literals makes the intent explicit
    // and the trace auditable.
    private static let vKeyCode: CGKeyCode = CGKeyCode(kVK_ANSI_V)
    private static let cmdKeyCode: CGKeyCode = CGKeyCode(kVK_Command)

    private let log = SpeakLog.paste

    // DI hooks — `@Sendable` so the class stays `Sendable` without `@unchecked`.

    /// Returns whether the process is AX-trusted. Injected so tests can control
    /// the outcome without requiring Accessibility to be granted in CI.
    let isAccessibilityTrusted: @Sendable () -> Bool

    /// Pre-paste settle delay. Injected so tests can pass `.zero`.
    /// Default 100 ms — [decision] VoiceInk/Hex settle before posting events
    /// so the clipboard write commits and the first responder is ready.
    /// Spec dictation-flow.md §5.
    let settle: Duration

    /// Writes `text` to the system pasteboard (the clipboard floor). Injected so
    /// tests never clobber the real `NSPasteboard.general` — a real write would
    /// hijack the user's clipboard during `make test`. Default writes the general
    /// pasteboard (WRITE only, never read).
    let writeClipboard: @Sendable (String) -> Void

    /// Posts one synthetic keyboard `CGEvent`. Injected so tests never post real
    /// Cmd+V events to `.cghidEventTap` — a real post lands in whatever window
    /// currently has focus (e.g. the terminal running the tests) and pastes the
    /// clipboard there. Default posts to the HID tap.
    let postEvent: @Sendable (CGEvent) -> Void

    /// Production clipboard-floor write: `clearContents()` + `setString`. Extracted
    /// as the injectable default so the production path is byte-for-byte unchanged.
    public static let defaultWriteClipboard: @Sendable (String) -> Void = { text in
        let pb = NSPasteboard.general
        _ = pb.clearContents()                    // returns Int (change count); unused
        _ = pb.setString(text, forType: .string)  // returns Bool; unused — a false result
                                                   // is only observable by reading (prohibited)
    }

    /// Designated init. Production callers (DictationController line ~142
    /// `inserter: PasteboardWriter()`) use the defaults and are unaffected.
    public init(
        isAccessibilityTrusted: @escaping @Sendable () -> Bool = { AXIsProcessTrusted() },
        settle: Duration = .milliseconds(100),   // [decision] spec dictation-flow.md §5
        writeClipboard: @escaping @Sendable (String) -> Void = PasteboardWriter.defaultWriteClipboard,
        postEvent: @escaping @Sendable (CGEvent) -> Void = { $0.post(tap: .cghidEventTap) }
    ) {
        self.isAccessibilityTrusted = isAccessibilityTrusted
        self.settle = settle
        self.writeClipboard = writeClipboard
        self.postEvent = postEvent
    }

    // MARK: - TextInserting

    /// Write `text` to the system pasteboard and fire a synthetic Cmd+V.
    ///
    /// Steps (in order):
    ///   1. Clipboard floor (always runs — text always lands on clipboard).
    ///   2. AX-trust gate (no AX → throw `.pasteRequiresAccessibility`; text is on clipboard).
    ///   3. Settle delay.
    ///   4. Post Cmd-down → V-down → V-up → Cmd-up to `.cghidEventTap`.
    ///
    /// - Throws: `SpeakError.pasteRequiresAccessibility` when AX is not granted.
    ///           `SpeakError.pasteboardBusy` when CGEvent construction fails.
    public func insert(_ text: String) async throws {
        log.info(
            "PasteboardWriter: writing \(text.count, privacy: .public) chars to pasteboard"
        )

        // ── Step 1: clipboard floor (WRITE only, never read) ─────────────────
        // Runs unconditionally — text is recoverable from the clipboard even
        // if the AX gate or event posting fails below.
        // Delegate through the injected seam. Production writes NSPasteboard.general
        // (see `defaultWriteClipboard`); tests inject a recorder so the real
        // clipboard — and the user's focused window — are never touched. Never reads.
        writeClipboard(text)

        // ── Step 2: AX-trust gate ────────────────────────────────────────────
        // Synthetic keyboard events are silently dropped when AX is not granted.
        // Posting them would appear to succeed (no OS error) but nothing would
        // paste. We detect this early and throw a recoverable error instead.
        guard isAccessibilityTrusted() else {
            log.info(
                "PasteboardWriter: AX not trusted — text on clipboard; skipping Cmd+V"
            )
            throw SpeakError.pasteRequiresAccessibility
        }

        // ── Step 3: settle delay ─────────────────────────────────────────────
        // Give the clipboard write time to commit and let the target app's first
        // responder re-focus after the hotkey tap. [decision] dictation-flow.md §5
        try await Task.sleep(for: settle)

        // ── Step 4: Cmd-down → V-down → V-up → Cmd-up ───────────────────────
        try simulateCmdV()

        log.info("PasteboardWriter: Cmd+V sequence posted to .cghidEventTap")
    }

    // MARK: - Pure plan function (unit-testable)

    /// Returns the ordered 4-event plan for a Cmd+V chord.
    ///
    /// Pure function: no side effects, no OS calls. Maps to CGEvents in
    /// `simulateCmdV()`. Tests assert this plan directly without posting events.
    ///
    /// Sequence:
    ///   Cmd-down (.maskCommand) → V-down (.maskCommand) →
    ///   V-up (.maskCommand)     → Cmd-up ([])
    ///
    /// [decision] VoiceInk/Hex post the modifier key events explicitly so the
    /// system sees a full chord press rather than a V keypress with a flag set.
    static func pasteEventPlan() -> [PasteKeyEvent] {
        [
            PasteKeyEvent(keyCode: cmdKeyCode, keyDown: true, flags: .maskCommand),
            PasteKeyEvent(keyCode: vKeyCode, keyDown: true, flags: .maskCommand),
            PasteKeyEvent(keyCode: vKeyCode, keyDown: false, flags: .maskCommand),
            PasteKeyEvent(keyCode: cmdKeyCode, keyDown: false, flags: [])
        ]
    }

    // MARK: - Private

    /// Map `pasteEventPlan()` entries to `CGEvent` instances and post each.
    ///
    /// - Throws: `SpeakError.pasteboardBusy` when `CGEvent` construction fails
    ///   (rare; indicates the event infrastructure is unavailable).
    private func simulateCmdV() throws {
        // `CGEventSource(stateID:)` returns nil when the event infrastructure is
        // unavailable (rare; occurs in headless CI or when Accessibility is denied).
        // Architecture §11 uses `source` as an optional — nil is valid; CGEvent
        // still constructs with a nil source on most platforms.
        let source = CGEventSource(stateID: .hidSystemState)

        // Build ALL events before posting any. If construction fails mid-sequence
        // and we had already posted Cmd-down, the modifier would be stuck held.
        // All-or-nothing construction avoids that robustness regression.
        var events: [CGEvent] = []
        for entry in Self.pasteEventPlan() {
            guard let event = CGEvent(keyboardEventSource: source,
                                      virtualKey: entry.keyCode,
                                      keyDown: entry.keyDown) else {
                log.error(
                    "PasteboardWriter: CGEvent construction failed — cannot simulate Cmd+V"
                )
                throw SpeakError.pasteboardBusy
            }
            event.flags = entry.flags
            events.append(event)
        }

        // Post all four events in sequence: Cmd-down → V-down → V-up → Cmd-up.
        // Via the injected `postEvent` seam — production posts to `.cghidEventTap`
        // ([verified] Swift instance method, not the obsoleted free fn); tests inject
        // a recorder so no real Cmd+V ever reaches the focused window.
        for event in events {
            postEvent(event)
        }
    }
}
