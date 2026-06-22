# Validation & Hardening — Findings Report (`speak`)

> **Status:** LIVE — built across the validation phase (2026-06-22). Author: orchestrator.
> **Mode:** report-first (user directive) — **NO code changes until the user approves a fix batch.**
> **Scope:** master feature-complete through Wave 2 (HEAD d20a7b3 at audit start).
> Phase 1 (grounding) complete; Phase 2 (per-seam bug hunt) + Phase 3 (adversarial verify) pending.

Severity key: **P0** = ship-blocking / data-loss / crash · **P1** = correctness/reliability · **P2** = polish.
Each finding marks who can close it: **[agent]** = agent-fixable · **[human]** = needs live machine / Apple Intelligence.

---

## Headline

The codebase is **healthy and ahead of its open-source peers** on most seams. Phase-1B found
**zero false `[verified]` tags** in the code (every Apple-API claim checked against the on-machine
macOS 26 SDK holds). Phase-1A found speak **best-in-class** on hotkey robustness (watchdog +
rate-limiter + wake re-arm), the secure-field guard (unique), streaming STT with live partials
(peers are batch), multi-monitor HUD, and on-device free cleanup. The real gaps are a **small,
concrete set** — two ship-relevant P1 code gaps, a handful of P2s, doc drift in the skills, and
test-coverage holes (mostly around paths that need a live machine).

---

## Phase 1A — OSS comparison (vs VoiceInk / Hex; Handy+Whispering = same non-Swift Epicenter app, excluded)

### Real code gaps
- **[P1][agent] Paste inter-event delay missing.** `PasteboardWriter.simulateCmdV()` posts all 4
  Cmd+V events (⌘-down, V-down, V-up, ⌘-up) in a tight <1ms loop. VoiceInk inserts **10ms** between
  each (`CursorPaster.pasteShortcutEventDelay = 0.01`). Without it, **Electron apps, web views, and
  some Cocoa text fields silently drop the chord** — directly implicated in the human-gate live-paste
  checklist. Fix: `try await Task.sleep(for: .milliseconds(10))` between events (function already async). ~3 lines.
- **[P1][agent] Hold-mode stuck `isCapturing` on tap interruption.** If the tap dies mid-hold-dictation,
  `SpeakEngine` stays `.recording` until the watchdog re-arms. VoiceInk emits a synthetic release on
  teardown (`ShortcutMonitor.swift:156-165`). Fix: in `HotkeyMonitor.tearDownTap()`, if
  `binding.trigger == .hold && lastBoundKeyDown`, emit `.stopCapture` before teardown. ~3 lines.
- **[P2][agent] No STT model prewarming.** First dictation loads SpeechAnalyzer cold (~1-3s). VoiceInk
  prewarms via a dummy transcription 3s post-launch + on wake. Fix: lightweight `SpeechPrewarmer`,
  non-blocking, guarded on `SpeechTranscriber.isAvailable`. ~30 lines.
- **[P2][agent] No locale asset reservation.** speak calls `downloadAndInstall()` but never
  `AssetInventory.reserve(locale:)` nor handles `.reservationLimitReached`. On a device with many
  reserved locales, transcription can fail after install. ~15 lines.
- **[P3][agent] HUD window level `.floating` → consider `.statusBar`** (Hex uses `.statusBar`; VoiceInk also `.floating`, so aspirational).
- **[v0.1] flagsChanged-only event mask** limits bindings to modifier keys; add `keyDown` for arbitrary combos.
- **[v1] Import/backup** (VoiceInk has it; speak has JSON export only).

### Confirmed deliberate non-gaps (do NOT "fix")
Clipboard restore (we never read the pasteboard — hard rule) · Screen-Recording perm (VoiceInk-only feature) ·
Input Monitoring (removed wave 22, AX-only verified) · AppleScript paste fallback (CGEvent sufficient) ·
Cloud cleanup (ours is on-device/free — strictly better).

---

## Phase 1B — Skill ⇄ macOS 26 SDK truth audit (Xcode 26.5 / 17F42; swiftc -typecheck + .swiftinterface)

