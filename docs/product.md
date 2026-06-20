# `speak` — Product Definition (WHAT + WHY)

> **Status**: The destination. This defines what `speak` IS and what the
> finished product looks like. Architecture (`architecture.md`) says HOW;
> `roadmap.md` says IN WHAT ORDER; `benchmark.md` says WHEN IT IS DONE.
> This file describes the *real, full product* — not a time-boxed slice.
> Changing the destination is a human decision; the build loop builds toward it.

---

## 0. One sentence

> *The Mac-native, free, local-first voice dictation app that turns your speech
> into clean, finished text at the cursor — privately, on-device, and open.*

`speak` is an **AI dictation** app: speech becomes text, **and the AI writes it
neatly** — filler removed, punctuation and capitalization correct, formatted to
fit where it lands. The clean transcript is the product. The same core
experience as Wispr Flow, but it never leaves your machine.

---

## 1. The final outcome — what the finished product is

When `speak` is done, this is true. (This is the destination the loop builds
toward; `benchmark.md` makes each line testable.)

- A **menubar app** that sits idle until a hotkey wakes it.
- You **press the hotkey, speak, and stop.** A live overlay streams your words
  as you talk. On stop, the **AI cleans the transcript** (removes "um/uh,"
  fixes grammar and punctuation, formats) and **pastes finished text at the
  cursor** — in any app.
- **Everything runs on-device.** No account, no login, no cloud, no telemetry,
  works fully offline. Audio and text never leave the Mac.
- **Speech-to-text and cleanup are both pluggable, local models** — native
  Apple engines by default, swappable for other local small models. Plug and
  play.
- It is **free, unlimited, and open source (MIT).**
- It keeps a **local, searchable, exportable history** of everything dictated.
- It is **fast** — local processing beats the cloud round-trip — and it is
  **private by construction**, not by policy.

### What it looks like (the headline flow — this must feel perfect)

1. User triggers the hotkey (default: **double-tap Fn**; fully customizable).
2. Menubar icon turns **red**; a floating overlay appears near the cursor.
3. User speaks; the **partial transcript streams live** in the overlay
   (volatile results, near-instant).
4. User stops (single-tap Fn).
5. Status: **processing** (yellow) — transcript is finalized, then the **AI
   cleanup pass** turns it into neat, finished text.
6. Finished text is **pasted at the cursor** (write-to-pasteboard + simulated
   Cmd+V; never reads the pasteboard).
7. Menubar returns to **idle**. The dictation is saved to local history.

---

## 2. What `speak` is NOT (non-goals)

- **Not** an agentic coding tool. (That was the abandoned `deepvoice`; archived
  in `research/sample-ideation.md`.)
- **Not** a chatbot, voice assistant, or meeting scribe.
- **Not** cloud. No accounts, login, or telemetry. (Cloud STT may exist *only*
  as a later, explicit, user-keyed opt-in — never the default, never required.)
- **Not** account-bound or sync-mandatory. Local is the point.

---

## 3. Personas

| Persona | Primary pain with the cloud incumbents |
|---|---|
| Developer on Apple-Silicon Mac | Paid subscription, audio in someone else's cloud, no real local option |
| Writer | Same + wants it offline (planes, trains, anywhere) |
| Accessibility user (RSI) | Same + needs it *free*, and needs no-hold activation |
| Privacy-sensitive (lawyer, doctor, journalist) | **Cloud upload of audio is a hard deal-breaker** |

---

## 4. Why now — the window is *structural*, not temporal `[verified]`

The opportunity is not "the incumbent is slow." The incumbent (**Wispr Flow**)
is, in fact, advancing aggressively (Android, AI cleanup levels, transforms,
100+ languages). The window is open for a deeper reason:

- **Wispr is architecturally cloud.** Audio is uploaded to its servers (OpenAI
  for STT, a fine-tuned Llama for cleanup), an account is mandatory, and there
  is no offline mode. It **cannot** become local/free/open/offline without
  abandoning its own subscription + cloud business. `[verified]` (see
  `specs/verification-ledger.md`)
