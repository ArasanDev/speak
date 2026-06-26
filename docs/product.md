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

## 6b. WWDC26 architectural opportunity

macOS 26 / WWDC26 adds a `LanguageModelSession` **provider API** that allows
third-party model backends (Anthropic, Google, MLX) to satisfy the same Swift
`LanguageModelSession` interface that `FoundationModelsCleaner` already uses.
`[inferred from WWDC26 session notes]`

**What this means for `speak`:**

1. **Zero cleanup-code changes for provider swap.** `FoundationModelsCleaner`
   calls `LanguageModelSession` today; swapping the backend to MLX or Anthropic
   is a session-init parameter, not a new conformer. `[inferred]`
2. **MLX as in-process provider (V1-13)**: MLX Swift models run on the Neural
   Engine, no daemon, no IPC. Estimated throughput: ~500 tok/s for Qwen3-0.6B
   on M4 Max. `[inferred from MLX Swift benchmarks]`
3. **Anthropic as optional cloud provider (V1-13)**: the provider pattern keeps
   audio 100% local — only the cleanup prompt (cleaned text, never audio) goes
   over the wire. This is the first opt-in cloud feature; clearly disclosed.
4. **Google models**: same provider pattern; the user supplies a key. Never
   default; never mandatory.

**Implementation note**: verify the provider API shape against the local macOS 26
SDK before writing any conformance code (`swiftc -typecheck`). Do not rely on
training-data API shapes for WWDC26 additions — they are post-cutoff.

**Roadmap pointer**: provider integration is task V1-13 (WWDC26 Foundation Models
provider integration) in `roadmap.md`.

---

## 6c. The `speak` difference — and the road to Jarvis

### Five structural advantages (no competitor holds all five simultaneously)

1. **MIT open source** — VoiceInk is GPL; every other competitor is closed.
2. **100% local LLM, zero setup** — Foundation Models runs on-device, no API key,
   no model download, no daemon. Works on first launch.
3. **No account, no usage limits** — Wispr caps free at 2k words/week; SuperWhisper
   needs a Pro subscription for its best features; VoiceInk needs paid cloud keys.
4. **Apple-native pipeline** — SpeechAnalyzer + Foundation Models = Neural Engine
   acceleration, improves with every macOS update for free.
5. **Free forever** — MIT is the business model. No freemium wall. No tier.

### The soul: voice is a bandwidth multiplier for human thought

When you type, 3–4 lines. When you speak, 10–20 lines — and the ideas come
out differently: fuller, more connected, more honest. `speak`'s job is not
"clean transcription." It is:

> **Speak freely. `speak` understands where you are and who's reading,
> then writes it perfectly for that surface.**

### The progression

- **Today**: speak → STT → LLM cleanup → paste (email, Slack, docs)
- **v0.1**: speak → context-aware LLM → perfect format for the destination
  (code, agent prompt, commit message, technical instruction)
- **v1**: speak → screen context → LLM with full app + selection + clipboard
  awareness → output indistinguishable from expert writing
- **v2+**: speak → AI understands intent → structures as agent task → the
  dictation is the instruction that executes

The agentic era changes what a "good dictation" is. The user speaking into a
coding terminal is not dictating text — they are giving instructions to an agent.
`speak` is the **input layer for the agentic era**, starting from dictation and
growing into that role. SuperWhisper shipped coding-agent integration in April 2026.
`speak` builds it in v0.1 — locally, free, and open. `[decision]`

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

### 7.3 First-run onboarding (2 permissions, clearly explained)
Welcome → **Microphone** → **Accessibility** (each with *why* + deep-link to
System Settings) → hotkey picker → test dictation → done. Two prompts is
manageable; the flow must justify each with a screenshot. Onboarding drop-off
is a top risk — the bar is "a fresh user gets to a working dictation with no
confusion," not a stopwatch.

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

### v0.1 — Language, Engine & Intelligence (6 tasks, all additive)

