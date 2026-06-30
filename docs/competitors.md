# Competitor Landscape
> Reference doc. Authority: `specs/verification-ledger.md` for any `[verified]` claim.
> Read when: positioning, README claims, benchmark.md comparisons.

---

## The frontier: Wispr Flow `[verified]`

- **Pricing** `[verified]`: Free "Flow Basic" 2k words/wk (Mac/Win), 1k (iPhone); Pro $15/mo or $12/mo annual.
- **STT** `[verified]`: Cloud — OpenAI Whisper via Wispr servers. No local option.
- **Cleanup** `[verified]`: Cloud — fine-tuned Llama via Wispr servers. No local option.
- **Account** `[verified]`: mandatory. Zero-retention claimed but all audio processed in cloud.
- **No offline mode** `[verified]`: requires internet for every dictation.
- **Platforms** `[verified]`: macOS 12+ (Intel + AS), Windows 10/11, iOS 18.3+, Android (Feb 2026).
- **Languages** `[verified]`: 100+, auto-detect, code-switching, Hinglish.
- **AI levels** `[verified]`: None / Light / Medium / High; Transforms; Command Mode (Pro).
- **Latency** `[verified]`: ~700ms p99 to 1–2s (dominated by cloud round-trip).
- **Dictation history** `[unverified]`: none found — a gap speak can own.
- **2026 trajectory** `[verified]`: actively expanding — Android, Transforms, Scratchpad, Admin Portal. Not coasting.

---

## Summary comparison table

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
| Multiple hotkey bindings | 🚧 v0.1 | ✅ (up to 4) | ✅ (per-mode) | 🔶 | ❌ | ✅ |
| Local persistent history | ✅ | ❌ `[unverified]` | ✅ | ❌ | ❌ | ❌ |
| Works offline | ✅ | ❌ `[verified]` | ✅ (local models) | ✅ (STT only) | ✅ (STT only) | ✅ |
| Speaker diarization (offline) | 🚧 v2 | ❌ | ✅ | ❌ | 🔶 (beta) | ❌ |
| File transcription (audio/video) | ❌ | ❌ | ✅ | ❌ | ✅ | ❌ |
| History sync between devices | 🚧 v2 | ✅ | ✅ | ❌ | ❌ | ❌ |
| iOS app | 🚧 v2 | ✅ | ✅ | 🔶 (buggy) | ❌ | ❌ |
| Android app | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ |
| Windows support | ❌ | ✅ | ✅ (limited) | ❌ | ❌ | ✅ |
| Pricing | **Free, unlimited, MIT** | $15/mo (2k/wk free tier) | $8.49/mo / $250 lifetime | $25–49 one-time | €59 one-time | Free + $25/mo beta |

✅ = done · ❌ = no · 🔶 = partial/paid/limited · 🚧 = planned (roadmap task shown)

---

## Other local/transcription-only apps

- **Aiko / TypeWhisper**: free, OSS, local Whisper; no AI cleanup at all. `[verified]`
- **FluidVoice**: GPLv3; 5 pluggable STT engines (Nemotron/Parakeet/Apple/Whisper/Cohere); no live AI cleanup. `[verified]`
- **MacWhisper**: file and batch transcription, not a live dictation product; AI cleanup requires cloud API key. `[verified]`
- **VoiceInk**: GPLv3, local STT, but AI cleanup is BYOK cloud — no on-device LLM. $25–49. `[verified]`
- **SuperWhisper**: most powerful local option; Pro $8.49/mo; local STT but cloud LLM is the default encouraged path. Closed source. `[verified]`

All miss the bundle: local STT + local AI cleanup + MIT + no account + no cap + offline.

---

## speak's structural moat

Five properties speak holds simultaneously. No competitor holds all five.

- **100% local LLM cleanup, zero setup**: `Foundation Models` runs on-device; no API key, no model download, no daemon. Works the moment the app launches. `[verified]`
- **MIT open source**: more permissive than VoiceInk's GPL; the only MIT dictation app in the category. `[verified]`
- **No account, no cap**: Wispr free tier caps at 2k words/wk; SuperWhisper's full feature set requires Pro. speak has no tier and no cap. `[verified]`
- **Fully offline**: all core flows work with networking disabled. Wispr requires cloud for every dictation. `[verified]`
- **Local persistent history**: Wispr has none found `[unverified]`; speak owns this gap as a built guarantee.

Wispr cannot acquire these without abandoning its subscription + cloud architecture. The window is structural, not temporal.
