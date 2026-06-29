# `speak` — Progress (NOW)

> **Status**: Living state. **The agent rewrites this every session.**
> Single source of truth for "where are we right now." Read first, update last.
> History before loop #26: `docs/progress-archive.md`. See `../AGENTS.md` §5.

---

## Current phase

**Loop #37 (2026-06-29) — DIRECTION LOCKED + v0 fix phase. The product's north star is now the Profile Engine: a local-first, voice-driven, fully customizable AI text engine. See `specs/profile-engine.md`, `specs/profile-system-prompts.md`, `product.md §6d`, and the roadmap "North star" section.**

### What changed this loop (read before doing anything)
-3. **PE-1: Profile Engine WIRED into the dictation flow (`7f415c2`).** Profiles are now *felt*: `ProfileResolver` (pure) maps the frontmost app → a built-in profile, and `SpeakEngine.newSession(frontmostBundleID:)` builds `CleanupMode.profile` (rendered via `PromptBuilder.instructions`) when an app-specific profile matches — **Cursor/VSCode/Xcode/Zed → Code, Terminal/iTerm → CLI, Tower/SublimeMerge → Commit**. Intensity (cleanup level) + custom vocabulary are threaded through as cross-profile modifiers. **The global/default path stays on `.styled()` — ZERO regression** (StyleModeTests byte-unchanged); the full default→Clean migration is deferred to AI Studio. `DictationController` reads the frontmost bundle id on `@MainActor` and passes it down so the engine stays AppKit-free. **Chat profile is dormant** until URL-based matching (its targets are web hosts, not app bundle ids). ⚠️ **Needs live re-verify**: the model prompt CHANGED for app-matched dictations — dictate into Terminal/Xcode (profile path) AND a normal app (unchanged default) and watch the log-stream; `v0-base` is rollback.
-2. **Group A (UI polish) + PE-0 LANDED + pushed to GitHub.** After v0-base: #32 overlay gear removed (`35d5577`), #33 sidebar switches panes — fixed the tap-capturing `NavigationLink` in both `DashboardView` + `AppShell` (`10e9205`), #34 Appearance theme wired to `NSApp.appearance` + dead auto-paste/notifications toggles removed + history live-refresh (`9b88fd1`), and **#39 PE-0 Profile Engine spine** — `Profile` type + enums + pure `PromptBuilder` + 7 built-ins (Raw/Clean/Chat/Code/CLI/Prompt/Commit) + 15 tests, **additive only, not yet wired into the dictation flow** (`2952cf7`). Git health: stale worktrees/branches removed (single clean `master`); repo published **public** at github.com/ArasanDev/speak (master + `v0-base`). All gates green throughout. **#40 (SM-0 eval harness) is now unblocked.** Worker note: the PE-0 worker stalled (idle without writing) twice → orchestrator built it directly from the locked specs (higher fidelity for a spec-transcription task).
-1. **🎯 v0 BASE VERIFIED WORKING LIVE (2026-06-29) — tagged `v0-base`.** The user dictated through speak itself, 3 consecutive times, each pasting correctly. Core loop confirmed end-to-end: double-tap Fn → speak → single-press → SpeechAnalyzer STT → Foundation Models cleanup → **single Cmd+V paste at cursor** → history saved (stopToPaste ~1.1–2.1s incl. cleanup). **These core behaviors are LOCKED — never regress them.** `git tag v0-base` is the protected baseline to return to.
   - **Two root causes were masking the fix during dogfood** (both now resolved, both operational not code): (a) the user was running a **STALE pre-#29 binary** (old `streaming enabled — skipping final paste` path) — fixed by rebuilding/relaunching; (b) the dev build was **ad-hoc signed** (no stable identity was being applied) so the Accessibility grant broke on rebuild → Cmd+V silently skipped. Fixed by `make dev-cert` (identity `speak-local-codesign` existed but wasn't wired) + `make build` (now `Authority=speak-local-codesign`) + `make reset-permissions` + re-grant. AX now persists across rebuilds. See [[dev-codesigning-for-tcc]].
