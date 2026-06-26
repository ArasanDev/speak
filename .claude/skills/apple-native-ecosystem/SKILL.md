---
name: apple-native-ecosystem
description: Use when making ANY architectural decision about which Apple framework to use — the complete catalog of native macOS 26 frameworks available to speak, with guidance on when each applies. Read this BEFORE reaching for a third-party package.
---

# Apple Native Ecosystem — speak's Framework Catalog

## The Principle

Apple Silicon + macOS 26 native frameworks = the architecture spine. Third-party engines
(WhisperKit, MLX, Sarvam) are **plugins TO this spine**, not replacements for it.
Go native-first; add third-party only when native cannot reach.

**Decision rule**: If Apple ships a framework that does the job on-device, use it. If it
has a coverage gap (languages, accuracy, capability), plug in the third-party engine behind
the same protocol seam — never bypass the native stack.

## The Neural Engine Pipeline (speak's core data flow)

```
voice
  → AVAudioEngine (CPU)             ← audio capture, buffer management
  → SpeechAnalyzer / DictationTranscriber (Neural Engine)  ← STT
  → NaturalLanguage / NLTagger (CPU, microseconds)         ← protect proper nouns
  → Foundation Models (Neural Engine)                      ← AI cleanup
  → NSPasteboard write + CGEvent Cmd+V (CPU)               ← paste
```

Every AI step runs on the Neural Engine. CPU only handles I/O and event simulation.
Unified memory means zero copy between CPU/GPU/Neural Engine — this is the Apple Silicon
advantage that no x86 or discrete-GPU laptop can match.

---

## Framework Catalog (macOS 26 / WWDC26)

### Speech & Audio

**`SpeechAnalyzer`** — primary STT `[verified: used in v0]`
- Three modules (WWDC26 clarification `[inferred from official sources]`):
  - `DictationTranscriber` — short utterances, push-to-talk. **speak's primary module.**
  - `SpeechTranscriber` — long-form audio (meetings, lectures). Use for future meeting-capture.
  - `SpeechDetector` — voice activity detection (VAD). Pair with a transcriber.
- 2.2× faster than Whisper Large V3 Turbo on Apple Silicon `[inferred from WWDC26]`
- 9 languages in v0; language expansion via WhisperKit (v0.1) or Sarvam (v0.1, Indian languages)
- ⚠️ Custom vocabulary gap: new modules may NOT support `contextualStrings` — see `speechanalyzer-stt` skill

**`AVAudioEngine`** — audio graph `[verified: used in v0]`
- `AVAudioUnitEQ` node: add for noise suppression (high-pass filter at 80Hz) — V1-5 (quiet mode)
- `AVAudioPCMBuffer`: tap for RMS level via `vDSP_rmsqv` — silence detection for auto-segmentation

**`Accelerate / vDSP`** — signal processing `[verified APIs]`
- `vDSP_rmsqv` — RMS power of audio buffer; use for silence threshold in V1-6 (auto-segmentation) and 30s chunking for Sarvam STT
- `vDSP_maxv`, `vDSP_meanv` — level metering for overlay waveform
- No new dependency; `Accelerate` is a system framework

**`CoreAudio`** — low-level audio `[available, not needed in v0]`
- Use only if AVAudioEngine proves insufficient for noise shaping or multi-channel routing

---

### AI / ML

**`Foundation Models`** — on-device LLM for cleanup `[verified: used in v0]`
- `LanguageModelSession` is the call site; system prompt + user prompt → cleaned text
- WWDC26: **provider API** (`LanguageModel` protocol) allows MLX, Gemini, Claude behind same session `[inferred from official sources — verify shape via apple-docs MCP]`
- Streaming generation `[inferred]`; structured output via `response_format` `[inferred]`
- Context window: `[unverified — verify via apple-docs MCP]`
- Multimodal (image input) added at WWDC26 `[inferred from official sources]`
- Framework source being open-sourced `[inferred from official sources]`

**`Core AI`** (NEW at WWDC26) — `import CoreAI` `[inferred from official sources]`
- **Supersedes CoreML for LLM/generative AI workloads**
- CoreML still works (not deprecated) but Core AI is the target for ALL new ML integration
- Native support: LLMs, streaming generation, tool calling, third-party model plugins
- Dynamic routing: describe capability requirements → Core AI routes to on-device / Private Cloud Compute / user extension automatically
- Impact: V1-1 (MLX), V1-13 (FM provider API) — verify whether Core AI is the integration layer before coding
- ⚠️ **Action required**: V1-0a is a dedicated research task to verify Core AI API shape via `apple-docs` MCP before any new ML engine work

