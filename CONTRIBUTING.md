# Contributing to `speak`

`speak` is a macOS-native, local-first AI voice dictation app built autonomously
by an agent team and welcoming human contributors. This document covers how to
build, test, and navigate the repo; what the architecture seams are; and the hard
rules that must never be traded away.

---

## Build and test

Requirements: macOS 26 (Tahoe), Apple Silicon, Xcode 26+.

```bash
# Install build tools (one-time; dev tooling only — not runtime deps)
brew install xcodegen swiftlint xcbeautify

# Build
make build        # xcodegen generate → xcodebuild → Speak.app + SpeakCore.framework

# Test
make test         # xcodebuild test (XCTest + Swift Testing); all must pass

# Lint
make lint         # swiftlint; force-unwrap / force-cast / force-try are errors

# Structural moat audit
make verify-moat  # 7/7 source-tree checks (MIT, no third-party imports, no egress, ...)

# Run
make run          # build + launch the menubar app
```

`make build` runs `xcodegen generate` automatically. A clean clone has no
`.xcodeproj` (it is git-ignored; `project.yml` is the source of truth).

**CI**: GitHub Actions runs `xcodebuild build` + `swiftlint` on every push.

---

## Navigating the repo

The repo is structured for autonomous agent operation as much as human reading.
The loading order matters:

| File | Purpose |
|---|---|
| `AGENTS.md` | Operating manual — the mission, hard rules, autonomous loop |
| `docs/progress.md` | Living state. Read first every session, update last. |
| `docs/roadmap.md` | Build order; dependency-ordered phases; done-when criteria |
| `docs/architecture.md` | How it is built — modules, types, Swift signatures |
| `docs/benchmark.md` | Definition of done — parity vs Wispr Flow (the frontier) |
| `docs/quality.md` | Tests, risks, ship checklist |
| `docs/human-verification.md` | Live-gated items that require a real Mac + permissions |
| `SPEC.md` | Consolidated human-readable spec (competitive positioning, personas, UX) |
| `specs/` | Point-in-time plans and the verification ledger |
| `research/` | Evidence archive — read-only; never the source of direction |

Do not treat `research/` as direction. It is historical reasoning; the
`docs/` set is the active source of truth.

---

## Architecture seams

`speak` has two targets:

- **`SpeakCore.framework`** — the headless dictation engine. All protocol
  definitions, pipeline logic, data types, and storage. No SwiftUI. This is the
  portability seam: a future iOS or CLI target extracts it without touching `App`.
- **`Speak.app`** (the `App` target) — the SwiftUI menubar shell. Owns
  `MenuBarExtra`, the overlay panel, the settings window, onboarding, and
  `DictationController` (the `@MainActor ObservableObject` that wires everything
  together).

### The pipeline

```
HotkeyMonitor (CGEventTap)
    → DictationController (App, @MainActor)
        → SpeakEngine (actor, SpeakCore)
            → CaptureSession (actor)
                → AppleSpeechTranscriber : Transcribing   ← swap any STT here
                → FoundationModelsCleaner : LLMCleaning   ← swap any LLM here
                → PasteboardWriter : TextInserting
            → HistoryStore (SQLite3)
```

Every seam is a protocol (`Transcribing`, `LLMCleaning`, `TextInserting`,
`HistoryStoring`). Mock conformances make every seam headless-testable.

### Key source directories

```
SpeakCore/
  Engine/       CaptureSession, SpeakEngine, SpeakError, SpeakLog
  STT/          Transcribing protocol, AppleSpeechTranscriber
  Cleanup/      LLMCleaning protocol, FoundationModelsCleaner
  Hotkey/       HotkeyMonitor, DoubleTapDetector, HotkeyBinding
  Paste/        TextInserting protocol, PasteboardWriter
  Permissions/  PermissionManager, OnboardingState
  Storage/      HistoryStore (SQLite), SettingsStore (UserDefaults)
  Logging/      SpeakLog (os.Logger categories)

App/
  SpeakApp.swift          MenuBarExtra entry point
  DictationController.swift  @MainActor ObservableObject; wires engine + hotkey
  Overlay/               TranscriptOverlayPanel (NSPanel, non-activating)
  Settings/              Settings window (SwiftUI)
  Onboarding/            Three-step permission onboarding flow
```

