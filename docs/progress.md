# `speak` — Progress (NOW)

> **Status**: Living state. **The agent rewrites this every session.**
> Single source of truth for "where are we right now." Read first, update last.
> Never delete history — append. See `../AGENTS.md` §5.

---

## Current phase

> ## 🚩 READ THIS FIRST (handoff banner — 2026-06-22, Wave 1 v0-polish — MERGED, ALL 4 GATES GREEN)
> **Wave 1 (three parallel worktrees) complete + integrated to master. `make build`/`test`/`lint`/`verify-moat` all green on combined master.**
> Per `specs/acceleration-roadmap.md` §2. Salvaged from three agents that died at the session limit mid-task — partial files were finished, wired, gated, and merged (no work discarded).
>
> **1.1 — Hotkey recorder UI** (`App/Settings/HotkeyRecorderView.swift` new +508; `SettingsView.swift` ShortcutsSettingsTab; `DictationController.swift`):
>   - Record-a-combo sheet in Settings▸Shortcuts; persists via `BindingStore`; current binding shown via `HotkeyBinding.displayString`; live re-bind through `controller.rebindHotkey(_:)`.
>   - Mode picker ships **Toggle + Push-to-Talk** only. **Hybrid is DEFERRED** — `HotkeyBinding.Trigger` has just `.doubleTap`/`.hold`; hybrid needs core `HotkeyMonitor` hold-vs-double-tap timing disambiguation (a separate engine task, not UI). Honest footer notes this.
>
> **1.2 — Language picker populated** (`SpeakCore/STT/LocaleSupport.swift` new +102; `SettingsView.swift` TranscriptionSettingsTab):
>   - `SpeechTranscriberLocaleSource` exposes `supportedLocales()`/`installedLocales()` (both Apple `get async`, compile-verified against local macOS 26 SDK). Picker loads async with a ProgressView placeholder (never blank), "(download)" badge for un-installed models, persists `store.language`, resets to first-supported if stored locale vanishes. Selection flows live: `SpeakEngine.newSession()` reads `settings.language` at call time → next dictation uses it, no restart.
>   - Caveat: whether SpeechAnalyzer auto-installs a supported-but-not-installed locale at session start is `[unverified — live]`; `provisionAsset` handles download at transcription time regardless.
>
> **1.3 — Menubar state colors** (`App/Theme/SpeakTheme.swift` +5 tokens; `App/SpeakApp.swift` MenuBarLabel; `DictationController.swift` `#if DEBUG forceIcon`; `DebugLaunchDispatcher.swift` +2 debug routes):
>   - Per-state symbol+tint: idle=waveform/secondary, listening=waveform.circle.fill/red, processing=hourglass/yellow, done=checkmark.circle/green, error=xmark.circle/red. +VoiceOver labels. 600ms done-flash reuses existing `doneFlashNanoseconds`. Rendering via `.symbolRenderingMode(.palette)` + `.foregroundStyle(tint)`.
>   - **⚠️ COLOR RENDERING `[unverified — human visual check]`:** agent env can't screencapture the menubar layer. Verify with `open build/DerivedData/Build/Products/Debug/Speak.app --args --debug-open menubar-icon-listening` → icon should be RED. If monochrome, authorized fallback is `NSStatusItem` + `button.image?.isTemplate = false` (a separate post-P8 task — do NOT do inline).
>
> **Worktree note:** the 1.3 worktree (`agent-a4e257b3191f0f3d1`) is the orchestrator's own primary working dir, so it could not self-remove after merge — clean it up next session (`git worktree remove --force` once operating elsewhere). The 1.1/1.2 worktrees were removed.
>
> **Wave 1.4 + 2.5 ALSO MERGED (same integration pass, all 4 gates green: build / 378 tests 0-fail / lint 0-serious / moat 7/7):**
> - **1.4 cleanup intensity** (`App/Settings/SettingsView.swift` AICleanupSettingsTab; `App/Components/CleanupDiffView.swift`): 4-level None/Light/Medium/High wired end-to-end + raw-vs-cleaned diff surfaced. (None = raw passthrough, skips the LLM.)
> - **2.5 onboarding polish** (`App/Onboarding/OnboardingView.swift` + `OnboardingViewModel.swift`): live current-hotkey display (reads `UserDefaultsBindingStore` in-seam), gesture-mode-agnostic copy fix; "Try it now" pill + overlay waveform were already wired (verified, no work needed).
>
> **⚠️ ORCHESTRATION GOTCHA (learned this session):** the orchestrator's own cwd is a git worktree (`agent-a4e257b3191f0f3d1`). Subagents spawned with `isolation: worktree` did NOT get isolated trees — they committed onto the orchestrator's worktree branch, stacking commits. Safe only because file seams were disjoint + git serialized commits. **For genuinely parallel file-mutating work, create explicit `git worktree add` dirs manually or serialize.** That branch is now fully merged; clean it up next session (`git worktree remove --force` once operating from the main checkout).
>
 **Wave 2.1 + 2.4 ALSO MERGED (manual isolated worktrees; all 4 gates green on combined master: build / 397 tests 0-fail / lint 0-serious / moat 7/7):**
