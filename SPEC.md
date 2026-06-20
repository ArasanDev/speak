# `speak` — Product Specification

> A single, human-readable consolidated spec for **`speak`**: a macOS-native,
> local-first, free, open-source AI voice dictation app. For sharing, onboarding,
> and pitching.
>
> **This is the human-facing synthesis.** The agent-facing sources of truth are
> `docs/` (the layered build loop) and `specs/verification-ledger.md` (the
> primary-source ledger). Where this spec and `docs/` differ, the ledger wins —
> see the [verification summary](#13-verification-ledger-summary) and the
> [required `docs/` corrections appendix](#15-appendix-required-docs-corrections).
>
> **Tagging**: every competitive or platform fact is tagged `[verified]`
> (primary source in the ledger), `[inferred]` (inference chain stated), or
> `[unverified]` (no primary source — flagged, do not rely on until tested).
> **Date**: 2026-06-20.

---

## 1. Vision — what `speak` is

> *The Mac-native, free, local-first voice dictation app that turns your speech
> into clean, finished text at the cursor — privately, on-device, and open.*

`speak` is an **AI dictation** app. You press a hotkey, talk, and stop. A live
overlay streams your words as you speak; on stop, an on-device AI **writes the
transcript neatly** — filler removed, punctuation and capitalization correct,
formatted to fit where it lands — and pastes the finished text at the cursor, in
any app. The clean transcript is the product.

It is the **same core experience as Wispr Flow** — the category frontier — but it
**never leaves your machine**: no account, no login, no cloud, no telemetry,
fully offline, free, and open source under MIT. Speech→text *and* AI
neat-writing are both core, both on-device, both pluggable local models.

`speak` is deliberately small and opinionated. It does one thing — dictate clean
text at the cursor — and does it privately, locally, and for free.

### What `speak` is NOT

- **Not** an agentic coding tool. (That was the abandoned `deepvoice` idea,
  archived in `research/sample-ideation.md` — do not build it.)
- **Not** a chatbot, voice assistant, or meeting scribe.
- **Not** cloud. No accounts, login, or telemetry. (Cloud STT may exist *only*
  as a later, explicit, user-keyed opt-in — never the default, never required.)
- **Not** account-bound or sync-mandatory. Local is the point.
- **Not** cross-platform in v0. Mac + Apple Silicon only.

---

## 2. The problem & why now — a *structural* window, not a temporal one

The opportunity is **not** "the incumbent is slow." The frontier — **Wispr
Flow** — is in fact advancing aggressively: in 2026 it shipped Android, AI
cleanup levels (Auto Cleanup), Transforms, Command Mode, a Scratchpad, an Admin
Portal, extended sessions, and 100+ languages. `[verified]` `speak` does **not**
win by out-shipping Wispr on breadth.

The window is open for a **deeper, structural reason**:

- **Wispr is architecturally cloud.** Audio is uploaded to its servers (OpenAI
  for STT, a fine-tuned Llama for cleanup); an account is **mandatory**; there is
  **no offline mode**. `[verified]` It **cannot** become local / free / open /
  offline / no-account without abandoning its own subscription + cloud business
  model. The window does not close when Wispr ships features — it stays open
  because Wispr is *structurally* cloud and cannot follow `speak` into the local
  position without dismantling its revenue model.
- **The on-device stack is now good enough to match it.** Apple shipped
  **`SpeechAnalyzer`** (on-device STT, macOS 26) and the **`Foundation Models`**
  framework (on-device LLM for cleanup) — both native, free, Apple-Silicon.
  `[verified]` A category-leading dictation experience can now run *entirely
  locally*.
- **Plenty of small, local, production-grade models** exist beyond Apple's
  (WhisperKit / Parakeet for STT; Qwen / Gemma / Phi via Ollama / MLX for
  cleanup), and they are plug-and-play. `[verified]`

So `speak` occupies the one position the incumbent structurally cannot:
**fully local, free, open, offline, private, no-account.**

---

## 3. Market & competitive landscape

### 3.1 Category snapshot (verified — see ledger §3)

| App | Price | Open source | Local | Platforms | Note |
|---|---|---|---|---|---|
| **Wispr Flow** (frontier) | $15/mo · $12/mo annual · free 2k-words/wk tier `[verified]` | No `[verified]` | **No (cloud-only)** `[verified]` | Mac (Intel+AS) / Win / iOS / Android `[verified]` | The bar. Account mandatory; OpenAI STT + Llama cleanup. |
| Superwhisper | $8.49/mo · $84.99/yr · $249.99 lifetime `[verified]` | No | Local + cloud / BYOK `[verified]` | Mac / iOS | — |
| Willow | $12–15/mo `[verified]` | No | Hybrid | Mac / iOS | AI enhancement |
| MacWhisper | indie `[verified]` | No | Local | Mac | local Whisper app |
| VoiceInk | $25–49 (free from source) `[verified]` | **GPLv3** `[verified]` | Local | Mac | — |
| FluidVoice | free `[verified]` | **GPLv3** `[verified]` | Local | Mac | 5 pluggable engines — architectural role model |
| Aiko | free `[verified]` | **OSS** `[verified]` | **Local** `[verified]` | Mac / iOS | Whisper, on-device |
| TypeWhisper | free `[verified]` | **OSS** `[verified]` | **Local** `[verified]` | Mac | no telemetry |
| **speak** | **free, unlimited** | **MIT** | **100% local** | Mac (Apple Silicon) | local + free + open + no-account + history |

**`speak`'s unoccupied position**: the **only** app that is *simultaneously*
MIT-open, unlimited-free, fully-local, offline, and no-account — with the
frontier's UX ambition (live streaming overlay + on-device AI neat-writing).

### 3.2 The frontier reference (Wispr Flow), verified

- **Pricing** `[verified]`: $15/mo monthly or $12/mo annual ($144/yr); a free
  "Flow Basic" tier (2k words/wk on Mac/Win, 1k on iPhone) including dictionary,
  snippets, 100+ languages, Privacy Mode.
- **Platforms** `[verified]`: macOS 12+ (Intel **and** Apple Silicon), Win 10/11,
  iOS 18.3+, Android (Feb 2026). Linux `[unverified]`.
- **Activation** `[verified]`: push-to-talk (hold **Fn** on Mac) + hands-free
  (**Fn+Space** toggle) + Command Mode (Pro).
- **Languages** `[verified]`: 100+, auto-detect, code-switching, Hinglish.
- **Accuracy / latency** `[verified]` (3rd-party): ~97% EN; ~700ms p99 to 1–2s,
  dominated by the cloud round-trip.
- **AI cleanup / editing** `[verified]`: Auto Edits; Auto Cleanup (4 levels);
  Transforms; Command Mode.
- **Account / processing** `[verified]`: account **mandatory**, 100% cloud
  (OpenAI STT + fine-tuned Llama cleanup), no offline mode, zero-retention
  *claimed*.
- **Dictation history** `[unverified]`: no persistent, searchable history found
  (only a temporary "retry") → a gap `speak` can own.

> **Why this matters for positioning** (corrected against the ledger): Wispr
> **has** a free tier, **uses** Fn for activation, and is multi-platform /
> Intel+AS / 100+ languages. So `speak`'s true differentiators are **not**
> "free" or "the Fn hotkey." They narrow to the structural bundle:
> **local-only + open-source (MIT) + offline + no-account + local persistent
> history + lower local latency.**

### 3.3 The parity map (embedded — the testable definition of done)

`speak`'s definition of "as good as Wispr Flow" is the parity map from
`docs/benchmark.md`. Every category capability sorts into one of three buckets,
each with a **delivery phase** (so the *full north-star vision* is captured and
sequenced, never shrunk to v0):

- **MATCH** — the core dictation *experience* `speak` must equal to be credible.
- **BEAT** — where `speak` wins *by design* (the structural moat).
- **SKIP (by design)** — cloud-dependent / off-strategy features, consciously not
  built in v0, each with a future home.

**Embedded counts**: **7 MATCH** rows · **8 BEAT** rows · **4 SKIP/SKIP→MATCH**
rows (**19 capability rows total**; the Languages row is **SKIP→MATCH**, phased
into the experience over time — it is not a MATCH row).

#### The parity matrix (north-star, phased)

| Capability | Frontier (Wispr) | `speak` north-star target | Bucket | Phase | Binary acceptance criterion |
|---|---|---|---|---|---|
| Transcription accuracy | ~97% EN `[verified]` | Within frontier tolerance on the test corpus | MATCH | v0 | WER on the §3.4 corpus ≤ Wispr WER + `T_wer` |
| End-to-end latency | ~700ms p99 → 1–2s (cloud) `[verified]` | Beat cloud round-trip locally | **BEAT** | v0 | Median stop→paste (no LLM) < `L_e2e`, ≤ Wispr measured |
| First-partial latency | streaming `[unverified]` | Live volatile results in overlay | MATCH | v0 | First volatile result → overlay < `L_partial` |
| Languages | 100+, auto-detect `[verified]` | Match over time via SpeechAnalyzer locales + WhisperKit | SKIP→MATCH | v0 en-US → v0.1+ | v0: en-US/en-GB; v0.1: installed locales; v1: WhisperKit 99-lang |
| Activation / hotkey | Fn hold + Fn+Space toggle `[verified]` | Customizable; default double-tap-Fn start / single-tap stop | MATCH | v0 | Hotkey fires globally; rebindable; false-trigger rate < `F_rate` |
| Streaming overlay | post-segment `[unverified]` | Live word-by-word volatile transcript | **BEAT** | v0 | Overlay shows partials updating < `L_partial` lag |
| Paste / insertion | OS-level inject `[verified]` | Write-never-read + Cmd+V; AX fallback v1 | MATCH | v0 | Paste works in ≥ `N/M` apps, no read-prompt; **Terminal tested** |
| **AI neat-writing (cleanup)** | Auto Edits / Auto Cleanup / Transforms (cloud) `[verified]` | On-device cleanup: filler removal, punctuation, capitalization, formatting | **MATCH** | **v0** | Stop→paste yields *cleaned* text via on-device `Foundation Models`; toggle works; raw fallback if engine unavailable |
| Richer cleanup (tone/style/per-app) | configurable levels, Transforms `[verified]` | Tone/style modes, per-app formatting | MATCH | v1 | Multiple cleanup styles selectable; per-app rules |
| Pluggable cleanup models | n/a (cloud only) | Ollama (Qwen/Gemma/Phi), MLX as alternatives | **BEAT** | v0.1 | User can swap cleanup engine in settings |
| Voice commands / editing | Command Mode (Pro, cloud) `[verified]` | Local command mode | SKIP | v1+ | Deferred; local-LLM-driven when cleanup matures |
| Custom dictionary / snippets | yes, syncs `[verified]` | Local dictionary + snippets (no sync) | MATCH (local) | v0.1 | Snippet expansion + custom terms persist locally |
| Dictation history | **none found** `[unverified]` | Local, searchable, exportable history | **BEAT** | v0 | Every session stored locally; substring search; clear/export |
| Cross-device sync | dictionary/snippet/scratchpad `[verified]` | Not in v0 (no account = moat) | SKIP | v2 opt-in | iCloud / local-network opt-in later; never mandatory |
| Privacy / data | cloud upload, account, zero-retention claim `[verified]` | Nothing leaves device; no account | **BEAT** | v0 | No network egress of audio/text; no account; offline works |
| Price | $15/mo (+capped free) `[verified]` | Free, unlimited, forever | **BEAT** | v0 | $0, no word cap, no tier |
| Open source | closed `[verified]` | MIT, public repo | **BEAT** | v0 | Repo public under MIT |
| Platforms | Mac/Win/iOS/Android `[verified]` | Mac-first; portability seam preserved | SKIP | v1+ | v0 Mac AS only; `SpeakCore` seam kept |
| Offline | requires internet `[verified]` | Fully functional offline | **BEAT** | v0 | All core flows work with networking disabled |

#### The BEAT moat — the win condition

Each is something Wispr **cannot** match without abandoning its model:

1. **100% local + offline** — Wispr requires internet + cloud upload. `[verified]`
2. **Free & unlimited** — Wispr's free tier is capped at 2k words/wk. `[verified]`
3. **Open source (MIT)** — Wispr is closed. `[verified]`
4. **No account** — Wispr mandates one. `[verified]`
5. **Local persistent history** — Wispr has none. `[unverified]` (the gap `speak`
   owns; `speak`'s *own* history is a built guarantee).
6. **Lower latency** — local beats the ~700ms–2s cloud round-trip. `[verified]`
7. **Privacy** — no audio/text egress; vs Wispr → OpenAI subprocessor.
   `[verified]`

These must *hold* for v0 to ship — they are the reason `speak` exists.

#### SKIP (by design) — and where each goes later

| Frontier feature | Why skip in v0 | Future home |
|---|---|---|
| Cloud sync (dictionary/snippets/scratchpad) | needs account + cloud (kills the moat) | **v2 iCloud / local-network opt-in** |
| Cloud AI Transforms / Command Mode | server LLM | local LLM equivalent v0.1→v1 |
| 100+ languages day 1 | scope; depends on locale models | v0.1 (SpeechAnalyzer) → v1 (WhisperKit) |
| Win / Android / iOS | Mac-first focus | v1+ via `SpeakCore` seam |
| Team / enterprise admin | account-based; off-strategy | not planned (anti-moat) |

> **Strategic guardrail**: "done = Wispr Flow" must **never** push a SKIP-bucket
> cloud feature into v0 — that would trade away the local/free/open moat. Cloud
> sync, server-side commands, and cross-device accounts stay SKIP with a v1+/v2
> **opt-in** note, never MATCH.

### 3.4 How MATCH rows are *measured* (not asserted)

- **Corpus**: a fixed ~20-clip set (quiet + noisy + accented EN), same audio fed
  to `speak` (SpeechAnalyzer) and to Wispr; WER computed against a human
  reference. Corpus + references stored in the repo.
- **Latency**: instrument `CaptureSession` timestamps (hotkey→listening,
  stop→paste); 30 trials; report median + p95; compare to Wispr measured on the
  same clips/machine.
- **Paste compatibility**: run the cross-app matrix; `N/M` is the *measured* pass
  count.
- **Decision rule**: if SpeechAnalyzer WER > Wispr + `T_wer`, ship WhisperKit as
  the v0.1 default.

---

## 4. Personas

| Persona | Primary pain with the cloud incumbents |
|---|---|
| Developer on Apple-Silicon Mac | Paid subscription, audio in someone else's cloud, no real local option |
| Writer | Same + wants it offline (planes, trains, anywhere) |
| Accessibility user (RSI) | Same + needs it *free*, and needs no-hold activation |
| Privacy-sensitive (lawyer, doctor, journalist) | **Cloud upload of audio is a hard deal-breaker** |

---

## 5. Product & UX — the dictation→neat-text experience

### 5.1 The headline flow (this must feel perfect)

1. User triggers the hotkey (default: **double-tap Fn**; fully customizable).
2. Menubar icon turns **red**; a floating overlay appears near the cursor.
3. User speaks; the **partial transcript streams live** in the overlay (volatile
   results, near-instant).
4. User stops (single-tap Fn).
5. Status: **processing** (yellow) — transcript is finalized, then the
   **on-device AI cleanup pass** turns it into neat, finished text.
6. Finished text is **pasted at the cursor** (write-to-pasteboard + simulated
   Cmd+V; never reads the pasteboard).
7. Menubar returns to **idle**. The dictation is saved to local history.

### 5.2 AI neat-writing is v0 core — not optional

"Speech → *neat* text" is the product identity (matching Wispr's core). Default
cleanup runs on Apple's on-device **`Foundation Models`** framework (an Apple
framework — so it does **not** violate the no-third-party-deps rule). It is
pluggable via the `LLMCleaning` protocol, settings-toggleable, and falls back to
the **raw transcript** whenever cleanup is off or the engine is unavailable —
the paste always succeeds. Doing this **on-device + free** is the BEAT over
Wispr's cloud cleanup.

### 5.3 The hotkey (signature UX)

- **Default**: double-tap Fn = start, single-tap Fn = stop & paste.
- **Why Fn**: on every Mac keyboard, easy reach, no holding required (RSI-kind).
  Fn emits `kVK_Function` (0x3F). `[verified]`
- **Double-tap is custom-detected**: no macOS API emits it; `speak` monitors the
  key and counts taps within a short, **tunable** window (default 0.4 s — a
  `[decision]` flagged to tune in dogfood, not load-bearing).
- **Always customizable** from the start: F-keys, single-key toggle, modifier
  combos, double-tap-Cmd; persisted. (Fn behavior varies on external keyboards —
  handled gracefully, alternatives offered.) *Note: Fn is not unique to `speak` —
  Wispr uses it too; the moat is local/open, not the key choice.*

### 5.4 Streaming states

| State | Menubar | Overlay |
|---|---|---|
| Idle | gray waveform | none |
| Listening | red dot | visible, streaming partial text |
| Processing | yellow spinner | frozen text + cleanup spinner |
| Done | green flash → gray | fades out, neat text pasted |
| Error | red X | error message + retry |

### 5.5 First-run onboarding (3 permissions, clearly explained)

Welcome → **Microphone** → **Accessibility** → **Input Monitoring** (each with
*why* + a deep-link to System Settings) → hotkey picker → test dictation → done.
Three prompts is a lot; the flow justifies each with a screenshot. The bar is "a
fresh user reaches a working dictation with no confusion" — comprehension, not a
stopwatch. Onboarding drop-off is a top risk.

### 5.6 History & settings

- **Local, searchable, exportable history** of every dictation (raw + cleaned
  text, timestamp, engine), in `~/Library/Application Support/speak/`. Substring
  search, clear, export. Capacity is a tunable setting, not a hardcoded constant.
- **Settings**: hotkey rebinding, language (en-US, en-GB minimum), STT engine,
  cleanup engine + on/off toggle, paste mode.

---

## 6. Architecture summary

> Full blueprint and verbatim Swift signatures live in `docs/architecture.md` —
> referenced here, not duplicated.

**Stack**: Swift 5.9+ / SwiftUI · macOS 26 (Tahoe, shipped **Sept 15 2025**)
`[verified]` · Apple Silicon. A single Swift codebase — **no Rust, no FFI, no
cross-platform layer** (settled decision). The app is `speak.app` (SwiftUI
menubar) embedding **`SpeakCore.framework`** (the headless dictation engine and
the portability seam — engine logic stays behind clean protocol boundaries so a
future Windows/iOS/CLI target can extract it without a rewrite).

**The pluggable pipeline** — both halves are protocol-driven so any local model
drops in:

- **Speech → text**: the `Transcribing` protocol. Default
  `AppleSpeechTranscriber` (Apple **`SpeechAnalyzer`**, `Speech` framework;
  on-device, macOS 26+, Apple Silicon, volatile + finalized results). `[verified]`
  Alternatives: WhisperKit / Parakeet / whisper.cpp (v0.1+).
- **Text → neat text**: the `LLMCleaning` protocol. Default
  `FoundationModelsCleaner` (Apple **`Foundation Models`**; on-device LLM,
  macOS 26, Apple Silicon + Neural Engine — same model class as Writing Tools).
  `[verified]` Alternatives: Ollama (Qwen 2.5 3B / Gemma 3 4B / Phi-4-mini),
  MLX (v0.1+). The default path is **zero-dependency, on-device, free**.

**Supporting pieces** (signatures in `architecture.md` §6):
`CaptureSession` (actor: idle → listening → processing → done | error);
`HotkeyMonitor` (`CGEventTap`, global Fn detection, double-tap, rebinding);
`PasteboardWriter` (`NSPasteboard` **write-never-read** + simulated `Cmd+V`);
`HistoryStore` (SQLite); `SettingsStore` (typed `UserDefaults`);
`PermissionManager` (mic / Accessibility / Input Monitoring state machine);
logging via `os.Logger` only (no `print`). Concurrency: `SpeakEngine` and
`CaptureSession` are actors; UI and hotkey callbacks on `@MainActor`; the main
thread is never blocked.

**No magic numbers**: every numeric target traces to a measured value, a cited
platform constraint, or a `[decision]` in the derivation ledger
([§9 below](#9-the-derivation-ledger-no-orphan-constants)).

---

## 7. Privacy posture

The moat *is* the privacy guarantee — privacy by construction, not by policy:

1. **No audio or text leaves the device.** Ever, by default. No network egress.
2. **No accounts, no login, no telemetry.** `speak` sends nothing anywhere.
3. **Transcripts stay local** (`~/Library/Application Support/speak/`),
   searchable and exportable, never synced without an explicit opt-in.
4. **Hardware mute**: a chord toggles capture; when muted, no audio is read —
   impossible to bypass.
5. **Works fully offline.** Networking off changes nothing about the core flow.

Contrast: Wispr uploads audio to OpenAI (STT) + a fine-tuned Llama (cleanup),
mandates an account, and has no offline mode. `[verified]`

---

## 8. Scope & roadmap — the version ladder (order of value, no dates)

> **There is no deadline.** This is an autonomous, agent-driven build: the loop
> runs across as many cycles as it takes until the **complete product** exists.
> "Done" is defined by testable criteria (the [v0 ship gate](#11-the-v0-ship-gate)),
> never by dates, effort, or hours. **v0 is the *complete core*, not an MVP.**

### v0 — the complete core (the real product)

A real, private, neat-writing dictation app that rivals the frontier's core
experience: speech→text via `SpeechAnalyzer`; **AI neat-writing** via on-device
`Foundation Models`; customizable double-tap-Fn hotkey; live streaming overlay;
paste at cursor (write-only + Cmd+V); 3-permission onboarding; local searchable
history; settings; 100% local, free, open (MIT), offline.
**Done when** the v0 MATCH gate + all BEAT rows + the ship checklist pass.

### v1 — attractive & friendly

More languages (SpeechAnalyzer locales; WhisperKit for the long tail); richer
cleanup (tone/style modes, per-app formatting, snippets, custom dictionary);
pluggable models surfaced in the UI (Ollama/WhisperKit) with guided setup;
onboarding / menubar / overlay polish; latency tuning; CLI shim
(`speak --start/--stop/--status`); Intel Mac via whisper.cpp.

### v2 — creative & expansive

Code-aware mode; voice editing/commands ("make this shorter") via local LLM;
local cross-device continuity (opt-in, **never** account-mandatory); advanced
app-specific behaviors.

### v3+ — frontier & creative

Open-ended directions the product earns as it matures. No pre-commitment.

> Later versions make `speak` more attractive, friendlier, and more creative —
> they never backfill missing core. v1–v3+ are defined *now* so v0 is architected
> to make them additive, never a rewrite.

---

## 9. The derivation ledger (no orphan constants)

Every numeric target in this spec references one of these symbols; each traces to
a measured value, a platform constraint, or a `[decision]` + rationale. (Single
source of truth: `docs/benchmark.md` §7 — reproduced here, not re-invented.)

| Symbol | Value (v0) | Derivation | Type |
|---|---|---|---|
| `T_wer` | +3 pts | tolerance over Wispr's ~97% EN; tune after first corpus run | `[decision]` |
| `L_e2e` | < 2.0 s median (incl. on-device cleanup); raw-only path < 1.0 s | beats Wispr's cloud cleanup path (~1–2s) while staying local | `[decision]` from frontier latency `[verified]` |
| `L_partial` | < 200 ms | matches `architecture.md` §12 first-partial p95; SpeechAnalyzer volatile results near-instant `[verified]` | platform-derived |
| `N/M` | ≥ 13/16 | = `quality.md` §3 compatibility matrix size + ship gate; **measured** | `[decision]`, single source = `quality.md` §3 |
| `F_rate` | < 1 / 30 min | = `roadmap.md` P5 done-when (typing test in Notes) | `[decision]`, single source = `roadmap.md` P5 |
| double-tap window | 0.4 s | human double-tap timing; flagged to tune in dogfood, not load-bearing | `[decision]`, tune empirically |
| history size | "last N" (a setting) | no frontier anchor (Wispr has none); a tunable setting, not a constant | `[decision]` |

---

## 10. Risks

| # | Risk | Mitigation | Decision rule |
|---|---|---|---|
| 1 | SpeechAnalyzer WER worse than Wispr in noise | WhisperKit fallback (v0.1) | If WER > Wispr + `T_wer` in quiet tests, ship WhisperKit as default |
| 2 | Fn key is OS-controlled / conflicts vary | Customizable hotkey from v0 | If >10% report Fn doesn't fire, promote a non-Fn default |
| 3 | **Paste**: write+Cmd+V bypass `[unverified]` + macOS 26.4 Terminal paste-provenance check | Write-never-read; **test paste in Terminal/iTerm early at P6** before relying on it | If Cmd+V prompts in any top-20 app, switch that app to AX paste |
| 4 | 3-permission onboarding drop-off | Streamlined flow, deep-links, walkthrough | If drop-off >25%, add a "skip & configure later" path |
| 5 | Local LLM adds 1–2s latency | Streaming UI; per-session disable | If median cleanup >2.5s, default cleanup OFF |
| 6 | Apple changes SpeechAnalyzer / Foundation Models access | Pluggable protocols; WhisperKit/Ollama ready | If API deprecated, ship the alternative as default |
| 7 | Wispr copies local-first | Open source + community + MIT moat | Compete on free + open + dev UX — Wispr can't go local without abandoning cloud revenue |
| 8 | Apple-Silicon-only limits reach | Intel via whisper.cpp in v1 | Not a v0 risk; revisit at v1 |

Full register (likelihood × impact, all 12 rows): `docs/quality.md` §8.

---

## 11. The v0 ship gate

v0 ships when **all three** hold — measured, not asserted:

1. **MATCH gate** (`benchmark.md` §4): en-US WER ≤ Wispr + `T_wer`; stop→paste is
   *cleaned* via on-device Foundation Models (toggle + raw fallback work); median
   stop→paste (incl. cleanup) < `L_e2e` and ≤ Wispr measured; first volatile
   result → overlay < `L_partial`; paste works in ≥ `N/M` apps with zero
   read-prompts (Terminal tested); hotkey global + rebindable, false-trigger
   < `F_rate`; local history search/clear/export works.
2. **BEAT rows** (`benchmark.md` §3): all seven structural moat rows hold
   (offline, free, MIT, no account, local history, lower latency, no egress).
3. **Ship checklist** (`quality.md` §9): build/sign/notarize clean; no `print`;
   no force-unwrap / `try!` / `as!` outside tests; no global mutable state;
   write-only pasteboard; no third-party deps; `brew install --cask speak` works
   on a clean machine; dogfood + top-3 bugs fixed; tests green.

---

## 12. Distribution & GTM

- **License**: **MIT** — community moat; less restrictive than the GPL
  competitors (VoiceInk, FluidVoice). `[verified]`
- **Distribution**: **Homebrew Cask + signed `.dmg`** — **not sandboxed** in v0
  (global hotkeys + simulated Cmd+V require it). A sandboxed Mac App Store variant
  is a later, reduced-scope option.
- **Signing**: Developer ID + notarization (required for Gatekeeper on macOS 26).
  `[verified]`
- **Updates**: Homebrew + manual `.dmg` initially; evaluate Sparkle for in-app
  updates as the product matures.
- **Positioning line**: *the only Mac dictation app that is simultaneously local,
  free, open-source, offline, and account-free — with the frontier's neat-writing
  experience.*

---

## 13. Verification-ledger summary

The `docs/` set was originally generated by an open-source model and tagged
`[verified]` without an actual check. On 2026-06-20, three parallel research
agents verified the load-bearing claims against primary sources
(`specs/verification-ledger.md`). Headline verdicts:

| Claim | Verdict | Corrected value |
|---|---|---|
| `SpeechAnalyzer` exists, on-device, macOS 26 | `[verified]` | Foundation holds; API shape accurate |
| macOS 26 = Tahoe | `[verified]` (date corrected) | Shipped **Sept 15 2025 (Q3)**, not Q4 |
| `Foundation Models` on-device LLM (cleanup) | `[verified]` | macOS 26, Apple Silicon + Neural Engine |
| `CGEventTap` perms + Fn = `kVK_Function` 0x3F | `[verified]` | Hotkey approach valid |
| Write+Cmd+V paste **bypass** | **`[unverified]`** | Test at P6; macOS 26.4 added a Terminal paste-provenance check (`_sourceSigningIdentifier`, ~74-app list). General "write-not-read avoids the *read* prompt" is `[verified]`. Michael Tsai source dated **2026-04-03**. |
| Wispr "polishing, not shipping" thesis | **`[refuted]`** | Wispr is in aggressive 2026 expansion → reposition to the *structural* moat |
| "Free" + "Fn hotkey" as differentiators | **`[corrected]`** | Wispr has a free tier and uses Fn → moat narrows to local + open + offline + no-account + history |
| Superwhisper price | `[corrected]` | **$8.49/mo** (not $9.99) |
| WhisperKit repo | `[corrected]` | renamed → **`github.com/argmaxinc/argmax-oss-swift`** (v1.0.0, May 2026; MIT) |

**Verdict**: the technical foundation is **sound — build can proceed.** Two
strategic corrections (the Wispr thesis; the "free"/Fn differentiators) and one
technical risk (the paste bypass) are folded into this spec and into `docs/`.

---

## 14. Open questions

| # | Question | Status | Needed by |
|---|---|---|---|
| 1 | Xcode/Swift toolchain available; repo needs `git init` | Unverified — check before P0 | P0 |
| 2 | `Foundation Models` runtime availability/quality on target Macs (Apple Intelligence gating, M-series, locale) | Verify empirically at P3.5; raw fallback exists | P3.5 |
| 3 | Does write+`Cmd+V` avoid the paste prompt incl. the macOS 26.4 Terminal provenance check? | `[unverified]` — test in Terminal/iTerm | P6 |
| 4 | Developer ID signing cert for notarization | Unverified | P11 |

---

## 15. Appendix — required `docs/` corrections

> `docs/product.md` is **immutable** by process (the build loop treats the
> destination as human-owned). These corrections are recorded here, derived from
> ledger §4, so they are not lost. Items already applied to `docs/` on 2026-06-20
> are marked **[applied]**; items still pending in-place edits are marked
> **[pending]**.

1. **`product.md` §4 "Why now"** — **[applied]**. The "Wispr is polishing /
   coasting" premise was `[refuted]`; product.md §4 now states the *structural*
   window (Wispr cannot go local/free/open without abandoning cloud + subscription
   revenue). This spec uses that corrected framing. Re-verify product.md §4 reads
   structurally before any external share.
2. **`product.md` §5 differentiation matrix** — **[applied]**. Corrected: Wispr
   **has a free tier**, **uses Fn**, is **Intel+AS / multi-platform / 100+ langs**.
   `speak`'s true differentiators narrow to **local-only + open-source (MIT) +
   offline + no-account + local history + lower local latency**. Do not let any
   future edit reintroduce "free" or "Fn" as the moat.
3. **`architecture.md` §11** — **[pending]**. The prose ("Works in ~95% of apps")
   overstates a path the ledger marks `[unverified]`. Reconcile: keep
   "write-never-read" (`[verified]` for the *read* prompt) but treat the
   write+Cmd+V **bypass** of the macOS 26.4 Terminal paste-provenance check as
   `[unverified]` — **test empirically at P6** (§14 already correctly tracks this;
   §11/§14 reference the corrected Tsai date 2026-04-03).
4. **Dates & citations** — **[applied]** in the verified docs: macOS 26 = Sept 15
   2025 (Q3); Superwhisper $8.49; WhisperKit repo = `argmax-oss-swift`; Michael
   Tsai post = 2026-04-03. Never copy a stale citation (e.g. "$9.99", "2026-04-09",
   old WhisperKit path) through into a share.
5. **Opportunities to keep encoded** — Wispr has **no persistent dictation
   history** `[unverified]` and **no offline mode** `[verified]`; both are `speak`
   BEAT rows and central to the pitch.

> **Structural change flagged for human approval**: `docs/benchmark.md` should be
> registered in the `AGENTS.md` §1 navigation table as the definition-of-done doc
> (it is referenced throughout but the nav addition is a structural doc change —
> do not edit `product.md` to accomplish it).
