---
name: macos-paste-pipeline
description: Use when implementing or modifying the NSPasteboard write and Cmd+V paste simulation pipeline in SpeakCore — specifically PasteboardWriter, text selection logic (cleaned vs raw), or paste-provenance behavior on macOS 26.
---

# macOS Paste Pipeline — Implementation Pointer

## Architectural Seam

Type: `PasteboardWriter` — lives at `SpeakCore/Paste/PasteboardWriter.swift`

Responsibilities:
1. Write the final text to `NSPasteboard.general`.
2. Simulate `Cmd+V` via `CGEvent` to paste at the cursor in the frontmost app.

Text selection rule: use `TranscriptionResult.cleanedText` when cleanup is on AND produced a non-nil result; otherwise fall back to `TranscriptionResult.rawText`. The session reaches state `done` either way — paste always fires with whatever text is available.

## Hard Constraints — Non-Negotiable

- **NEVER READ the pasteboard — only WRITE.** macOS 26 introduced paste-protection that flags apps reading the pasteboard without user intent. Reading is prohibited even for diagnostic purposes. Write only; simulate Cmd+V; do not inspect what was there before or after.
- **Password-field failure is expected and correct.** Secure text fields (e.g., password inputs) reject synthetic paste events. Detect this (no error thrown by the OS — the paste silently does nothing) and transition to error state gracefully. Do not attempt workarounds that could expose sensitive content.
- Use `os.Logger`. No `print`. No force-unwrap. No `try!`.
- v0: Apple frameworks only (`NSPasteboard`, `CGEvent`). No Accessibility API paste workarounds.

## Unverified — Empirical Test Required at P6

`[unverified]` Whether writing to `NSPasteboard` and simulating `Cmd+V` avoids the macOS 26.4 Terminal paste-provenance prompt is **NOT confirmed**. macOS 26.4 added a Terminal-specific paste-provenance check; behavior may differ across TextEdit, Slack, and Terminal.

**Do not claim this works until P6 empirical tests pass in all three targets.** The P6 test matrix is: TextEdit (plain text field), Slack (rich text), Terminal (paste-provenance check). Tag findings from those tests as `[verified]` or `[unverified]` in `specs/verification-ledger.md`.

## Roadmap P6 Done-When

- `PasteboardWriter` writes text to `NSPasteboard.general` and fires a synthetic `Cmd+V`.
- Correct text is pasted: `cleanedText` when available, `rawText` otherwise.
- Session reaches `done` in both the cleaned and raw-fallback paths.
- Session reaches error state (not crash) when pasting into a password field.
- Empirical paste test passes in TextEdit and Slack; Terminal result documented in `specs/verification-ledger.md` with `[verified]` or `[unverified]` tag.

## Verify at Implementation Time

Confirm the `CGEvent` keyboard-event approach for Cmd+V simulation against current Apple docs — specifically which event types to post, whether `CGEventPost` or `CGEventTapPostEvent` is appropriate for this use case, and any macOS 26 changes to synthetic event handling. Use `apple-docs-mcp` (if available) or `https://developer.apple.com/documentation/coregraphics`. Tag all API claims before committing.