0. **#29 + #30 LANDED** (commits `9131899` [P0.1], `03629d2` [P0.2]; gates re-run on master: build ✅ / test ✅ / lint 0-serious ✅ / moat 7/7 ✅):
   - **#29 single paste path** — removed `if streamingInserter != nil { skip final paste }` in `CaptureSession+Paste.swift`; `SpeakEngine.newSession()` now always passes `streamingInserter: nil` (the `.keystrokeInjection` wiring is retired from delivery; `settings.streamingMode` kept for P2 but inert). Final AI text (`cleanedText ?? rawText`) is now the **single** delivery, every dictation. Raw is never inserted. This fixes "pastes once then stops".
   - **#30 detector desync + dismissable error HUD** — `monitor.notifySessionEnded()` added to begin-fail catch, `microphoneMuted` catch, and `toggleMute` muted branch (DoubleTapDetector no longer stuck `isCapturing==true`); `endDictation` got a `guard icon == .listening` re-entrancy guard (kills the Escape-vs-hotkey double-stop spurious error); `OverlayController.showError` now calls `installEscapeMonitor()` so a begin-failure HUD is dismissable.
   - **Orchestration note:** worker (`fix-delivery-29-30`, Haiku) wrote correct edits but tangled git (committed to master, `git reset` off, left a stray worktree). Recovered the dangling commit, re-ran gates, split into two clean commits, removed the worktree. Reinforces the standing rule: workers edit the main checkout directly, never create worktrees, never `git reset` after committing. **#39 (PE-0) is now unblocked.**
