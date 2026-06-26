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
> **fix-input2 MERGED `d05e740` (2026-06-26):** 7 hardening fixes gated (build ✅ lint 0-serious ✅ moat 7/7 ✅ modified-seam tests ✅):
> - C1 `notifySessionEnded()`: reset double-tap detector after out-of-band stop (Escape/CLI/error) — third-tap-to-start bug fixed
> - C2 auto-cancel stuck recording when tap dies mid-session
> - C4 CGEvent tap callback: `passRetained` → `passUnretained` (leaked 1 CGEvent per flagsChanged)
> - C5 `shutdown()` method: properly invalidates timers + stops run loop (prevents HotkeyMonitor memory leak)
> - C6 `CLIPortServer`: `.defaultMode` → `.commonModes` (CLI `--stop/--status` now works during modals/sheets)
> - C7 spurious `permissionsNeeded` flicker on re-arm: only set when AX actually missing
> - NEW-4/5/6/7: `eventTap`/`runLoopSource`/`wakeRearmTimer` lock-guarded; Option key binding fixed; settings dedupe
>
> **Wave 3 (deferred until after validation):** code-aware mode, voice editing, history power-tools.
>
> **Human-gate track (owner-only):** live paste in 3 apps, latency numbers [plumbing ready],
> menubar-color visual check, live rebind-fires check, style-effectiveness check, P11 notarized release.
>
> **Harness changes (2026-06-26):**
> - `.claude/settings.json` created: permission allowlist + `PostCompact` hook re-anchors to progress.md banner.
> - `.claude/loop-prompt.md` created: tight loop prompt for `/loop` and `/schedule`.
> - `docs/progress-archive.md` created: sessions #1–#25 + old banners archived here.
> - `wave23-cli` worktree removed (was already merged to master; tree was clean).

---

## In progress

- **Fresh review agents running** (loop #27, 2026-06-26): 5 parallel seam-review agents confirming post-fix-input2 state. Will be reconciled with existing validation-findings.md.

---

## Blocked

**User approval gate.** The full findings report (`specs/validation-findings.md`) is ready. All Phase 1–3 work is complete. Batches A/B/C-remaining/D/E are documented and prioritized but **code changes require user approval** per the report-first constraint. This is the only gate before implementation.

---

## Next up

**USER DECISION REQUIRED — review `specs/validation-findings.md` Phase 4 and approve batches.**

Recommended implementation order (all file-disjoint → parallel worktrees safe):
1. **Batch A** (builder-engine, `CaptureSession.swift` + `SpeakEngine.swift`) — safety-critical, smallest
2. **Batch B** (builder-audio-stt, `AppleSpeechTranscriber.swift`) + **Batch C-remaining** (builder-input: paste 10ms gap C3, weak-self C8) — parallel with A
3. **Batch D** (builder-app/engine/storage) — 10 medium robustness items
4. **Batch E** (builder-qa) — polish + test coverage additions
5. After all batches: full `make test` baseline + human-gate (live paste, latency, false-trigger rate)

**After validation completes:** Wave 3 (code-aware mode, history power-tools, P11 notarized release).

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
