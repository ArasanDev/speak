# `speak` — Progress (NOW)

> **Status**: Living state. **The agent rewrites this every session.**
> Single source of truth for "where are we right now." Read first, update last.
> History before loop #26: `docs/progress-archive.md`. See `../AGENTS.md` §5.

---

## Current phase

> ## 🚩 VALIDATION & HARDENING PHASE (started 2026-06-22) — user-directed
> **Feature-complete through Wave 2. Build is green: `make build/test/lint/verify-moat` all pass.**
> (434 tests, 0 failures, moat 7/7 as of Wave 2 integration.)
>
> User asked: compare against OSS competitors, SDK-ground the skills (written from research/docs,
> not the on-machine macOS 26 SDK), and hunt ALL bugs across ALL flows/coverage, then validate.
> Decisions: **Agent fan-out** (not heavyweight Workflow) + **report-first** (NO code changes until
> user approves the findings report).
>
> **Phase 1 (grounding — read-only):**
> - 1A `val-oss-compare` — OSS competitor comparison matrix
> - 1B `val-skill-sdk` — Skill⇄SDK truth audit
> - Status: started 2026-06-22, **results not captured in progress.md** — unknown if complete.
>
> **Phase 2 (per-seam SDK-grounded bug hunt — swift-code-review) → Phase 3 (adversarial verify)
> → Phase 4 (single prioritized findings report)**: not yet started.
>
> **Active worktree with uncommitted validation fixes** (DO NOT DISCARD):
> `.wt/fix-input2` on branch `fix/input2` — 7 modified files + `InputValidationFixTests.swift` (new).
> Modified: `DictationController.swift`, `CLIPortServer.swift`, `HotkeyDetection.swift`,
> `HotkeyMonitor.swift`, `PasteboardWriter.swift`, `HotkeyMonitorTests.swift`, `PasteTests.swift`.
> These are in-progress validation fixes. Review, gate, and merge or discard before proceeding.
>
> **Wave 3 (deferred until after validation):** code-aware mode, voice editing, history power-tools.
>
> **Human-gate track (owner-only):** live paste in 3 apps, latency numbers [plumbing ready],
> menubar-color visual check, live rebind-fires check, style-effectiveness check, P11 notarized release.
>
> **Harness changes this session (2026-06-26):**
> - `.claude/settings.json` created: permission allowlist for `make/*`, `xcodebuild/*`, `git/*` etc.
>   (no more per-command prompts in the loop) + `PostCompact` hook re-anchors agent to progress.md banner.
> - `.claude/loop-prompt.md` created: tight loop prompt for `/loop` and `/schedule`.
> - `docs/progress-archive.md` created: sessions #1–#25 + old banners archived here.
> - `wave23-cli` worktree removed (was already merged to master; tree was clean).

---

## In progress

- **Validation phase 1A/1B** — state unknown. Re-run or confirm results before moving to Phase 2.
- **`fix-input2` worktree** — uncommitted validation fixes. Needs orchestrator review + gate run + decision to merge or discard.

---

## Blocked

Nothing blocking the build. The 4 gates are green. The validation phase is the critical path before Wave 3.

---

## Next up

**Option A — Continue validation (recommended):**
1. Determine if Phase 1A/1B agents completed. If not, re-run them.
2. Review + merge the `fix-input2` validation fixes (run gates: `make build/test/lint/verify-moat`).
3. Run Phase 2 bug hunt (per-seam swift-code-review fan-out).
4. Phase 3 adversarial verify → Phase 4 single findings report → user approves → fix.

**Option B — Human-gate first:**
Run the live verification pass (`docs/human-verification.md`) — the 3 TCC grants + Apple Intelligence +
one spoken dictation + paste-into-TextEdit/Slack/Terminal + latency measurement.

**Wave 3 scope (after validation):**
- Code-aware mode (voice editing)
- History power-tools
- P11 notarized release (scaffolded, needs Developer ID cert)

---

## Open questions

| # | Question | Status |
|---|---|---|
| V1 | Did Phase 1A (`val-oss-compare`) and 1B (`val-skill-sdk`) agents complete? | Unknown — check progress notes or re-run |
| V2 | What are the `fix-input2` changes exactly? Should they merge? | Review `.wt/fix-input2` diff before merging |
| 3 | Does write+`Cmd+V` avoid the paste prompt incl. macOS 26.4 Terminal provenance check? | `[unverified]` — test in Terminal (human) |
| 4 | Developer ID signing cert for notarization? | Unverified — needed for P11 |
| V3 | Does `DictationTranscriber` (new SpeechAnalyzer module) support `contextualStrings` custom vocabulary? H4 seam may be silently broken. | Verify via `apple-docs` MCP before V01-1 (WhisperKit) work begins |

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
