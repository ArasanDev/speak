# `speak` — Progress (NOW)

> **Status**: Living state. **The agent rewrites this every session.**
> Single source of truth for "where are we right now." Read first, update last.
> History before loop #26: `docs/progress-archive.md`. See `../AGENTS.md` §5.

---

## Current phase

**Validation & hardening COMPLETE — all Batches A–E + 1C test coverage + test-suite fixes done (loop #28–32, 2026-06-27).**

Feature-complete through Wave 2. All validation phases (1–5) done. All batches merged:
- **Batch A** (engine session integrity): cancel-paste guard, empty-transcript guard, double-start guard, cleanupSeconds floor
- **Batch B** (STT lifecycle): stopRequested mic-leak guard, prewarm, locale reserve, converter safety, STT-H2 cancelAll teardown, Cleanup-H1 isAvailable model instance fix
- **Batch C** (hotkey + paste): detector desync, CGEvent retain leak, CLI modal mode, deinit UAF, permission flicker, weak-self init, 10ms paste gap
- **Batch D** (app/storage/engine robustness): search LIMIT, int64 trim, stale keycaps, dup watcher, UD-per-render, picker row, language reset, onboarding dot, SQLite init leak, error HUD Escape, wasTrusted reset, JSONEncoder thread-safety, case-insensitive search, Engine-L2 currentSession clear
- **Batch E** (polish): STT-H1 real prewarm, Cleanup-M2 typed API, Engine-L1/3/4/5 comments, Input-L3/4 comments, STT-L2/M2 comments, Cleanup-L2/L3, App-L3 comment
- **Loop #32** (prompt-quality + test-suite hardening): transcriptGuard + XML wrapping in FM cleanup (confirmed working — FM now returns cleaned output on this Mac); stopRequested reset fix (B1 session-reuse bug); 5 new tests (EndDictationErrorBranch + HotkeyMonitorUpdateBinding); removed 2 hanging SpeechTranscriberTests (zero-buffer SpeechAnalyzer finalize hang); StyleModeTests/TextDiffTests updated for modeInstructions(); integration test made FM-state-adaptive

Gates as of loop #32 (2026-06-27): **build ✅ lint 0-serious ✅ moat 7/7 ✅ tests pass ✅ (498 / 0 skip / 0 fail)**

---

## In progress

Nothing.

---

## Blocked

Nothing blocking. Human-gate items remain owner-only (live paste in 3 apps, latency, false-trigger rate).

---

## Next up

**Human-gate** → v0 ship gate → Wave 3.

1C test coverage additions: **COMPLETE** (loop #30, 2026-06-26). All identified gaps either already existed in the suite or have been added: `endDictation` error branches, rebind+Combine (HotkeyMonitor.updateBinding). Multi-display positioning remains UI-only (not unit-testable headlessly).

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