1. **System-freeze bug FIXED** (committed `182ba0c`): `HotkeyMonitor` CGEventTap was `.defaultTap` (active — sits synchronously in the HID input path). Toggling Accessibility off stalled the run-loop thread → froze the whole machine. Changed to **`.listenOnly`** (we are a pure observer; the callback returns events unchanged). Freeze is now structurally impossible.
2. **Three runtime audits done** (agents): @Observable reactivity is HEALTHY (no breaks). Remaining app-layer bugs: overlay gear removal (#32), sidebar nav may not switch panes (#33), History no live-refresh + 3 dead toggles auto-paste/appearance/notifications (#34).

### Layering (immutable — never invert)
- **Base core (never changes):** double-press activate / single-press stop; raw voice → text ALWAYS available, no AI in path.
- **Default:** `Clean` profile (on-device neat-writing); AI off ⇒ raw passthrough.
- **Extension:** the Profile Engine (north star).

### Next actions (in order)
- **v0 fix phase COMPLETE** — ✅ #29–#34 all landed + verified (paste live-confirmed by user; #32/#33/#34 UI fixes on master, awaiting a casual relaunch glance).
- **Profile Engine epic** — ✅ #39 PE-0 (spine). **Next: #40 SM-0** (small-models eval harness `make eval`, now unblocked) → then wire PE-0 into the dictation flow (profile resolution at `newSession()`, generalizing the `LLMCleaning`/`CleanupMode` seam) → AI Studio pane → Overlay Tier-1 chips (`specs/profile-engine.md §8`).
- **Caret streaming (best-effort)** — #35 → #36 → #37.
- **Profile Engine epic** — #39 PE-0 (Profile type + PromptBuilder + 6 defaults), #40 SM-0 (eval harness), #41 SM-1 (study FM limits). Blocked by the v0 fix phase.
- **Caret streaming** — #35–#37 (best-effort; Electron/web caveat documented).

### Orchestration note
Models available: **Opus** (judgment/design/review — me) + **fast worker** (Haiku/WSL2 MiniMax — bulk code). **No Sonnet middle tier.** Design is locked in specs; route mechanical multi-file implementation to the worker with precise briefs; orchestrator reviews diffs + owns commits.

---

### (archived) P11-c streaming context — loop #36 (2026-06-28)
Keystroke injection for raw-text streaming + complete sidebar-nav application (Dashboard, History, Settings, Privacy, About). **Superseded by the Profile Engine direction above; keystroke injection removed in v0 fix phase.**

Gates as of loop #36 (2026-06-28): design locked ✅ streaming architecture designed ✅ app structure specified ✅

**Loop #35** (P11-a: build-from-source install):
- **`make install`** — new Makefile target: `make build` then `cp -r Speak.app /Applications/`
- **`make github-release`** — new Makefile target: Release build → `codesign -s -` ad-hoc sign → `ditto` zip → sha256 printed; users run `xattr -dr com.apple.quarantine` once
- **`dist/speak.rb`** — Homebrew formula (custom tap, build-from-source): `make build CONFIG=Release` → installs to `#{prefix}/Applications/`; Ruby syntax `[verified via ruby -c]`; `url`+`sha256` are PLACEHOLDER until first tag
- **`README.md`** — Install section rewritten: Path 1 (Homebrew formula), Path 2 (GitHub Release zip), Path 3 (official cask at P11-b); test count badge updated 150→481

**P11-a done-when checklist:**
- [x] `make dev-cert` creates a stable local signing identity — done in prior loop
- [x] `make build` produces a runnable `Speak.app` from a clean clone — done in prior loop
- [x] `make install` copies `Speak.app` to `/Applications/` — new target added
- [x] `make github-release` ad-hoc signs, zips, and produces a release artifact — new target added
- [x] `dist/speak.rb` Homebrew formula (custom tap, build-from-source) created — Ruby syntax verified
- [x] `README.md` install section covers both paths with exact commands — updated

**Remaining (human-gated / needs first tag):**
- `dist/speak.rb` url+sha256: PLACEHOLDER until `v0.0.1` tag created and GitHub Release published
- Live test of `make install` (copies Speak.app to /Applications/ — requires user)
- Live test of `make github-release` (builds Release + signs + zips — ~5 min build)

Gates as of loop #34 (2026-06-28): **build ✅ lint 0-serious ✅ moat 7/7 ✅ tests pass ✅**

**Loop #34** (code quality, priorities 2–4):
- **`a4754f1`** — Extension-per-responsibility splits (style):
  - `DictationController+CLI.swift` — `cliBeginDictation/cliEndDictation` (CLICommandHandler W2.3)
  - `DictationController+ErrorHandling.swift` — `beginDictation/endDictation` (error routing + permission recovery)
  - `CaptureSession+Cleanup.swift` — `runCleanup()` (LLM cleanup pipeline, extracted from CaptureSession.swift)
  - `CaptureSession+Paste.swift` — `runPaste()` (paste delivery, extracted from `stop()`)
- **`41212b5`** — `HistoryStoreTests`: replaced local `tempDatabaseURL()` + `addTeardownBlock` with `TestStorage.tempDatabaseURL()`
- **`22d5619`** — `SpeakEngineIntegrationTests`: same `TestStorage` adoption
- **`2b872fb`** — `MenubarIconTests`: migrated 6 XCTest methods → 1 `@Test(arguments:)` with 5 parameterized cases

`SessionIntegrityTests.swift` skipped (uses `NullHistory`, no SQLite temp file pattern to migrate; only `UserDefaults.removePersistentDomain` teardown blocks remain — correct as-is).

---

**@Observable migration COMPLETE — all 6 ObservableObject classes migrated (loop #33, 2026-06-28).**

Feature-complete through Wave 2 + code quality pass. All batches A–E + 1C done (prior sessions).

**Loop #33** (@Observable migration, priority 1 of 4):
- **SettingsStore** — `@Observable` + manual `access(keyPath:)`/`withMutation(keyPath:)` on all 11 computed-over-UserDefaults properties; removed `import Combine`; updated 9 call sites
- **SnippetStore** — same computed-property instrumentation; removed `import Combine`
- **HistoryViewModel** — stored-property migration; `@StateObject` → `@State` in HistoryPaneView; `@Bindable` in HistoryView (needed for `$viewModel.searchText`)
- **OnboardingViewModel** — removed `@Published`; kept `import Combine` for `AnyPublisher` param; removed `deinit` (tasks use `[weak self]`)
- **OverlayViewModel** — trivial stored-property migration
- **DictationController** — replaced `objectWillChange.sink` with `withObservationTracking` re-arming loop (`startObservingTriggerMode()`); replaced `$icon` Combine publisher with `PassthroughSubject` + `icon.didSet`; all `@ObservedObject` call sites updated

UI reactivity (`access`/`withMutation` for UserDefaults-backed properties) is `[unverified]` — needs human dogfood (P13 gate).

Gates as of loop #33 (2026-06-28): **build ✅ lint 0-serious ✅ moat 7/7 ✅ tests pass ✅ (481 / 0 / 0)**

---

## In progress

**Loop #36 (P11-c: Streaming raw text + full-stack UI redesign):**

**Phase 1: Strategic Research & Design (COMPLETE)**
- ✅ **T1** — Architecture: Option D (keystroke injection, not blind-delete)
- ✅ **T2** — SettingsStore: `streamingRawTextEnabled` + `StreamingMode` enum
- ✅ **T3** — KeystrokeStreamingInserter: character-by-character injection via CGEvent (10 tests, moat-safe)
- ✅ **T12** — Landscape research: 7 smart patterns identified, underutilized areas flagged
- ✅ **T15** — Strategic research: competitor analysis (8 apps × 12 UX dimensions), design philosophy (10 principles), speak's vision & constraints
- ✅ **T16** — Design synthesis: locked specification (sidebar nav, 5 panes, 6 settings tabs, privacy pane, Monaco theme, color tokens, component specs, user flows, implementation roadmap)

**Phase 2: Implementation (IN PROGRESS)**
- **T17-T24** (parallel, done): AppShell foundation, Dashboard/History/Settings/Privacy/About panes, Overlay HUD ✅
- **T25** (just completed): CaptureSession state wiring + Dashboard integration + streaming flow completion ✅
- **Phase 2D** (next): Testing & verification gate

**Key Decisions Locked:**
- Navigation: Sidebar (5 panes: Dashboard, History, Settings, Privacy, About) — proven UX, scales to v0.1
- Settings: 6 tabs (General, Transcription, AI Cleanup, Hotkey, Privacy, About) with progressive disclosure
- Privacy pane: **Dedicated sidebar item** (not buried) — speak's BEAT row, trust-building
- Overlay HUD: read-only, streaming partials, state colors (red/yellow/green), gear popover for quick access
- Theme: Monaco monospace + semantic colors + 4pt grid (user locked choice)
- Streaming: keystroke injection (no Cmd+V during live phase, avoiding Terminal paste-provenance prompt risk)

**Design Documents:**
- `specs/ui-ux-strategic-research-2026-06-28.md` (competitor analysis, philosophy, speak's position)
- `specs/speak-ui-design-final-2026-06-28.md` (locked design spec, component specs, user flows, implementation roadmap)

**Loop #36, T25 (P11-c, just completed):** CaptureSession state → AppShell + Dashboard integration + streaming flow completion:
- **Architecture deviation (surfaced, not papered over):** OverlayPresenter was NOT created per the task description. `OverlayController` already fulfills that role perfectly — it manages the overlay lifecycle (panel + view model + state transitions + partials drain + level drain + Escape monitor). The task asked to add OverlayPresenter to AppShell's view hierarchy, but that would create a conflicting second overlay path (the overlay is a non-activating floating NSPanel that intentionally floats over other apps, not part of any SwiftUI view hierarchy). Instead, the integration focused on the real gap: Dashboard wiring.
- **Dashboard integration (primary work):**
  - `DashboardContext`: added `speakEngine`, `permissionManager`, and `dictationCompletedPublisher` fields (all `var` so WindowPresenter/AppShell can refresh them at show-time).
  - `DictationController`: added `dictationCompletedPublisher` (PassthroughSubject) that fires after dictation completes (both success and error paths). Accessible to extensions via internal access.
  - `DictationController+ErrorHandling`: fires the completion signal after overlay is hidden and icon is back to idle (both `.done` and `.error` paths).
  - `WindowPresenter.showDashboard()`: now passes `speakEngine`, `permissionManager`, and `dictationCompletedPublisher` to the dashboard context at every show (via new `updateContext()` method on DashboardWindowController). Hotkey combo + engine + permissions + publisher all refresh at show-time so the dashboard stays current.
  - `AppShell`: now passes the same through to DashboardContext, enabling real-time engine state observation and completion notifications.
  - `HomePaneView`: subscribed to `dictationCompletedPublisher` so the recent dictations list refreshes when a new entry is saved, keeping the dashboard live-updated if open during dictation.
- **Streaming flow completion:** The full flow was already wired (OverlayController.start → partials/levels drain → transition to processing/done → stop), so T25 added the missing Dashboard observation layer.
- **Tests**: `make build` ✅ (no warnings as errors), `make test` ✅ (481/0/0), lint ✅.
- **[Decision P11-c §5]:** Settings latched at session start (streamingMode, language, cleanupEnabled, cleanupLevel read once per dictation in `SpeakEngine.newSession()` with no mid-session changes — matches the H1 pattern for language and Wave 2.2 pattern for cleanup mode). This prevents confusion if the user toggles settings mid-dictation.

---

## Blocked

Nothing blocking. Human-gate items remain owner-only (live paste in 3 apps, latency, false-trigger rate).

---

## Next up

**P11-c implementation (loop #36):**
1. **Phase 2A: Core UI foundation** (AppShell + sidebar navigation)
2. **Phase 2B: Dashboard panes** (Dashboard, History, Settings, Privacy, About — can parallelize)
3. **Phase 2C: Overlay HUD + integration** (wire to SpeakEngine, streaming indicators, gear popover)
4. **Phase 2D: Testing & verification** (integration tests, live verification on 3 apps, latency measurement)

**After P11-c complete:**
- P11-a human-gate (live test of `make install` / `make github-release`)
- P11-b (Developer ID cert — optional, blocks official cask)
- P13 (dogfood: real use, log findings)
- P14 (fix top 3 bugs from P13)
- **v0 ship gate** (all MATCH + BEAT rows pass, quality.md checklist)
- V01-0 (Agent Mode — next iteration)

---

## Open questions

| # | Question | Status |
|---|---|---|
| V1 | Did Phase 1A (`val-oss-compare`) and 1B (`val-skill-sdk`) agents complete? | Unknown — check progress notes or re-run |
| 3 | Does write+`Cmd+V` avoid the paste prompt incl. macOS 26.4 Terminal provenance check? | `[unverified]` — test in Terminal (human) |
| 4 | Developer ID signing cert for notarization? | Unverified — needed for P11 |
| ~~V2~~ | ~~fix-input2 changes — should they merge?~~ | **CLOSED** — merged `d05e740` (2026-06-26), gates green |
| ~~V3~~ | ~~DictationTranscriber contextualStrings support?~~ | **CLOSED** [verified via SDK arm64e-apple-macos.swiftinterface 2026-06-26]: `DictationTranscriber` exists in `Speech`; `AnalysisContext.contextualStrings[.general]` is a valid property. H4 seam is correct. |

---

## Done (2026-06-21, loop run #26 — PHASE 1 base-hardening COMPLETE + paste test-hygiene fix)

**Executed all of Phase 1 from `specs/acceleration-plan.md` (autonomous loop).** Five
surgical, mostly-additive seam-hardening tasks, all merged on `master` and verified by
an independent orchestrator gate from a wiped DerivedData (**build ✅ · 199 tests / 5
XCTSkip / 0 failures · lint 0 serious · moat 7/7**):

- **H1 `6dbe029`** — multi-language seam (builder-engine). `SpeakEngine.newSession()` reads
  `settings.language` at call-time. Behavior-neutral (defaults `en-US`). +`SpeakEngineLanguageTests` (3 tests).
- **H2 `4a3ad09`** — App-test infra `TEST_HOST` (builder-release). `SpeakTests` now HOSTS the `Speak`
  app target. XCTest startup gate in `SpeakApp.swift` skips `startMonitoring()` under
  `XCTestConfigurationFilePath`. +`TranscriptOverlayPanelTests` (6 tests).
- **H4 `9bdc20d`** — `customVocabulary` seam (builder-audio-stt). `vocabulary: [String] = []` on
  `AppleSpeechTranscriber`, wired into `AnalysisContext.contextualStrings[.general]`. SDK-verified
  against `arm64e-apple-macos.swiftinterface`. +7 tests.
- **H5 `f2b1d1f`** — `StreamingTextInserting` protocol (builder-input). Define-only (`insertChunk(_:)` /
  `finalize()`). No conformer. Additive, zero risk.
- **H3 `9a3c8c4`** — Decompose `DictationController` (builder-app). 415→361 lines. Extracted
  `OverlayController` + `WindowPresenter`. Behavior identical. +`OverlayControllerTests` (8) +
  `WindowPresenterTests` (4).

**Paste test-hygiene fix `30e99f2`:** `PasteboardWriter` now has injectable `writeClipboard` +
`postEvent` seams; tests inject a `PasteSideEffectRecorder`. Confirmed no paste into user's terminal
during `make test`.

**Orchestration lesson (durable):** `Agent(isolation:"worktree")` did NOT isolate named/background
subagents in CC 2.1.x — they wrote the shared checkout. Verify `git worktree list` after spawning.
Standing fix: each agent calls `EnterWorktree` first + never commits.

---

## Done (2026-06-21, loop run #25 — LIVE base verified + full-product acceleration plan)

**Milestone: the v0 base WORKS LIVE.** User ran `make dev-cert` + `make run`, granted permissions,
and **dictated development instructions into Claude Code using speak itself** — recursive feedback loop.
Confirmed live (`c9392bd`): double-tap Fn start/stop, overlay over other apps, partials streaming live,
paste at cursor into terminal with no macOS 26.4 paste-prompt, raw-fallback with Apple Intelligence off.

**Pivoted mission: "finish v0" → "build the full product, fast."**

**`specs/acceleration-plan.md` produced** from 3 parallel scouts (architecture audit, product roadmap,
competitor analysis). Four locked user decisions: base-hardening-first · local-first+pluggable-later ·
**full-window dashboard** · **Monaco** typographic theme.
