// SpeakCore/Paste/KeystrokeStreamingInserter.swift
//
// Concrete `StreamingRawTextInserting` conformer. Implements character-by-character
// keystroke injection via CGEvent, with no pasteboard reads (moat-safe).
//
// Keystroke injection strategy:
//   For each character in the input chunk, convert to UTF-16 and post keyDown+keyUp
//   events using `CGEvent.keyboardSetUnicodeString(stringLength:unicodeString:)`.
//   This approach works for arbitrary Unicode (accents, emoji, non-ASCII) without
//   relying on keycode mapping (which is fragile and locale-dependent).
//
// Order of operations in `insertChunk(_:)`:
//   1. AX-trust gate: if `AXIsProcessTrusted()` returns false → throw
//      `SpeakError.pasteRequiresAccessibility`. [Decision] Check on every chunk
//      (stateless, simpler) rather than tracking a flag. Production callers
//      will have AX trusted and will not repeat this check; tests can control
//      the outcome via the injected `isAccessibilityTrusted` closure.
//   2. Settle delay: `Task.sleep` for `settle` duration (default 100 ms) before
//      posting events. [decision] Same rationale as PasteboardWriter: the hotkey
//      completion needs time for the first responder to re-focus.
//   3. Character injection: for each character (or UTF-16 unit), construct keyDown
//      and keyUp CGEvents with the character's Unicode via `keyboardSetUnicodeString`,
//      post them. All events are built before posting any (all-or-nothing pattern).
//
// No pasteboard reads anywhere in this conformer (moat compliance).
//
// SDK verifications (swiftc -typecheck against macOS 26 SDK):
//   • `AXIsProcessTrusted()` from `ApplicationServices` (via AppKit re-export) [verified]
//   • `CGEvent(keyboardEventSource:virtualKey:keyDown:)` → `CGEvent?` [verified]
//   • `CGEvent.keyboardSetUnicodeString(stringLength:unicodeString:)` instance method [verified]
//   • `CGEvent.post(tap: .cghidEventTap)` — Swift instance method [verified]
//   • String → Array(char.utf16) UTF-16 encoding [verified]

import AppKit
import ApplicationServices
import os

/// Injects text character-by-character via synthetic keystroke events.
///
/// A streaming conformer of `StreamingRawTextInserting` that posts individual
/// character-by-character CGEvents rather than using the pasteboard. Each call to
/// `insertChunk(_:)` posts a sequence of keyDown+keyUp pairs (one per character,
/// UTF-16 encoded). No pasteboard reads occur.
///
/// Thread safety: `Sendable` so session actors can store and call the inserter
/// across `await` suspension points without isolation warnings.
public final class KeystrokeStreamingInserter: StreamingRawTextInserting, Sendable {

    private let log = SpeakLog.paste

    // DI hooks — `@Sendable` so the class stays `Sendable` without `@unchecked`.

    /// Returns whether the process is AX-trusted. Injected so tests can control
    /// the outcome without requiring Accessibility to be granted in CI.
    let isAccessibilityTrusted: @Sendable () -> Bool

    /// Pre-keystroke settle delay. Injected so tests can pass `.zero`.
    /// Default 100 ms — [decision] same as PasteboardWriter: allow the hotkey
    /// completion to settle and the first responder to re-focus.
    let settle: Duration

    /// Posts one synthetic keyboard `CGEvent`. Injected so tests never post real
    /// keystroke events — a real post lands in whatever window currently has focus
    /// and types there. Default posts to the HID tap.
    let postEvent: @Sendable (CGEvent) -> Void

    /// Designated init. Production callers use the defaults and are unaffected.
    public init(
        isAccessibilityTrusted: @escaping @Sendable () -> Bool = { AXIsProcessTrusted() },
        settle: Duration = .milliseconds(100),
        postEvent: @escaping @Sendable (CGEvent) -> Void = { $0.post(tap: .cghidEventTap) }
    ) {
        self.isAccessibilityTrusted = isAccessibilityTrusted
        self.settle = settle
        self.postEvent = postEvent
    }

    // MARK: - StreamingRawTextInserting