> - **2.1 pluggable cleanup models** (`SpeakCore/Cleanup/{OllamaCleaner,MLXCleaner}.swift` new; `EngineFactories.swift`; `SettingsStore.swift` CleanupEngine enum; `App/Settings/{SettingsView,OllamaSetupSheet}.swift`): user-selectable cleaner behind `LLMCleaning`; FM stays default. **Moat kept 7/7 by shipping Ollama/MLX as `isAvailable==false` stubs — ZERO networking symbols in the build; real localhost-HTTP impl deferred to a future `SpeakLLM` module outside the moat-audited source dirs (v0.1).** Caveat: engine selection applies on app restart (not next-dictation) — benign in v0 since all non-FM engines are raw-fallback stubs; live subscription lands with the real cleaners.
> - **2.4 latency metrics** (`SpeakCore/Engine/LatencyRecord.swift` + `Insights/LatencyStats.swift` new; `CaptureSession.swift`; `HistoryStore.swift`/`HistoryEntry.swift`; `App/Dashboard/Panes/InsightsPaneView.swift`; +20 `LatencyRecordTests`): instruments stop→paste (monotonic `DispatchTime`), partitions raw (`cleanupSeconds==0.0` sentinel) vs cleanup (`>0`) populations, surfaces median/p95 in Insights color-coded against `benchmark.md §7` budgets (raw<1.0s, cleanup<2.0s). **Advisor caught a real bug** (clock-delta jitter made the raw bucket never match `==0`; fixed by returning literal `0.0` from runCleanup's no-cleanup branches). Plumbing only — real numbers need a live dictation run (human-gate).
>
> **Wave 2.2 ALSO MERGED (cherry-picked code commit, all 4 gates green: build / test / lint 0-serious / moat 7/7):**
> - **2.2 richer cleanup** (`SpeakCore/Cleanup/{Cleaner,FoundationModelsCleaner}.swift`; `SpeakEngine.swift`; +`StyleModeTests`): tone/style modes + snippet expander (`snippetStore.makeExpander()`) were ALREADY wired; net-new is the **custom-dictionary clause** — `customVocabulary` now rides inside `CleanupMode.styled(style, level, customVocabulary:)` and is read at call time (H1 pattern), injecting a "preserve these spellings exactly" clause into the FM prompt (50-term cap `[decision]`; empty list → byte-identical-to-baseline prompt, no regression). Style-effectiveness needs live FM to confirm (human-gate). (Agent also self-edited progress.md → discarded; orchestrator owns this file.)
>
> **Next:** Wave 2.3 CLI shim (running — CFMessagePort behind `CLITransport`, contract in `specs/acceleration-roadmap.md` §3). After 2.3, Wave 2 is complete → Wave 3 (code-aware mode, voice editing, history power-tools) + Human-gate track (live paste in 3 apps, latency numbers [plumbing ready], menubar-color visual check, live rebind-fires check, style-effectiveness check, P11 release) — all owner-only.

> ## OLD BANNER (handoff banner — 2026-06-22, Wave 0 live-bug cleanup — MERGED)
> **Two live bugs fixed + integrated to master. ALL 4 GATES GREEN on combined master.**
> Per `specs/acceleration-roadmap.md` Wave 0. The core loop works live (owner dictated this session).
>
> **0.1 — HUD "Cleaning up…" hang FIXED** (`SpeakCore/Engine/CaptureSession.swift`):
>   - Root cause: `runCleanup()` called `cleaner.clean()` (Foundation Models `respond()`) with no
>     timeout; if FM hangs, the `await` never returns → `endDictation()` blocked → overlay stuck in
>     `.processing` forever. Secondary: a thrown cleanup error surfaced an un-dismissable error HUD.
>   - Fix: `runCleanup()` is now `async` (never throws). `clean()` is raced against `T_cleanup = 10 s`
>     (unstructured `Task` + `CheckedContinuation`, double-resume guarded by `OSAllocatedUnfairLock<Bool>`).
>     ALL outcomes — off / unavailable / timeout / throw — fall back to raw transcript → session reaches
>     `.done` → overlay always hides. `T_cleanup = 10 s` (4× architecture p95 budget) added to `benchmark.md §7`.
>   - +4 tests in `CaptureSessionTests.swift` (throw→raw, generic-error→raw, hang→timeout→raw, slow-but-valid→cleaned).
>
> **0.2 — Input Monitoring REMOVED** → onboarding asks **Microphone + Accessibility only** (matches VoiceInk/Wispr):
>   - Why: the CGEventTap is `.defaultTap` → gated on Accessibility alone; IM was vestigial scaffolding from
>     an earlier listen-only-tap design, and the onboarding step *falsely* claimed IM was needed for the hotkey.
>     Empirically confirmed: the hotkey fires with IM NOT granted on the live machine. The tap itself was NOT touched.
>   - New step order: **welcome → microphone → accessibility → hotkey → done** (4 steps, was 5).
>   - Removed across 15 files: `PermissionKind.inputMonitoring`, `requestInputMonitoring()`, `IOHIDCheckAccess`/
>     `IOHIDRequestAccess`/`import IOKit.hid`, `SpeakError.inputMonitoringDenied`, the onboarding step + false copy,
>     the debug route, and all IM tests (`IOKit.hid` dropped from the moat allowlist).
>   - **Docs re-grounded by orchestrator (this commit):** `AGENTS.md §2.2`, `.claude/skills/swift-code-review.md`,
>     `docs/architecture.md`, `docs/product.md §7.3`, `specs/verification-ledger.md` — all updated to "Mic + Accessibility only".

> ## OLD BANNER (handoff banner — 2026-06-22, secure-field paste guard)
> **SECURE-FIELD PASTE GUARD — BUILT & ALL 4 GATES GREEN.**
> Build ✅ · Tests ✅ (374 tests / 5 XCTSkip / 0 failures; +4 new secure-field guard tests) · Lint ✅ (0 serious) · Moat ✅ (7/7).
> **Uncommitted in worktree** — orchestrator reviews diff and owns the commit.
>
> **Problem:** When the user's cursor was in a password/secure text field, `PasteboardWriter.insert()`
> would paste dictated speech into it — a privacy/safety footgun.
>
> **Fix:** Added a secure-field detection gate (step 3) in `PasteboardWriter.insert()`, between the
> AX-trust gate (step 2) and the settle delay (step 4). Uses the Accessibility API to query
> `kAXFocusedUIElementAttribute` → `kAXSubroleAttribute` of the frontmost focused element.
> If the subrole is `kAXSecureTextFieldSubrole` ("AXSecureTextField"), throws
> `SpeakError.pasteIntoSecureField(text:)` and refuses to paste.
>
> **Fail-safe:** Any AX query failure returns `false` → paste proceeds normally. Never blocks
> legitimate pastes on ambiguous results. The clipboard floor (step 1) always runs first so text is
> never lost regardless of gate outcome.
>
> **UX:** DictationController catches `.pasteIntoSecureField` specifically (parallel to the existing
> `.pasteRequiresAccessibility` arm), routes text to Scratchpad, shows the HUD error message
> "Won't paste into a password field — text saved to history." Stays `.idle`, does NOT set
> `permissionsNeeded` (no permission is missing — this is a deliberate safety refusal).
>
> **AX constant verified:** `kAXSecureTextFieldSubrole == "AXSecureTextField"` [verified:
> HIServices/AXRoleConstants.h:408 in local macOS 26 SDK].
>
> **Files changed:**
>   - `SpeakCore/Engine/SpeakError.swift` — new `.pasteIntoSecureField(text:)` case + recoverySuggestion
>   - `SpeakCore/Paste/SecureFieldDetector.swift` — new file: `focusedElementIsSecureField()` free function
>   - `SpeakCore/Paste/PasteboardWriter.swift` — new `isFocusedFieldSecure` injected closure + step 3 gate
>   - `App/DictationController.swift` — new catch arm for `.pasteIntoSecureField`
>   - `SpeakTests/PasteTests.swift` — 4 new tests in `SecureFieldGuardTests`
>
> **Note on `StreamingTextInserting`:** protocol-only (no conformer, not wired in v0). Does NOT need
> the same guard; flagged as a future concern when H5 streaming paste lands.

> ## OLD BANNER (handoff banner — 2026-06-22, P0 correctness fix: long-dictation truncation)
> **P0 TRUNCATION BUG FIX — BUILT & ALL 4 GATES GREEN.**
> Build ✅ · Tests ✅ (all pass, 5 pre-existing XCTSkip, 2 new regression tests added) · Lint ✅ (0 serious) · Moat ✅ (7/7).
> **Uncommitted in worktree** — orchestrator reviews diff and owns the commit.
>
> **Bug:** Long dictation pasted only the last few words even though the HUD displayed the full text.
>
> **Root cause confirmed:** `CaptureSession.ingest()` did `latestChunk = chunk` (replace) on every
> chunk. `SpeechAnalyzer` with `.progressiveTranscription` emits one `isFinal == true` chunk per
> *speech window* (not per utterance) — each containing only that window's text. So `latestChunk`
> held only the last window's text. `OverlayTextAccumulator` is NOT to blame: it uses
> newest-non-empty-wins (also replace, not concat), but it works because volatile chunks for a
> given window are cumulative — each successive volatile contains more of that window's hypothesis.
> The HUD shows the last volatile (the best hypothesis) per window, which looks complete because
> volatiles grow within each window. The final-path bug only manifests across windows.
>
> **Fix:** Added `private var finalizedText: String = ""` to `CaptureSession`. `ingest()` now
> appends each `isFinal` chunk's text to `finalizedText` (space-separated). `stop()` uses
> `finalizedText` when non-empty, falling back to `latestChunk?.text` for short speech where no
> isFinal chunk arrived (volatile-only sessions). `latestChunk` still updates on every chunk
> for the partials/HUD path — behavior unchanged there.
>
> **Trailing-volatile-after-finals edge case:** if a session ends with isFinal chunks + a dangling
> volatile that was never finalized, that volatile tail is not included in `finalizedText`. In
> production this is safe: `AppleSpeechTranscriber.stop()` calls
> `finalizeAndFinishThroughEndOfInput()` which promotes the pending volatile to isFinal before the
> stream closes, so `ingest()` captures it as a final chunk. [decision: relying on this behavior]
>
> **paste == HUD note:** this fix makes paste contain the full transcript (all finalized windows).
> Whether paste byte-matches the HUD end-state string depends on separator spacing between windows —
> tagged `[unverified]` (cannot confirm without a live multi-segment audio corpus). The correctness
> claim is: paste now contains the full utterance text, not just the last window's words.
>
> **Files changed:** `SpeakCore/Engine/CaptureSession.swift` (+18 lines fix, +15 lines comment)
> and `SpeakTests/CaptureSessionTests.swift` (+89 lines: 2 new regression tests).
>
> **New tests (fail→pass demonstrated by stash run):**
>   - `testMultiSegmentFinalChunksAreJoinedInResult` (FAIL pre-fix → PASS post-fix, verified by stash run):
>     simulates 2 speech windows (3 volatile + 1 isFinal each); asserts `rawText == "hello world how are you"`.
>     Pre-fix result was `"how are you"` (last isFinal only).
>   - `testShortUtteranceWithNoFinalChunkUsesLastVolatile` (PASS pre-fix and post-fix — fallback guard):
>     volatile-only session; verifies latestChunk fallback still works when no isFinal chunks arrived.
>     This test is a regression guard, not a fail→pass test (volatile-only path was never broken).

> ## OLD BANNER (2026-06-21, W2.1+W2.2 HUD rebuild)
> **W2.1 + W2.2 — ACTIVE-DICTATION HUD → native-Apple quality — BUILT & ALL 4 GATES GREEN.**
> Build ✅ · Tests ✅ (all pass, 5 pre-existing XCTSkip) · Lint ✅ (0 serious) · Moat ✅ (7/7).
> **Uncommitted in worktree** — orchestrator reviews diff and owns the commit.
>
> **What changed:**
>   - **W2.1 Live mic level wiring**: `AudioCapture` now computes RMS on each input buffer
>     (new static `rmsLevel(buffer:)`) and yields it on a parallel `AsyncStream<Double>`
>     (`startLevelStream()`). `AudioCaptureProviding` protocol + `AppleSpeechTranscriber`
>     conformance exposes the live `AudioCapture` to `CaptureSession.levels()` and
>     `SpeakEngine.currentLevels()`. `OverlayController` drains the level stream in a
>     parallel `levelsTask` (like `partialsTask`) with one-pole smoothing via `levelSmoothed`.
>   - **W2.2 HUD rebuild**: `OverlayState` gains `.error` (payload-free; reason in separate
>     `errorReason: String?` property). `OverlayViewModel` gains `errorReason` + `isCleaningUp`.
>     `TranscriptOverlayView` rebuilt: 15-bar `WaveformView` (VoiceInk blueprint) with per-bar
>     phase ripple (`levelBarHeightsPhased`), Monaco font tokens, `.error` red-pill state,
>     "Cleaning up…" vs "Pasting…" copy keyed on `isCleaningUp`, Reduce-Motion aware,
>     VoiceOver announcements on every state transition.
>   - **Escape-to-cancel**: global `NSEvent` monitor in `OverlayController` observes Escape
>     while panel is visible; fires `onEscapeCancel` → `DictationController.cancelDictation()`.
>   - `DictationController` wired: `showError()` on begin/end failure, `cancelDictation()` verb,
>     honest `isCleaningUp` flag passed at `start()`.
>   - `DebugLaunchDispatcher`: new `overlay-demo-error` target for the error state.
>   - **7 new tests**: error state transitions, level reset, isCleaningUp propagation,
>     `AudioCapture.rmsLevel`, `levelBarHeightsPhased` (5 cases).
>
> **Note on VoiceOver API:** `NSAccessibility.post(element:notification:userInfo:)` with
> `.announcementRequested` + `NSAccessibility.NotificationUserInfoKey` is the macOS 26
> renamed API — used correctly (compile-verified against local SDK).

> ## OLD BANNER (2026-06-21, Phase 2 build)
> **PHASE 2 (full-product dashboard) — EVERY FEATURE BUILT & GREEN; only live human
> verification remains** (running the app on a real Mac — the pre-existing `#8` gate).
> The full-window Wispr-style app is complete; Home screen **visually verified on-screen**.
> Definitive gate from **wiped DerivedData**: build ✅ · **268 tests / 5 XCTSkip / 0
> failures** ✅ · lint **0 serious** ✅ · moat **7/7** ✅. Tree clean at `76d4716`; no
> agents/worktrees running.
>
> **Shipped this phase (commits):**
>   - **WaveA.0/A.1** `7b1187f` — Monaco theme token (`SpeakTheme`) + `KeyCapView` +
>     dashboard spine (sidebar IA, `NavigationSplitView`, `DashboardWindowController`).
>   - **WaveB.1** `176efba` — Style modes seam (`CleanupStyle`×`CleanupLevel`→`.styled`,
>     per-mode prompt composition, settings-derived at `newSession()`) + Style pane.
>   - **WaveA.2** `96daf79` — `InsightsStats` (pure, injected now/calendar) + Insights pane
>     + Home recents (builder-app, integrated by orchestrator).
>   - **WaveA.3** `972594e`+`9e32eb4` — **direction correction from a real Wispr
>     screenshot + web research** (`research/wispr-flow-ui-verified.md`): Home = day-grouped
>     feed + stats rail (was inverted with History); hybrid full-app activation
>     (`.regular` Dock+menu when window open, `.accessory` on close); added **Transforms**
>     + **Scratchpad** sidebar items; greeting + orange `fn` keycap.
>   - **WaveB.2+B.3** `79a8d56` — Snippets (model+`SnippetExpander`+`SnippetStore`, applied
>     BEFORE cleanup in `CaptureSession`) + Dictionary pane (`CustomVocabulary` helper).
>   - **#18** `c53b367` — persist dictation `duration` (SQLite migration) → WPM stat.
>   - **WaveD (partial)** `b7ac26e` — menubar Style + Language quick submenus.
>   - Orchestration: `8a50f1a` — team agents now carry a **worktree-first + never-commit**
>     contract (root-caused via claude-code-guide: bg subagents don't auto-isolate in CC 2.1.x).
>
> **VISUALLY VERIFIED** (`--debug-open dashboard` + `screencapture`): full Mac app with app
> menu, 8-item sidebar, greeting+`fn` keycap, TODAY/YESTERDAY feed, stats rail — matches the
> real Wispr Home in Monaco. (A later WPM-screenshot attempt flaked on a Space/display
> switch; layout already proven, WPM test-verified.)
>
> **Wave D — COMPLETE:** menubar Style/Language submenus (`b7ac26e`) · **Paste Last
> Transcript** Cmd+Ctrl+V (`4a8bd4d`) · **HUD live duration counter** (`db58c87`) ·
> **Command Mode** — full end-to-end: `.command` transform prompt (`da40b0d`),
> `CommandModeService` orchestration + `AccessibilitySelection` AX read/replace (`a67dfdd`),
> `CommandChordDetector` (`a87d1cf`), and the **live Fn+Ctrl trigger wiring** —
> `HotkeyMonitor` emits chord edges (suppresses normal Fn only while Ctrl held → core
> dictation byte-for-byte unchanged when Ctrl up) + `CommandModeController` captures the
> spoken instruction and runs the transform (`c2d48c6`) · **Scratchpad paste-failure
> fallback** — `SpeakError.pasteRequiresAccessibility(text:)` routes failed text to the
> Scratchpad (`76d4716`). App launches clean; chord wiring init verified non-crashing.
>
> **Render-verified (`#16`):** launched **all 8 panes** in the real app via
> `--debug-open dashboard:<section>` (seeded vocab/snippets) — **every pane renders
> crash-free**, including the populated-`List` panes (Dictionary/Snippets/History), which
> rules out the documented diffRows assertion (preview-only, not the real app). Insights
> confirmed = plain SwiftUI bars (no Charts dep) in live code. Home is screenshot-verified;
> pixel-level capture of panes 2–8 was blocked by the user's active Mission Control Space
> (single display; `screencapture` can't reach another Space without AX) — environment, not
> code. Use `--debug-open dashboard:<section>` to screenshot any pane when a Space is free.
>
> **W1.0/W1.1 COMPLETE (2026-06-21, next-iteration-plan.md Wave 1):**
>   - **W1.0 verified**: Right-Command fires `CGEventType.flagsChanged` (not keyDown/keyUp);
>     `kVK_RightCommand = 54` [verified: swiftc + macOS 26 SDK]. Left vs right ⌘ are
>     disambiguated by keycode on the flagsChanged event; both set `.maskCommand` in flags.
>   - **W1.1 implemented**: Default binding changed from Fn (63) to Right-Command (54).
>     Critical fix: `handle()` now uses `modifierMask(forKeyCode:)` → `.maskCommand` for
>     Right-Command (not `.maskSecondaryFn`, which is always false for ⌘ events).
>     `lastBoundKeyDown` tracks the binding's key separately from `lastFnDown` (Fn+Ctrl
>     chord detector). Fn debouncer (40 ms, VoiceInk pattern) applied Fn-path-only.
>     Shared display helpers: `HotkeyBinding.keySymbol` + `.displayString`.
>     `DictationController.currentHotkeyCombo()` now uses `keySymbol` instead of "Fn".
>     Gates: build ✅ · tests ✅ · lint 0 serious ✅ · moat 7/7 ✅. Left in worktree
>     for orchestrator review.
>
> **REMAINING — only LIVE HUMAN VERIFICATION (the pre-existing `#8` gate; agent cannot do):**
>   Run on a real Mac: grant the 3 permissions, dictate (core loop), exercise paste +
>   overlay, and try **Command Mode** (select text in another app, hold Fn+Ctrl, speak,
>   release → AX-replaced) + the **paste-failure → Scratchpad** path. Every code path is
>   built + unit-tested where possible + render-verified crash-free; what needs a human is
>   *observing it run live with a voice + permissions + real apps* — by nature, not by gap.
>   **No un-built features remain.**
>
> **Locked user decisions:** local-first/pluggable-later · full-window dashboard ·
> **Monaco** ([[monaco-font-theme]]) · **Wave C (WhisperKit/Ollama) deliberately OUT** —
> third-party deps break the moat. Base hard rules (`CLAUDE.md`/`AGENTS.md`) still bind.
>
> **Durable lessons (METHOD — re-verify live, not from memory):** (1) `Agent(isolation:
> "worktree")` does NOT isolate **named/background** subagents in CC 2.1.x — they write the
> shared checkout. Verify `git worktree list` after spawning; the standing fix is each agent
> calls `EnterWorktree` first + never commits (now in the team prompts). (2) SourceKit goes
> **stale/phantom** after edits — a clean `make build` is the only authority, never the LSP.
> [[agent-first-acceleration-model]]


**The entire v0 surface is built — engine, pipeline, AND all UI — and the app is
RUNNABLE.** Engine seam (P0–P3.5) + P5 hotkey + P6 paste + P9 history + the
**`SpeakEngine` facade** + **app-shell wiring**, and now the full UI: **P10
settings, P8 menubar states, P4 partial overlay, P7 3-permission onboarding**
(built after the user authorized the UI phase, 2026-06-21). `make run` launches a
menubar app that, given live permissions, runs **onboarding → double-tap Fn →
overlay streams partials → capture → on-device cleanup → paste at cursor → local
history**, with a Settings window (live cleanup toggle) and state-reflecting
menubar, plus a **History window** and a **hardware-mute** toggle (loop #16).
`make test` **150 tests (130 XCTest + 20 Swift Testing; 5 XCTSkip live-FM), 0
failures**; `make verify-moat` **7/7** (5 of 7 structural BEAT rows proven by
automated audit — no egress, no account, no third-party, MIT, offline).

**Two further autonomous gaps were closed in loop #16** (2026-06-21): the **History
window UI** (SPEC §5.6 / roadmap P9 — was the last unbuilt UI surface; store layer
was already done+tested) and **hardware mute** (SPEC §7.4 / product.md §8 #4 — was
"design posture, not yet implemented"; now enforced in the engine). `make test`
**150 tests (130 XCTest + 20 Swift Testing; 5 XCTSkip live-FM), 0 failures**;
`make verify-moat` **7/7**; lint 0 serious.

**The autonomously-buildable scope is now genuinely exhausted (re-confirmed by a
SPEC §5–§7 feature scan).** What remains for the v0 ship gate is **irreducibly live
or a data dependency**, all tracked in **`docs/human-verification.md`**: grant
Accessibility (Microphone handled in onboarding) + enable Apple Intelligence; the live UI screens
(§4.1–4.6, now incl. the History window §4.5 and the mute behavior §4.6); the
global hotkey firing; paste into TextEdit/Slack/**Terminal** (the #1 `[unverified]`
— macOS 26.4 paste-provenance); live Foundation Models cleanup quality; the §6
~20-clip WER corpus (audio only a human can supply); Developer-ID sign/notarize
(P11). None are marked passed — "done = verified, not assumed." **The runnable app +
the checklist is the complete handoff.** Every UI screen's *logic* is unit-tested;
only the *rendered/live* behavior is deferred. One known-deferred UI affordance
remains (not a blocking gap): the hotkey-**rebind recording** UI (Settings shows the
binding read-only; the binding system + default persist and are tested) and a global
mute **chord** (the mute menu toggle ships; the chord is live-gated follow-up).

> **Launch-survival VERIFIED (loop run #15, orchestrator):** `make build` then
> launched `Speak.app` three times on the dev Mac (no permissions granted). Each
> run: process alive, STAT `S` (idle event loop, not a CPU spin), normal startup
> CPU, clean termination. `sample` showed the **main thread in `NSApplicationMain`**
> (the AppKit run loop) — NOT stuck in `semaphore_wait`/`DictationController.init`,
> so the full startup path executed: `HotkeyMonitor` init semaphore signaled →
> `applicationDidFinishLaunching` → `startMonitoring()` (permission-denied handled
> gracefully) → steady-state idle. This upgrades "runnable" from *inferred* (build
> compiles) to *verified* (the new startup path actually runs without crashing or
> hanging). The hotkey/paste/onboarding-window *rendered behavior* still needs
> permissions + a human (human-verification.md) — but does-it-launch is now proven.

> **Design decision (this session):** history-save lives in `SpeakEngine.endDictation`
> as best-effort (logged + swallowed) — a failed DB write must NOT fail a dictation
> whose text already pasted. Paste-failure, by contrast, errors the session (it IS
> the delivery) and stays in `CaptureSession`. Failure semantics decided the seam.

> **Orchestrator review note (loop #6):** caught + fixed a latent correctness
> bug before commit — `DoubleTapDetector` was fed `CGEvent.timestamp / 1e9` as
> seconds, but that field is mach-absolute-time units (timebase ≠ 1 ns on Apple
> Silicon), which would have stretched the 0.4 s window to ~16 s. Unit tests
> couldn't catch it (they inject synthetic seconds, bypassing the conversion).
> Fixed to read `DispatchTime.now().uptimeNanoseconds` (documented ns) at handle
> time; HID-tap latency ≪ window. Known v0 follow-ups (note-only): the
> `@unchecked Sendable` callback-thread vs main-thread access to
> `binding`/`eventTap`/`detector` is an unsynchronized race, and the init
> CFRunLoop thread leaks per instance (fine for a single app-lifetime monitor).

---

## Done (this session — 2026-06-21, loop run #26 — PHASE 1 base-hardening COMPLETE + paste test-hygiene fix)

**Executed all of Phase 1 from `specs/acceleration-plan.md` (autonomous loop).** Five
surgical, mostly-additive seam-hardening tasks, all merged on `master` and verified by
an independent orchestrator gate from a wiped DerivedData (**build ✅ · 199 tests / 5
XCTSkip / 0 failures · lint 0 serious · moat 7/7**):

- **H1 `6dbe029` — multi-language seam** (builder-engine). `SpeakEngine.newSession()`
  reads `settings.language` at call-time (mirrors the `cleanupEnabled` per-call
  pattern); dropped the baked-in `locale` stored property + init param. **Behavior-
  neutral** — `SettingsStore.language` already defaults `en-US`. `DictationController`
  needed zero change. +`SpeakEngineLanguageTests` (3 tests).
- **H2 `4a3ad09` — app-test infra `TEST_HOST`** (builder-release). `SpeakTests` now
  HOSTS the `Speak` app target (`TEST_HOST`/`BUNDLE_LOADER = $(BUILT_PRODUCTS_DIR)/
  Speak.app/Contents/MacOS/Speak`), so App-shell types are unit-testable. XCTest
  startup gate in `App/SpeakApp.swift` skips `startMonitoring()` under
  `XCTestConfigurationFilePath` (no live hotkey/permission machinery in tests).
  +`TranscriptOverlayPanelTests` (6-test focus-steal guard — guard only, not live proof).
- **H4 `9bdc20d` — `customVocabulary` seam** (builder-audio-stt). Optional
  `vocabulary: [String] = []` on `AppleSpeechTranscriber`, wired into
  `AnalysisContext.contextualStrings[.general]` via `setContext` before `start`.
  `SettingsStore.customVocabulary` slot. **API SDK-verified** against the
  `arm64e-apple-macos.swiftinterface` (the docs MCP returned nothing — the swiftinterface
  was the source of truth); empty-default guard keeps it behavior-neutral. Whether the
  model biases on hints is `[inferred]` (needs a live corpus). +7 tests.
- **H5 `f2b1d1f` — `StreamingTextInserting` protocol** (builder-input). Define-only
  (`insertChunk(_:) async throws` / `finalize()`) beside `TextInserting` — the forward
  seam for word-by-word streaming paste. No conformer.
- **H3 `9a3c8c4` — decompose `DictationController`** (builder-app; backlog #6, now DONE).
  415→**361** lines (lint file_length warning cleared). Extracted `OverlayController`
  (overlay model+panel+partials lifecycle) + `WindowPresenter` (History/Onboarding
  windows). Behavior identical; public surface unchanged. Now unit-testable via H2's
  TEST_HOST — +`OverlayControllerTests` (8) + `WindowPresenterTests` (4).

**Paste test-hygiene fix — `30e99f2` (USER-REPORTED, mid-loop).** While running
`make test`, the user saw a fixture string (`SPEAK_PHASE_D_AX_TEST_<uuid>`) **paste into
their focused terminal**. Root cause: the two `PasteboardWriterTests` exercised the REAL
`insert()` path — real `NSPasteboard.general` write + real 4-event Cmd+V to
`.cghidEventTap`. With AX trusted, that Cmd+V landed in whatever window had focus (the
terminal running the suite) and pasted the clipboard; it also clobbered the user's
clipboard every run. **Fix:** two injectable `@Sendable` seams on `PasteboardWriter` —
`writeClipboard` + `postEvent` — with production defaults byte-for-byte identical to the
prior behavior; the tests inject a `PasteSideEffectRecorder` and assert against it (AX-
trusted → 4 events to the recorder, not the tap; AX-untrusted → clipboard floor via
recorder then throw, 0 events). Confirmed `grep`-clean of real `.post(tap`/
`NSPasteboard.general` in tests + a re-run produced **no paste into the user's terminal**.
This was the ONLY non-hermetic test (H2's startup gate already blocks the live hotkey tap).

**Orchestration incident + recovery (durable lesson, see handoff banner).**
`Agent(isolation:"worktree")` did NOT isolate — all four parallel agents wrote the shared
main checkout. Caught a live race mid-flight (intermingled uncommitted edits + a non-
compiling `SpeakEngine.swift`), halted writers via SendMessage, and serialized. It
happened to land a clean linear history (disjoint files), which I verified by
`git worktree list --porcelain` + my own clean gate rather than trusting agent reports.
H3 then ran as plain serial sole-writer. Also: SourceKit threw 3 separate phantom-error
episodes (false "cannot find type"/"extra argument"/type-mismatch) after
`xcodegen generate` + file moves — each disproved by a clean `make build`. **The clean
build is the only authority; verify worktree isolation before fan-out.**

**Held at the Phase-1 exit gate (deliberate):** code-complete + automated gates green;
the *re-run LIVE RUN core loop* exit item is human-gated. Did NOT roll into Phase 2 —
that large strategic surface (Wave A dashboard etc.) wants the user in the loop.

## Done (this session — 2026-06-21, loop run #25 — LIVE base verified + full-product acceleration plan)

**Milestone: the v0 base WORKS LIVE.** The user ran `make dev-cert` + `make run`,
granted permissions, and **dictated their development instructions into Claude Code
*using speak itself*** — a recursive feedback loop (the product directing its own
build). Confirmed live (recorded in `human-verification.md` "LIVE RUN #1",
`c9392bd`): double-tap Fn start / single-tap stop, overlay over other apps, partials
streaming live, paste at cursor **into a terminal surface with no macOS 26.4
paste-prompt**, raw-fallback with Apple Intelligence off. The user is happy with the
base and **pivoted the mission from "finish v0" to "build the full product, fast."**

**Produced the full-product execution contract — `specs/acceleration-plan.md`
(`bb17491`, then `e60a665`).** Synthesized from **3 parallel scouts** (orchestrator
fanned out, then reviewed): `scout-architecture` (seam audit — the base is already
clean + extensible; the engine factory pre-declares WhisperKit/Ollama cases; harden
list is *surgical* H1–H5, with a "leave-alone" list), `scout-product` (full roadmap
v0→v3+ with citations), `scout-competitors` (Wispr Flow primary + VoiceInk /
Superwhisper / MacWhisper / FluidVoice / Aiko; winning patterns; our local-first
wedge; flagged Aqua/Handy/Hex as zero-coverage gaps + §11 Wispr analysis is
recall-based). **Four locked user decisions:** base-hardening-first · local-first +
pluggable-later · **full-window dashboard** (Phase-2 UI spine, sidebar IA) ·
**Monaco** typographic theme (saved to cross-session memory + design-system token).

**Status at wind-down:** plan written + committed; **Phase 1 NOT yet started** (the
user wound the session here, just before the fleet launched). Tree clean at
`e60a665`, no agents/worktrees running. The next session resumes at
`specs/acceleration-plan.md` Phase 1 (see the handoff banner under "Current phase").

## Done (this session — 2026-06-21, loop run #24 — HotkeyMonitor split + human-gate 3-bucket map)

**`HotkeyMonitor.swift` split 775→527 (`3ea2804`, builder-input main-tree sole
writer; orchestrator verified from clean + committed).** Pure intra-module file-move
— all symbols are `public` in the single `SpeakCore` module, so relocating them is
invisible to every consumer. Extracted: `HotkeyBinding.swift` (109 — `HotkeyEvent`,
`HotkeyBinding`+Codable), `HotkeyDetection.swift` (130 — `holdEdge`,
`DoubleTapDetector`, `TapRestartRateLimiter`), `BindingStore.swift` (36 —
`BindingStoring`, `UserDefaultsBindingStore`); `HotkeyMonitor.swift` keeps the class
only. Each symbol now in exactly one file (verified by grep); `Carbon.HIToolbox`
followed `kVK_Function`; `MoatAuditTests` enumerates `SpeakCore/` by directory so the
new files are picked up with no change. **Note:** the editor LSP flashed false
"Invalid redeclaration" diagnostics post-split — stale SourceKit index after
`xcodegen generate`, NOT real (a fresh `make build` from clean SUCCEEDED). Gates
(orchestrator re-ran from clean): build SUCCEEDED, **test 191 (5 XCTSkip, 0 failures
— identical baseline)**, lint 0 serious, moat 7/7.

**`human-verification.md` per-row 3-bucket classification (`94e5163`).** Every §4 UI
row now tagged `[B-render ✓]` (already agent-verified by the `verify-visual.sh`
screenshot harness) / `[B-config → #6]` (a config input assertable in code once
App-test-infra exists — a **regression guard, NOT behaviour proof**) / `[C-live]`
(irreducibly human: needs real input + permissions + the window server). The
distinction is **advisor-corrected**: focus-steal / full-screen / timing rows are
window-server *behaviours* and stay `[C-live]` — a passing config assertion must NOT
check a behaviour box (the §3.1 false-pass trap). The mute gate `[B-unit ✓]` is the
one already-closed Bucket-B (`SpeakEngineMuteTests`, headless in SpeakCore).

**Decision — #6 (DictationController decomposition) recommended DEFERRED, not run.**
Grounded read: the 402-line controller is *not in pain* (clean MARK sections, strong
docs, launch-harness-tested). Decomposing it is modest-value polish carrying real
regression risk on the app's central wiring, and it is **non-v0-gating**. With the v0
ship gate now **100% human-blocked**, the critical path is the **human verification
pass (#8)**, not more agent refactoring. #6 is left **execute-ready** (recommended
seam: extract an `OverlayPresenter`; coupled with the `TEST_HOST` app-test infra that
would unlock Bucket-B closure) for when the maintainability investment is wanted.

**Net after loop #24:** every clearly-justified agent-doable item is done — the one
real defect found+fixed (#9), the human gate honestly mapped, one low-risk refactor
landed (#5). What remains is (a) the human-only ship gate (#8) and (b) optional,
non-gating maintainability polish (#6, execute-ready). The runnable app + the
fully-classified `human-verification.md` is the complete handoff.

## Done (this session — 2026-06-21, loop run #23 — live Xcode-MCP autonomy + History/overlay previews)

**The Xcode MCP bridge is now a live verification oracle (orchestrator, encoded
`agent-tooling.md §3.1`, commit `2382a5d`).** Proved the `xcrun mcpbridge` `xcode`
server is authorized + working: `XcodeListWindows → windowtab2`, `RenderPreview`
produces real, inspectable snapshots. Drove it directly to **agent-verify the
static-appearance subset** of the visual gate — Onboarding (5-step flow, privacy
copy) and Settings (hotkey mode, language/engine pickers, AI-cleanup toggle) both
render correctly. **Scope guardrail (advisor-corrected):** a passing preview closes
*static appearance only* — NOT window-server behavior, live timing, or the menubar
SF-Symbol color (system templates symbols monochrome → a false-pass trap). Classify
each `[deferred — visual]` row **per-row, not per-surface**, into preview-verifiable
/ unit-testable-config / irreducibly-live. **Hard constraint encoded:** the bridge
binds to the *main* checkout's `Speak.xcodeproj`, so worktree isolation and
live-Xcode verification are mutually exclusive — pick one per agent.

**HistoryView List crash — diagnosed + fixed, confirmed NON-regression (`d0ee182`,
builder-app in the main tree as sole writer; orchestrator reviewed + verified +
committed).** The live bridge *caught a real defect*: the populated History
`#Preview` crashed under the XOJIT harness (`OutlineListCoordinator.diffRows` /
`ViewListTree.visitItem` — NSOutlineView row-height assertion). builder-app launched
the real app via `--debug-open history` + `screencapture`; the **shipping window
renders + scrolls correctly** → preview-only platform defect, **not a P9
regression**. Orchestrator independently confirmed by viewing the screenshot. Fix
hardens production anyway: `List { ForEach }` (decouple container identity from
data) + always-mounted List with an empty-state `.overlay` (removes the VStack↔List
switch on async []→[N] reloads). Empty-state preview now passes; populated preview
still hits the irreducible XOJIT defect (documented; production not degraded to
satisfy a preview tool). Added 4 static overlay `#Previews` (listening placeholder /
listening+partial / processing / done) with an in-file honesty boundary (content
layout only, not panel/window-server behavior). **Gates: build + test SUCCEEDED,
lint 0 serious, verify-moat PASS.**

**Net after loop #23:** the live Xcode bridge converts a meaningful slice of the
former "human-only visual" gate into agent-verifiable static-appearance checks, and
the protocol is durably encoded for future sessions/agents. Next agent-doable step:
re-classify `human-verification.md` per-row using the §3.1 3-bucket model + run a
full RenderPreview static-appearance sweep across the remaining UI surfaces.

## Done (this session — 2026-06-21, loop run #22 — P11 release scaffolding + QA ship-gate audit)

Orchestrated fan-out (3 agents: builder-input Phase D, builder-release P11,
builder-qa audit). Phase D landed in #21 below. This entry covers P11 + the audit.

**P11 — release pipeline scaffolding (`d790b72`, builder-release in a worktree;
orchestrator reviewed + fixed + merged):** replaced the stubbed `make release`
with the full Developer ID pipeline — `generate → release-preflight (guards
DEV_ID/NOTARY_PROFILE/export plist) → xcodebuild archive (Release) →
-exportArchive (developer-id, signs SpeakCore.framework inside-out) → codesign
--verify + spctl --assess → hdiutil .dmg → notarytool submit --wait → stapler
staple → spctl gate`. New: `scripts/export-options.plist` (developer-id /
automatic), `dist/speak.cask.rb` (Cask Cookbook; `depends_on macos: ">= :tahoe"`
— macOS 26 floor, `:tahoe == "26"` [verified Homebrew macos_version.rb]; version
`0.0.1` matches the roadmap v0 ship tag), `docs/release.md` (cert + notarytool
one-time setup). CI hardened: concurrency cancel-in-progress + a `verify-moat`
pre-build step. No secrets committed (env-injected). **Orchestrator caught + fixed
3 nits pre-merge:** cask `>= :sequoia` (macOS 15) → `>= :tahoe` (macOS 26 — the
app can't run on Sequoia); version `0.1.0` → `0.0.1`; a dangling
`make release-export-plist` reference. Validated: `make -n release` parses,
`ruby -c` cask OK, `plutil` OK, ci.yml YAML OK, **moat 7/7**. Live notarization is
`[deferred — human]`: needs the user's Developer ID cert + App-Store-Connect/notary
credential — the pipeline runs to that boundary, can't cross it headlessly.

**QA ship-gate audit (builder-qa, read-only):** audited every `benchmark.md` §3
BEAT / §4 MATCH row + `quality.md` §9 against the code. **Verdict: ZERO
bucket-(b) unimplemented code paths hidden behind unchecked roadmap boxes** — the
"v0 code surface is essentially complete" assumption is confirmed. Specifically
traced the highest-doubt P2 (mic prompt, PCM logging, clean stop) + P3 (partial/
final transcripts, engine id) boxes → all unchecked for *live-only* reasons, code
is present + wired (cited file:line). Only genuine remaining code gaps: **(1) P11**
(now scaffolded above) and **(2) the §6 WER corpus** — `computeWER` harness is
ready but `SpeakTests/Fixtures/` has only `hello_speech.caf`; needs ~20 real-speech
clips + reference transcripts a **human** must supply. Everything else is human-only
live/visual verification. Independent test run during the audit: **191 tests
(169 XCTest + 22 Swift Testing), 5 XCTSkip (live FM), 0 failures; moat 7/7.**

**Net after loop #22:** the agent-doable v0 code work is now genuinely exhausted —
QA-confirmed. The v0 ship gate is blocked solely on the **human live-verification
pass** (`human-verification.md`) + the **WER corpus** + the **cert-gated
notarization**. Two optional non-v0-gating code-health refactors remain queued
(split `HotkeyMonitor` 775 ln; decompose `DictationController` 402 ln) — awaiting
user green-light.

## Done (this session — 2026-06-21, loop run #21 — Phase D: robust paste)

Phase D of `specs/dictation-flow.md` — robust paste with graceful AX fallback:

- [x] **`SpeakError.pasteRequiresAccessibility` (SpeakCore/Engine/SpeakError.swift):** additive case; `recoverySuggestion` directs user to System Settings → Accessibility. Documented as graceful-degradation (text-on-clipboard), not a fault — mirrors `.microphoneMuted` pattern.
- [x] **`PasteboardWriter` rewritten (SpeakCore/Paste/PasteboardWriter.swift):**
  - Clipboard floor (clearContents + setString) runs unconditionally before any gate — text always recoverable.
  - AX-trust gate: `isAccessibilityTrusted: @Sendable () -> Bool` (injected; default `AXIsProcessTrusted()`). False → log + throw `.pasteRequiresAccessibility`.
  - Settle delay: `settle: Duration` (injected; default 100 ms `[decision]` per VoiceInk/Hex + spec §5). Tests inject `.zero`.
  - Explicit 4-event Cmd chord: Cmd-down → V-down → V-up → Cmd-up to `.cghidEventTap`.
  - `pasteEventPlan() -> [PasteKeyEvent]` pure static function (unit-testable without posting events). `PasteKeyEvent` struct is `internal` + `Sendable`.
  - `kVK_Command = 0x37` [verified: Carbon/HIToolbox swiftc 2026-06-21].
  - No new imports required: `ApplicationServices` (for `AXIsProcessTrusted`) was already in the project allowlist.
- [x] **`DictationController.endDictation` (App/DictationController.swift):** specific `catch SpeakError.pasteRequiresAccessibility` BEFORE generic catch: `permissionsNeeded = true`, `icon = .idle` (not `.error`), `.info` log. Mirrors `.microphoneMuted` pattern. Reuses existing `permissionsNeeded` published property.
- [x] **`PasteboardWriterTests` (SpeakTests/PasteTests.swift — new suite):** 3 new tests: plan shape (4 entries, correct keyCodes/flags), AX-false → throws + clipboard floor verified (test-only read), AX-true → completes. All 6 prior `PasteTests` unchanged.
- `make build` PASSED, `make test` **169 tests, 5 skipped (live FM), 0 failures**, `make verify-moat` **7/7**, lint 0 serious.
- **Live paste into TextEdit/Terminal**: `[deferred — human verification]` (unchanged from P6).

## Done (this session — 2026-06-21, loop run #20 — Phase C: recording HUD visual states + level meter)

Phase C of `specs/dictation-flow.md` — recording HUD upgrade:

- [x] **`OverlayState` enum (App/Overlay/TranscriptOverlayView.swift):** `.listening`, `.processing`,
      `.done` — drives HUD visual state. `OverlayViewModel` now publishes `overlayState` + `level: Double`.
- [x] **Bottom-center positioning (spec §4 consensus: VoiceInk/Wispr/Handy):** panel repositioned from
      top-center to `visibleFrame.minY + 24pt`. Repositions on `NSApplication.didChangeScreenParametersNotification`
      (block-based observer, `[weak self]`, removed in deinit — no leak).
- [x] **`.stationary, .ignoresCycle` added to `collectionBehavior`** alongside existing
      `.canJoinAllSpaces, .fullScreenAuxiliary`. Panel still `.nonactivatingPanel`, `canBecomeKey=false`,
      `orderFrontRegardless` — never steals focus (load-bearing).
- [x] **Three HUD visual states:** listening (5-bar waveform + partial text or "Listening…" placeholder),
      processing ("Cleaning up…" + ProgressView spinner), done (checkmark.circle.fill + "Done").
- [x] **Level meter: placeholder path taken** (not fake-VU). `level: Double` on the model is the real
      wire point; bars run a neutral uniform breathing animation (clearly not mic-reactive: all 5 bars
      breathe together at 0.15–0.30 amplitude, 1.2 s cycle). Real feed deferred to builder-audio-stt +
      builder-engine (AVAudioEngine tap RMS → `AsyncStream<Double>` → DictationController → OverlayViewModel).
- [x] **`LevelMath.swift` (SpeakCore/Overlay/):** pure public functions: `levelLinear(fromDB:)` (Hex formula),
      `levelSmoothed(previous:target:)` (Handy 0.7/0.3), `levelBarHeights(level:barCount:minHeight:maxHeight:)`
      (cosine envelope, 5 bars, 3–20 pt). No AppKit/SwiftUI — fully unit-tested.
- [x] **`endDictation()` hide-timing fixed:** panel stays visible during processing ("Cleaning up…")
      and done (600ms flash). Panel hides AFTER done flash, not at stop(). `transitionOverlay(to:)` cancels
      partials task at processing. Error path still hides immediately.
- [x] **Debug targets extended (DebugLaunchDispatcher):** `overlay-demo` (listening + sample text + level=0.6),
      `overlay-demo-processing`, `overlay-demo-done`. Three separate states are screenshot-verifiable.
- [x] **13 unit tests (OverlayLevelTests.swift):** dB→linear, clamping, smoothing math, convergence,
      bar count, bounds, symmetry — all pass.
- `make build` PASSED, `make test` 163 tests 0 failures, `make verify-moat` 7/7, lint 0 errors.

## Done (this session — 2026-06-21, loop run #19 — Phase B: push-to-talk + trigger mode UI)

Phase B of `specs/dictation-flow.md` — two trigger modes, user-selectable:

- [x] **`HotkeyBinding.Trigger` cleaned up:** removed `.singleTapToggle` (was never
      implemented; documented in `HotkeyMonitor.swift` with rationale). Changed to
      `String` RawValue so UserDefaults persistence uses stable string keys (`"doubleTap"`,
      `"hold"`). Old persisted payloads (synthesized Codable format) fail `try?` in
      `UserDefaultsBindingStore.load()` → `nil` → fallback to `defaultBinding` —
      exactly the spec's "fall back cleanly" requirement. Added `HotkeyBinding.with(trigger:)`
      helper for `DictationController` to apply a trigger change without losing
      keyCode/modifiers/window.
- [x] **`holdEdge(isFnDown:wasDown:)` pure free function (Phase B):** maps Fn key
      state transitions to `HotkeyEvent?`. Press leading edge (false→true) → `.startCapture`;
      release trailing edge (true→false) → `.stopCapture`; no transition → `nil`. No
      clock, no CGEventTap, no side effects — directly unit-testable.
- [x] **`HotkeyMonitor.handle(proxy:type:event:)` dual-mode dispatch:** `lastFnDown`
      updated BEFORE the branch so both modes see correct edge state. `.doubleTap` branch:
      unchanged behavior — guard on press leading edge, call `detector.register(tapAt:window:)`.
      `.hold` branch: call `holdEdge(isFnDown:wasDown:)` on every edge — no timestamp,
      no window. Comment documents the synthetic-release safety guarantee: `buildTap()`
      resets `lastFnDown=false` on every tap teardown (Phase A), so a mid-hold teardown
      never leaves hold stuck "on".
- [x] **`SettingsStore.triggerMode`:** `HotkeyBinding.Trigger` property persisted as
      `rawValue` String under key `speak.settings.triggerMode`. Default `.doubleTap`. Getter
      falls back to `.doubleTap` on unknown raw value. Parallel to `pasteMode` pattern.
- [x] **`SettingsView` Activation section (Phase B):** inline `Picker` "Double-tap Fn
      (toggle)" | "Hold Fn (push-to-talk)" + contextual hint text. Writes directly to
      `store.triggerMode` (ObservableObject); frame height bumped to 380 for the new section.
- [x] **`DictationController` trigger-mode wiring:**
      - On init: reads `settingsStore.triggerMode` → builds updated binding via
        `monitor.binding.with(trigger:)` → calls `monitor.updateBinding(_:)`. Keeps
        `SettingsStore` and `UserDefaultsBindingStore` in sync from first launch.
      - Combine subscription on `settingsStore.objectWillChange` → `DispatchQueue.main.async`
        hop (allows the write to commit before reading) → `monitor.updateBinding(binding.with(trigger:))`.
        Mode switch is live, no relaunch. `AnyCancellable` stored in `triggerModeCancellable`.
- [x] **Synthetic-release safety (Phase A coordination):** no new hold-state variable
      was added. Existing `buildTap()` already calls `detector.reset(); lastFnDown = false`
      on every arm/re-arm — so a mid-hold tap teardown clears `lastFnDown`, and the next
      Fn press is treated as a fresh start. No additional reset path needed.
- [x] **Tests (new, all passing):**
      - `HotkeyBindingCodableTests`: added `testHoldTriggerRoundTrip`,
        `testDoubleTapTriggerRoundTrip`, `testStalePersistedTriggerDecodesNilAndFallsBack`.
        Fixed `testRoundTripWithModifiers` to use `.hold` instead of removed `.singleTapToggle`.
      - `HoldEdgeTests` (5 tests): `testPressEdgeEmitsStartCapture`,
        `testReleaseEdgeEmitsStopCapture`, `testKeyRepeatWhileHeldEmitsNil`,
        `testNoChangeWhileReleasedEmitsNil`, `testPressReleaseCycle`.
- [x] `make build` ✓, `make test` **175 tests (153 XCTest + 22 Swift Testing; 5 XCTSkip),
      0 failures**, `make lint` 0 serious, `make verify-moat` **7/7**.

Done-when (spec §6-B): hold-to-talk and double-tap-lock both work from Fn; pure-unit-tested
with injected state. Live OS behavior [deferred — human verification] per standard rows.

## Done (this session — 2026-06-21, loop run #18 — Phase A: hotkey re-arm + lifecycle fixes)

Phase A of `specs/dictation-flow.md` — the "make it fire without relaunch" set:

- [x] **Non-blocking `HotkeyMonitor.init` (spec §1.3 fix):** semaphore wait removed.
      Dedicated run-loop thread is spawned and returns; init completes immediately.
      No `sema.wait()` on the main thread. Fixes the priority-inversion backtrace.
- [x] **Re-arm watchdog (core fix, spec §1.2):** CFRunLoopTimer fires every 100ms
      on the run-loop thread. While ungranted: polls `AXIsProcessTrustedWithOptions([prompt:false])`
      silently. On untrusted→trusted edge: calls `buildTap()` on-thread — no relaunch.
      Stream is stable for monitor lifetime; consumers don't need to re-subscribe.
- [x] **`HotkeyMonitor.start()` safely re-callable:** sets `armingDesired` flag + wakes
      run loop; `buildTap()` tears down any half-built tap first (clean retry).
- [x] **Gate tap on Accessibility only (spec §2):** `armingDesired=true` + AX granted =
      arm. IM missing does not block. `IOHIDCheckAccess` used for status display only.
- [x] **Input Monitoring non-blocking in onboarding (spec §2):** `OnboardingStateMachine`
      now only treats Mic + AX as blocking permissions. IM has its own step (user is guided
      to grant it) but `blockingPermissions` never contains `.inputMonitoring`, and
      `isComplete == true` when Mic+AX are granted regardless of IM state.
- [x] **`DictationController` re-arm wiring:** `startMonitoring()` calls `monitor.start()`
      once (non-throwing). `armStateChanges` stream clears/sets `permissionsNeeded` on the
      `@MainActor` when tap arms/disarms. Event-consume Task started once and stable.
- [x] **Tap-disabled watchdog (spec §3):** `tapDisabledByTimeout`/`ByUserInput` re-enables
      tap via `CGEvent.tapEnable`; `TapRestartRateLimiter` caps restarts at 5/2s (Loop OSS
      [decision]); `NSWorkspace.didWakeNotification` schedules a re-arm 3s after wake
      (AltTab pattern [decision]).
- [x] **Single-instance guard (spec §1.4):** `AppDelegate.applicationDidFinishLaunching`
      checks `NSRunningApplication.runningApplications(withBundleIdentifier:)` before
      constructing `DictationController`; finds another `com.speak.app` instance → activates
      it + exits. No contention from duplicate launches.
- [x] **`CoreFoundation` added to moat import allowlist** (CFRunLoop/CFRunLoopTimer).
- [x] **App-Intents noise:** no reliable plist key; left a one-line note; did not rabbit-hole.
- [x] **New tests:** `PhaseARearmTests.swift` — 17 tests for `TapRestartRateLimiter` (pure,
      injectable timestamps) + re-arm edge-logic invariants. `OnboardingFlowTests.swift`
      updated for Phase A semantics (IM non-blocking; 4 new tests, 3 updated assertions).
- [x] `make build` ✓, `make test` **167 tests (145 XCTest + 22 Swift Testing; 5 XCTSkip),
      0 failures**, `make lint` 0 serious, `make verify-moat` **7/7**.

Done-when (spec §6-A): grant Accessibility live → tap arms within ~0.2 s with no relaunch;
double-tap Fn fires start/stop. This is [deferred — human verification] per standard rows.

## Done (this session — 2026-06-21, loop run #17 — agent-drivable visual verification)

**Breakthrough: the agent now closes the UI-rendering half of `human-verification.md`
itself — no human, no permissions.** The remaining v0 gate was entirely live behaviour;
this session proved how much of it the agent can drive on the real Mac.

- [x] **Capability probe (grounded, not assumed):** macOS 26.5 / arm64. Authoritative
      on-device model check (`SystemLanguageModel.default.availability`) =
      **`appleIntelligenceNotEnabled`** → live cleanup genuinely needs the human to enable
      Apple Intelligence (corrected an earlier misread of the *cloud* opt-in key). De-risked
      the linchpin: external **AX UI-scripting is blocked** (`osascript not allowed assistive
      access`) but **`screencapture` is not** → harness must drive windows *from inside the
      app*, never by clicking from outside.
- [x] **`#if DEBUG` verification surface (`App/Debug/DebugLaunchDispatcher.swift`,
      `SpeakCore/Debug/FixtureAudioProducer.swift`, builder-app):** `--debug-open <target>`
      opens any window / runs the real pipeline from `open --args`. 10 targets. All gated
      DEBUG; `make verify-moat` stays **7/7** (never leaks to release).
      - **Orchestrator fix (`App/SpeakApp.swift`):** the dispatcher only skipped
        `startMonitoring()` for `simulate-dictation`; every other target still ran
        `showOnboardingIfNeeded()`, popping the production welcome window *on top* of the
        requested one (all screenshots showed welcome). Fixed: a debug target now fully owns
        the launch — no normal startup — so each capture is isolated. Re-verified.
- [x] **`scripts/verify-visual.sh` (NEW):** re-runnable harness — per-target launch →
      settle → `screencapture` → kill. Bug fixed (`local` split under `set -u`).
- [x] **RENDERED ✓ — all 9 window targets, orchestrator Read every PNG:** onboarding ×6
      (correct icon/copy/button/step-dot each), Settings, History (empty state), overlay
      ("the quick brown fox"). Recorded in `human-verification.md §4` with a hard integrity
      boundary: **renders ≠ behaves-live**; no behaviour checkbox flipped.
- [x] **Onboarding permission-grant fix (builder-app, adjacent — kept after review):**
      `PermissionManager.requestAccessibility()` / `requestInputMonitoring()`
      (`AXIsProcessTrustedWithOptions` + `IOHIDRequestAccess`); the onboarding "Grant"
      buttons now *register the app in the permission lists* instead of only deep-linking —
      without this the app may never appear in System Settings for the user (would block the
      Bucket C grant step). Production behaviour change, vetted; build/test/moat green.
- [x] **CLAUDE.md Commands section de-staled** (was "repo is pre-build, run `git init`").
- **Deferred (unchanged):** `simulate-dictation` live STT→cleanup→**paste** — paste needs
  Accessibility, so folded into the §0/§3 permission pass (the visible paste-into-TextEdit
  will be the proof). Terminal paste-provenance stays P11 (unsigned dev build). The 3 TCC
  grants + Apple-Intelligence enable + one spoken dictation remain the human residue.

## Done (this session — 2026-06-21, loop run #16 — History window + hardware mute)

- [x] **History window UI (SPEC §5.6 / roadmap P9 — last unbuilt UI surface)**
      - **`App/History/HistoryViewModel.swift` (NEW, `@MainActor ObservableObject`):**
        reads the shared `historyStore` via `recent(limit:)`/`search(_:)`/`clear()`/
        `export()`; live debounced substring search (cancels the in-flight query on
        each keystroke); `recentLimit = defaultHistoryMaxEntries` (single-sourced to
        `HistoryStore`, no second magic number); export → `NSSavePanel` writing JSON.
      - **`App/History/HistoryView.swift` (NEW):** search field, entry list (cleaned
        ?? raw + timestamp + engineId), Export/Clear footer, empty + no-match states.
      - **`App/History/HistoryWindowController.swift` (NEW):** `NSWindow + NSHostingView`
        (mirrors `OnboardingWindowController`; resizable). Opened from a new
        "History…" menu item.
      - **`DictationController`:** now exposes the `historyStore` (the same instance
        the engine writes to) and a lazy `showHistory()`. Roadmap P9 "History window
        (UI)" row flipped `[ ]` → `[~]` (logic verified; rendered window deferred-visual
        §4.5). Also corrected the **stale P9 row** that claimed save wasn't wired —
        `SpeakEngine.endDictation` has called `history.save(_:)` since loop #9
        (verified by `SpeakEngineIntegrationTests`).
      - `import UniformTypeIdentifiers` (UTType.json) added to the moat allowlist in
        both `MoatAuditTests.swift` and `scripts/verify-moat.sh`.
- [x] **Hardware mute (SPEC §7.4 / product.md §8 #4 — was "not yet implemented")**
      - **Enforcement point = the engine, not the UI** (bypass-proof): added an
        actor-isolated `muted` flag to `SpeakEngine`; `beginDictation()` guards on it
        and throws a new `SpeakError.microphoneMuted` **before** any `CaptureSession`
        or transcriber is constructed → "when muted, no audio is read." Added
        `isMuted` / `setMuted(_:)` / `toggleMute()`. **Both halves of SPEC §7.4
        "toggles capture":** muting also `cancelDictation()`s an *in-flight* session
        (advisor caught that a start-only gate would keep reading audio from a
        dictation already running); `DictationController.toggleMute` mirrors that in
        the UI (hide overlay → idle).
      - **`SpeakError.microphoneMuted` (NEW case):** additive to the §6 verbatim list,
        surfaced in a header comment. It is a *refusal*, not a fault — `DictationController`
        catches it specifically and stays `.idle` (no `.error` flash, no overlay).
      - **UI:** "Mute/Unmute Microphone" menu item + a "Muted — dictation disabled"
        line; `DictationController.toggleMute()` mirrors `engine.isMuted` into a
        published flag for the menu checkmark.
      - **`SpeakTests/SpeakEngineMuteTests.swift` (NEW, 7 XCTest, all green, NO skip):**
        uses a `RecordingTranscriber` that records whether `startStream` was ever
        called. The load-bearing tests — `testMutedRefusesBeginAndNeverStartsTranscriber`
        (muted → throws `.microphoneMuted` **and** `didStartStream == false` **and**
        state `.idle`) and `testMutingStopsInFlightCapture` (mute while `.listening`
        → session no longer listening). Plus default-unmuted, set/toggle semantics,
        unmuted-allows-begin, unmute-restores.
      - **v0 scope (honest):** the mute *toggle* ships as a menu item; a global mute
        *chord* (SPEC §7.4 wording) is a tracked, live-gated follow-up (human-
        verification.md §4.6) — not built, to avoid unverifiable surface.
      - README guarantee #4 updated from "design posture, not yet implemented" to the
        engine-enforced + unit-tested reality.
- [x] **Verification:** `make build` clean; `make test` **150 tests (130 XCTest +
      20 Swift Testing), 5 XCTSkip (pre-existing live-FM), 0 failures**; `make
      verify-moat` **7/7**; `make lint` **0 serious** (my new files: 0 violations).
- [x] **SPEC §5–§7 feature scan (advisor-requested, to confirm no third gap):**
      every §5 flow/UX item, §6 seam, and §7 privacy guarantee now maps to built +
      tested code. Remaining items are live-gated (human-verification.md) — autonomous
      scope is exhausted.

## Done (this session — 2026-06-21, loop run #15 — P12 public docs)

- [x] **Phase 12 — public docs (README/CONTRIBUTING/CHANGELOG); GIF deferred**
      - **`README.md` (rewrite):** what it is, the structural moat (with the honest
        caveat that Wispr also has a free tier + Fn — the wedge is the bundle),
        install (build-from-source now; Homebrew cask at P11), usage (hotkey/
        overlay/settings/history/3 permissions), **privacy section listing all 5
        `product.md` §8 guarantees**, #1/#2/#3/#5 citing `make verify-moat` as a
        re-runnable proof (#4 hardware-mute = design posture, not yet implemented),
        build commands, honest pre-release status, MIT.
      - **`CONTRIBUTING.md` + `CHANGELOG.md` (NEW):** build/test/lint/verify-moat,
        the layered docs model, architecture seams, hard rules; Keep-a-Changelog
        `[Unreleased] — v0`.
      - **`human-verification.md` §5 (NEW):** demo GIF + screenshots deferred
        (need a live recorded run; unblocked by §0+§2+§3 passing).
      - Docs only — no Swift touched; build/test unaffected (143 tests / moat 7/7
        remain valid). Corrected a false skeleton claim ("only local+free+open" —
        Aiko/TypeWhisper/FluidVoice also qualify).

## Done (this session — 2026-06-21, loop run #14 — P7 Permissions Onboarding)

- [x] **Phase 7 COMPLETE — Permissions onboarding (step-state machine `[verified]`; rendered flow `[deferred — visual]`)**
      - **`SpeakCore/Permissions/OnboardingState.swift` (NEW):** Pure `Sendable` value
        types + free function `OnboardingStateMachine.evaluate(...)`. `OnboardingStep`
        enum (welcome/microphone/accessibility/inputMonitoring/hotkey/done),
        `OnboardingEvaluation` struct (currentStep, isComplete, blockingPermissions).
        No UI dependencies — fully headless-testable. Convenience overload accepts a
        live `PermissionManager` on `@MainActor`.
      - **`SpeakTests/OnboardingFlowTests.swift` (NEW, 14 tests, Swift Testing,
        all green):** all-granted+complete → `.done`, all-granted-flag-not-set →
        `.hotkey`, mic-only-missing (`.notDetermined` + `.denied`) → `.microphone`,
        accessibility-only-missing → `.accessibility`, inputMonitoring-only-missing
        (`.notDetermined` + `.denied`) → `.inputMonitoring`, multiple-missing ordering,
        `.restricted` counts as not-granted, `.requesting` counts as not-granted,
        completed-flag-true-but-mic-denied → not-complete (re-show path).
      - **`SpeakCore/Permissions/PermissionManager.swift` (MODIFIED — P7 wiring):**
        Wired `inputMonitoring` case using `IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)`
        (Apple IOKit.hid). Maps `kIOHIDAccessTypeGranted` → `.granted`,
        `kIOHIDAccessTypeUnknown` → `.notDetermined`, default → `.denied`.
        [verified: swiftc -typecheck against macOS 26 SDK, 2026-06-21].
        Live correctness is [deferred — human-verification.md §4.4].
        Replaced the stub `.notDetermined` that made input monitoring permanently
        undetectable.
      - **`SpeakCore/Storage/SettingsStore.swift` (MODIFIED):** Added
        `hasCompletedOnboarding: Bool` (key `speak.settings.hasCompletedOnboarding`,
        default `false`). Mirrors the existing Keys/getter-setter pattern.
      - **`App/Onboarding/OnboardingViewModel.swift` (NEW):** `@MainActor
        ObservableObject`; owns `PermissionManager` + `SettingsStore` references;
        polls TCC at 1.5 s [decision: poll interval]; auto-advances on grant;
        `finish()` / `skip()` set `hasCompletedOnboarding = true`; `[weak self]` Task.
      - **`App/Onboarding/OnboardingView.swift` (NEW):** SwiftUI flow — Welcome /
        PermissionStep (3 states: loading spinner, needs-grant, granted+checkmark) /
        HotkeyStep / DoneStep. "Skip for now" footer (risk #4 mitigation). Step-dots.
      - **`App/Onboarding/OnboardingWindowController.swift` (NEW):** `@MainActor`;
        creates `NSWindow + NSHostingView` (not a WindowGroup scene — rationale
        [decision: NSWindow vs WindowGroup, file header]); auto-close after `.done`
        step + 1.5 s delay [decision: 1.5 s close delay, inline comment].
      - **`App/DictationController.swift` (MODIFIED):** Owns `PermissionManager`
        (shared with onboarding); `showOnboardingIfNeeded()` called at `startMonitoring()`
        start AND in each permission-denied catch block (revocation → re-surface path,
        P7 done-when #3). Lazily creates `OnboardingWindowController`.
      - **`SpeakTests/MoatAuditTests.swift` (MODIFIED):** `IOKit.hid` added to
        Apple-framework allowlist. `Combine` also added (was missing; used by
        `ObservableObject`). All 9 moat tests still pass.
      - **`scripts/verify-moat.sh` (MODIFIED):** Same allowlist additions.
      - **`SpeakTests/PermissionTests.swift` (MODIFIED):** Replaced stale
        `inputMonitoringIsNotDeterminedUntilP5` (now false: IOKit wired) with
        `inputMonitoringStatusResolvesWithoutHanging` — asserts returns without
        hanging and is a valid state; does NOT assert the exact value (TCC-env-dependent).
      - **`docs/human-verification.md` §4.4 (NEW):** Full list of deferred visual rows
        for the rendered onboarding (14 rows), including deep-link anchor correctness,
        IOHIDCheckAccess live correctness, revocation re-show path, and window-front
        behavior.
      - **Test counts:** `make test` → **123 XCTest (5 XCTSkip pre-existing live-FM),
        0 failures + 20 Swift Testing tests, 0 failures.** `make verify-moat` → **7/7**.
      - **P7 done-when rows:**
        - `[verified]` `OnboardingStateMachine.evaluate(...)` pure step machine — 14 tests.
        - `[verified]` `hasCompletedOnboarding` persists in `SettingsStore` (round-trip logic, mirrors tested pattern).
        - `[verified]` `inputMonitoring` status now backed by `IOHIDCheckAccess` (typecheck).
        - `[verified]` Show-on-launch: `showOnboardingIfNeeded()` evaluates the machine at `startMonitoring()`.
        - `[verified]` Revocation → error path: `showOnboardingIfNeeded()` called in permission-denied catches.
        - `[deferred — visual]` All rendered UI, system prompts, deep-link pane correctness — human-verification.md §4.4.

## Done (this session — 2026-06-21, loop run #13 — P4 overlay + P8 finish)

- [x] **Phase 4 — Partial overlay (wiring + logic `[verified]`; live `[deferred — visual]`)**
      - **`App/Overlay/` (NEW):** `TranscriptOverlayPanel` — an `NSPanel` with
        `.nonactivatingPanel` + `.floating` + `canBecomeKey/Main = false`, joins
        all spaces + `.fullScreenAuxiliary`, hosts a SwiftUI card. **Never steals
        focus** (load-bearing: the user dictates into another app).
      - **`SpeakCore/Engine/OverlayText.swift` (NEW):** `OverlayTextAccumulator`
        pure type (newest-non-empty chunk wins) — 11 unit tests.
      - **`DictationController`:** drains `engine.currentPartials()` on a
        `[weak self]` Task, routes to an `OverlayViewModel` via `MainActor.run`;
        shows the panel on `.listening`, hides + clears on `.done`/`.error`.
      - 123 tests, 0 failures; `make verify-moat` 7/7. Overlay live behavior →
        `human-verification.md` §4.3.
- [x] **Phase 8 — Menubar states (wiring `[verified]`; live visual `[deferred]`)**
      - Already wired via `MenubarIcon` + `DictationController` (reactive label,
        600 ms done-flash). Added `icon = .processing` before the `endDictation`
        await so every transition (idle→listening→processing→done→idle) surfaces.
      - Roadmap P8 + checklist §4.2. Distinct colors = cosmetic polish (deferred).

## Done (this session — 2026-06-21, loop run #12 — P10 Settings, UI build authorized)

- [x] **Phase 10 — Settings (store + toggle wiring `[verified]`; window `[deferred — visual]`)**
      - User explicitly authorized building the remaining UI now (overriding the
        earlier "defer UI on unverified foundations" caution).
      - **`SpeakCore/Storage/SettingsStore.swift` (NEW):** typed, observable
        `UserDefaults` wrapper; **injectable defaults** for test isolation.
        `cleanupEnabled`, `cleanupEngine`, `sttEngine`, `language`, `pasteMode`
        (+ v0.1/v1 enum placeholders).
      - **`SpeakCore/Engine/EngineFactories.swift` (NEW):** `defaultTranscriber(for:)`
        / `defaultCleaner(for:)` per architecture §10.1/§10a.1; unbuilt engines
        log + fall back to the v0 default, never `fatalError`.
      - **`SpeakEngine` now takes `settings`** (resolves the §6 deferral): kept the
        injected transcriber/cleaner for DI, but `newSession()` gates the cleaner
        by `settings.cleanupEnabled` **at call time** → the toggle applies
        per-dictation, no restart. Updated the two callers (DictationController +
        integration test, the latter with a test-isolated `SettingsStore`).
      - **`App/Settings/` Settings window:** cleanup toggle, STT/cleanup-engine/
        language/paste-mode pickers, hotkey display; wired into the menu.
      - **`SettingsStoreTests` (NEW):** persistence round-trips + factory gating
        (`cleanupEnabled=false → nil cleaner`, `true → FoundationModelsCleaner`).
      - `MoatAudit` allowlist += `Combine` (Apple; `ObservableObject`) — still
        rejects any non-Apple import.
      - `make build` clean; `make test` **112 total, 5 XCTSkip, 0 failures**;
        `make verify-moat` 7/7; lint 0 serious. **Window live behavior deferred**
        (`human-verification.md` §4.1); store + toggle gating are `[verified]`.

## Done (this session — 2026-06-21, loop run #11 — autonomous BEAT-row verification)

- [x] **Structural moat audit + headless latency measurement + WER harness**
      - **`SpeakTests/MoatAuditTests.swift` (NEW, 9 tests, all green):**
        XCTest-based source-tree audit that permanently regression-guards the
        benchmark.md §3 BEAT moat rows. Import allowlist (9 tests) asserts:
        - `testMITLicenseExists` — LICENSE exists and contains "MIT License". `[verified]`
        - `testNoThirdPartyImports` — every `import` ∈ Apple allowlist. `[verified]`
        - `testNoNetworkEgress` — no URLSession/NWConnection/CFSocket/getaddrinfo etc. `[verified]`
        - `testNoAccountOrAuthCode` — no ASAuthorization/LAContext/SecItemAdd etc. `[verified]`
        - `testNoPaywallOrWordCap` — no StoreKit/wordCap/isPremium/paywall etc. `[verified]`
        - `testOfflineByConstruction` — Speech+FoundationModels+SQLite3 all present (on-device). `[verified]`
        - `testNoPasteboardRead` — no string(forType:)/pasteboardItems read calls. `[verified]`
        - `testNoPrintInProductionCode` — no bare print() in SpeakCore/App. `[verified]`
        - `testNoForceUnwrapInProductionCode` — no try!/as!/force-unwrap in production. `[verified]`
      - **`scripts/verify-moat.sh` (NEW) + `make verify-moat` (NEW Makefile target):**
        Standalone shell audit — 7/7 checks PASS. Runs without Xcode; re-runnable in CI
        as a pre-build step. Covers MIT license, import allowlist, networking symbols,
        identity-auth symbols, paywall symbols, pasteboard reads, print() calls.
      - **`SpeakTests/LatencyAndAccuracyTests.swift` (NEW, 10 tests, all green):**
        Headless latency measurement + WER harness.
        - `testFirstPartialLatency` — 5 trials after 1 warm-up on hello_speech.caf:
          **p50 = 42 ms** (budget: < 100 ms ✓), **p95 = 43 ms** (budget: < 200 ms ✓).
          `[verified — measured, headless file-fed proxy; not real-time user-facing lag]`
        - `testLocalPipelineLatency` — raw-fallback path, no paste, no FM:
          **median = 60 ms** (budget: < 1000 ms ✓), p95 = 63 ms.
          `[verified — measured, headless; full stop→paste deferred to human-verification.md]`
        - WER harness (`WERHarnessTests`) — 8 tests prove correctness (perfect match,
          deletion, substitution, punctuation ignored, case-insensitive, empty edge cases).
          Demo on fixture: "Cased in one, two, three." vs "Testing one two three" → high
          WER expected (synthetic speech). Harness ready; full §6 corpus is a data dependency
          a human must supply. `[verified — harness correct; WER gate deferred — corpus needed]`
      - `make build` clean. `make lint` 0 new serious violations (non-serious
        warnings only: for_where, trailing_comma, type/file/function length,
        identifier_name). `make test` **88 total, 5 XCTSkip (pre-existing live-FM),
        0 failures** (orchestrator re-verified — the "83" figure mid-run was stale;
        actual is 88, i.e. 20 new tests, 68 → 88). All prior green.
      - **`make verify-moat` output (run 2026-06-21):** 7/7 PASS — MIT ✓, imports ✓,
        networking ✓, auth ✓, paywall ✓, pasteboard-read ✓, print ✓.

## Done (this session — 2026-06-21, loop run #10 — app-shell wiring, END-TO-END)

- [x] **App shell wired — `make run` exercises the full flow** (live-gated)
      - **`App/DictationController.swift` (NEW, `@MainActor ObservableObject`):**
        builds the production `SpeakEngine` (AppleSpeechTranscriber +
        FoundationModelsCleaner + PasteboardWriter + HistoryStore), owns a
        `HotkeyMonitor`, consumes `monitor.events` → `beginDictation`/`endDictation`,
        publishes a `MenubarIcon` state.
      - **Graceful degradation:** `HistoryStore.makeProductionStore()` throw →
        `NullHistoryStore` fallback (dictation unaffected); `monitor.start()`
        permission-denied → `permissionsNeeded` flag + System Settings deep-link,
        no crash. `AppDelegate` arms monitoring in `applicationDidFinishLaunching`.
      - **`SpeakCore/Engine/MenubarIcon.swift` (NEW):** pure enum +
        `init(for: CaptureSession.State)`, exhaustive switch (new state = compile
        error). **`SpeakTests/MenubarIconTests.swift`** — 6 tests, the only
        headless-verifiable piece here; all green.
      - Retired `App/MicTestController.swift` (P2 affordance now subsumed).
      - **Orchestrator fix:** the done-flash literal was 1.5 s with a *phantom*
        "benchmark §7" citation (no such row) and contradicted roadmap P8's 600 ms
        → corrected to 600 ms citing P8 (single source), removing a magic number.
      - `make build` clean; `make test` **68 total, 5 XCTSkip, 0 failures**.
      - **Everything end-to-end is `[deferred — needs human verification]`**
        (`docs/human-verification.md`); only the icon mapping is `[verified]`.

## Done (this session — 2026-06-21, loop run #9 — SpeakEngine facade + integration)

- [x] **`SpeakEngine` facade + first real-component integration test**
      - **`SpeakCore/Engine/SpeakEngine.swift` (NEW, `actor`):** assembles
        transcriber + cleaner? + inserter? + history; verbs `beginDictation` /
        `endDictation` / `cancelDictation`; `currentState` / `currentPartials`
        observation. History save is best-effort (do/catch + log + swallow) in
        `endDictation`. Documented §6 deviations: `SettingsStore` deferred to P10
        (`cleaner == nil` ⇒ cleanup off); `actor` (matches §8) not
        `@unchecked Sendable` class; `async throws` verbs.
      - **`SpeakTests/SpeakEngineIntegrationTests.swift` (NEW):** fixture-audio
        `AppleSpeechTranscriber` → real `CaptureSession` → real
        `FoundationModelsCleaner` (`isAvailable=false` → raw fallback) → real
        `HistoryStore` (temp file) → mock inserter. Asserts end-to-end `.done`,
        raw transcript, `cleanedText == nil`, inserter received text, exactly 1
        history entry. **PASSED** — first time real components ran together.
      - `make test` **62 total, 0 failures**; all 61 prior green.

## Done (this session — 2026-06-21, loop run #8 — P9 HistoryStore)

- [x] **Phase 9 COMPLETE — SQLite history store**
      - **`SpeakCore/Storage/HistoryEntry.swift` (NEW):** `public struct HistoryEntry: Sendable, Identifiable, Equatable` — verbatim §6 fields + `public init` + `Equatable` for test assertions.
      - **`SpeakCore/Storage/HistoryStoring.swift` (NEW):** `public protocol HistoryStoring: Sendable` — `save`, `recent(limit:)`, `search(_:)`, `clear()`, `export()` all `async throws`.
      - **`SpeakCore/Storage/HistoryStore.swift` (NEW):** `public actor HistoryStore: HistoryStoring` — raw SQLite3 C API (no third-party deps). `init(databaseURL:maxEntries:)` + `makeProductionStore()` convenience. Actor isolation is the entire data-race-safety story. `sqlite3_bind_int64` for limit (not `Int32`, which would overflow on `Int.max`). `SQLITE_TRANSIENT` shim via `unsafeBitCast` so text binds copy the Swift buffer. `setupSchema` extracted to a static nonisolated helper to avoid Swift 5 actor-init warning. Schema stores `createdAt` as `REAL` (Double epoch), ordered by `createdAt DESC, rowid DESC` everywhere for deterministic ordering under sub-second save bursts. Capacity trim deletes `NOT IN (SELECT rowid ... LIMIT maxEntries)`.
      - **`benchmark.md` §7 "history size"** row filled in: 10,000 entries `[decision]` with derivation (≈ 4 MB). `defaultHistoryMaxEntries` public constant + init param.
      - **`SpeakTests/HistoryStoreTests.swift` (NEW, 11 tests, all green):** covers all P9 done-when rows — persistence across reopens, newest-first ordering + limit, search in rawText/cleanedText/no-match, clear, export (JSON, valid, readable), capacity trim, nil cleanedText round-trip, non-nil round-trip.
      - `make build` zero new warnings. `make lint` zero new errors (one pre-existing warning in `PasteTests.swift`). `make test` **61 total, 5 XCTSkip (live-FM), 0 failures.** 11 new P9 tests all green; all 50 prior green.
      - SpeakError case used: `.unknown(String)` — existing case, no new case invented.

---

## Done (previous session — 2026-06-20, loop run #7 — P6 PasteboardWriter)

- [x] **Phase 6 code-complete (live criteria deferred) — paste seam**
      - **`SpeakCore/Paste/TextInserting.swift` (NEW):** `public protocol TextInserting: Sendable`
        with `func insert(_ text: String) async throws`. The paste-seam abstraction:
        `CaptureSession` calls this just before reaching `.done`; tests inject a
        mock; the real `PasteboardWriter` uses NSPasteboard + CGEvent.
      - **`SpeakCore/Paste/PasteboardWriter.swift` (NEW):** `final class PasteboardWriter: TextInserting`.
        Stateless (only a `SpeakLog.paste` Logger) → auto-`Sendable`, no `@unchecked`.
        - `insert(_:)` step 1: `NSPasteboard.general.clearContents()` + `setString(_:forType:.string)`
          — WRITE ONLY. Never reads the pasteboard (hard rule).
        - `insert(_:)` step 2: `simulateCmdV()` — `CGEventSource(stateID:.hidSystemState)`,
          `CGEvent(keyboardEventSource:virtualKey:kVK_ANSI_V=0x09:keyDown:)` (kVK_ANSI_V
          constant from Carbon/HIToolbox, `[verified]` = 9 = 0x09), `.flags = .maskCommand`,
          `.post(tap:.cghidEventTap)` (Swift instance method, not the obsoleted free fn).
          nil `CGEvent` → logs + throws `SpeakError.pasteboardBusy` (no force-unwrap).
      - **`SpeakCore/Engine/CaptureSession.swift` (MODIFIED — additive):**
        - Added `private let inserter: (any TextInserting)?` storage.
        - Extended `init` with `inserter: (any TextInserting)? = nil` (default nil
          → all existing call-sites and tests compile unchanged).
        - In `stop()`: after building `result`, before `state = .done`, calls
          `try await inserter.insert(cleanedText ?? rawText)` when inserter is non-nil.
          On throw: sets `state = .error(speakError)`, finishes partials continuation,
          clears streamTask, rethrows — no resource leak.
      - **`SpeakTests/PasteTests.swift` (NEW, 6 tests, all green):**
        - `testInserterNilDoesNotInsertAndSessionIsDone` — pre-P6 path unchanged.
        - `testInserterReceivesCleanedTextWhenCleanupSucceeds` — insert gets cleanedText.
        - `testInserterReceivesRawTextWhenCleanerIsNil` — insert gets rawText.
        - `testInserterReceivesRawTextWhenCleanerIsUnavailable` — graceful-fallback path.
        - `testInserterThrowsTransitionsSessionToError` — SpeakError.pasteboardBusy.
        - `testInserterGenericThrowWrappedToPasteboardBusy` — generic error mapping.
      - **SDK verifications (swiftc -typecheck + runtime, 2026-06-20):**
        - `NSPasteboard.clearContents()` → Int [verified]
        - `NSPasteboard.setString(_:forType:.string)` → Bool [verified]
        - `CGEventSource(stateID:.hidSystemState)` → optional [verified]
        - `CGEvent(keyboardEventSource:virtualKey:keyDown:)` → optional [verified]
        - `CGEvent.post(tap:.cghidEventTap)` instance method [verified]
        - `kVK_ANSI_V = 9 = 0x09` [verified: runtime]
        - `CGEventFlags.maskCommand` [verified]
      - **make build**: zero new warnings. **make lint**: 0 new serious violations.
        **make test**: 50/50 (5 XCTSkip = pre-existing live FM); 6 new P6 tests green;
        all 44 prior tests still pass.
      - **P6 done-when rows:**
        - `[verified]` `TextInserting` protocol + `PasteboardWriter` conformer compile clean.
        - `[verified]` `CaptureSession(inserter:nil)` → no insert, session → `.done`.
        - `[verified]` Cleanup on: inserter receives `cleanedText`.
        - `[verified]` Cleanup off: inserter receives `rawText`.
        - `[verified]` Cleanup unavailable: inserter receives `rawText`.
        - `[verified]` Insert throws → session → `.error(.pasteboardBusy)`.
        - `[verified]` All 44 prior tests still green.
        - `[deferred — needs human verification]` Paste into TextEdit (plain text).
        - `[deferred — needs human verification]` Paste into Slack (rich text).
        - `[deferred — needs human verification]` Terminal paste-provenance —
          **the project's #1 `[unverified]`: whether write+Cmd+V avoids macOS 26.4's
          Terminal pastejacking check. Must be tested by a human in a running app.**
        - `[deferred — needs human verification]` Password-field silent no-op (no crash).

## Done (this session — 2026-06-20, loop run #6 — P5 HotkeyMonitor)

- [x] **Phase 5 code-complete (live criteria deferred) — `HotkeyMonitor` (CGEventTap global hotkey)**
      - **`SpeakCore/Hotkey/HotkeyMonitor.swift` (NEW):** Full P5 implementation.
        - `HotkeyEvent: Sendable` — `startCapture | stopCapture` (verbatim §6).
        - `HotkeyBinding: Codable, Sendable` — custom `Codable` for `CGEventFlags`
          (encodes `modifiers.rawValue: UInt64`). Default binding: `kVK_Function`
          (0x3F=63, Carbon/HIToolbox [verified]), `modifiers: []`, `.doubleTap`,
          `doubleTapWindow: 0.4` (benchmark.md §7 [decision], trace comment inline).
        - `DoubleTapDetector: Sendable` — pure value-type detector. No CGEventTap,
          no wall-clock. Timestamps injected → fully testable. State: idle →
          first-tap-recorded → startCapture emitted → stopCapture on next single tap.
          `reset()` clears all state.
        - `BindingStoring` protocol + `UserDefaultsBindingStore` — thin testable
          boundary; loads/saves via `JSONEncoder`/`JSONDecoder` in UserDefaults.
        - `HotkeyMonitor` (final class, `@unchecked Sendable`): spawns a private
          CFRunLoop thread for tap callbacks; installs tap via
          `CGEvent.tapCreate(tap:place:options:eventsOfInterest:callback:userInfo:)`
          [verified: obsoletes CGEventTapCreate, SDK 2026-06-20]. Event mask:
          `.flagsChanged` only (Fn does NOT produce keyDown [verified: flagsChanged
          rawValue=12]). Press-edge detected via `.maskSecondaryFn` [verified:
          rawValue=8388608, SDK]. `self` passed via `Unmanaged.passUnretained`
          through `userInfo` — no global mutable state, no retain cycle.
          `CGEvent.tapEnable` re-enables on `tapDisabledByTimeout/ByUserInput`.
          `CGEvent.tapCreate` nil → distinguishes `accessibilityDenied` (via
          `AXIsProcessTrusted()`) from `inputMonitoringDenied` with clean error,
          no force-unwrap. Emits `HotkeyEvent` via `AsyncStream` continuation.
        - **Fn-key event model** [inferred, deferred]: `.maskSecondaryFn` as the
          Fn/Globe key bit is a standard CoreGraphics convention. Live confirmation
          (does this actually fire for the physical Fn key while another app has
          focus) requires a non-sandboxed run with permissions granted → deferred.
      - **`SpeakTests/HotkeyMonitorTests.swift` (NEW, 19 tests):**
        - `HotkeyBindingCodableTests` (6): default binding constants, round-trips
          (default, with modifiers, empty modifiers).
        - `DoubleTapDetectorTests` (11): within-window→start, at-edge→start,
          outside-window→no-event, single-tap→no-event, start→single→stop,
          isCapturing state after start and stop, reset clears state and allows
          fresh double-tap, three-taps cycle, restart after stop.
        - `UserDefaultsBindingStoreTests` (2): save+load round-trip, nil when nothing stored.
      - **`make build`**: zero new warnings. **`make lint`**: 0 serious violations
        (1 new non-serious `file_length` on `HotkeyMonitor.swift` at 417 lines —
        accepted; the verification comment block is the documentation). **`make test`**:
        44/44 PASS (5 XCTSkip = pre-existing live FM path; 19 new P5 tests green).
      - **SDK verifications (all done with `swiftc -typecheck` against macOS 26 SDK):**
        - `CGEvent.tapCreate(...)` [verified] — CGEventTapCreate obsoleted Swift 3
        - `CGEvent.tapEnable(tap:enable:)` [verified]
        - `CGEventType.flagsChanged` rawValue=12 [verified]
        - `CGEventFlags.maskSecondaryFn` rawValue=8388608 [verified]
        - `kVK_Function` = 63 = 0x3F [verified: compiled + ran]
        - `CGEventTapCallBack` callback type [verified]
      - **P5 done-when rows:**
        - `[verified]` Double-tap Fn within 400ms window emits `startCapture`
          (DoubleTapDetector test, injected timestamps).
        - `[verified]` Single-tap Fn after start emits `stopCapture` (same).
        - `[verified]` `HotkeyBinding` Codable round-trip (encode/decode preserves
          keyCode, modifiers.rawValue, trigger, doubleTapWindow).
        - `[verified]` Taps outside window do not trigger (pure detector test).
        - `[deferred — needs human verification]` Double-tap Fn triggers start/stop
          while **another app has focus** (requires live run + Accessibility grant).
        - `[deferred — needs human verification]` First run triggers Accessibility +
          Input Monitoring permission prompts (requires live run, fresh install).
        - `[deferred — needs human verification, P13]` False-trigger rate < 1/30min
          (dogfood in Notes, benchmark.md §7 F_rate).

## Done (this session — 2026-06-20, loop run #5 — P3.5 CaptureSession)

- [x] **Phase 3.5 COMPLETE on the engine seam — `CaptureSession` orchestration**
      closes every P3.5 done-when row that doesn't require an external state
      change (Apple Intelligence enabled, or a live paste into a focused app).
      - **`SpeakCore/Engine/CaptureSession.swift` (NEW — 295 lines, 0 lint
        warnings):** `actor CaptureSession` per `architecture.md` §6, §7.1.
        Public API: `init(transcriber:cleaner:locale:cleanupMode:)`,
        `start()`, `stop() -> TranscriptionResult`, `cancel()`,
        `partials() -> AsyncStream<TranscriptChunk>`, `currentState`, `isTerminal`.
      - **State machine**: `.idle → .listening → .processing → .done` (or
        `.error` from any non-terminal step). Implemented verbatim per
        architecture §7.1.
      - **STT lifecycle**: `start()` spawns a background `Task` that consumes
        the STT `AsyncThrowingStream` and `await`s each chunk into the actor
        (`ingest(_:)`) before reading the next. `stop()` `await`s
        `transcriber.stop()` (which triggers finalization on the real
        SpeechAnalyzer), then `await`s the stream task to drain, then reads
        `latestChunk?.text` as the raw transcript. This is the
        synchronization point that makes the partial-stream + final-result
        contract race-free.
      - **Cleanup wiring** (the P3.5 contract, architecture §10a.1):
        - `cleaner == nil` (cleanup off) → `cleanedText = nil`,
          `engineId = STT id`.
        - `cleaner.isAvailable == false` → `cleanedText = nil`, **no error**
          (graceful fallback, session reaches `.done`).
        - `cleaner.clean()` throws `SpeakError` → propagated unchanged.
        - `cleaner.clean()` throws anything else → wrapped in
          `SpeakError.llmCleanupFailed` (canonical mapping).
        - `cleaner.clean()` succeeds → `cleanedText` populated,
          `engineId = "<stt>+<cleaner>"`.
      - **Partials stream** (`partials()`): an `AsyncStream<TranscriptChunk>`
        for the live overlay (P4). Replaces any prior consumer on each call
        (intentional: the session is single-consumer per dictation); the
        stream finishes when the session terminates.
      - **Stream-failure path**: when the STT stream throws mid-session, the
        session moves to `.error(.transcriberUnavailable(...))` and `stop()`
        re-throws on the next call.
      - **`SpeakTests/CaptureSessionTests.swift` (NEW — 13 tests, all
        green):** mock `Transcribing` (class, `@unchecked Sendable`) +
        mock `LLMCleaning` + `CleanerRecorder` actor for call assertions.
        Covers: initial state, start transitions, double-start throws,
        stop-without-listening throws, cancel→`.error(.sessionCancelled)`,
        stop returns latest-chunk text, cleanup-off→`cleanedText=nil`,
        cleanup-on→`cleanedText` populated + engineId = `<stt>+<cleaner>`,
        cleaner-unavailable→graceful fallback to raw (`.done`, NOT `.error`),
        cleaner-throws-SpeakError→propagates, cleaner-throws-generic→wrapped
        in `SpeakError.llmCleanupFailed`, STT-stream-fails→`stop()` re-throws
        `SpeakError.transcriberUnavailable`, partials stream emits every
        chunk in order and finishes.
      - **`CaptureSession.State: @retroactive Equatable`**: file-local
        conformance added so the test assertions (`XCTAssertTrue(state == .done)`)
        don't depend on Stringly-typed matching. `@retroactive` silences
        Swift 6's "could be added upstream" warning (we own the type).
      - **Build/lint/test**: `make build` clean (no new warnings),
        `make lint` 3 non-serious violations (all `file_length`/`function_body_length`,
        accepted; the AppleSpeechTranscriber + FoundationModelsCleaner
        violations pre-existed and were already accepted for documentation),
        `make test` 25/25 PASS (5 XCTSkip = live FM path; mock-orchestration
        tests are 13/13 PASS).
      - **Roadmap P3.5 boxes checked** in `docs/roadmap.md` with `[verified]`
        tags; the *sample-dictation-cleaned* row carries the explicit
        caveat that the **live** path stays `[inferred]` until P13 dogfood
        (FM is gated off on the dev Mac).

## Done (this session — 2026-06-20, loop run #4 — P3 SpeechAnalyzer STT)

---

## Done (this session — 2026-06-20, loop run #4 — P3 SpeechAnalyzer STT)

- [x] **Phase 3 COMPLETE — SpeechAnalyzer STT.**
      - **`SpeakCore/STT/AppleSpeechTranscriber.swift`**: `Transcribing` conformer
        backed by Apple SpeechAnalyzer (macOS 26+). Engine id `"apple-speech-en-US"`.
      - **Authoritative lifecycle implemented** ([verified] WWDC25 #277):
        `analyzer.start(inputSequence:)` returns after setup (NOT after all input) →
        bridge feeds AnalyzerInput → bridge task completes (all input fed) →
        `finalizeAndFinishThroughEndOfInput()` closes `transcriber.results` →
        results drain → stream finishes. Not calling `finalize` caused a hang (diagnosed
        by orchestrator and fixed).
      - **Audio injection**: `AudioBufferProducing` protocol injected at init;
        default `LiveAudioCapture` wraps P2's `AudioCapture`; tests inject
        `FixtureAudioProducer`. No-arg factory `AppleSpeechTranscriber()` works unchanged.
      - **Format conversion** [verified at runtime]: `bestAvailableAudioFormat` returns
        16kHz mono Int16 interleaved; P2 produces Float32 non-interleaved. `AVAudioConverter`
        bridges them correctly. Bug caught: original check compared only sample rate + channel
        count, missing `commonFormat` difference → converter not built → "Audio sample data
        must be 16-bit signed integers" error. Fixed to compare `commonFormat` + `isInterleaved`.
      - **Asset provisioning**: `AssetInventory.status` + `assetInstallationRequest` →
        `downloadAndInstall()`. Locale validated via `SpeechTranscriber.supportedLocale`.
        `SpeechTranscriber.isAvailable` static gate.
      - **Clean stop**: `stopSession()` calls `audioProducer.stop()` (ends buffer stream)
        → bridge exits → `inputCont.finish()` → `finalize` runs in session task → results
        drain → session task exits. No zombie tasks.
      - **`SpeakTests/SpeechTranscriberTests.swift`**: 4 tests. `testTranscribesFixture`
        produces real transcription: fixture "Testing one two three" → final transcript
        `'cased in one, two, three.'` — one, two, three found [inferred: "testing" → "cased"
        is model behavior with synthetic speech]. `testStopTerminatesStream` confirms no hang.
      - **Fixture**: `SpeakTests/Fixtures/hello_speech.caf` (16kHz mono Float32, 1.3s).
      - **`make build`**: zero warnings. **`make lint`**: 0 serious violations (1 non-serious
        file-length warning on the implementation file — accepted; comments are required
        for API verification). **`make test`**: 10/10 PASS.
      - **P2 format note** (surfaced for orchestrator): P2 hard-bakes 16kHz Float32 output.
        SpeechAnalyzer's `bestAvailableAudioFormat` = 16kHz Int16 interleaved. P3 converts.
        Optimal path would be: P2 outputs native mic format, P3 does one conversion to Int16.
        Not a blocking issue — P3 handles it — but worth noting for P13 latency tuning.

---

## Done (prior session — 2026-06-20, loop run #3)

- [x] **Xcode 26.5 installed + activated** (human ran `xcode-select -s`,
      `xcodebuild -runFirstLaunch`, `-license accept`). `xcodebuild` works;
      macOS 26.5 SDK present; `swiftlint` 0.63.3 via brew. Open Q#1 fully resolved.
- [x] **Phase 0 COMPLETE — canonical Xcode build system.**
      - **Decision (mine, under delegation; implements Q#5)**: generate the
        mandated `.xcodeproj` with **XcodeGen** from a checked-in `project.yml`,
        rather than hand-author a fragile `.pbxproj` or use the Xcode GUI (which
        an agent can't drive). XcodeGen is **build-time only** — never linked into
        the app — so it doesn't touch the Apple-frameworks-only runtime moat
        (`AGENTS.md` §2.4). `Speak.xcodeproj` is git-ignored; `project.yml` is the
        source of truth; `make build` regenerates it (works from a clean clone).
      - Three §5 targets build: `Speak.app` (application), `SpeakCore.framework`
        (the portability seam), `SpeakTests` (unit-test bundle). Engine `.swift`
        files moved into the framework target with **zero code change** (they were
        already in the §5 layout).
      - `Makefile` (`build`/`test`/`lint`/`run`/`clean`/`release`-stub),
        `.swiftlint.yml` (enforces §3: force_unwrap/force_cast/force_try = error),
        GitHub Actions CI (`.github/workflows/ci.yml` — `xcodebuild` + swiftlint;
        **[unverified]** until the repo has a remote + a push).
      - **Verified**: `make clean && make build` → runnable `Speak.app`;
        `make lint` → 0 violations; `make test` → 4/4 pass via `xcodebuild test`.
      - **Retired the temporary SwiftPM/smoke scaffolding** (`Package.swift`,
        `Smoke/`) — its only purpose (no XCTest under CLT) is gone now that
        `xcodebuild test`/`swift test` run the canonical `SpeakTests`.
- [x] **Phase 1 COMPLETE — menubar scaffold.** `App/SpeakApp.swift`: a
      `MenuBarExtra` app (waveform idle icon) with an **About speak…** item +
      Quit, running as **LSUIElement** (no Dock icon). Links `SpeakCore` and logs
      via `SpeakLog.engine` on launch (proves the framework seam). **Launched and
      confirmed running** (pid alive, menubar-only). Roadmap P1 done-when met.
- [x] **Engine-core foundation built + verified under CLT (no Xcode needed).**
      Implemented the framework-agnostic core from `architecture.md` §6 in the
      **final §5 layout**: `SpeakError` (Engine/), `Transcribing`+`TranscriptChunk`
      (STT/), `LLMCleaning`+`CleanupMode` (Cleanup/), `TranscriptionResult`
      (Engine/, split to its own file), `SpeakLog` OSLog categories (Logging/).
      `swift build` **green, zero warnings**. Verification: XCTest/swift-testing
      both ship only inside full Xcode, so `swift test` can't run under CLT — so
      I added a temporary `speak-smoke` executable target (`swift run speak-smoke`)
      that exercises every type/seam with mock `Transcribing`/`LLMCleaning`
      conformers: **16/16 checks pass**. The canonical swift-testing suite
      (`SpeakTests/EngineCoreTests.swift`) is authored and runs once Xcode lands.
      - **Decision (mine, logged)**: user delegated all technical calls → built
        the engine core in parallel with the Xcode install. Reason is *non-churn*,
        not speed: these §6 types are stable across build systems and the .swift
        files drop into the Xcode `SpeakCore.framework` target unchanged.
      - **Minor verbatim-spec deviations (strict additions, surfaced)**: added
        explicit `public init`s to `TranscriptChunk` and `TranscriptionResult`
        (a public struct needs a public init to be constructible cross-module —
        §6 omitted them); `TranscriptionResult` lives in its own file rather than
        inside `CaptureSession.swift`. Neither changes the type shape.
      - **Deferred from this increment**: `HotkeyBinding` (its `modifiers:
        CGEventFlags` isn't `Codable` out of the box → needs custom coding; it's
        CoreGraphics/P5 territory anyway) and `CaptureSession`/`SpeakEngine` (the
        state machine needs a paste-seam abstraction decision — next unit).
- [x] **`git init` + first commit** (`e3f9b63`) — repo is now version-controlled;
      commit discipline (`AGENTS.md` §7) is live. Staged the full doc set +
      research; excluded `.claude/*.lock` transient state.
- [x] **Phase 0 pure-text deliverables** (verifiable without Xcode):
      `LICENSE` (MIT), `.gitignore` (macOS/Xcode/SwiftPM/secrets), `.swift-version`
      (`5.9`). README skeleton already existed.
- [x] **Reframed the "everything is blocked" chain** (prior session was too
      broad). Probed the Command-Line-Tools SDK: `swiftc -typecheck` **succeeds**
      for `import Speech`, `import FoundationModels`, `import AVFoundation`,
      `import SQLite3` → the framework headers are present. The true blocker is the
      **app shell + `.app` bundle**, not the engine. → A large slice of `SpeakCore`
      pure logic (`Transcribing`/`LLMCleaning` protocols, `CaptureSession` state
      machine, `TranscriptChunk`/`TranscriptionResult`/`SpeakError`, `SpeakLog`,
      `SettingsStore`, `HistoryStore` SQLite) is buildable + `swift test`-able now
      behind mock conformances, with zero Xcode. **Awaiting the human's go on the
      SwiftPM-now path** (adding a build system alongside the mandated `.xcodeproj`
      is a rails-move → ask, per `AGENTS.md` §4).

## Done (prior session — 2026-06-20)

- [x] **Verified the load-bearing claims** against primary sources (3 parallel
      research streams). Result in `specs/verification-ledger.md`.
  - Foundation is **sound**: `SpeechAnalyzer` (on-device, macOS 26 Tahoe, shipped
    Sept 15 2025), `CGEventTap` perms + Fn=`kVK_Function` 0x3F all `[verified]`.
  - **Bonus**: macOS 26 ships `Foundation Models` (on-device LLM) `[verified]` →
    enables native, zero-dependency AI cleanup in v0.
  - **Refuted**: the Wispr "polishing, not shipping" thesis — Wispr is in
    aggressive expansion. Repositioned to the *structural* moat.
  - **Corrected**: Wispr has a free tier + uses Fn + is multi-platform; competitor
    prices; WhisperKit repo path; macOS ship date.
  - **`[unverified]`**: the specific paste write+Cmd+V bypass — **test at P6**
    (macOS 26.4 added a Terminal paste-provenance check).
- [x] **Created `docs/benchmark.md`** — the definition of done: category parity
      map (Wispr = frontier), MATCH/BEAT/SKIP buckets, phased, with a derivation
      ledger (no hardcoded magic numbers). This is the loop's objective function.
- [x] **Rewrote `docs/product.md`** — added the final-outcome / "what it looks
      like" destination; the full, time-free version ladder (v0 = complete core,
      v1 friendly, v2 creative, v3+ frontier); AI neat-writing as core; pluggable
      local models; corrected structural positioning.
- [x] **Made AI neat-writing v0 core** across the docs: `LLMCleaning` protocol +
      `FoundationModelsCleaner` (Apple framework → no third-party-dep violation),
      wired into `CaptureSession.processing` (finalize → cleanup → paste).
      `architecture.md` §10a, `roadmap.md` P3.5, `quality.md` cleanup tests,
      `benchmark.md` cleanup → v0 MATCH.
- [x] **Removed all project-schedule time** (dates, "14 days", effort S/M/L/XL,
      "first 48 hours", stopwatch UX targets) from every doc. Build is an
      unbounded loop; "done" = testable criteria only.
- [x] Updated `AGENTS.md` (no deadline; cleanup core; `benchmark.md` registered)
      and ran a coherence pass (cross-refs, version labels, zero residual time).
- [x] **Completed the `specs/wispr-parity-and-spec.md` plan** (the spec/benchmark
      track that `/loop` was pointed at):
  - [x] **Authored `SPEC.md`** (root) — the human-readable consolidated spec:
        vision, structural why-now, market + **embedded parity map**, personas,
        UX, architecture summary, privacy, roadmap, risks, GTM, ledger summary,
        and a `docs/`-corrections appendix. Single voice; claims tagged.
  - [x] **Adversarial review (plan task #6) found 6 blocking + 4 nits; all 6
        blocking FIXED, re-validated to 0**. The sonnet reviewer caught real
        factual errors that orchestrator greps missed — corrected in
        `benchmark.md`/`SPEC.md` (the plan's own deliverables; `product.md` and
        the other immutable docs untouched):
    - B1: `benchmark.md` §3 history row was falsely `[verified]` → `[unverified]`
          (ledger §2 ground truth).
    - B2: `SPEC.md` embedded counts were wrong on all figures → corrected to
          **7 MATCH · 8 BEAT · 4 SKIP/SKIP→MATCH = 19 rows**.
    - B3: `benchmark.md` §1 snapshot had no per-row verdict tags → added
          `[verified]`/`[corrected]` per ledger §3.
    - B4: `benchmark.md` §1 malformed "Superwhisper/MacWhisper" row → split into
          a correct standalone **MacWhisper** row.
    - B5: Wispr annual price "$12/yr" (implies $12 total/yr) → **$12/mo annual
          ($144/yr)** per ledger §2.
    - B6: §3 BEAT list (7 structural) vs §2 matrix (8 BEAT) reconciled with a
          scope note + a fixed §4 v0-BEAT enumeration.
    - Nits N3 (missing matrix columns — values still trace to §7) and N4
          (`architecture.md` "~95% of apps" stale claim) left for the human;
          N2 (product.md "modified this run") was a **false alarm** — mtime
          `1781956811` is unchanged from this run's baseline (last touched in the
          prior session).
  - [x] **Validation (task #7) passes after fixes**: every MATCH row has a binary
        criterion tracing to `benchmark.md` §7 (no orphan constants); no stale
        citations leaked (Tsai 2026-04-03, `argmax-oss-swift`, Superwhisper $8.49,
        paste bypass `[unverified]`); why-now is structural (no "Wispr coasting");
        no cloud SKIP in a v0 MATCH. `docs/product.md` untouched (mtime at baseline).
- [x] **Verified toolchain (open Q#1)**: `swift` 6.3.2 present, target
      `arm64-apple-macosx26.0` ✓ — but **`xcodebuild` is ABSENT** (only Command
      Line Tools active, no full Xcode) and the dir is **not a git repo**. Phase 0
      is therefore **blocked** until Xcode is installed + `git init` is approved.

---

## In progress

Nothing. The spec/benchmark track is complete (`benchmark.md`, `SPEC.md`,
`verification-ledger.md` all done + validated). The `/loop` pointed at the spec
plan was stopped on completion (job `ddc5d3fd` deleted) — it would otherwise
thrash, since the next work (Phase 0) is blocked on a human gate.

---

## Blocked

- **Nothing blocks the build.** Xcode is installed; P0/P1 are done; P2 is ready.
- Deferred (not blocking): CI YAML is **[unverified]** (no git remote yet — needs
  a push to a macOS-26 runner to confirm); Developer ID signing cert for
  notarization is still needed at P11 (Open Q#4).

---

## Next up

1. **P2 — Audio capture (CRITICAL PATH)**: `PermissionManager` (mic state) +
   `AudioCapture` (`AVAudioEngine`, 16kHz mono PCM) streaming PCM buffers to an
   `AsyncStream`. First run triggers the mic permission prompt; logs buffer stats
   via `SpeakLog.audio`; clean stop on cancel. These are framework-bound (AppKit/
   AVFoundation) → they live in `SpeakCore` but are exercised through the app for
   the permission prompt. Add `NSMicrophoneUsageDescription` to the app plist.
2. **P3 — SpeechAnalyzer**: `AppleSpeechTranscriber` against `Speech`
   (verify API surface vs current Apple docs first).
3. **Engine-core unit (do alongside P2/P3)**: `CaptureSession` actor state
   machine (§7.1) + `SpeakEngine` facade. Needs a paste-seam abstraction
   (`TextInserting` protocol so the core stays testable; real `PasteboardWriter`
   NSPasteboard impl is app-side) — design + document in `architecture.md` first.
   Then `HotkeyBinding` Codable (custom coding for `CGEventFlags`).
4. **P3.5 cleanup → P5 hotkey → P6 paste** along the critical path.
3. **P1 → P2 → P3 → P3.5 (cleanup) → P5 → P6** along the critical path.
4. The loop runs until `benchmark.md` §4 MATCH gate + §3 BEAT rows +
   `quality.md` §9 all pass. No deadline.

---

## Decisions logged

| Date | Decision | Rationale | Source |
|---|---|---|---|
| 2026-06-20 | **XcodeGen generates the canonical `.xcodeproj`** from `project.yml` (git-ignored project; `make build` regenerates) | An agent can't drive the Xcode GUI and hand-authored `.pbxproj` is fragile/version-specific; XcodeGen is build-time-only (not linked into the app) so it preserves the Apple-frameworks-only runtime moat (§2.4). Implements Q#5's canonical-Xcode decision | This session (loop #3); advisor concurrence |
| 2026-06-20 | **AI neat-writing is v0 core**, default = on-device `Foundation Models` | "Speech→neat text" is the product identity (= Wispr's core); Foundation Models is an Apple framework, so v0 stays zero-third-party-dep, local, free | `verification-ledger.md`; user direction |
| 2026-06-20 | **No deadlines / no time anywhere** — unbounded build loop | Agent-driven development; "done" = testable criteria, not dates | User direction |
| 2026-06-20 | **v0 = complete core, not MVP**; full v0–v3+ ladder defined up front | Knowing v1–v3 lets v0 be architected so later versions are additive, never a rewrite | User direction; `product.md` §9 |
| 2026-06-20 | Reposition to the **structural** moat (local+free+open+offline+no-account+history) | Wispr "why now / coasting" thesis refuted; the durable wedge is what Wispr can't do without abandoning cloud revenue | `verification-ledger.md` §2 |
| 2026-06-20 | `benchmark.md` is the **definition of done** + loop objective function | "Be as good as Wispr" must be testable, not a vibe | User direction |
| 2026-06-20 | **Spec/benchmark track complete; stopped the 1-min `/loop`** (`ddc5d3fd`) on validation pass | The loop was scoped to `specs/wispr-parity-and-spec.md`, now done (SPEC.md + review + validation, 0 blocking). Next work (Phase 0) is blocked on a human gate (Xcode + `git init`), so continued firing would only thrash or risk an unactionable cold-cycle Swift attempt | This session; advisor guidance |
| 2026-06-18/19 | Build `speak` (Mac dictation); Swift-native single codebase; Apple `SpeechAnalyzer` default behind pluggable `Transcribing`; double-tap Fn; write-never-read paste; MIT; non-sandboxed v0 | (carried from prior sessions) | `research/`, prior `progress.md` |

---

## Open questions

| # | Question | Status | Needed by |
|---|---|---|---|
| 1 | Xcode/Swift toolchain available here? Repo needs `git init`. | **Resolved 2026-06-20**: `git init` **DONE** (`e3f9b63`); `swift` 6.3.2 ✓; **`xcodebuild` ✗ (no full Xcode)**. Xcode-bound P0 parts blocked; the rest is not. | P0 |
| 5 | **Build+test `SpeakCore` logic via SwiftPM now, or wait for Xcode?** | **Resolved/implemented 2026-06-20 (loop #3)**: canonical `.xcodeproj` via **XcodeGen** (`project.yml` source of truth). SwiftPM scaffolding retired. | P0 ✓ |
| 2 | `Foundation Models` runtime availability/quality for cleanup on the target Macs (Apple Intelligence gating, M-series, locale)? | Verify empirically at P3.5; raw fallback exists | P3.5 |
| 3 | Does write+`Cmd+V` avoid the paste prompt incl. the macOS 26.4 Terminal provenance check? | `[unverified]` — test in Terminal/iTerm | P6 |
| 4 | Developer ID signing cert for notarization? | Unverified | P11 |

---

## Session log

- **2026-06-20 (agent-harness / context-engineering)**: Built the autonomous
  build harness — 8 skills (`.claude/skills/`: 3 thick doc-grounded + 5 thin
  per-seam Apple-API pointers) and a 7-agent standing team (`.claude/agents/team/`,
  one per architecture seam). Wired project MCP (`.mcp.json`): `apple-docs`
  (✔ connected) + `xcode` (`xcrun mcpbridge`, Xcode 26.5 — connects but needs a
  one-time in-Xcode auth). Established the **swiftc-against-the-local-SDK**
  verification backbone (cutoff-proof) and ran an SDK-anchored, adversarially
  citation-checked verification workflow over all 8 skills (14 agents). Applied
  11 upheld fixes; 10 claims correctly deferred (empirical-by-design). **Two
  source-of-truth API bugs caught + fixed**: `architecture.md` §6 + §9 used
  `LanguageModel.default` / `LanguageModel` (do not resolve) → `SystemLanguageModel`
  + `.availability`; `roadmap.md` P3 §14.1 anchor → §10.2. Added the harness to
  `AGENTS.md`/`CLAUDE.md` navigation so a fresh `/loop` discovers it. Lesson:
  agents share the Jan-2026 cutoff, so skills must carry post-cutoff truth verified
  against the live SDK, never recalled. See `docs/agent-tooling.md`.
- **2026-06-20**: Verified load-bearing claims (foundation sound; Foundation
  Models unlock; Wispr thesis repositioned). Created `benchmark.md` +
  `verification-ledger.md`. Rewrote `product.md`. Elevated AI cleanup to v0 core.
  Stripped all schedule-time from the doc set. Coherence pass clean. Ready for P0.
- **2026-06-20 (loop run)**: Authored `SPEC.md` (opus) embedding the parity map.
  Adversarial review (sonnet) found **6 blocking defects** (false `[verified]`
  history tag; wrong embedded row counts; untagged §1 snapshot; malformed
  MacWhisper row; "$12/yr" mispricing; §3↔§2 BEAT mismatch) — orchestrator
  verified each against the ledger and **fixed all 6** in `benchmark.md`/`SPEC.md`
  (`product.md` and other immutable docs untouched), re-validated to **0
  blocking**. Lesson: mechanical greps (`grep -c`) missed factual + counting
  errors a real review caught — don't declare "done" before the reviewer reports.
  Resolved open Q#1: `swift` 6.3.2 present but `xcodebuild` absent → Phase 0
  blocked on installing Xcode + `git init`. Completed the spec plan and stopped
  the `/loop` (`ddc5d3fd`). Build can resume once the human gate is cleared.
- **2026-06-20 (loop run #2)**: `git init` + first commit (`e3f9b63`) with MIT
  `LICENSE`, `.gitignore`, `.swift-version`. Reframed the prior session's
  "everything blocked on Xcode" — it was too broad. Probed the CLT SDK:
  `swiftc -typecheck` passes for `Speech`/`FoundationModels`/`AVFoundation`/
  `SQLite3`, so the real blocker is the app shell, not the engine. A large slice
  of `SpeakCore` pure logic is `swift test`-able now behind mocks. Surfaced the
  SwiftPM-now-vs-wait decision (Open Q #5) to the human and stopped the loop on
  it (human-gated; the answer re-triggers). Lesson: don't let one missing tool
  collapse into "nothing is actionable" — separate the verification gap (Xcode)
  from the genuinely-buildable core.
- **2026-06-20 (loop run #3)**: Human installed + activated Xcode 26.5. Chose
  **XcodeGen** to generate the canonical `.xcodeproj` from `project.yml` (agent
  can't drive the GUI; build-time-only tool preserves the runtime moat).
  **Completed Phase 0** (3 §5 targets build via `make build`; lint clean; tests
  green via `xcodebuild test`) and **Phase 1** (menubar app launched + verified).
  Retired the temporary SwiftPM/`Smoke` scaffolding. Next: P2 audio capture.
- **2026-06-21 (W4.1)**: Implemented the transparency moat. Two deliverables:
  (1) **4-level cleanup intensity** — `CleanupLevel` extended from 3 cases
  (basic/balanced/thorough) to 4 (none/light/medium/high). `SpeakEngine.newSession()`
  gates on `level == .none` → skips the LLM pass entirely. `FoundationModelsCleaner.
  styledInstructions` updated with named, traceable prompt clauses per level. Default
  changed from `.balanced` to `.medium`. All prompt clauses carry `[decision W4.1]`
  tags. `StylePaneView` and all tests updated; old rawValues (basic/balanced/thorough)
  no longer decode → fallback to `.medium` (pre-release clean break, [decision]).
  (2) **`CleanupDiffView`** — new `App/Components/CleanupDiffView.swift`, a standalone
  SwiftUI view using Monaco tokens (speakMono*, speakDiffInsert, speakDiffDelete) with
  3 display modes (inline/side-by-side/cleaned). Backed by `SpeakCore/Diff/TextDiff.swift`
  — pure dependency-free word-level LCS diff (`textDiff(raw:cleaned:)` → `[DiffSegment]`).
  Unit-tested in `SpeakTests/TextDiffTests.swift` (edge cases + level mapping + prompt
  traceability). All 4 gates green: `make build`, `make test` (301 tests, 5 XCTSkip,
  0 failures), `make lint` (0 errors), `make verify-moat` (7/7 PASS).
- **2026-06-21 (W3.1)**: Settings screen IA redesign. Replaced the flat 4-section Form
  with a 7-tab `TabView` (General · Shortcuts · Transcription · AI Cleanup · Dictionary ·
  Privacy · About). Monaco `SpeakTheme` design language throughout; SpeakSpacing grid, no
  magic numbers. Key changes: (1) **cleanupEnabled/cleanupLevel collapse** — single
  `effectiveCleanupLevel` computed property on `SettingsStore` (getter gates on
  `cleanupEnabled` for back-compat with legacy `enabled=false/level=medium` state; setter
  keeps both in sync). The AI Cleanup tab shows one picker, not Toggle+Picker. Progressive
  disclosure: Style/Engine pickers disabled when level==.none. (2) **Shortcuts tab** shows
  current hotkey binding read-only via `DictationController.currentHotkeyDisplayString`
  (forwarded from `monitor.binding.displayString`); mode labels are key-agnostic (W1.1 safe);
  "Record…" button stub for W3.2. (3) **Privacy tab** — moat surface: lock badge headline +
  four on-device guarantee rows (no cloud audio/AI, no account, never reads clipboard).
  (4) Extension point stubs: restore-clipboard (W3.4), transcript auto-delete (W3.3).
  Files changed: `App/Settings/SettingsView.swift` (full rewrite), `SpeakCore/Storage/
  SettingsStore.swift` (+effectiveCleanupLevel), `App/DictationController.swift`
  (+currentHotkeyDisplayString), `App/SpeakApp.swift` (SettingsView init update),
  `App/Debug/DebugLaunchDispatcher.swift` (SettingsView init update),
  `SpeakTests/SettingsStoreTests.swift` (+5 effectiveCleanupLevel tests, all pass).
  All 4 gates green: `make build` ✅ · `make test` ✅ · `make lint` 0 errors ✅ ·
  `make verify-moat` 7/7 ✅. Left uncommitted in worktree for orchestrator review.
- **2026-06-19**: Doc restructure into `AGENTS.md` + `docs/` + `research/`.
