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

## Phase 2 — per-seam code bug hunt  *(4 of 6 seams in: engine, cleanup, storage, app; input + STT pending)*

Confidence that the codebase is healthy is **reinforced**: storage SQLi = CLEAN, logging-privacy = CLEAN, cleanup fallback contract + actor-safety = CLEAN, no `print`/force-unwrap/global-state/networking found. The real bugs are concentrated in the **engine session lifecycle** and **cleanup prompt building**.

### HIGH-VALUE confirmed bugs (→ Phase 3 adversarial verify before any fix)
- **[P1] Cancel-during-processing pastes against user intent** (`CaptureSession.stop()` ~L213-320). `stop()` checks state once, then `await`s `transcriber.stop()`, `runCleanup` (up to 10s), `inserter.insert`. A `cancel()` (mute/quit) arriving during those awaits sets `.error(.sessionCancelled)`, but `stop()` resumes, **pastes anyway**, and overwrites `state = .done` — the cancel is silently lost. Fix: re-check `if case .error = state { throw e }` after the last await and before paste + before `.done`. *Directly violates the "never paste against intent / be very safe" rule.* (hunt-engine P1-2b, high conf.)
- **[P1] CLI double-`--start` re-entrancy double-starts a session** (`SpeakEngine.beginDictation()` ~L183, L198-210). No `guard currentSession == nil`; two `--start` (or hotkey+CLI race) before `icon` flips both call `beginDictation()` → `newSession()` overwrites `currentSession`, and `transcriber.startStream` runs **twice on the same shared transcriber**, orphaning the first session's live `streamTask`. Fix: `guard currentSession == nil else { return }` atop `beginDictation()`. (hunt-engine P1-3, high conf. The CLI icon-gate window from 2.3's caveat is real after all.)
- **[P2→P1?] Empty-transcript clobbers clipboard** (`CaptureSession.stop()` ~L249-295 / `SpeakEngine` ~L279). Silent start+stop → `rawText == ""` → `inserter.insert("")` (clipboard floor **wipes the user's clipboard**) + saves a zero-char history entry. Fix: guard empty `rawText` → reach `.done`, skip paste + history. (hunt-engine P1-1, high conf.)
- **[MEDIUM-security] Command-mode prompt injection** (`FoundationModelsCleaner` ~L207-214). Dictated instruction interpolated verbatim into a double-quoted system-prompt slot (`instruction: "\(trimmed)"`); only whitespace-trimmed. A crafted utterance can close the quote and inject a competing instruction. Fix: escape `"`→`'` (or `\"`) and strip `\n`. FM guardrails attenuate but the structural seam is real. (hunt-cleanup N1, med conf.)
- **[MEDIUM-security] Vocabulary-term prompt injection** (`FoundationModelsCleaner` ~L301-302). Same class: dictionary terms wrapped in `"\"\($0)\""`; a term containing `"`/`\n` breaks out. Fix: same escaping. (hunt-cleanup N2, med conf.)
- **[P2, med-high] Start/stop race leaves the mic hot forever** (`AppleSpeechTranscriber` ~L160,196-198). If `stop()` arrives before the session Task reaches `setStopProducer` (L198), `stopSession()` finds nil producer+task (no-ops), then `run()` starts the mic and blocks on `await bridgeTask.value` with no escape — mic never released. Fix: register `sessionTask` synchronously (not fire-and-forget `Task{}`) or add a `stopRequested` flag checked after `audioProducer.start()`. (hunt-stt N-1.)
- **[P2] Stream consumer-abandonment leaks the mic** (`AppleSpeechTranscriber` ~L145). `startStream` has no `continuation.onTermination` — a consumer that cancels its task without calling `stop()` orphans the session + leaves the tap installed. Fix: `continuation.onTermination = { _ in Task { await state.stopSession() } }`. (hunt-stt N-2.)
- **✅ Refuted (STT side):** empty-transcript *hang* — the results stream closes cleanly on silence (hunt-stt P1-1). (Engine-side empty-text clipboard-clobber above is still real.)

### MEDIUM confirmed bugs
- **[Med] `cleanupSeconds` near-zero sentinel collision** (`CaptureSession` ~L525). If the two `DispatchTime.now()` reads return the same ns (fast machine / mocked cleaner), the cleanup-ran path yields `0.0` → `LatencyStats` misclassifies it as the **raw** population. Fix: substitute a 1ns floor when end==start so the `==0`/`>0` partition stays honest. (hunt-engine N-4.)
- **[Med] Int32 truncation in `trimToCapacity`** (`HistoryStore` ~L265) — `sqlite3_bind_int(Int32(maxEntries))` vs `recent()` using `int64`. Latent (UI caps well below Int32.max) but inconsistent. Fix: `sqlite3_bind_int64`. (hunt-storage N-1.)
- **[Med] `search()` has no `LIMIT`** (`HistoryStore` ~L162-175) — a common-word search over 10k rows decodes all matches at once (heap spike). Fix: `LIMIT 500`. (hunt-storage N-2.)
- **[Med] Dashboard shows stale hotkey keycaps after rebind** (`WindowPresenter`/`DashboardWindowController`) — `hotkeyCombo` captured at controller construction, not at `show()`. (hunt-app N5.)
- **[Med] Duplicate `watchForCompletion` watcher on onboarding re-show** (`OnboardingWindowController` ~L147) — task not stored; a 2nd `show()` spawns a 2nd poll, both racing to set `autoCloseTask`; first becomes uncancellable. (hunt-app N3.)
- **[Med] `UserDefaults` read on every render** (`OnboardingViewModel` ~L67) — `currentHotkeyDisplayString` allocates a `UserDefaultsBindingStore` + reads UD per body render. (hunt-app N2.)
- **[Med] `.accessibility` paste-mode picker row selectable despite `.disabled(true)`** (`SettingsView` ~L125) — `.disabled` on the tag doesn't block selection; keyboard-nav can write the stub mode. (hunt-app N9.)
- **[Med] Silent language reset** (`SettingsView` ~L317-333) — stored locale unsupported on this Mac → silently reset to `s[0]` with no user feedback. (hunt-app N8; echoes 1.2.)

### LOW / polish (confirmed)
- Wrong progress dot highlighted on the Done screen (`OnboardingView` ~L106; `.done` excluded from `allSteps` → index nil → dot 0 lit). (hunt-app N7, easy.)
- `cancel()` doesn't guard `.done` terminal state → can re-enter `.error` + double `transcriber.stop()` (hunt-engine N-1).
- Late `ingest()`/`failStream()` after `cancel()` can still mutate state (hunt-engine N-2).
- Two separate `Date()` calls make `duration` vs `createdAt` slightly inconsistent (hunt-engine N-3, one-line fix).
- `endDictation()` post-await overwrite (lower-blast-radius sibling of P1-2b) (hunt-engine N-5).
- HotkeyRecorderView NSEvent monitor `[self]` value-capture fragility (hunt-app N1).
- `icon = .listening` set before `overlayController.start()` returns (hunt-app N4).
- No per-term length cap on vocabulary (graceful raw-fallback, latency cost) (hunt-cleanup N3).
- `engineId`/encode-failure silent fallbacks in storage (hunt-storage N-4/5/6, info).
- **STT P2-1** no model prewarm (cold-start ~1-3s on first dictation) — confirmed (hunt-stt; overlaps 1A P2).
- **STT P2-2** no `AssetInventory.reserve(locale:)` → OS can evict model under storage pressure — confirmed (hunt-stt; overlaps 1A P2).
- **STT P3 (hardware portability, latent on current Macs):** converter-init-failure feeds wrong format to analyzer silently (N-3); `rmsLevel` assumes Float32 channel data (N-4); converter-failure error lacks format logging (N-5); double-space join between isFinal segments `[unverified live model]` (N-6).

### DOC-only (confirmed, matches Phase 1B)
- `FoundationModelsCleaner` header `[verified]` tags wrong: `LanguageModelSession.init(model:guardrails:instructions:)` doesn't exist (code uses correct two-step); `GenerationError` not `@frozen`/exhaustive. (hunt-cleanup C1/N4.)

### Test-coverage additions (agent-doable, from 1C + confirmed)
`triggerMode` + `cleanupStyle` + `.mlx` round-trip tests; CLI real-gate (not the reimplementation); `endDictation` error branches E2E; `rebindHotkey`+Combine; snippet-in-session E2E; partials drain; empty-transcript; multi-display positioning; OnboardingViewModel lifecycle.

## Phase 3 — adversarial verification of findings  *(pending — will target the 5 HIGH-VALUE bugs + 2 security injections)*
## Phase 4 — prioritized fix batches for user approval  *(pending)*
