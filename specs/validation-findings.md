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

## Phase 2 — per-seam code bug hunt  *(ALL 6 seams in: engine, cleanup, storage, app, STT, input)*

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

#### Input seam (hunt-input — final seam)
- **[P1] Double-tap detector desync after out-of-band stop** (`HotkeyMonitor.buildTap` ~L349-352 + `DictationController.endDictation` ~L541-563). `DoubleTapDetector.isCapturing` is only reset in `buildTap()`, but sessions end *without the monitor knowing* (Escape→`endDictation`, CLI `--stop`, auto-stop, error). After such a stop `detector.isCapturing` stays `true`, so the **next double-tap is swallowed** (first tap returns `.stopCapture` to an idle engine = no-op; second tap returns nil) — the user must double-tap a *third* time. Reproducible on every Escape-stop. Fix: add `HotkeyMonitor.syncCapturingState(_:)`/`reset()` and call from `endDictation()`. ~5 lines. (hunt-input NEW-1, high conf. **This is high-frequency + user-visible — arguably the most impactful input bug.**)
- **[P1, MEDIUM-HIGH conf] `tapCallback` over-retains the passed-through CGEvent** (`HotkeyMonitor` ~L423,L427). Returns `Unmanaged.passRetained(event)`; the `CGEventTapCallBack` typedef (`CGEventTypes.h:451`) has **no `CF_RETURNS_RETAINED`** → return is +0, so `passRetained` leaks one CGEvent per flagsChanged (every modifier press while armed). Low-frequency but unbounded over app lifetime. Fix: `passUnretained(event)` at both sites (2-char ×2). **Note:** both compile (Swift can't verify CF ownership from the typedef) — Phase 3 must confirm against an authoritative OSS CGEventTap impl (AltTab). (hunt-input NEW-3.)
- **[P1, latent] `deinit` UAF — watchdog timer not invalidated** (`HotkeyMonitor` ~L222-232, timer ~L279-303). `deinit` tears down the tap but never invalidates the 100ms `CFRunLoopTimer` (which holds `Unmanaged.passUnretained(self)`) nor `CFRunLoopStop`s the thread. App-lifetime use masks it; **real UAF in tests** that create/destroy short-lived instances. Fix: store timer as ivar, `CFRunLoopTimerInvalidate` + `CFRunLoopStop` in `deinit`. (hunt-input NEW-2, med conf.)
- **⚠️ CONFLICT — CLI double-`--start` severity.** hunt-engine rated this **P1** (double `beginDictation` on shared transcriber). hunt-input rates the *gate* as illusory but **LOW real-world impact**: both `--start` Tasks are queued on MainActor and run serially, so the second hits a non-idle engine and no-ops. **The two reports disagree on whether the engine actually no-ops the second start.** → **Phase 3 must resolve: does `beginDictation()` self-guard against a non-nil `currentSession`, or not?** If it does, hunt-input is right (low); if not, hunt-engine is right (P1 — the `guard currentSession == nil` fix stands). This is the #1 Phase-3 reconciliation target.

##### Input — MEDIUM/LOW (confirmed)
- **[P2] `tearDownTap()` mutates `eventTap`/`runLoopSource` off the run-loop thread** (called from `stop()`+`deinit` on main; races `handleTapDisabled`/`buildTap` on the tap thread). `NSLock` guards only the bool flags, not the tap pointers → TSan-visible data race; not hit in practice. Fix: extend lock or route via `CFRunLoopPerformBlock`. (hunt-input NEW-4.)
- **[P2] `wakeRearmTimer` torn read/write across threads** (written in `handleWakeNotification` on the NSWorkspace thread + the rearm callback on the run-loop thread, unlocked). (hunt-input NEW-5, low.)
- **[P2] `modifierMask(forKeyCode:)` defaults to `.maskCommand`** (`HotkeyDetection` ~L45) for any unrecognized keyCode → a binding outside Fn/L-Cmd/R-Cmd would derive down-state from the wrong flag and never register. Bounded by what the W1.1 recorder permits. Fix: verify recorder scope; else add cases / return an always-false sentinel. (hunt-input NEW-6, low — **cross-check against recorder allow-list**.)
- **[P2] `triggerModeCancellable` over-fires** (`DictationController` ~L235-247) — sinks `objectWillChange` (fires on *any* `@Published` change) → spurious `updateBinding()` + UserDefaults write on every unrelated settings edit. Fix: `store.$triggerMode.removeDuplicates()`. (hunt-input NEW-7, low — efficiency/noise only. Overlaps the 1.2 "silent reset" cluster.)
- **✅ Confirmed SAFE (do NOT fix):** `CLIPortServer` `MainActor.assumeIsolated` (callback is scheduled on `CFRunLoopGetMain()` — correct); `updateBinding` no-re-arm (callback live-reads `binding` — correct by design); `CLIPortServer.encodeReply` `passRetained(data)` (the `CFMessagePortCallBack` return **IS** `CF_RETURNS_RETAINED` — correct, *contrast with NEW-3's CGEventTap which is not*); SecureFieldDetector fail-open direction (correct fail-safe). (hunt-input P1-3/P1-4 + non-bugs.)

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

## Phase 3 — adversarial verification of findings  *(COMPLETE — 4 of 4 skeptics in)*

Method: independent skeptics, "REFUTED unless the exact reachable path is traced." Read-only.

### skeptic-engine (CONFIRMED all 3; primary-source) ✅
- **CLAIM 1 — cancel-during-processing paste → CONFIRMED-REAL.** `CaptureSession` is a Swift `actor` (L32); `stop()` suspends at `await task.value` (L237); `cancel()` enters the actor during suspension, sets `state=.error(.sessionCancelled)` (L347); `stop()` resumes with **no state re-check**, pastes at L281, then `state=.done` (L320) overwrites `.error`. Fix (re-check `if case .error = state { throw }` after L237, before L281) = **correct & sufficient.**
- **CLAIM 2 — empty-transcript clobber → CONFIRMED-REAL.** No empty guard anywhere in `stop()`: L249 `transcribed=""` → L253 `rawText=""` → L263 `runCleanup("")`→(nil,id,0.0) → L284 `inserter.insert("")`. Fix (guard `rawText.isEmpty` after L253 → skip paste+history, reach `.done`) = **correct & sufficient.**
- **CLAIM 3 — CLI double-`--start` → CONFIRMED-REAL. CONFLICT RESOLVED: hunt-engine RIGHT, hunt-input WRONG.** `SpeakEngine` is `public actor` (L53), **NOT `@MainActor`**. `beginDictation()` (L192-204) has only a mute guard — **zero `currentSession` guard** before `newSession()`. Suspension at `await session.start()` (L203) lets a 2nd call enter, replace `currentSession` (L177), and orphan the 1st session's `streamTask` (leaks indefinitely). hunt-input's "serializes on MainActor → second no-ops" is structurally wrong (it's a bare actor, and the guard it assumed does not exist). Fix (`guard currentSession == nil else { return }` before L201) = **correct & sufficient.**

### skeptic-cleanup (both injections REFUTED) ❌→dropped
- **Command-mode prompt injection → REFUTED.** Dictated text lands in the session **instructions** slot (`LanguageModelSession(model:instructions:)`); selected text is a separate channel (`session.respond(to:)` L99). The `"\(trimmed)"` quotes are NL prose, not a grammar the model parses to "close quote + inject" — at most a generic jailbreak (dictating "ignore previous…"), not a code-level seam. **No privilege boundary: the user is the operator** (own hotkey → own instruction → own selected text → own document). On-device, no tools/network → no exfiltration. Worst case = unexpected text in the user's own doc. **Fix unnecessary** (string-sanitizing does nothing; the model parses meaning, not quote syntax).
- **Vocabulary-term prompt injection → REFUTED on threat-model grounds.** ⚠️ **Correction:** skeptic-cleanup reported "the code does not exist" — that was a **stale-baseline artifact** (it read the `wave23-cli` worktree's pre-Wave-2.2 `FoundationModelsCleaner.swift` = 293 lines). In **ship** code (master, 319 lines) the vocab clause **does exist**: L287-309 interpolates `customVocabulary.prefix(50)` terms as `"\"\($0)\""` into the FM system instructions (matches hunt-cleanup N2 + my Wave 2.2 work). It is still correctly **dropped**, but for the reason that holds regardless of code location: **no privilege boundary** — the user types their own dictionary terms into their own prompt to clean their own text on-device with no tools/network. (`customVocabulary` ALSO flows into `AppleSpeechTranscriber.contextualStrings` as a typed STT hint — a second, safe path.)
- **Threat-model note:** classic injection needs attacker≠user, or model tools/network, or output→trusted downstream. None hold (on-device FM, no function-calling, output is clipboard text the user sees first). → **Both removed from the fix backlog.**

### skeptic-stt (1 confirmed, 1 refuted)
- **CLAIM 1 — start/stop race → mic hot forever → CONFIRMED-REAL.** `startStream()` creates the session Task (L147) then a **separate fire-and-forget** `Task { await state.setSessionTask(task) }` (L160). Actors serialize but give no ordering guarantee between the two. If `stop()`→`stopSession()` wins actor entry before L160 runs: `stopProducer`/`sessionTask` both nil → no-op; then the session Task proceeds → `audioProducer.start()` (L197, **mic hot**) → `setStopProducer` (L198, nobody will call it) → `await bridgeTask.value` (L248, **blocks forever**). Mic runs until process exit. Fix (`stopRequested` flag set in `stopSession()`, checked right after L197 → `audioProducer.stop()`+return) = **correct & sufficient; no protocol change.**
- **CLAIM 2 — consumer-abandonment leak → REFUTED (production).** The ONLY production caller is `CaptureSession.start()` (L184); every exit (`stop()` L231, `cancel()` L344) calls `await transcriber.stop()`. No reachable abandonment path; test callers always stop too. `onTermination` would also double-fire `stopSession()` on the normal path (benign but pointless). → **Dropped: unnecessary.**

### skeptic-input (both CONFIRMED; primary-source on the leak)
- **CLAIM 1 — detector desync after out-of-band stop → CONFIRMED-REAL.** `DoubleTapDetector.register()` (HotkeyDetection L147-165): `isCapturing==true`→`.stopCapture`+reset; else 2nd-tap-in-window→`.startCapture`; else record+nil. `detector.reset()` is called **only** in `buildTap()` (L349), which runs only on the AX untrusted→trusted edge + wake-rearm. `endDictation()` / `cancelDictation()` / Escape / CLI `--stop` never reset it. So after any out-of-band stop, the next double-tap needs a **3rd tap** (tap1→`.stopCapture` no-op + resets, tap2→records+nil, tap3→`.startCapture`). **FIX CAVEAT (important):** `detector` is documented run-loop-thread-only (L163); a `notifySessionEnded()` from the main actor must reset via the `NSLock` **or** a lock-guarded `pendingDetectorReset` flag applied by the run-loop thread (mirror the `armingDesired` pattern) — the naive reset adds a data race. Fix correct in concept; **must** address threading.
- **CLAIM 2 — `passRetained` CGEvent leak → CONFIRMED-REAL (primary source).** `CGEventTypes.h:451` typedef has **no `CF_RETURNS_RETAINED`**; the header comment (L444-446) states the calling code retains the event and releases it after the callback returns → Get Rule → callback must return **+0**. `passRetained` at HotkeyMonitor L423/L427 hands the system a +1 it never releases → one CGEvent leaked per flagsChanged. Hammerspoon / AltTab / karabiner-elements all pass through with no extra retain. Fix (`passUnretained` at both sites) = **correct & sufficient**, no threading implications.

---

## ⚠️ Audited-baseline note (read before trusting line numbers)

Skeptics + hunters read the **`wave23-cli` worktree** (HEAD `d3382c5`); ship is **`master`** (`d8db7a6`). Diff of the 9 audited source files: **7 IDENTICAL** to ship → their line numbers + verdicts stand verbatim (CaptureSession, AppleSpeechTranscriber, HotkeyMonitor, HotkeyDetection, DictationController, PasteboardWriter, CLIPortServer). **2 were behind ship** (`SpeakEngine.swift`, `FoundationModelsCleaner.swift` — the worktree predates Wave 2.2 vocab plumbing). Both re-checked against ship:
- **A3 (CLI double-start) re-verified against ship:** `beginDictation()` is at ship L198; only `guard !muted` (L203) precedes `newSession()` (L207); **no `currentSession` guard** → finding HOLDS. (Skeptic's L192-204 cites stale numbers; ship = L198-207.)
- **Vocab-injection re-checked against ship:** code DOES exist (L287-309) — see corrected verdict below; still dropped, on threat-model grounds.

**Confidence asymmetry:** the 9 CONFIRMED high-value bugs got adversarial verification (4 of ~13 claims were refuted — a real ~30% false-positive rate). The **12 MEDIUM** + the **hunt-input2 NEW** findings did NOT get an adversarial pass. → Every Batch C-NEW/D item is tagged **"re-confirm the exact site before implementing"**; an implementer must grep the live line before editing.

---

## VERDICT TALLY (Phase 2 + Phase 3)

**CONFIRMED-REAL (9):** cancel-during-processing paste · CLI double-start · empty-transcript clobber · STT start/stop mic-leak race · detector desync · passRetained leak · paste 10ms gap (code-confirmed; live-impact `[unverified]`) · hold-mode stuck on tap death · deinit UAF (latent app / real in tests).
**REFUTED & DROPPED (4):** command-mode prompt injection · vocab-term injection (code didn't exist) · STT consumer-abandonment leak · STT empty-transcript hang.
**MEDIUM confirmed (12):** cleanupSeconds sentinel · Int32 trim · search no-LIMIT · stale keycaps · dup watcher · UserDefaults-per-render · picker row selectable · silent language reset · tearDownTap race · wakeRearmTimer race · modifierMask default · triggerMode over-fire.

### Addendum — hunt-input2 (late Phase-2 input re-hunt; not Phase-3-verified, but concrete + actionable)
- **[refines C2 — deeper diagnosis]** The stuck-session-on-tap-teardown affects **double-tap mode too, not just hold.** Root cause is controller-level: `startArmStateTask()` (DictationController L479-489) on `armed==false` only sets `permissionsNeeded=true` — it never calls `cancelDictation()`. So when `tearDownTap()` fires mid-session, the engine stays `.listening` and after rebuild `detector.isCapturing==false` makes the next tap read as a fresh first-tap against a still-running engine. **The robust fix is at the controller: on disarm while `icon==.listening`, dispatch `endDictation()` (preserve transcript) / `cancelDictation()`** — this subsumes the tap-level `.stopCapture` yield in C2. *(Reconcile with skeptic-input C2 + NEW-1 during Batch C.)*
- **[NEW][P2] Weak-self race in monitor init** (HotkeyMonitor L217-219): `Thread.detachNewThread { [weak self] in self?.runLoopMain() }` — if the monitor is released before the thread starts, `runLoopMain()` never runs, `tapRunLoop` never set, monitor silently dead (no crash). Latent in app (held for lifetime); real in transient/test paths. Fix: strong capture (or `Unmanaged.passRetained` + `takeRetainedValue` in the closure).
- **[NEW][P3, high-conf] CLI source on `.defaultMode` not `.commonModes`** (CLIPortServer L124,137): while a modal is up (onboarding window, settings sheet, menu-tracking) the run loop switches modes and the CLI callback never fires → `speak --status`/`--stop` silently 3s-timeout. Fix: `.commonModes` for both add+remove. *(Real CLI usability bug if CLI-while-modal is a use case.)*
- **[NEW][P3, high-conf] Spurious `permissionsNeeded` flicker on every expected re-arm** (DictationController L486-489): each `tearDownTap()` yields `armStateChanges(false)` → `permissionsNeeded=true` for one tick on every normal wake/rate-limit re-arm (AX still granted). Fix: only set `permissionsNeeded=true` on disarm when `AXIsProcessTrusted()==false`.
- **[NEW][P3, low] rate-limiter is per-arm-cycle** (HotkeyMonitor L385-388): `restartRateLimiter.reset()` on every `buildTap()` → never permanently gives up on a persistent macOS tap-disable. Doc-gap / may be intentional; note in code.

---

## Phase 4 — prioritized fix batches for user approval

> **AWAITING USER APPROVAL — no code changes yet.** Batches are file-disjoint by seam → safe to fan out in parallel worktrees (one owner each); orchestrator reviews diffs + owns commits. Every batch ends green on `make build/test/lint/verify-moat`.

### ⭐ BATCH A — Safety-critical session integrity *(builder-engine; `CaptureSession.swift` + `SpeakEngine.swift`)*
Directly protects the hard rules "never paste against intent" + "don't corrupt other apps' clipboard."
- **A1** Cancel-during-processing paste: re-check `if case .error = state { cleanup; throw }` after the last `await` in `stop()` (post-L237), before paste (L281) and before `.done` (L320).
- **A2** Empty-transcript clobber: guard `rawText.isEmpty` after L253 → skip paste + skip history, reach `.done`.
- **A3** CLI double-start: `guard currentSession == nil else { return }` atop `beginDictation()` (ship: after `guard !muted` L203, before `newSession()` L207).
- **A4 (bundled MEDIUM)** cleanupSeconds sentinel: 1ns floor when `end==start` so the raw/cleanup partition stays honest.
- *+regression tests for A1/A2/A3 (cancel-during-await, empty path, re-entrant start).*

### ⭐ BATCH B — Resource-leak / lifecycle P1 *(builder-audio-stt: `AppleSpeechTranscriber.swift`)*
- **B1** Start/stop mic-leak race: `stopRequested` flag set in `stopSession()`, checked immediately after `audioProducer.start()` (L197) → `audioProducer.stop()` + return. No protocol change. *(Refuted siblings B-abandon NOT done.)*

### ⭐ BATCH C — Hotkey lifecycle & paste P1 *(builder-input: `HotkeyMonitor.swift` + `HotkeyDetection.swift` + `DictationController.swift` + `PasteboardWriter.swift`)*
One owner — these all cluster in the input seam (C1/C2/C4/C5 share `HotkeyMonitor`).
- **C1** Detector desync: `notifySessionEnded()` resetting `detector`+`lastBoundKeyDown` via lock / `pendingDetectorReset` flag (NOT a naive main-actor reset — threading caveat), called from `endDictation()` + `cancelDictation()`.
- **C2** Stuck-session on tap teardown (hold AND double-tap): tap-level — in `tearDownTap()`, if `_binding.trigger == .hold && lastBoundKeyDown` → `yield(.stopCapture)`; **plus** the more robust controller-level fix (hunt-input2): in `startArmStateTask()`, on disarm while `icon==.listening` → `endDictation()`. Implement together — the controller fix covers double-tap mode the tap-level yield misses.
- **C6 (NEW, P3 high-conf)** CLI source mode: `.defaultMode`→`.commonModes` at CLIPortServer L124,137 so `--status`/`--stop` work while a modal is open.
- **C7 (NEW, P3 high-conf)** Suppress `permissionsNeeded` flicker: only set it on disarm when `AXIsProcessTrusted()==false` (DictationController L486-489).
- **C8 (NEW, P2)** Monitor-init weak-self race: strong-capture `self` in `Thread.detachNewThread` (HotkeyMonitor L217-219).
- **C3** Paste 10ms gap: `try await Task.sleep(for: .milliseconds(10))` between the 4 CGEvents (`simulateCmdV` → `async throws`; call site `try await`). *(code-confirmed vs VoiceInk; live-paste impact is a Human-Gate item.)*
- **C4** `passRetained`→`passUnretained` at L423/L427.
- **C5** deinit UAF: store watchdog timer as ivar → `CFRunLoopTimerInvalidate` + `CFRunLoopStop(tapRunLoop)` in `deinit`.

### BATCH D — Medium robustness *(builder-app + builder-engine/storage; storage + app UI files)*
search() `LIMIT 500` · `Int32`→`int64` in `trimToCapacity` · stale hotkey keycaps (capture at `show()`) · dup `watchForCompletion` watcher · `UserDefaults`-per-render · `.accessibility` picker row selectable · silent language reset (surface feedback) · `triggerMode` `removeDuplicates()` · tearDownTap/wakeRearmTimer lock coverage (TSan) · modifierMask recorder-scope check.

### BATCH E — Polish + test-coverage *(builder-qa; optional, lowest risk)*
Onboarding dot/Done-screen index · cancel `.done` guard · late-ingest guard · two-`Date()` consistency · prewarm + `AssetInventory.reserve` (STT P2) · the 1C test-coverage additions (triggerMode/cleanupStyle/.mlx round-trips, real CLI gate, endDictation error branches, rebind+Combine, snippet-in-session, partials drain, empty-transcript, multi-display, OnboardingViewModel lifecycle).

### DOC-only (no risk; bundle anytime)
Fix the 3 skill drifts (Phase 1B): `foundation-models-cleanup` FM init pattern + stale `CleanupMode`; `cgeventtap-hotkey` Input-Monitoring reason; soften altool "removed"→"deprecated". Plus `FoundationModelsCleaner` header `[verified]` tag correction.

### Recommended order
**A → B/C in parallel → D → E.** A is the safety core (smallest, highest-value). B and C are file-disjoint from A and each other → parallel worktrees. D/E are robustness/polish. Human-Gate items (live paste in 3 apps, latency, false-trigger rate, notarize) remain owner-only and unblock `v0.0.1`.

---

## Phase 5 — Fresh seam review (loop #27, 2026-06-26, post fix-input2)

> **Scope:** 5 parallel seam-review agents ran against master post-merge of fix-input2. Read-only.
> Agents: review-cleanup ✅ · review-app ✅ · review-audio-stt ✅ · review-engine ⏳ · review-input ⏳
> **All findings below are NEW** (not in Phase 2–3). Merges into Batches A–E or new Batch F.

### Phase 5 — NEW HIGH findings

**[STT-H1][agent] SpeechPrewarmer.warmModel() is effectively a no-op**
`SpeakCore/STT/SpeechPrewarmer.swift` lines 67–94. `warmModel()` only calls the static `SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith:)` — it never constructs a `SpeechAnalyzer` instance with `Options(priority:.background, modelRetention:.processLifetime)`. Whether a bare static format query causes model loading is `[inferred]`; if not, the prewarm does nothing and the 1–3s cold-start on first dictation is not eliminated. Fix: create a real `SpeechAnalyzer` instance in `warmModel()` using the verified `Options` API (SDK-confirmed). → Add to BATCH E (STT P2).

**[STT-H2][agent] Missing `cancelAll()` on Steps 3–4 failure in `Session.run()` — analyzer abandoned**
`SpeakCore/STT/AppleSpeechTranscriber.swift` lines 283–290. If `finalizeAndFinishThroughEndOfInput()` (Step 3, `async throws` [SDK verified]) or `resultsTask.value` (Step 4) throws, the error propagates without calling `analyzer.cancelAndFinishNow()` [SDK verified: `async`, no throws]. The analyzer is left live; the bridge task may hold `inputCont`. B1 (mic-leak race in `startStream`) is a separate site. Fix: `defer { Task { await state.cancelAll(analyzer: analyzer) } }` after the analyzer is created. → Add to BATCH B.

**[Cleanup-H1][agent] `isAvailable` checks a different `SystemLanguageModel` instance than `clean()` uses**
`SpeakCore/Cleanup/FoundationModelsCleaner.swift` lines 55 / 86–89. `isAvailable` reads `SystemLanguageModel.default.availability`; `clean()` constructs `SystemLanguageModel(useCase:.general, guardrails:.permissiveContentTransformations)`. These are different instances. If Apple gates availability per guardrail config, false-available: `isAvailable` → true, `clean()` → throws `assetsUnavailable`. Fix: store a single `let model = SystemLanguageModel(useCase:.general, guardrails:.permissiveContentTransformations)` as an ivar and check `model.availability` in `isAvailable`. → Add to BATCH B (cleanup seam, file-disjoint from A).

**[App-H1][agent] `HistoryStore.init` leaks SQLite handle on open failure or `setupSchema` throw**
`SpeakCore/Storage/HistoryStore.swift` lines 65–77. `sqlite3_open_v2` sets `*ppDb` to a non-nil error-reporting handle even on failure (documented). The `init` throws → `deinit` never called → `sqlite3_close_v2` never invoked. Same issue if `setupSchema` throws after a successful open. Fix: `if let db { sqlite3_close_v2(db) }` before any `throw` in `init`. → Add to BATCH D.

**[App-M2][agent] Error overlay HUD has no Escape-dismiss path**
`App/Overlay/OverlayController.swift` lines 209–225 + `App/DictationController.swift` lines 595–601. In the `beginDictation` error path, `start()` was never called, so the Escape monitor was never installed. `showError()` only *keeps* an existing monitor — it doesn't install one. In the `endDictation` error path the monitor IS installed but `onEscapeStop` guards `icon == .listening` (dead in `.error`). Result: error HUD is not user-dismissible via Escape. Fix: in `DictationController.onEscapeStop`, loosen the guard to `icon == .listening || icon == .error`. → Add to BATCH D.

### Phase 5 — NEW MEDIUM findings

**[Cleanup-M1][agent] `isAvailable` emits `.info` on every availability check (hot path)**
`FoundationModelsCleaner.swift` line 59. `isAvailable` is called per-session. `.info` is visible in Console.app by default. Change to `.debug`. → BATCH D.

**[Cleanup-M2][agent] `respond(to:String)` uses `@_disfavoredOverload` path**
Both `LanguageModelSession.init(model:instructions:String?)` and `session.respond(to:String)` use `@_disfavoredOverload` (SDK-verified). Compiles and works today; Apple's intent is migration to typed `Instructions`/`Prompt` API. Low urgency but worth tracking before Apple drops the overloads. → BATCH E.

**[App-M1][agent] `HistoryStore.export()` silently drops 3 benchmark fields**
`SpeakCore/Storage/HistoryStore.swift` lines 197–203. `ExportEntry` omits `duration`, `stopToPasteSeconds`, and `cleanupSeconds` (added in migrations). Export JSON cannot round-trip a full `HistoryEntry`. → BATCH D.

**[STT-M2][agent] `stop()` may return before session task fully terminates**
`SpeakCore/STT/AppleSpeechTranscriber.swift` line 184. The session task registration (fire-and-forget `Task`) may not run before `stop()` checks `sessionTask == nil` and returns. The tail (B1 bail path) is <1ms but undocumented. → BATCH E (add `@testable` comment; no code change needed unless TSan surfaces it).

### Phase 5 — NEW LOW findings

**[Cleanup-L1][agent]** MLXCleaner/OllamaCleaner emit `.warning` on every `isAvailable` poll → should be `.debug`. → BATCH D.
**[Cleanup-L2][agent]** 50-term vocab cap: no `.debug` log when truncation occurs. → BATCH E.
**[Cleanup-L3][agent]** `CleanupLevel.none` unreachable branch has no `assertionFailure` in debug builds. → BATCH E.
**[App-L1][agent]** `effectiveCleanupLevel` setter fires `objectWillChange` twice (double SwiftUI re-render per picker change). → BATCH D.
**[App-L2][agent]** Double `DispatchQueue.main.async` wrapping in trigger-mode Combine subscription (outer `.receive(on:)` + inner `async` — one hop sufficient). → BATCH D.
**[App-L3][agent]** `onboardingController` held for app lifetime after completion (minor memory — objects are small; pattern is uniform). → BATCH E (low priority).
**[App-L4][agent]** History search is case-sensitive (`instr()` uses BINARY collation); no UI affordance. Fix: `lower(rawText)` + `lower(?)`. → BATCH D.
**[App-L5][agent]** `startArmStateTask` inner `MainActor.run` is redundant (already on main actor from `@MainActor` class). → BATCH D.
**[STT-L1][agent]** `SpeechPrewarmer.warmModel()` bare `do {}` scope with misleading "no catch needed" comment. → BATCH E (cleanup alongside STT-H1 fix).
**[STT-L2][agent]** `LocaleSupport.needsDownload` compares `.identifier` strings — normalization assumption undocumented. → BATCH E (add comment).

---

### Phase 5 — NEW findings from review-input ✅

**[Input-M1][agent] `stop()`+`start()` never re-arms tap if AX was already granted**
`HotkeyMonitor.swift` — `watchdogTick()`. `wasTrusted` is NOT reset in `stop()` or `tearDownTap()`. After `stop()+start()`, every watchdog tick sees `nowTrusted=true && wasTrustedPrev=true` — the rising edge never fires — `buildTap()` never called — tap permanently dead. Wake re-arm (`handleWakeNotification`) is unaffected (calls `buildTap()` directly). Impact: any disable/re-enable scenario is silently broken. Fix: reset `wasTrusted = false` under the lock in `stop()`. → **Batch D**.

**[Input-M2][agent] `UserDefaultsBindingStore` `@unchecked Sendable` with non-thread-safe instances**
`BindingStore.swift`. `JSONEncoder` and `JSONDecoder` are instance properties; both are not thread-safe per Apple docs. `save()` is public with no thread constraint. `@unchecked Sendable` suppresses the concurrency checker. Fix: create `JSONEncoder()`/`JSONDecoder()` locally in each call. → **Batch D**.

**[Input-L1]** Two separate lock acquisitions for `wasTrusted` RMW in `watchdogTick()` — fragile TOCTOU (safe today: same thread; hazard if future code writes from another thread). → **Batch D** (combine with Input-M1 fix).
**[Input-L2]** `shutdown()` call site in App target unverified — `deinit` never fires in practice; leaked CGEventTap at process exit if not called. Needs App-layer verification. → **Batch D** (add `AppDelegate.applicationWillTerminate` call).
**[Input-L3]** Wake observer fires on main thread; `CFRunLoopAddTimer` cross-thread call undocumented at callsite. Safe per CF threading model but misleading. → **Batch E** (add clarifying comment).
**[Input-L4]** Task cancellation mid-`simulateCmdV()` can leave ⌘ modifier stuck (if cancelled between event posts). Self-healing but worth noting for a future cancellation-aware paste path. → **Batch E**.

### Phase 5 — NEW findings from review-engine ✅

**[Engine-M1][agent] Double `transcriber.stop()` on cancel()-during-stop() race**
`CaptureSession.swift` lines ~232 + ~390. Both `stop()` and `cancel()` call `await transcriber.stop()`. A `cancel()` arriving while `stop()` is suspended between transcriber.stop() and stream drain submits a second stop. A1's cancel guard correctly aborts paste/done, but if `AppleSpeechTranscriber.stop()` is not idempotent (double-close of `AVAudioEngine`), behavior is undefined. Fix: `guard !stopping` flag on `CaptureSession`. `[unverified: AppleSpeechTranscriber.stop() idempotency]` → **Batch D** (or Bundle with A1).

**[Engine-M2][agent] Stream drain `await task.value` has no timeout**
`CaptureSession.swift` line ~237. After `transcriber.stop()`, `stop()` awaits the background stream task indefinitely. STT hang (hardware fault / heavy load) → session permanently stuck in `.processing`, overlay never hides, engine wedged until restart. `T_cleanup` timeout exists for cleanup; none for drain. → **Batch D**.

**[Engine-L1]** `beginDictation` silently returns on re-entrancy — no throw/signal to caller. DictationController's hotkey debouncer is the guard; this is a defence-in-depth gap. → **Batch E**.
**[Engine-L2]** `currentSession` set before `try await session.start()` — if `start()` throws for a resource error (future), `currentSession` not cleared, wedging `beginDictation`. Fix: `defer { if case .idle = session.state { currentSession = nil } }`. → **Batch D**.
**[Engine-L3]** `partials()` replaces `partialsContinuation` without explicit `finish()` on prior one. Safe (relies on auto-finish-on-deinit) but intent unclear. → **Batch E**.
**[Engine-L4]** `llmCleanupFailed` defined but never thrown (cleanup always falls back). Dead code; needs comment. → **Batch E**.
**[Engine-L5]** `max(0, cleanupSeconds)` floor unreachable (sentinel is `0.0`, delta always ≥ 0). → **Batch E** (add comment or remove).

## Updated batch assignments (post Phase 5)

**BATCH B additions:** STT-H2 (`cancelAll` on finalization failure) · Cleanup-H1 (isAvailable model mismatch)
**BATCH D additions:** App-H1 (SQLite handle leak) · App-M2 (error HUD Escape dismiss) · Cleanup-M1 (isAvailable log level) · App-M1 (export missing fields) · Cleanup-L1 (MLX/Ollama log level) · App-L1 (double objectWillChange) · App-L2 (double dispatch) · App-L4 (case-insensitive search) · App-L5 (redundant MainActor.run) · Input-M1 (wasTrusted not reset) · Input-M2 (JSONEncoder thread-safety) · Input-L1+L2 (lock + shutdown) · Engine-M1 (double transcriber.stop) · Engine-M2 (no drain timeout) · Engine-L2 (currentSession not cleared on throw)
**BATCH E additions:** STT-H1 (prewarm no-op fix) · Cleanup-M2 (disfavored overloads) · STT-M2 (stop ordering doc) · Cleanup-L2/L3 · App-L3 · STT-L1/L2 · Input-L3/L4 · Engine-L1/L3/L4/L5
