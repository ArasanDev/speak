# `speak` — Benchmark & Definition of Done (vs the category frontier)

> **Status**: The testable target. `speak` is "done" not when the roadmap is
> checked, but when this benchmark passes: every **MATCH** row meets its
> criterion *measured against the frontier*, every **BEAT** row holds, every
> **SKIP** row is consciously documented.
>
> **This file is the autonomous loop's objective function.** Each `/loop` cycle
> evaluates progress against the v0 MATCH gate (§4).
>
> **Depends on**: `product.md`, `specs/verification-ledger.md` (all competitive
> facts here are verified there). **Date**: 2026-06-20.
>
> **Reading the buckets**: **MATCH** = must equal the frontier to be credible ·
> **BEAT** = `speak` wins by design · **SKIP** = cloud/off-strategy, deliberately
> not built (with a future home noted).

---

## 0. The positioning this benchmark encodes (read first)

The frontier is **Wispr Flow** — and per verification (2026-06-20) it is *not*
coasting; it is in aggressive feature expansion (Android, Auto Cleanup,
Transforms, Scratchpad, Command Mode, 100+ languages). So `speak` does **not**
win by out-shipping Wispr on breadth.

`speak` wins on a **structural** moat Wispr cannot copy without abandoning its
cloud + subscription business: **100% local, offline, free, open-source (MIT),
no account.** Wispr is architecturally cloud (audio → OpenAI STT + Llama
cleanup, account mandatory). That is the durable wedge.

So the bar is: **match Wispr on the core dictation *experience*, beat it on
privacy/cost/openness/latency, and consciously skip its cloud-dependent
breadth** — delivering breadth later, locally, on `speak`'s own terms.

---

## 1. Category snapshot (verified — see ledger §3)

| App | Price | Open source | Local | Platforms | Note (verdict per ledger §3) |
|---|---|---|---|---|---|
| **Wispr Flow** (frontier) | $15/mo · $12/mo annual ($144/yr) · free 2k-words/wk tier | No | **No (cloud-only)** | Mac/Win/iOS/Android | The bar. Account mandatory. `[verified]` |
| Superwhisper | $8.49/mo · $249 lifetime | No | Local + cloud/BYOK | Mac/iOS | price `[corrected]` ($8.49, not $9.99) |
| Willow | $12–15/mo | No | Hybrid | Mac/iOS | subscription `[corrected]` |
| MacWhisper | indie (one-time) | No | **Local** | Mac | Local Whisper app (J. Bruin) `[verified]` |
| VoiceInk | $25–49 (free from source) | **GPLv3** | Local | Mac | not free `[corrected]` |
| FluidVoice | free | **GPLv3** | Local | Mac | pluggable engines (role model) `[verified]` |
| Aiko | free | **OSS** | **Local** | Mac/iOS | Whisper, on-device `[verified]` |
| TypeWhisper | free | **OSS** | **Local** | Mac | no telemetry `[verified]` |
| **speak** | **free, unlimited** | **MIT** | **100% local** | Mac (AS) | local + free + open + no-account (the subject) |

`speak`'s unoccupied position: the **only** one that is *simultaneously* MIT-open,
unlimited-free, fully-local, and no-account — with the frontier's UX ambition.

---

## 2. Parity matrix (full vision, phased)

Captures the **north-star** product, then sequences each capability. Every
numeric target carries a derivation (§7) — no hardcoded magic numbers.