**`CoreML`** — legacy ML inference `[verified: used by WhisperKit + Parakeet]`
- Still fully functional; not deprecated
- WhisperKit and FluidAudio/Parakeet both use CoreML under the hood — that's fine
- Do NOT use raw CoreML for NEW integration work; use Core AI instead

**`NaturalLanguage`** — text analysis `[verified existing framework]`
- `NLLanguageRecognizer` — detect language of transcribed text (50+ languages); use to auto-route to Sarvam STT language code
- `NLTagger` with `.personalName`, `.placeName`, `.organizationName` — identify proper nouns before LLM cleanup so the model doesn't "correct" them
- `NLTokenizer` with `.sentence` unit — sentence boundary detection; use for V1-6 (auto-segmentation) instead of a custom heuristic
- `NLEmbedding` — semantic similarity; future use for smart history deduplication
- Zero dependency, zero download, all macOS versions

**`Vision`** — image analysis `[available; future use]`
- Screen OCR for context awareness (VoiceInk does this); speak uses AX accessibility API instead (preferred, no screenshot required)
- Callable as a tool from Foundation Models (WWDC26) `[inferred from official sources]`

---

### App Integration

**`AppIntents`** — Siri + Shortcuts `[inferred from WWDC26 — SiriKit deprecated]`
- SiriKit formally deprecated at WWDC26; AppIntents is the ONLY path for Siri integration
- App Schemas: no hardcoded trigger phrases — Siri understands intent schema naturally
- "Hey Siri, start dictating" → fires `StartDictationIntent` automatically
- Testing: new `AppIntents Testing` framework validates intents without UI automation
- Roadmap: V1-0b

**`ActivityKit` (Live Activities)** — dictation progress indicator `[inferred from WWDC26]`
- Live Activities confirmed on macOS at WWDC26
- Show waveform animation + elapsed time + word count during dictation
- Updated locally via `ActivityKit` (no push needed for in-session updates)
- Roadmap: V1-0c

**`WidgetKit`** — home/notification center widgets `[verified: available on macOS]`
- Stats widget: streak, words today, WPM — in Notification Center
- Roadmap: v1 polish (no dedicated task yet)

**`CoreSpotlight`** — searchable history `[available]`
- Index dictation history entries in Spotlight
- Users can find past dictations via ⌘Space search
- Roadmap: v1 polish (no dedicated task yet)

---

### Text Processing

**`NaturalLanguage`** — see AI/ML section above

**`NSDataDetector`** — structured data extraction `[available]`
- Detect phone numbers, addresses, dates, URLs in transcripts
- Future: auto-link detected entities in History view

**`NSLinguisticTagger`** — legacy, superseded by `NLTagger` `[available but avoid]`
- Use `NLTagger` for all new work

---

## What NOT to Use

| Avoid | Use Instead | Reason |
|---|---|---|
| `SiriKit` | `AppIntents` | Deprecated at WWDC26 |
| Raw `CoreML` for new LLM work | `Core AI` | CoreML not designed for generative AI |
| `SFSpeechRecognizer` | `SpeechAnalyzer / DictationTranscriber` | Legacy; worse accuracy; cloud option |
| `NSPasteboard` reads | AX `kAXSelectedTextAttribute` | speak's moat: never read pasteboard |
| Third-party audio SDKs | `AVAudioEngine` + `vDSP` | Native is sufficient; no new deps |
| `Vision` OCR for context | AX accessibility API | AX: no screenshot, better privacy |

---

## Third-Party Plugin Points

Third-party engines slot in behind native protocol seams — the native pipeline runs unchanged:

| Seam | Native default | Third-party plugins |
|---|---|---|
| `Transcribing` protocol | `AppleSpeechTranscriber` (SpeechAnalyzer) | `WhisperKitTranscriber` (v0.1), `SarvamSpeechTranscriber` (v0.1) |
| `LLMCleaning` protocol | `FoundationModelsCleaner` (Foundation Models) | `OpenAICompatibleCleaner` (Ollama/Sarvam/OpenAI/Groq) (v0.1), `MLXModelCleaner` (v1) |
| App integration | `StartDictationIntent` (AppIntents) | Raycast extension, Alfred deep link (v1) |

**Key rule**: native default is always active and zero-config. Third-party is always opt-in, always requires explicit user configuration, never breaks the moat (7/7).

---

## Verify at Implementation Time

For any framework listed as `[inferred]` or `[unverified]`:
```sh
# Type-check a probe file against the local macOS 26 SDK
swiftc -typecheck \
  -sdk "$(xcrun --show-sdk-path)" \
  -target arm64-apple-macosx26.0 \
  /tmp/probe.swift

# Or use apple-docs MCP:
# Query the framework name + type name — returns current SDK documentation
```

The local macOS 26 SDK is the cutoff-proof source of truth. Never trust model training
memory for post-2025 Apple API shapes.
