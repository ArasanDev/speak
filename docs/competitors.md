# speak — Competitor Analysis (June 2026)

> **Status**: Research-grounded; update each quarter or after a major competitor
> release. Read alongside `benchmark.md` (testable parity criteria) and
> `product.md` §5–6 (positioning).

---

## The landscape

Voice dictation tools split into three lanes. Lane 1 — **general dictation**
(email, Slack, docs) — is served by Wispr Flow, VoiceInk, and SuperWhisper.
Lane 2 — **developer / power user** (coding terminals, agent prompts, technical
writing) — is underserved: SuperWhisper added coding-agent integration in April
2026 and Talon Voice serves the RSI/accessibility crowd, but nothing offers a
clean, zero-setup experience. Lane 3 — **file transcription** (meeting recordings,
YouTube, batch subtitle export) — belongs to MacWhisper; `speak` does not compete
here.

`speak` sits at the intersection of Lane 1 and Lane 2: the only tool that is
**simultaneously** 100% local (audio + LLM), MIT open source, account-free,
unlimited, and zero-setup on any Mac. Its structural advantage is that Wispr Flow
— the best-polished incumbent — is architecturally cloud and cannot become local
without dismantling its subscription business. `speak` wins by going where the
frontier cannot follow, then growing into Lane 2 as the first dictation tool built
for the agentic era.

---

## The 5 competitors

### Wispr Flow — best polish, but cloud-locked `[verified]`

**Core**: Hold or double-tap hotkey → AI cleanup (4 levels: None / Light / Medium
/ High) → paste. Context-aware (reads frontmost app bundle ID → adjusts
tone/casing per category). Command Mode (voice-edit selected text). Transforms
(highlight text → cloud LLM rewrite; presets + custom; diff overlay). Flow Bar
(persistent floating UI). Snippets. Dictionary (auto-add from typing corrections).
History + stats + streaks. Scratchpad.

**STT**: Cloud (OpenAI Whisper via Wispr servers). No local option.
**LLM**: Cloud (fine-tuned Llama on Wispr servers). No local option.
**Languages**: 100+, auto-detect mid-sentence. Hinglish model.
**Platforms**: Mac, Windows, iOS (keyboard extension, Dynamic Island), Android.
**Privacy**: Audio uploads to Wispr servers. Account mandatory. No offline mode.
**Pricing**: Free 2,000 words/week; Pro $15/mo; Teams $12/seat/mo; Enterprise custom.

**Weaknesses**: subscription; cloud upload; account required; no offline; no local
LLM; no open source.

---

### SuperWhisper — most powerful, best developer UX `[verified]`

**Core**: Unlimited custom modes (Pro), each with own hotkey, STT model, LLM,
auto-activation rule, custom prompt. Auto-activate a mode when a specific app is
frontmost OR a specific browser URL is active. Super Mode reads active app +
selected text + clipboard via macOS accessibility APIs → context-aware output
without manual prompt engineering. Filler word removal (Mar 2026). Hallucination
detection.

**STT**: Local — Whisper (tiny → Ultra V3 Turbo), Parakeet V2+V3 (25 languages),
S1 (proprietary model), S1-Mini (experimental Jun 2026). Cloud — Deepgram Nova
2/3/Medical, ElevenLabs Scribe V2, OpenAI API.
**LLM**: Local — Ollama (all models), any OpenAI-compatible endpoint. Cloud —
GPT-4o/4.1/5, Claude Haiku/Sonnet/Opus (all series), Gemini, Grok, Llama 4,
Mixtral, OpenRouter. Cloud models hosted by SuperWhisper (Pro included — no user
API key needed for the hosted set).
**Coding agent integration** (v2.13.0 Apr 2026): Claude Code, Open Code, Pi,
Codex — transcript pipes directly into terminal agent pipeline; plugin system.
**Speaker diarization**: offline, built-in since Oct 2024. Speaker naming.
**History**: word-level timestamps, audio playback, segmented playback, full-text
search, re-process any entry with a different mode, sync between Macs (Jun 2025).
**Other**: deep links (`superwhisper://`), Raycast/Alfred extensions, CSV vocab
import, British English transform, media-pause on record, AirPods fade.
**Platforms**: macOS (primary), Windows (limited), iOS, iPad.
**Privacy**: local models = 100% on-device. Cloud models = text to SuperWhisper/
provider. API keys encrypted on disk. SOC 2 Type II, HIPAA compliant.
**Pricing**: Free (basic, Whisper Tiny/Base only); Pro $8.49/mo / $84.99/yr /
$249.99 lifetime; Enterprise custom.