- **The on-device stack is now good enough to match it.** Apple shipped
  **`SpeechAnalyzer`** (on-device STT, macOS 26) and a **`Foundation Models`**
  framework (on-device LLM for cleanup) — both native, free, Apple-Silicon.
  `[verified]` A category-leading dictation experience can now run entirely
  locally.
- Plenty of **small, local, production-grade models** exist beyond Apple's
  (WhisperKit/Parakeet for STT; Qwen/Gemma/Phi via Ollama/MLX for cleanup),
  and they are **plug-and-play**. `[verified]`

So `speak` does not race the incumbent on breadth. It occupies the one position
the incumbent structurally cannot: **fully local, free, open, offline, private.**

---

## 5. Positioning & the durable moats

**Position**: the only dictation app that is **simultaneously** local-only,
free, open-source (MIT), offline, and account-free — with a category-leading
neat-writing experience.

**The durable moats** (the incumbent cannot copy these without breaking its
model):

1. **Local + free + open + offline + no-account.** `[verified]` Wispr is
   cloud-only, account-mandatory, with a word-capped free tier. This bundle is
   structural, not a feature they can ship.
2. **Native on-device pipeline.** SpeechAnalyzer + Foundation Models: fastest on
   Apple Silicon, no model download, no licensing, improves with the OS for
   free. `[verified]`
3. **Pluggable local models (plug and play).** STT and cleanup are both swappable
   engines; power users pick their model, the default "just works." `[verified]`
   role model: FluidVoice ships 5 pluggable engines.
4. **Local, owned history.** The incumbent has no persistent dictation history;
   `speak` does — searchable, exportable, private. `[verified]` gap.

### Honest differentiation (corrected against verification)

| Dimension | Wispr Flow (frontier) | **speak** |
|---|---|---|
| Speech → neat text | Yes (cloud AI cleanup) | **Yes (on-device AI cleanup)** |
| Local / offline | **No** (cloud-only) | **Yes** |
| Price | $15/mo (+ capped free tier) | **Free, unlimited** |
| Open source | No | **Yes (MIT)** |
| Account required | **Yes** | **No** |
| Local dictation history | No | **Yes** |
| Pluggable local models | No | **Yes** |
| Languages | 100+ | core first, expanding (pluggable) |
| Platforms | Mac/Win/iOS/Android | Mac (Apple Silicon) first |

`speak` concedes breadth (platforms, languages-on-day-one) to win the moat;
breadth arrives later, locally, on `speak`'s terms. Full feature-by-feature
parity map and the testable definition of done live in `benchmark.md`.

---

## 6. The model architecture in one view (plug and play)

Both halves of the pipeline are protocol-driven so any local model can drop in:

- **Speech → text**: `Transcribing` protocol. Default `AppleSpeechTranscriber`
  (SpeechAnalyzer). Alternatives: WhisperKit / Parakeet / whisper.cpp.
- **Text → neat text**: `LLMCleaning` protocol. Default
  `FoundationModelsCleaner` (Apple on-device LLM — no third-party dependency).
  Alternatives: Ollama (Qwen 2.5 3B / Gemma 3 4B / Phi-4-mini), MLX models.

The default path is **zero-dependency, on-device, free**. Swapping a model is a
settings choice, not a rebuild. This is the architecture done properly — see
`architecture.md` §10.

---

## 7. UX principles

### 7.1 The hotkey (signature UX)
- **Default**: double-tap Fn = start, single-tap Fn = stop & paste.
- **Why Fn**: on every Mac keyboard, easy reach, no holding required (RSI-kind).
  Fn emits `kVK_Function` (0x3F). `[verified]`
- **Double-tap is custom-detected**: no macOS API emits it; `speak` monitors the
  key and counts taps within a short window. The window is a tunable setting,
  not a fixed constant.
- **Always customizable** (from the start): F-keys, single-key toggle, modifier
  combos, double-tap-Cmd. Persisted. (Note: Fn behavior varies on external
  keyboards — handled gracefully, alternatives offered.)

