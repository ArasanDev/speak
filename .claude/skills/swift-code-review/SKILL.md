---
name: swift-code-review
description: Review Swift code in the speak project against its non-negotiable conventions (no print, no force-unwrap, no global mutable state, no main-thread blocking) and the v0 hard constraints. Use before committing any Swift change or when reviewing a diff.
---

# Swift Code Review — `speak` conventions gate

This skill is the convention gate for every Swift change in `speak`. The rules
below are from `AGENTS.md` §2–3 and `architecture.md` §13 — they are **the
moat**, not style preferences. A change that violates one is not done. Review
the diff against each, and report violations with `file:line`.

## Hard coding rules (each is binary — flag every violation)

1. **No `print` for logging.** Use `os.Logger` (OSLog) via the categories in
   `SpeakCore/Logging/SpeakLog.swift`. A bare `print(` in production code fails review.
2. **No force-unwrap (`!`), no `try!`, no `as!`** in production code. Use
   `guard let` / `if let` / `throws` / `as?`. Exceptions only inside `SpeakTests/`.
3. **No global mutable state.** State is owned by an `actor` or injected via the
   SwiftUI environment. A top-level `var` or mutable `static var` fails review.
4. **Never block the main thread.** Audio/STT/cleanup run on background queues or
   actors; only UI work is `@MainActor`. Flag synchronous I/O or `await` chains on `@MainActor`.
5. **No omitted `[weak self]`** in long-lived/escaping closures that capture `self`.
6. **Every public type has a real Swift signature** matching `architecture.md` §6 —
   no pseudocode, no placeholder bodies in committed code.
7. **No magic numbers.** Every constant traces to a measured value, a platform
   constraint, or a `[decision]` in `benchmark.md` §7. A bare literal (timeout,
   window, capacity) with no such trace fails review — cite the source in a comment.

## Hard product constraints to check in any change (`AGENTS.md` §2)

- **100% local.** No network calls for audio/transcript/cleanup; no telemetry; no accounts. Flag any URLSession/analytics.
- **Never read the pasteboard** — only write. Any `NSPasteboard` *read* (`pasteboard.string(forType:)`, `pasteboardItems`) fails review outright.
- **Apple frameworks only (v0).** No third-party runtime dependency (SPM/Cocoapods/Carthage). Flag any new `import` of a non-Apple module.
- **Cleanup unavailability ≠ error.** When Foundation Models is unavailable, the session must fall back to raw text and reach `done`, never `error`.
- **Capture path + permissions:** a diff touching the capture path must honor `AGENTS.md` §2.7 (hardware mute → no audio captured); a diff adding an OS permission request must honor `AGENTS.md` §2.2 (exactly two permissions: Microphone + Accessibility; `.defaultTap`→AX, Input Monitoring not used in v0).

## How to review

Match the surrounding code (comment density, naming, idiom) — read before judging.
Report only real violations of the rules above, each with `file:line` and the rule
number. If a `[verified]` claim in the code contradicts a primary source, **stop and
surface it** rather than approving. Pair this with the official `code-review` and
`security-guidance` plugins for general correctness/vuln coverage.
