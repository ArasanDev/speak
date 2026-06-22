# Acceleration Roadmap — `speak` (post-live-loop, v0-finish → v1 → v2)

**Status:** ACTIVE execution contract. Author: orchestrator (Opus), 2026-06-22.
**Supersedes:** `specs/next-iteration-plan.md` (its W1–W4 are merged or folded below).
**Grounding:** `roadmap.md` (the dependency ladder), completed tasks #9–#21, and the
**decisive new fact** below. Every wave names owning team agents + model tier.

---

## 0. The decisive fact that reframes everything

The core loop **works live**. The owner has dictated successfully this session
(double-tap Right-Command → capture → stop → paste), which empirically clears the
P5/P6/P7 live-behavior items `roadmap.md` had marked `[deferred — needs human
verification]`. v0 is **functionally complete**; what remains is (a) live-bug
cleanup, (b) the human-only ship-gate measurements no agent can do, and (c)
climbing the v1→v2 feature ladder. We accelerate (b-track human, c-track agents)
in parallel.

Permission model is now **Mic + Accessibility only** (Input Monitoring removed —
it was vestigial; the `.defaultTap` tap is AX-gated). This matches VoiceInk/Wispr.

---

## 1. WAVE 0 — Live-bug cleanup *(IN FLIGHT)*

| # | Task | Owner | Tier | State |
|---|------|-------|------|-------|
| 0.1 | HUD "Cleaning up…" hangs / never closes after stop → bounded cleanup timeout + raw fallback + guaranteed terminal hidden state | builder-app | Sonnet | building |
| 0.2 | Remove redundant Input Monitoring (onboarding step, PermissionKind, IOHID*, SpeakError case, false UI copy) → Mic+AX only | builder-input | Sonnet | building |

Exit: both merged, full gate suite green, worktrees removed.

---

## 2. WAVE 1 — Finish v0 polish *(agent-doable; fan out after Wave 0)*

The remaining non-human v0 items from `roadmap.md` P8/P10 + the top Settings gap.

| # | Task | Owner | Tier | State |
|---|------|-------|------|-------|
| 1.1 | **Hotkey recorder sheet** — record-a-combo UI in Settings▸Shortcuts; write to `BindingStore`; show current binding via `displayString`. Toggle / Push-to-Talk modes. | builder-input + builder-app | Sonnet | ✅ MERGED (Hybrid deferred → needs HotkeyMonitor timing disambiguation; see Wave 3) |
| 1.2 | **Language picker populated** — surface actual `SpeechTranscriber.supportedLocales` in Settings▸Transcription, persisted in `SettingsStore`, flows live to next session. | builder-audio-stt + builder-app | Sonnet | ✅ MERGED |
| 1.3 | **Menubar state colors** — per-state color/symbol + VoiceOver labels + 600ms done-flash, palette rendering. | builder-app | Sonnet | ✅ MERGED (color render `[unverified — human visual check]`) |
| 1.4 | **Cleanup intensity + diff polish** (W4.1 follow-through) — ensure the 4-level None/Light/Medium/High + raw-vs-cleaned diff are wired end-to-end and surfaced in Settings▸AI Cleanup. | builder-cleanup + builder-app | Sonnet | next |

Parallelizable; isolate file seams (1.1/1.4 both touch Settings → sequence or split panes carefully). Orchestrator owns merges.

---

## 3. WAVE 2 — v1 "attractive & friendly" *(the feature ladder)*

| # | Task | Owner | Tier |
|---|------|-------|------|
| 2.1 | **Pluggable cleanup-model UI** — Ollama (Qwen2.5-3B / Gemma3-4B / Phi-4-mini) + MLX surfaced as user-selectable cleaners behind the existing `LLMCleaning` seam, with a guided setup flow. Foundation Models stays default; alternatives are opt-in, still 100% local. | builder-cleanup + builder-app | Sonnet |
| 2.2 | **Richer cleanup** — tone/style modes (professional/casual/…), per-app formatting rules, snippets + custom dictionary applied at cleanup time (panes already exist from #11–#13 — wire them into the pipeline). | builder-cleanup | Sonnet |
| 2.3 | **CLI shim** — `speak --start` / `--stop` / `--status` driving the running app (local IPC). | builder-infra/release + builder-engine | Sonnet |
| 2.4 | **Latency / metrics view** — surface measured stop→paste (raw + cleanup) per `benchmark.md §7`, feeding the P13/P14 numbers. | builder-app | Sonnet |
| 2.5 | **Onboarding + overlay polish** — first-run UX, "Try it now" hotkey test (pill turns green on trigger), latency tuning. | builder-app | Sonnet |

---

## 4. WAVE 3 — v1→v2 seeds *(scope confirmed when Wave 2 stabilizes)*

- **Code-aware mode** — detect editor/file-type context, format transcript accordingly (identifiers, symbols).
- **Voice editing/commands** — "make this shorter", "fix that sentence" — local-LLM driven (Command Mode seam from #15 is the base).
- **History power-tools** — full-text search, retry/reprocess through current settings, re-paste original-vs-cleaned, transcripts-as-JSON export.
- **Local cross-device continuity** — opt-in, never account-gated.

---

## 5. HUMAN-GATE TRACK *(parallel; owner-only — no agent can do these)*

These are the true v0 ship-gate blockers; agents cannot perform them.

- [ ] Live paste verified in **3 app categories** (TextEdit, Slack, Terminal/iTerm) — incl. the macOS 26.4 Terminal paste-provenance check (project's #1 `[unverified]`).
- [ ] **Latency measured**: median stop→paste raw < 1.0s; with cleanup < 2.0s (`benchmark.md §7`).
- [ ] **False-trigger rate** < 1 / 30 min in normal typing (Notes dogfood).
- [ ] **P11 release**: Developer ID sign + notarize + `.dmg` + Homebrew cask; Gatekeeper "verified".
- [ ] **Demo GIF** of the headline flow.

After these + `benchmark.md §3/§4` + `quality.md §9` → tag `v0.0.1`.

---

## 6. Execution model

- Fan out independent seams with `isolation: worktree`; one agent per task; orchestrator
  reviews each diff, owns merge + commit, removes worktrees immediately after merge.
- Every task ends green on `make build` + `make test` + `make lint` + `make verify-moat`.
- Hard rules unchanged: 100% local, Apple-frameworks-only (v0), no pasteboard *read*,
  `os.Logger` only, no force-unwrap, no magic numbers, tag every claim.
- Per-stage model tiering is explicit (Haiku mechanical / Sonnet implementation+judgment /
  Opus reserved for contract/security decisions).