### 7.2 Streaming states
| State | Menubar | Overlay |
|---|---|---|
| Idle | gray waveform | none |
| Listening | red dot | visible, streaming partial text |
| Processing | yellow spinner | frozen text + cleanup spinner |
| Done | green flash → gray | fades out, neat text pasted |
| Error | red X | error message + retry |

### 7.3 First-run onboarding (3 permissions, clearly explained)
Welcome → **Microphone** → **Accessibility** → **Input Monitoring** (each with
*why* + deep-link to System Settings) → hotkey picker → test dictation → done.
Three prompts is a lot; the flow must justify each with a screenshot. Onboarding
drop-off is a top risk — the bar is "a fresh user gets to a working dictation
with no confusion," not a stopwatch.

---

## 8. Privacy guarantees (put these in the README)

1. **No audio or text leaves the device.** Ever, by default.
2. **No accounts, no login, no telemetry.** `speak` sends nothing anywhere.
3. **Transcripts stay local** (`~/Library/Application Support/speak/`),
   searchable and exportable, never synced without explicit opt-in.
4. **Hardware mute**: a chord toggles capture; when muted, no audio is read.
5. **Works fully offline.** Networking off changes nothing about the core flow.

---

## 9. The version ladder (the full vision — no time, just order of value)

> **Principle**: v0 is **not an MVP** — it is the **complete core**: a real,
> private, neat-writing dictation app that rivals the frontier's core
> experience. Later versions make it **more attractive, friendlier, and more
> creative** — they never backfill missing core. We define v1–v3+ *now* so v0 is
> architected to make them additive, never a rewrite.

### v0 — the complete core (the real product)
Everything essential to a private, neat-writing dictation app:
- Speech → text via `SpeechAnalyzer` (pluggable `Transcribing`).
- **AI neat-writing** via on-device `Foundation Models` (pluggable
  `LLMCleaning`) — filler removal, punctuation, capitalization, formatting.
- Hotkey (double-tap/single-tap Fn + full customization).
- Live streaming overlay.
- Paste at cursor (write-only pasteboard + Cmd+V; AX fallback where needed).
- 3-permission onboarding.
- Local searchable/exportable history.
- Settings (hotkey, language, STT engine, cleanup engine + on/off, paste mode).
- 100% local, free, open (MIT), offline.
- **Done when** `benchmark.md`'s v0 MATCH gate + all BEAT rows pass.

### v1 — attractive & friendly (polish that delights)
- More languages (SpeechAnalyzer locales; WhisperKit for the long tail).
- Richer cleanup: tone/style modes, per-app formatting, snippets & custom
  dictionary, learned vocabulary.
- Alternative pluggable models surfaced in the UI (Ollama/WhisperKit), with
  guided setup.
- Onboarding, menubar, and overlay polish; latency tuning; metrics view.
- CLI shim (`speak --start/--stop/--status`).

### v2 — creative & expansive
- Code-aware mode (detect code context, format accordingly).
- Voice editing/commands ("make this shorter," "fix that") via local LLM.
- Local cross-device continuity (opt-in, never account-mandatory).
- Advanced, app-specific behaviors.

### v3+ — frontier & creative
- Open-ended creative directions (the product earns these as it matures).

There is no deadline on any of this. The loop advances the ladder until the
product is whole; each rung's "done" is defined by testable criteria, not dates.

---

## 10. Distribution & licensing

- **License**: **MIT** — community moat; less restrictive than the GPL
  competitors. `[verified]`
- **Distribution**: **Homebrew Cask + signed `.dmg`** (not sandboxed — global
  hotkeys + Cmd+V require it). A sandboxed Mac App Store variant is a later,
  reduced-scope option.
- **Signing**: Developer ID + notarization (required for Gatekeeper on
  macOS 26). `[verified]`
- **Updates**: Homebrew + manual `.dmg` initially; evaluate Sparkle for in-app
  updates as the product matures.

---

## 11. Tagging convention

Claims are tagged: `[verified]` (primary source — see
`specs/verification-ledger.md`), `[inferred]` (inference chain stated),
`[decision]` (opinionated choice), `[unverified]` (could not confirm — flagged).
If the build loop finds a `[verified]` claim that contradicts a primary source,
**stop and surface it** — do not silently override.