| Task | Feature | Key spec |
|------|---------|---------|
| V01-0 | **Coding agent integration** | Detect Claude Code/terminal frontmost → "[Agent Mode]" badge; imperative prompt format; auto-submit option; configurable app list |
| V01-1 | WhisperKit STT | 99 langs, MIT, CoreML, guided model download, language auto-detect |
| V01-2 | Ollama cleanup (real impl) | localhost:11434, Qwen2.5:3B default, 4 model presets, guided setup, loopback-only |
| V01-3 | Per-app context awareness | Bundle ID → AppContext (7 classes); injects tone/casing into cleanup prompt |
| V01-4 | Auto-dictionary learning | Post-paste diff → word substitution HUD → `customVocabulary`, max 3/session |
| V01-5 | Multiple hotkey bindings | Up to 4 bindings per action; mouse buttons 4–10; no app restart |
| V01-6 | Language auto-detect + overlay pill | Language badge in overlay; quick-switch pill; persists to `SettingsStore` |

**Done when**: all 7 V01-x done-when checklists pass + 4 gates green.

### v1 — Power User & Polish (14 tasks)

| Task | Feature | Key spec |
|------|---------|---------|
| V1-1 | MLX Swift cleanup | In-process, SPM, Qwen3-0.6B/1.7B, Neural Engine, guided download |
| V1-2 | Parakeet/FluidAudio STT | Apache 2.0, CoreML, ~80ms latency, English champion, guided download |
| V1-3 | Transforms | Highlight → Polish/Expand/Summarize/Prompt-Engineer via local LLM; custom transforms; diff overlay; auto-transform mode |
| V1-4 | Code-aware dictation | camelCase/snake_case pref; AX file context; identifier vocabulary |
| V1-5 | Quiet mode / noise suppression | `AVAudioUnitEQ` high-pass + gain; sensitivity slider; level meter in overlay |
| V1-6 | Auto-segmentation for messaging | RMS silence detector → auto-stop + Return key; configurable threshold |
| V1-7 | Course correction | "wait no" / "scratch that" detection → trim + re-accumulate; user-editable markers |
| V1-8 | Dictation recovery | Per-session `.caf` buffer; crash → relaunch shows Retry/Discard HUD |
| V1-9 | Inline history retry | Re-run raw text through current engine; before/after diff; Replace/Append |
| V1-10 | Streak tracking + stats | Daily streak, 30-day word chart (`Charts`), WPM 7-day rolling avg |
| V1-11 | Personal writing style samples | Up to 5 samples injected as few-shot; empty → no injection, baseline preserved |
| V1-12 | Clamshell / mic auto-selection | Wake/sleep subscription; best-available mic; clamshell warning HUD |
| V1-13 | WWDC26 provider integration | `LanguageModelSession` provider API; MLX + optional Anthropic (Keychain, opt-in) |
| V1-14 | iOS app foundation | `SpeakCore` SPM package; iOS 18+ app target; Custom Keyboard Extension |

**Done when**: all 14 V1-x done-when checklists pass + 4 gates green.

### v2 — Platform & Expansion (5 tasks)

| Task | Feature | Key spec |
|------|---------|---------|
| V2-1 | iOS app complete | Dynamic Island, Lock Screen widget, Action Button, iPad keyboard extension |
| V2-2 | iCloud sync (opt-in) | `NSUbiquitousKeyValueStore` + CloudKit, no speak account, conflict = last-write-wins |
| V2-3 | Speaker diarization | WhisperKit SpeakerKit; `speakerLabels` in history; toggle in Settings |
| V2-4 | Team features (serverless) | iCloud folder share for team dictionary/snippets; union merge; no speak server |
| V2-5 | Android / Windows | Scope after v2 iOS stable; outside Apple-only constraint — platform seam decision deferred |

**Done when**: all V2-1 through V2-4 done-when checklists pass (V2-5 deferred).

### v3+ — Enterprise & Frontier (4 tasks + open-ended)

| Task | Feature | Key spec |
|------|---------|---------|
| V3-1 | HIPAA BAA docs + compliance export | PDF export of privacy architecture; `make verify-moat` as technical appendix |
| V3-2 | Enterprise MDM profile | `.mobileconfig`; managed `UserDefaults`; no speak server |
| V3-3 | Advanced voice editing (multi-turn) | Edit stack (5 levels), 30s window, "revert" command, local LLM |
| V3-4 | Developer API / SDK | DocC docs for public `SpeakCore` SPM package; example CLI app |
| V3-open | Open-ended creative directions | The product earns these as real user patterns emerge |

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