---

## Hard rules (from `AGENTS.md` §2–3)

These are non-negotiable. A PR that violates any of them will not be merged.

**Runtime:**
- **100% local by default.** No cloud audio, no telemetry, no accounts. Works
  fully offline. Every network-egress symbol is banned by `make verify-moat`.
- **v0: Apple frameworks only.** No third-party runtime dependencies.
  `SpeechAnalyzer` and `Foundation Models` are Apple frameworks — allowed.
  `XcodeGen` and `xcbeautify` are build-time tools — allowed (not linked).
- **AI neat-writing is core, not optional.** Default cleanup = on-device
  `Foundation Models`, pluggable via `LLMCleaning`, with a raw-transcript
  fallback. Never remove or default-off the cleanup path in v0.

**Code conventions:**
- `os.Logger` only. **No `print`.** Verified by `MoatAuditTests`.
- **No force-unwrap** (`!`), `force-cast` (`as!`), or `force-try` (`try!`)
  outside test files. SwiftLint enforces these as errors.
- **No global mutable state.** Shared state lives in actors or `@MainActor`
  types. The main thread is never blocked.
- **Never read the pasteboard** — only write. `PasteboardWriter.insert(_:)`
  calls `NSPasteboard.general.clearContents()` + `setString(_:forType:.string)`,
  then simulates Cmd+V. Never calls any read API (`string(forType:)`,
  `pasteboardItems`, etc.). Verified by `MoatAuditTests.testNoPasteboardRead`.
- **No magic numbers.** Every constant traces to a measured value, a platform
  constraint, or a `[decision]` with rationale in `docs/benchmark.md` §7.

**Claims and tagging:**
- Tag claims `[verified]` / `[inferred]` / `[decision]` / `[unverified]`.
- Never tag `[verified]` from memory. Confirm with `swiftc -typecheck` against
  the local macOS 26 SDK, or via the `apple-docs` MCP server.
- If a `[verified]` claim contradicts a primary source, stop and surface it.

---

## Commit discipline

One commit per completed roadmap task. Format:

```
[P<N>] <task>: <what changed>
```

Examples:
```
[P5] hotkey: CGEventTap double-tap Fn, DoubleTapDetector, HotkeyBinding Codable
[P9] history: SQLite HistoryStore, HistoryStoreTests (11 tests)
```

Never commit broken code or secrets. Keep the working tree clean before spawning
sub-agents or branching. The orchestrator reviews diffs and owns commits.

---

## Verification discipline

Code is not done when written — done when verified. Before marking a task complete:

1. `make build` exits 0, no new warnings.
2. `make test` — all tests pass; new code has tests.
3. `make lint` — no new serious violations.
4. `make verify-moat` — still 7/7.
5. The specific done-when criterion from `docs/roadmap.md` is met.
6. `docs/progress.md` is updated with what was done + any decisions made.

Live-gated criteria (paste into real apps, hotkey with real permissions) cannot
be verified headlessly. Mark them `[deferred — needs human verification]` and
add a row to `docs/human-verification.md`. Never mark them passed without a
real run.

---

## Proposing changes

- For architectural or seam-level changes, read `docs/architecture.md` and open
  a discussion or issue first. The seams are stable by design.
- `docs/product.md` is immutable — it defines the destination and is
  human-owned. Do not propose changes to it in a PR.
- For new platforms, new STT/cleanup engines, or anything that adds a runtime
  dependency, read `AGENTS.md` §2 (the hard constraints) first.
- The `research/` directory is read-only evidence. Never turn it into direction.