**Weaknesses**: cloud LLM is the default/encouraged path; steep learning curve
(modes = configuring a server); closed source; no MIT; Intel Mac limited; account
needed for full Pro.

---

### VoiceInk — open source, cheapest, BYOK `[verified]`

**Core**: Any macOS app; push-to-talk + toggle; per-mode auto-activation (app +
URL); screen OCR for LLM context; AI assistant mode ("Hey!" trigger for in-context
LLM queries); 10 custom modes max.

**STT**: Local — Whisper (via whisper.cpp, all sizes) + Parakeet V2/V3
(FluidAudio, Neural Engine).
**LLM**: BYOK only — user supplies OpenAI / Anthropic / Google / OpenRouter API
keys. No hosted LLM. No local on-device LLM.
**Enhancement presets**: Polish, Email, Chat, Tweet/Post, Custom.
**Context**: app bundle ID + URL auto-activation; screen OCR for content (requires
Screen Recording permission; less reliable than accessibility API).
**Open source**: GPL v3 (`Beingpax/VoiceInk`); buildable from source for free.
**Platforms**: macOS (Apple Silicon, macOS 14.4+ required), iOS (buggy per
App Store reviews).
**Pricing**: $25 one-time (1 Mac) / $39 (2 Macs) / $49 (3 Macs); source = free.

**Weaknesses**: BYOK → user must pay OpenAI/Anthropic separately, no offline
cleanup; OCR context is unreliable vs accessibility API; iOS buggy; max 10 modes;
no sync; no diarization; no file transcription.

---

### MacWhisper — file transcription, not live dictation `[verified]`

**Core**: File-first product — drag any audio/video file, transcribe. YouTube URL
→ transcript. Batch process hundreds of files. Watch folder (auto-transcribe on
drop). SRT/VTT subtitle export. System audio capture (record Mac audio output).
Live dictation exists but is secondary.

**STT**: Local — Whisper tiny/base/small/medium/large/V3/V3 Turbo. Free tier
locked to small/base.
**LLM**: Cloud only — OpenAI API key required (GPT-4.1). No local cleanup.
**Speaker diarization**: beta, Pro tier.
**Platforms**: macOS only.
**Pricing**: Free; Pro €59 one-time; Mac App Store $6.99/mo / $29.99/yr /
$99.99 lifetime; Pro Max $149.

**Weaknesses**: not a live dictation product; AI cleanup requires cloud + API key;
no per-app context; diarization beta-quality. **`speak` does not compete in this
lane.**

---

### Talon Voice — voice operating system for developers `[verified]`

**Core**: Full hands-free computer control via voice commands + optional eye
tracking + noise control (pop/hiss). NOT a clean-prose dictation tool — it is a
programmable voice OS. Primary audience: RSI sufferers, developers wanting voice
coding, accessibility users.

**STT**: Conformer (proprietary, low-latency, optimized for commands). 2025 hybrid
added Whisper for prose dictation mode.
**Voice commands**: `.talon` declarative grammar + Python 3 actions. Community
grammar (`talonhub/community`, 6k GitHub stars) covers 15+ programming languages.
Context-sensitive (different commands per app/OS state). Cursorless (VS Code
extension: voice-select any code token by colored hat — the best voice code
editing system in existence).
**Eye tracking**: Tobii hardware required (~$200). Gaze-as-mouse.
**No LLM AI cleanup**: no AI text polish at all.
**Platforms**: macOS, Windows, Linux.
**Pricing**: Free (stable, frozen Jul 2023); $25/mo Patreon for beta features.

**Weaknesses**: steep setup; conformer accuracy lower than Whisper for prose;
closed-source core; no AI cleanup; eye tracker required for mouse control;
$25/mo Patreon for new features. **`speak` does not compete in this lane.**

---

## Feature matrix — speak vs. the field