| Capability | Frontier (Wispr) | `speak` north-star target | Bucket | Phase | Binary acceptance criterion |
|---|---|---|---|---|---|
| Transcription accuracy | ~97% EN `[verified]` | Within frontier tolerance on the test corpus | MATCH | v0 | WER on §6 corpus ≤ Wispr WER + tolerance `T_wer` (§7) |
| End-to-end latency | ~700ms p99 → 1–2s (cloud) `[verified]` | Beat cloud round-trip locally | **BEAT** | v0 | Median stop→paste (no LLM) < `L_e2e` (§7), measured ≤ Wispr's measured |
| First-partial latency | streaming `[unverified]` | Live volatile results in overlay | MATCH | v0 | First volatile result → overlay < `L_partial` (§7) |
| Languages | 100+, auto-detect, code-switch `[verified]` | Match over time via SpeechAnalyzer locales + WhisperKit | SKIP→MATCH | v0 en-US → v0.1+ | v0: en-US/en-GB; v0.1: SpeechAnalyzer installed locales; v1: WhisperKit 99-lang |
| Activation / hotkey | Fn hold + Fn+Space toggle `[verified]` | Customizable; default double-tap-Fn start / single-tap stop | MATCH | v0 | Hotkey fires globally; rebindable; false-trigger rate < `F_rate` (§7) |
| Streaming overlay | post-segment `[unverified]` | Live word-by-word volatile transcript | **BEAT** | v0 | Overlay shows partials updating < `L_partial` lag |
| Paste / insertion | OS-level inject `[verified]` | Write-never-read + Cmd+V; AX fallback v1 | MATCH | v0 | Paste works in ≥ `N/M` apps (§7), no read-prompt; **test Terminal** |
| **AI neat-writing (cleanup)** | Auto Edits / Auto Cleanup / Transforms (cloud) `[verified]` | On-device cleanup: filler removal, punctuation, capitalization, formatting | **MATCH** | **v0** | Stop→paste yields *cleaned* text via on-device `Foundation Models`; settings toggle; raw-transcript fallback if engine unavailable. Doing it **on-device + free** is the BEAT. |
| Richer cleanup (tone/style/per-app) | configurable levels, Transforms `[verified]` | Tone/style modes, per-app formatting | MATCH | v1 | Multiple cleanup styles selectable; per-app rules |
| Pluggable cleanup models | n/a (cloud only) | Ollama (Qwen/Gemma/Phi), MLX as alternatives | **BEAT** | v0.1 | User can swap cleanup engine in settings |
| Voice commands / editing | Command Mode (Pro, cloud) `[verified]` | Local command mode | SKIP | v1+ | Deferred; local-LLM-driven when cleanup matures |
| Custom dictionary / snippets | yes, syncs `[verified]` | Local dictionary + snippets (no sync) | MATCH (local) | v0.1 | Snippet expansion + custom terms persist locally |
| Dictation history | **none found** `[unverified]` | Local, searchable, exportable history | **BEAT** | v0 | Every session stored locally; substring search; clear/export |
| Cross-device sync | dictionary/snippet/scratchpad `[verified]` | Not in v0 (no account = moat) | SKIP | v2 opt-in | iCloud/local-network opt-in later; never mandatory |
| Privacy / data | cloud upload, account, zero-retention claim `[verified]` | Nothing leaves device; no account | **BEAT** | v0 | No network egress of audio/text; no account; offline works |
| Price | $15/mo (+capped free) `[verified]` | Free, unlimited, forever | **BEAT** | v0 | $0, no word cap, no tier |
| Open source | closed `[verified]` | MIT, public repo | **BEAT** | v0 | Repo public under MIT |
| Platforms | Mac/Win/iOS/Android `[verified]` | Mac-first; portability seam preserved | SKIP | v1+ | v0 Mac AS only; `SpeakCore` seam kept for later extraction |
| Offline | requires internet `[verified]` | Fully functional offline | **BEAT** | v0 | All core flows work with networking disabled |

---

## 3. BEAT — the structural moat (the win condition)

Each is something Wispr **cannot** match without abandoning its model:

1. **100% local + offline** — Wispr requires internet + cloud upload. `[verified]`
2. **Free & unlimited** — Wispr's free tier is capped at 2k words/wk. `[verified]`
3. **Open source (MIT)** — Wispr is closed. `[verified]`
4. **No account** — Wispr mandates one. `[verified]`
5. **Local persistent history** — Wispr has none. `[unverified]` (no persistent
   searchable history found, only temp "retry" — ledger §2; a gap `speak` can own)
6. **Lower latency** — local beats the ~700ms–2s cloud round-trip. `[verified]`
7. **Privacy** — no audio/text egress; vs Wispr → OpenAI subprocessor. `[verified]`

> **Scope of this list**: items 1–7 are the **structural** moat — what Wispr
> cannot copy without abandoning its cloud + subscription model. The §2 matrix
> also marks **streaming overlay** (v0) and **pluggable cleanup models** (v0.1)
> as BEAT (won by design, but *not* structural). The **full BEAT set = these 7 +
> those 2 = the 8 BEAT rows in §2.**

These must *hold* for v0 to ship — they are the reason `speak` exists.

---

## 4. v0 MATCH gate (the loop's ship condition)

v0 is "as good as Wispr on the core experience" when ALL hold (measured, §6):

- [ ] **Accuracy**: en-US WER ≤ Wispr WER + `T_wer` on the §6 corpus.
- [ ] **Neat writing**: stop→paste output is *cleaned* (filler removed,
      punctuated, capitalized, formatted) via on-device `Foundation Models`;
      toggle works; raw-transcript fallback when the engine is unavailable.