    /// Inject one chunk of text character-by-character via keystroke events.
    ///
    /// Steps (in order):
    ///   1. AX-trust gate (no AX → throw `.pasteRequiresAccessibility`; check on every call).
    ///   2. Settle delay.
    ///   3. For each character: convert to UTF-16, build keyDown+keyUp events, post them.
    ///      All events are built before any are posted (all-or-nothing pattern).
    ///
    /// - Parameter text: A partial string (typically a word or phrase). May be empty;
    ///   if empty, this method no-ops silently.
    /// - Throws: `SpeakError.pasteRequiresAccessibility` when AX is not granted.
    ///           `SpeakError.pasteboardBusy` when CGEvent construction fails.
    public func insertChunk(_ text: String) async throws {
        log.info(
            "KeystrokeStreamingInserter: injecting \(text.count, privacy: .public) chars"
        )

        // Guard against empty input — no-op.
        if text.isEmpty {
            log.debug("KeystrokeStreamingInserter: empty chunk, skipping")
            return
        }

        // ── Step 1: AX-trust gate ────────────────────────────────────────
        // Synthetic keyboard events are silently dropped when AX is not granted.
        // [Decision] Check on every call (stateless, simpler) rather than tracking
        // a flag. Production will have AX trusted; tests control via injected closure.
        guard isAccessibilityTrusted() else {
            log.info(
                "KeystrokeStreamingInserter: AX not trusted — text discarded; clipboard not written"
            )
            throw SpeakError.pasteRequiresAccessibility(text: text)
        }

        // ── Step 2: settle delay ─────────────────────────────────────────
        // Give the hotkey completion time to settle and the target app's first
        // responder time to re-focus. Same [decision] as PasteboardWriter.
        try await Task.sleep(for: settle)

        // ── Step 3: character-by-character keystroke injection ────────────
        try await injectCharacters(text)

        log.info("KeystrokeStreamingInserter: all keystrokes posted to .cghidEventTap")
    }

    /// Signal end-of-stream. No-op for keystroke mode (no buffer to flush).
    public func finalize() async throws {
        log.debug("KeystrokeStreamingInserter: finalize (no-op for keystroke mode)")
    }

    // MARK: - Private

    /// Build and post keyDown+keyUp events for each character in the text.
    ///
    /// All events are constructed first; if any construction fails, all are discarded
    /// and an error is thrown before any event is posted. This prevents the modifier
    /// state from being left stuck (all-or-nothing pattern from PasteboardWriter).
    ///
    /// - Throws: `SpeakError.pasteboardBusy` when `CGEvent` construction fails.
    private func injectCharacters(_ text: String) async throws {
        // `CGEventSource(stateID:)` returns nil when the event infrastructure is
        // unavailable (rare; occurs in headless CI). Architecture §11 uses it as
        // optional — nil is valid; CGEvent still constructs with a nil source.
        let source = CGEventSource(stateID: .hidSystemState)

        // Build ALL events before posting any. If construction fails mid-sequence,
        // all are discarded and no event is posted. This prevents stuck modifier state.
        var events: [CGEvent] = []

        for char in text {
            // Convert each character to UTF-16 for injection.
            let utf16 = Array(char.utf16)

            // Build keyDown event with the character's Unicode.
            guard let keyDown = CGEvent(keyboardEventSource: source,
                                        virtualKey: 0,
                                        keyDown: true) else {
                log.error(
                    "KeystrokeStreamingInserter: CGEvent keyDown construction failed"
                )
                throw SpeakError.pasteboardBusy
            }
            keyDown.keyboardSetUnicodeString(stringLength: utf16.count,
                                             unicodeString: utf16)
            events.append(keyDown)

            // Build keyUp event with the same character's Unicode.
            guard let keyUp = CGEvent(keyboardEventSource: source,
                                      virtualKey: 0,
                                      keyDown: false) else {
                log.error(
                    "KeystrokeStreamingInserter: CGEvent keyUp construction failed"
                )
                throw SpeakError.pasteboardBusy
            }
            keyUp.keyboardSetUnicodeString(stringLength: utf16.count,
                                           unicodeString: utf16)
            events.append(keyUp)
        }

        // Post all events in sequence: keyDown → keyUp → keyDown → keyUp ...
        // Via the injected `postEvent` seam — production posts to `.cghidEventTap`;
        // tests inject a recorder so no real keystroke ever reaches the focused window.
        for event in events {
            postEvent(event)
        }
    }
}