| Feature | **speak** | Wispr Flow | SuperWhisper | VoiceInk | MacWhisper | Talon |
|---|---|---|---|---|---|---|
| 100% local STT | ✅ | ❌ | ✅ (local option) | ✅ | ✅ | ✅ |
| 100% local LLM cleanup (no API key) | ✅ | ❌ | 🔶 (Ollama BYOK) | ❌ (BYOK cloud) | ❌ (BYOK cloud) | ❌ (none) |
| MIT open source | ✅ | ❌ | ❌ | 🔶 (GPL v3) | ❌ | ❌ |
| No account required | ✅ | ❌ | 🔶 (free tier limited) | ✅ | ✅ | ✅ |
| No usage limits / free forever | ✅ | ❌ (2k/wk free) | 🔶 (free = limited) | ✅ (BYOK costs) | 🔶 | ✅ |
| Per-app context awareness | 🚧 v0.1 | ✅ | ✅ (Super Mode) | ✅ (10 modes) | ❌ | ✅ |
| URL-based auto-activation | 🚧 v1 | ❌ | ✅ | ✅ | ❌ | ❌ |
| Custom modes (unlimited) | 🔶 (styles, not modes) | ✅ (categories) | ✅ (unlimited Pro) | 🔶 (max 10) | ❌ | ✅ |
| Re-process history with different mode | 🚧 v1 | ❌ | ✅ | ❌ | ❌ | ❌ |
| Screen-aware context (AX API) | 🚧 v1 | ✅ | ✅ | 🔶 (OCR only) | ❌ | ✅ |
| Coding agent integration | 🚧 v0.1 | ❌ | ✅ (Apr 2026) | ❌ | ❌ | ✅ (Cursorless) |
| Multiple hotkey bindings per action | 🚧 v0.1 | ✅ (up to 4) | ✅ (per-mode) | 🔶 | ❌ | ✅ |
| Deep link / automation protocol | 🚧 v1 | ❌ | ✅ (superwhisper://) | ❌ | ❌ | ✅ |
| Speaker diarization (offline) | 🚧 v2 | ❌ | ✅ | ❌ | 🔶 (beta) | ❌ |
| File transcription (audio/video) | ❌ | ❌ | ✅ | ❌ | ✅ | ❌ |
| YouTube/URL transcription | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ |
| Batch file processing | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ |
| History sync between devices | 🚧 v2 | ✅ | ✅ (Jun 2025) | ❌ | ❌ | ❌ |
| iOS app | 🚧 v2 | ✅ | ✅ | 🔶 (buggy) | ❌ | ❌ |
| Android app | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ |
| Windows support | ❌ | ✅ | ✅ (limited) | ❌ | ❌ | ✅ |
| Indian lang + codemix STT | 🚧 v0.1 (Sarvam Saaras) | 🔶 (limited multilingual) | 🔶 (WhisperKit some) | 🔶 (Whisper models) | 🔶 (Whisper models) | ❌ |
| Pricing | **Free, unlimited, MIT** | $15/mo | $8.49/mo / $250 lifetime | $25–49 one-time | €59 one-time | Free + $25/mo beta |

✅ = done · ❌ = no · 🔶 = partial/paid/limited · 🚧 = planned (roadmap task shown)

---

## What speak has that no competitor has simultaneously

1. **MIT open source** — more permissive than VoiceInk's GPL. No other app is
   open. Community moat: forks, PRs, and audits compound forever. `[verified]`
2. **100% local LLM cleanup, zero setup** — Foundation Models runs on-device;
   no API key, no model download, no daemon. Works the moment the app launches.
   `[verified]` VoiceInk needs BYOK cloud; SuperWhisper's local path needs
   Ollama daemon running.
3. **No account, no usage limit** — Wispr's free tier caps at 2k words/week.
   SuperWhisper's full feature set requires Pro. VoiceInk requires paid API keys
   for cleanup. `speak` has no cap and no tier. `[verified]`
4. **Apple-native pipeline** — SpeechAnalyzer + Foundation Models = zero download,
   zero third-party dependency, Neural Engine acceleration, improves with macOS
   updates at no cost. `[verified]`
5. **Free forever** — the MIT license is the business model. No subscription, no
   freemium wall, no "Pro to unlock." `[decision]`

These five are **simultaneous** — no competitor holds all five. And the leader
(Wispr Flow) cannot acquire them without abandoning its subscription + cloud
architecture.

---

## What speak must build — ranked by impact

These are the features competitors have that `speak` should adopt, ordered from
highest user-felt impact to lowest:

1. **Coding agent integration** [SuperWhisper v2.13, Apr 2026] — detect Claude
   Code/terminal frontmost, format transcript as imperative technical prompt,
   auto-submit option. The user is living this need right now. Highest impact,
   smallest code surface. → **V01-0**

2. **Per-app context awareness** [Wispr Flow, SuperWhisper, VoiceInk] — read
   frontmost app bundle ID, apply context-appropriate tone/casing/format
   automatically. Single biggest "feel-the-difference" UX for daily users.
   → **V01-3**

3. **WhisperKit multilingual** [SuperWhisper, VoiceInk] — unlock 99 languages
   and sub-100ms streaming. Expands the audience 10×. → **V01-1**

4. **Universal OpenAI-compatible cleanup** — one URLSession client covers Ollama, Sarvam-30B,
   OpenAI, Groq, OpenRouter. Power users plug in any compatible endpoint; local stays default.
   → **V01-2** (replaces Ollama-specific stub)

4b. **Sarvam Saaras codemix STT** — no competitor supports Tamil+English / Hindi+English
   code-switching natively. Sarvam's `codemix` mode handles 23 Indian languages seamlessly.
   This is the **India-first moat**: built from India, for the world. → **V01-3s**

5. **Transforms** [Wispr Flow] — highlight any text, local LLM rewrites it.
   `speak` BEATS Wispr here because it's 100% on-device. → **V1-3**

6. **Re-process history with different mode** [SuperWhisper] — any past dictation
   can be re-run through the current engine/mode. High utility, low friction.
   → **V1-9 (inline history retry)**

7. **URL-based auto-activation** [SuperWhisper, VoiceInk] — switch mode when
   specific website is active (browser tab URL). Useful for GitHub, Notion,
   email. → **V1 (extend V01-3)**

8. **Screen-aware context via AX API** [SuperWhisper Super Mode] — reads selected
   text + clipboard to inject context into cleanup prompt without manual switching.
   → **V1 (SuperMode equivalent)**

9. **Deep link / automation protocol** [SuperWhisper] — `speak://mode?key=X` for
   Raycast/Alfred/shortcuts. Power-user unlock, low code surface. → **V1**

10. **Speaker diarization** [SuperWhisper] — WhisperKit SpeakerKit. Useful for
    meeting/interview transcription. Not core for dictation. → **V2-3**

Features speak should **consciously skip** (not a bug, a moat):
- File / YouTube transcription → MacWhisper's lane; different UX
- Voice commands / scripting → Talon's lane; different complexity level
- Cloud LLM as default → breaks the moat by design
- Account + sync as requirement → breaks the moat by design

---

## The 6-month strategic plan

| Month | Focus | Key deliverables |
|---|---|---|
| **Month 1** (now) | **Ship v0** | Validate + fix `fix-input2`; human gate pass; Homebrew cask ready |
| **Month 2** | **v0.1 core** | V01-0 (agent mode), V01-3 (per-app context), V01-1 (WhisperKit), V01-2 (Ollama real impl) |
| **Month 3** | **v0.1 complete + v1 start** | V01-4 (auto-dictionary), V01-5 (multi-hotkey), V01-6 (language auto-detect); V1-3 (Transforms), V1-4 (code-aware) |
| **Month 4** | **v1 mid** | V1-1 (MLX), V1-2 (Parakeet), V1-5 (quiet mode), V1-6 (auto-segmentation), V1-7 (course correction) |
| **Month 5** | **v1 late + community** | V1-8–V1-12; Raycast extension; open source PRs from community; public benchmark |
| **Month 6** | **v2 start** | V1-13 (WWDC26 provider), V1-14 (iOS foundation); V2-2 (iCloud sync opt-in); V2-3 (diarization) |

The loop advances this plan autonomously. The orchestrator reviews diffs, owns
commits, and steers at drift — not at completion.