**No false `[verified]` tags in code.** Implementation > skill-spec, in the safe direction. Drift is **doc-only**:
- **[HIGH][agent-doc] `foundation-models-cleanup` skill:** shows `LanguageModelSession.init(model:guardrails:instructions:)` — wrong; `guardrails` is on `SystemLanguageModel(useCase:guardrails:)`. **Our code already uses the correct two-step pattern.** Skill would mislead future agents into non-compiling code.
- **[MED][agent-doc] `cgeventtap-hotkey` skill:** "`.listenOnly` requires Input Monitoring" has no Apple-header support; permission is gated by tap *location* (`.cghidEventTap`→AX), not options. Conclusion right, stated reason wrong.
- **[MED][agent-doc] `foundation-models-cleanup` skill:** `CleanupMode` enum stale (missing `styled(...)` + `command(...)`).
- **[LOW][agent-doc] ×3:** note `UnavailableReason`/`GenerationError` are non-`@frozen` (exhaustive switch needs `@unknown default` — our code avoids this, safe); `SpeechTranscriber.isAvailable` is `static`; soften altool "removed"→"deprecated" (verify at P11).

---

## Phase 1C — Flow & coverage audit (34 test files read; suite green 434/5-skip)

### P0 — cannot be closed by agents
- **[P0][human] FM-available clean path** (v0 core) — only the FM-*unavailable* path is tested; the real model-runs-and-returns path XCTSkips without Apple Intelligence. Needs a Mac with AI enabled.
- **[P0][human] Live AX-grant → CGEventTap re-arm** — only standalone boolean logic tested; the real 100ms poll + `CGEventTapCreate` re-arm edge has no automated test. Needs live grant.
- **[P0][human] Terminal paste-provenance `[unverified]`** — macOS 26.4 added a paste-provenance check; whether `CGEventPost` bypasses it for a dev-signed app is the codebase's largest `[unverified]`. Needs live test.

### P1 — agent-implementable test additions (+ some real risks)
- **[P1] Empty-transcript path (silence/mic-blocked) unguarded + untested** — `CaptureSession.stop()` returns `""`; behavior (paste empty, empty history entry) not verified. *Potential real bug, not just coverage — flag for Phase 2.*
- **[P1] Cleanup timeout + cancel simultaneous race** — no test for `cancelDictation()` arriving during the `runCleanup()` timeout-fire window. *Concurrency risk — Phase 2.*
- **[P1] CLI idempotency gate is a reimplementation** — tests use their own `idempotencyDecision()` mirroring `CLIPortServer.handle(data:)`; the real `MainActor.assumeIsolated` gate is never exercised → can silently regress.
- **[P1] `DictationController.endDictation()` error branches** (`.pasteRequiresAccessibility` / `.pasteIntoSecureField` / generic → Scratchpad) untested end-to-end.
- **[P1] `rebindHotkey()` + `triggerModeCancellable` Combine subscription** untested — regression silently breaks hold/double-tap switch.
- **[P1] Snippet expansion inside a `CaptureSession` run** untested (only `SnippetExpander` in isolation).
- **[P1] Multi-display HUD positioning** — no automated assertions.
- **[P1] `SettingsStore.triggerMode` not in round-trip battery** — key-name change wouldn't be caught.
- **[P1] `OverlayController.partialText` drain task** untested (all tests pass `partialsProvider: { nil }`).
- **[P1] `OnboardingViewModel` lifecycle** (`advance/skip/finish` + poll auto-advance) untested.

### P2 — polish (6): onboarding "Try it now" pill + `skip()`; history empty-state UI; CommandMode `begin/end`; menubar `.error`→`.idle` recovery; mute-while-`.processing`.

### Notable test-infra gaps
- `testInsertSucceedsWhenAXTrusted` **silently skips** the 4-event assertion in headless CI (the very environment most likely to regress paste).
- **WER corpus missing** — `WERHarnessTests` always passes (doc-only); `benchmark.md §4` accuracy row `[deferred]`.

---

## Phase 2 — per-seam code bug hunt  *(pending)*
## Phase 3 — adversarial verification of findings  *(pending)*
## Phase 4 — prioritized fix batches for user approval  *(pending)*
