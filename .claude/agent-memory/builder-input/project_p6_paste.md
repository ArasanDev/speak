---
name: project-p6-paste
description: P6 paste pipeline complete — TextInserting protocol, PasteboardWriter, CaptureSession wire-up, SDK verifications, deferred live rows
metadata:
  type: project
---

## P6 paste pipeline — code-complete (2026-06-20, loop run #7)

**Files created/modified:**
- `SpeakCore/Paste/TextInserting.swift` — `public protocol TextInserting: Sendable { func insert(_ text: String) async throws }`
- `SpeakCore/Paste/PasteboardWriter.swift` — `final class PasteboardWriter: TextInserting` (stateless → auto-Sendable)
- `SpeakCore/Engine/CaptureSession.swift` — additive: `inserter: (any TextInserting)? = nil` param; paste step before `.done`
- `SpeakTests/PasteTests.swift` — 6 new tests, all green

**SDK verifications (swiftc -typecheck + runtime, macOS 26 SDK):**
- `NSPasteboard.clearContents()` → `Int` (not Bool) [verified]
- `NSPasteboard.setString(_:forType:.string)` → `Bool` [verified]
- `CGEventSource(stateID:.hidSystemState)` → optional [verified]
- `CGEvent(keyboardEventSource:virtualKey:keyDown:)` → optional [verified]
- `CGEvent.post(tap:.cghidEventTap)` — Swift **instance method** (not obsoleted free fn) [verified]
- `kVK_ANSI_V = 9 = 0x09` from `Carbon.HIToolbox` [verified runtime]
- `CGEventFlags.maskCommand` [verified]

**Hard rule confirmed:** WRITE-only to pasteboard. Never reads. macOS 26.4 paste-protection triggers on reads, not writes.

**Deferred (live human test required):**
- TextEdit paste, Slack paste
- Terminal paste-provenance check — **the project's #1 `[unverified]`**; macOS 26.4 added a Terminal-specific pastejacking check; whether write+Cmd+V bypasses it is unknown
- Password-field silent no-op

**Why:** P6 is the delivery step. Mock-verified via `TextInserting` injection. Real `PasteboardWriter` fires live CGEvent into the focused app — untestable in a headless CI environment.

**How to apply:** When wiring `SpeakEngine` (P8/P9), pass a `PasteboardWriter()` as the `inserter` in `CaptureSession.init`. The protocol seam keeps the engine testable. The live rows above must be checked by a human before P6 is ship-gate complete.