- [ ] **Latency**: median stop→paste (incl. cleanup) < `L_e2e`, and ≤ Wispr's measured.
- [ ] **Live feedback**: first volatile result → overlay < `L_partial`.
- [ ] **Paste**: works in ≥ `N/M` apps (§7), zero read-prompts, Terminal tested.
- [ ] **Hotkey**: global, rebindable, false-trigger rate < `F_rate`.
- [ ] **History**: local search/clear/export works (the BEAT row that is also v0).
- [ ] All **v0 BEAT rows** hold (§2 matrix / §3 moat): offline, free (unlimited),
      MIT-open, no account, no egress, local history, lower latency, **plus the
      live streaming overlay** (the v0 BEAT rows; pluggable cleanup models is v0.1).

Plus the mechanical gates already in `quality.md` §9 (build/sign/notarize, no
`print`, no force-unwrap, etc.). **This MATCH gate + `quality.md` §9 = the loop's
exit condition.** Reconcile the app-count `N/M` and any latency number with
`quality.md` §3 and `architecture.md` §12 — single source of truth is §7 below.

---

## 5. SKIP (by design) — and where each goes later

| Frontier feature | Why skip in v0 | Future home |
|---|---|---|
| Cloud sync (dictionary/snippets/scratchpad) | needs account+cloud (kills the moat) | v2 iCloud/local-network **opt-in** |
| Cloud AI Transforms / Command Mode | server LLM | local LLM equivalent v0.1→v1 |
| 100+ languages day 1 | scope; depends on locale models | v0.1 (SpeechAnalyzer) → v1 (WhisperKit) |
| Win/Android/iOS | Mac-first focus | v1+ via `SpeakCore` seam |
| Team / enterprise admin | account-based; off-strategy | not planned (anti-moat) |

---

## 6. Quality benchmark protocol (how MATCH rows are *measured*, not asserted)

- **Corpus**: a fixed set of ~20 dictation clips (quiet + noisy + accented EN),
  same audio fed to `speak` (SpeechAnalyzer) and to Wispr Flow; compute WER vs a
  human reference transcript. Store the corpus + references in the repo.
- **Latency**: instrument `CaptureSession` timestamps (hotkey→listening,
  stop→paste); 30 trials, report median + p95; compare to Wispr measured on the
  same clips/machine.
- **Paste compatibility**: run the `quality.md` §3 matrix; `N/M` is the *measured*
  pass count, not a guess.
- **Decision rule** (from `quality.md` §8 risk #1): if SpeechAnalyzer WER >
  Wispr + `T_wer`, ship WhisperKit as the v0.1 default.

---

## 7. Derivation ledger (anti-hardcoding — every number traces here)

No magic numbers elsewhere; matrix/gate values reference these symbols.

| Symbol | Value (v0) | Derivation | Type |
|---|---|---|---|
| `T_wer` | +3 pts | tolerance over Wispr's ~97% EN; tune after first §6 run | `[decision]` (revisit P13) |
| `L_e2e` | < 2.0 s median (incl. on-device cleanup) | beats Wispr's cloud cleanup path (~1–2s) while staying local; raw-only path (cleanup off) target < 1.0s; consistent w/ `architecture.md` §12 | `[decision]` from frontier latency `[verified]` |
| `L_partial` | < 200 ms | matches `architecture.md` §12 first-partial p95; SpeechAnalyzer volatile results are near-instant `[verified]` | platform-derived |
| `N/M` | ≥ 13/16 | = `quality.md` §3 compatibility matrix size + ship gate; **measured, not assumed** | `[decision]`, single source = `quality.md` §3 |
| `F_rate` | < 1 / 30 min | = `roadmap.md` P5 done-when (typing test in Notes) | `[decision]`, single source = `roadmap.md` P5 |
| double-tap window | 400 ms | human double-tap timing; **flagged to tune in P13 dogfood, not load-bearing** | `[decision]`, tune empirically |
| history size | 10,000 entries | no frontier anchor (Wispr has none); derivation: avg entry ≈ 400 B (UUID 36 B + timestamps 30 B + text ~300 B + engineId 30 B + overhead) → 10 k entries ≈ 4 MB on disk, negligible on modern hardware; value is an init param (P10 Settings exposes it) `[decision]` — set in P9, source = `HistoryStore.defaultHistoryMaxEntries` | `[decision]` |

> **Rule for the build loop**: if you introduce a numeric constant not derivable
> from a measured value, a platform constraint, or a `[decision]` row here, that
> is a defect — add its derivation here or remove it.

---

## 8. What to fold into `docs/` (human action — see ledger §4)

This benchmark assumes the `product.md` corrections in `specs/verification-ledger.md`
§4 (the "why now" rewrite to a *structural* window; the differentiation-matrix
fixes for Wispr's free tier / Fn use / multi-platform). Apply those to
`product.md` (human-only) so the docs and this benchmark agree.
