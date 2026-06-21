# `speak` — Acceleration Plan (the full-product execution contract)

> **Created**: 2026-06-21, after the v0 base was confirmed working **live** (LIVE RUN
> #1 — the user dictated their own instructions *through speak*). Synthesized by the
> orchestrator from three parallel scouts: `scout-architecture` (seam audit),
> `scout-product` (full roadmap), `scout-competitors` (Wispr + rivals).
>
> **User steers (locked):** (1) **Base-hardening first** — get the seams right with
> the whole roadmap designed in, *then* fan out features. (2) **Local-first,
> pluggable later** — Apple frameworks stay the default + only dependency; alt
> engines (WhisperKit/Ollama/cloud) are *optional plugins the architecture is ready
> for*, never built or depended on as default.
>
> **Operating mode:** hackathon velocity — orchestrator + specialist fleet, parallel
> where independent, serial where dependent, worktree isolation for parallel
> file-mutation, headless `make` + live Xcode-MCP verification, orchestrator owns all
> commits. Hard rules in `CLAUDE.md`/`AGENTS.md` bind every task — never traded.

---

## 0. The headline finding — the base is SOLID

`scout-architecture` confirmed the v0 architecture is already clean and extensible:
the four protocol seams (`Transcribing`, `LLMCleaning`, `TextInserting`,
`HistoryStoring`) are properly injected, and `EngineFactories.swift` **already
declares enum cases for WhisperKit / whisper.cpp / Ollama** as compile-time stubs.
So "pluggable engines, Apple-default" — the exact steer — *is already the
architecture*. **Phase 1 is therefore surgical seam-hardening, NOT a rewrite.**

**Leave-alone list (well-built — do NOT churn):** `CaptureSession` state machine ·
`HotkeyMonitor` CFRunLoop threading · `PasteboardWriter` event plan · `HistoryStore`
SQLite actor · `FoundationModelsCleaner` per-call session · the protocol shapes
themselves. We harden the seams *around* these, not the cores.

---

## PHASE 1 — Base Hardening (sequenced, surgical) — DO THIS FIRST

Each task = one seam + its test + the gate (`make build/test/lint`, moat 7/7). All
are NON-behavior-changing or additive. Dependency graph noted; independent tasks
fan out in parallel (worktree-isolated), `H3` waits on `H2`.

| # | Task | Seam / change | Owner | Risk | Dep |
|---|------|---------------|-------|------|-----|
| **H1** | **Multi-language seam** | `SpeakEngine.newSession()` reads `settings.language` at call-time (mirror the existing `cleanupEnabled` pattern); drop the hardcoded `en-US` in `SpeakEngine.init`; `DictationController` stops baking locale at init. Unlocks live language switching with zero further change. | builder-engine | low | — |
| **H2** | **App-test infra (`TEST_HOST`)** | Make `SpeakTests` host the `Speak` app target so App-shell logic becomes unit-testable (today tests see only `SpeakCore`). Research the exact XcodeGen `TEST_HOST`/`BUNDLE_LOADER` incantation vs. current docs before editing `project.yml`. Guard `AppDelegate…startMonitoring()` under `XCTestConfigurationFilePath`. First customer: a construct-and-assert **regression guard** for `TranscriptOverlayPanel`'s focus-steal flags (guard only — NOT behaviour proof; those rows stay `[C-live]`). | builder-release (project.yml) + builder-app (guard+test) | moderate (project surgery) | — |
| **H3** | **Decompose `DictationController`** (the backlog #6) | Extract `OverlayController` (overlay lifecycle: model/panel/partials + start/transition/stop) and `WindowPresenter` (history + onboarding window presentation). Behaviour identical; now unit-testable via H2. Controller shrinks to engine↔hotkey↔UI-state wiring. | builder-app | moderate (central wiring — mitigated by H2 tests) | **H2** |
| **H4** | **`customVocabulary` seam** | Add optional `vocabulary: [String]` injection to `AppleSpeechTranscriber` (init param, empty default; `SpeechTranscriber` supports it per WWDC25). Thread an empty slot from `SettingsStore`. Seam only — no UI yet. Unlocks the v1 dictionary feature cleanly. | builder-audio-stt | low | — |
| **H5** | **`StreamingTextInserting` protocol** | Define a second protocol variant (`insertChunk(_:) async throws` / `finalize()`) beside `TextInserting`. **Define, do not implement.** Lets word-by-word streaming-paste snap in later without touching the existing seam. | builder-input | none (additive) | — |

**Phase-1 fan-out:** `H1`, `H2`, `H4`, `H5` are independent (different files) → run in
parallel, worktree-isolated. `H3` runs after `H2` merges (it consumes the test
infra). Orchestrator reviews each diff, re-runs gates from clean, owns the commits.

**Phase-1 exit gate:** all five merged · `make build/test/lint` green · moat 7/7 ·
live verification unaffected (re-run LIVE RUN core loop once). The base is then
*designed for the full roadmap* and we accelerate into Phase 2.

---

## PHASE 2 — Full Product Build (feature waves on the hardened base)

Mapped to the `scout-product` roadmap (v1/v2) + the `scout-competitors` winning
patterns. **Built on the Phase-1-hardened seams.** Waves fan out; within a wave,
specialists work in parallel worktrees.

### ⚠️ The ONE strategic fork that shapes all of Phase 2 — needs your call

**Menubar-only (today) vs. full-window Home dashboard (Wispr-style sidebar IA).**
Both `scout-competitors` and `ui-frontend-ideation.md §1.6` flag this as *the* most
consequential unsettled decision. Wispr's evidence: the **Home dashboard is the #1
reason users open the app daily**, and a sidebar (Home · Insights · Dictionary ·
Snippets · Style · Transforms) is the only IA that scales once v1 features land
without modal-stacking. You said "full product, full application UI, everything" —
which points hard at **building the dashboard**. I recommend it; it is the spine
Phase 2's UI hangs on. *Confirm and Phase 2 Wave A is the dashboard.*

### Design system (locked by the user, 2026-06-21)
**Typographic theme: `Monaco`** — the macOS-native monospace, chosen for its calm,
even, easy-on-the-eyes rhythm. Native + zero-dependency (fits the Apple-only wedge).
Applies across the UI: history/dashboard rows, timestamps, HUD transcript text,
keycaps. SwiftUI: `.font(.custom("Monaco", size:))` (or a `Font` extension token —
e.g. `Font.speakMono`). Pair with the system UI font for chrome/labels; Monaco for
*content + data* (the "log-file" feel the competitor research calls for). One source
of truth — define the token once, never hardcode the family string per view.

### Wave A — UI spine (the dashboard, if confirmed)
Full-window app with sidebar IA + day-grouped history dashboard (TODAY/YESTERDAY,
SF-Mono timestamps, full-text no-truncation, preserved empty rows). User-facing
naming (Style/Dictionary/Snippets/Transforms). `KeyCapView` (orange keycap) for
hotkeys. Beats Wispr's top-center attention-steal; we keep the bottom-center HUD.

### Wave B — Cleanup richness (the neat-writing moat, deepened)
Style modes (Default/Professional/Casual/Code/Email, per-mode prompt) · cleanup-level
picker (Basic/Balanced/Thorough — friendly abstraction over `LLMCleaning` prompts) ·
snippets (run *before* LLM cleanup) · dictionary/custom-vocabulary (consumes H4 seam).
All on-device Foundation Models; pluggable.

### Wave C — Engine plugins (seams ready → optional conformers)
WhisperKit (optional STT, 99 langs) + Ollama (optional cleanup) as **user-selectable
plugins** with guided setup — wired into the *already-declared* factory cases. Apple
stays default. This is where "pluggable later" becomes real, on your steer's timeline.

### Wave D — Flagship UX + polish
**Edit-before-paste with tap-to-pause countdown** (Wispr's killer feature — auto-paste
at ~1.2s, tap-to-pause, ⌘↩ paste / Esc cancel) · menubar Mode + Language submenus ·
live duration counter + confidence-colored partials in HUD · "Done — on clipboard"
Copy fallback for secure fields · Insights (words/WPM/streak, charts).

*(v2 — code-aware mode, voice editing/commands, opt-in local continuity — planned
after v1 waves land. v3+ deliberately undefined.)*

---

## Known intelligence gaps (flagged, not blocking)

- **Aqua Voice, Handy, Hex** — zero coverage in the repo. Worth a research pass before
  finalizing Phase-2 UI positioning (could inform the dashboard fork).
- **Wispr §11 deep-dive is recall-based** (`ui-frontend-ideation.md §11`, self-tagged
  `[recall]`). 3–4 real screenshots (HUD active, edit-before-paste, Snippets, Style)
  would upgrade ~80% to `[verified]`. The user has a (gitignored, personal) Wispr
  account — screenshots are theirs to optionally supply; we never commit them.

---

## Execution discipline (every wave)

Clean tree before spawning · one brief + one reference per agent · parallel
worktrees for file-mutation · live Xcode-MCP for visual verification (main tree, sole
writer) per `agent-tooling.md §3.1` · orchestrator reviews diffs + owns commits ·
two-commit minimum (code + orchestration) · update `progress.md` (read first, rewrite
last) each loop · hard rules never traded. **Done = verified, not assumed.**
