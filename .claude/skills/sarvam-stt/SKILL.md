---
name: sarvam-stt
description: Use when implementing Sarvam AI's Saaras v3 STT engine (v0.1 task V01-3s) — 23 Indian languages, codemix mode for Tamil+English / Hindi+English mixed speech, multipart REST API with 30s chunking. The India-first moat.
---

# Sarvam STT (Saaras v3) — Implementation Pointer

## Why this exists

No local STT model — SpeechAnalyzer (9 languages), WhisperKit (99 languages), Parakeet (English) —
handles Indian language code-switching well. Tamil+English ("Tanglish"), Hindi+English ("Hinglish"),
and other mixed-language speech are common in India. Sarvam's `codemix` mode handles this natively.
This is a genuine product differentiator: no competitor (Wispr Flow, SuperWhisper, VoiceInk) supports it.

## Architectural Seam

Protocol: `Transcribing` — lives at `SpeakCore/STT/Transcriber.swift`

```swift
public protocol Transcribing: Sendable {
    var id: String { get }
    func startStream(locale: Locale) -> AsyncThrowingStream<TranscriptChunk, Error>
    func stop() async
}
```

**Target file**: `SpeakCore/STT/SarvamSpeechTranscriber.swift` (new)
**Engine id**: `"sarvam-saaras-v3"` `[decision]`

**Note**: Sarvam's REST API is NOT a streaming endpoint (unlike SpeechAnalyzer / WhisperKit).
The `startStream` conformance must be emulated: record → chunk at 25s silence boundaries →
send REST requests sequentially → emit chunks as they return. This matches `isFinal: true`
semantics for each chunk and a final `isFinal: true` after the last chunk.

Wire via `EngineFactories.defaultTranscriber(for:)` when `SettingsStore.sttEngine == .sarvam`
AND a Sarvam API key is present in Keychain.

## REST API `[verified from official Sarvam docs, June 2026]`

```
POST https://api.sarvam.ai/speech-to-text
Header: api-subscription-key: <key>   ← NOT Bearer; this is the only supported auth
Content-Type: multipart/form-data

Fields:
  file              = <audio binary>   WAV/MP3/AAC/FLAC/OPUS/PCM/WebM/M4A
  model             = "saaras:v3"      recommended (23 languages); "saarika:v2.5" is legacy
  mode              = "codemix"        default for Indian users; see Mode table below
  language_code     = "unknown"        auto-detect, OR explicit e.g. "ta-IN"

Response (200 OK):
{
  "transcript": "the cleaned transcribed text",
  "language_code": "ta-IN",
  "language_probability": 0.97,
  "timestamps": {
    "words": ["word1", "word2"],
    "start_time_seconds": [0.0, 0.4],
    "end_time_seconds": [0.4, 0.9]
  }
}
```

**Max audio per request: 30 seconds.** Recordings longer than 30s must be chunked. `[verified]`

## Mode Options

| mode | When to use |
|------|------------|
| `"codemix"` | **Default** — mixed Indian+English speech (Tanglish, Hinglish, etc.) |
| `"transcribe"` | Pure single-language speech, standard punctuation |
| `"verbatim"` | No cleanup — exact words including fillers (for training/review use) |
| `"translate"` | Transcribe Indian language → English translation output |
| `"translit"` | Transliterate: Indian script → Roman letters (Hinglish style) |

Expose `mode` as a user setting in Settings → Transcription → Sarvam Options.
**Default to `codemix`** when the user's selected language is any Indian language or `"unknown"`.

## Supported Languages (saaras:v3, 23 total) `[verified]`

| Code | Language | Code | Language |
|------|----------|------|----------|
| `hi-IN` | Hindi | `ta-IN` | Tamil |
| `te-IN` | Telugu | `kn-IN` | Kannada |
| `ml-IN` | Malayalam | `bn-IN` | Bengali |
| `gu-IN` | Gujarati | `mr-IN` | Marathi |
| `pa-IN` | Punjabi | `od-IN` | Odia |
| `en-IN` | English (Indian) | `as-IN` | Assamese |
| `ur-IN` | Urdu | `ne-IN` | Nepali |
| `kok-IN` | Konkani | `ks-IN` | Kashmiri |
| `sd-IN` | Sindhi | `sa-IN` | Sanskrit |
| `sat-IN` | Santhali | `mni-IN` | Manipuri |
| `brx-IN` | Bodo | `mai-IN` | Maithili |
| `dgo-IN` | Dogri | `unknown` | Auto-detect |

In Settings → Transcription → Language: show these 23 + "Auto-detect". Default: `"unknown"`.

## 30-Second Chunking Strategy

```swift
// `[inferred]` — adapt to actual AVAudioEngine pipeline
// Record continuously into a rolling PCM buffer.
// Every ~100ms, check RMS level.
// When RMS < silenceThreshold for >0.5s AND buffer >= 10s:
//   → extract current buffer as WAV chunk
//   → reset buffer
//   → POST chunk to Sarvam
//   → emit TranscriptChunk(text: response.transcript, isFinal: false)
// Hard cap: if buffer reaches 25s with no silence, force-chunk anyway.
// On stop():
//   → send remaining buffer (even if < 10s)
//   → emit final chunk with isFinal: true
//   → concatenate all partial transcripts with " " separator
```

WAV encoding: 16kHz mono PCM, 16-bit. Use `AVAudioPCMBuffer` → `AVAudioFile` → Data.

## Auth & Key Storage `[decision]`

- **API key stored in Keychain only** — `kSecClassGenericPassword`, service `"ai.speak.sarvam"`, account `"api-key"`. Never `UserDefaults`.
- Settings → Transcription: `SecureField("Sarvam API key", ...)` writes to Keychain via `KeychainHelper`.
- Key is read from Keychain at transcription start; if absent → fall back to `AppleSpeechTranscriber` silently.

## Privacy Gate `[decision]`

```swift
// BEFORE sending any audio to Sarvam:
guard !settings.privacyMode else {
    // Privacy Mode on → never send audio to cloud
    return AppleSpeechTranscriber().startStream(locale: locale)
}
guard keychainKey != nil else {
    // No key configured → fall back silently
    return AppleSpeechTranscriber().startStream(locale: locale)
}
guard NetworkMonitor.shared.isConnected else {
    // No network → fall back, show HUD "Using on-device STT"
    showHUD(.noNetworkFallback)
    return AppleSpeechTranscriber().startStream(locale: locale)
}
```

## Error Handling

| Error | HTTP / Condition | Response |
|-------|-----------------|----------|
| Bad key | 401 | HUD: "Invalid Sarvam API key — check Settings → Transcription"; fall back |
| Audio too large | 413 | Reduce chunk size to 20s; retry once; then fall back |
| Rate limit | 429 | Retry after 1s × 2; then fall back to AppleSpeechTranscriber |
| No network | connection refused | Fall back; HUD: "Using on-device STT" |
| Server error | 5xx | Fall back; log via `os.Logger` |

All non-fatal errors fall back to `AppleSpeechTranscriber`. The user always gets a transcript.

## Pricing Reference (for Settings onboarding copy) `[verified June 2026]`

- ₹30/hour (~$0.36/hr)
- Free ₹100 credit on signup (~3.3 hours of dictation)
- Credits never expire
- Free tier: ₹100 credit, 60 req/min rate limit
- Startup program: 6–12 months free — link: sarvam.ai

## Verify at Implementation Time

```sh
# Test with a real WAV file (16kHz mono, <30s):
curl -X POST https://api.sarvam.ai/speech-to-text \
  -H "api-subscription-key: YOUR_KEY" \
  -F "file=@/path/to/sample.wav" \
  -F "model=saaras:v3" \
  -F "mode=codemix" \
  -F "language_code=unknown"

# Official docs:
# STT API: https://docs.sarvam.ai/api-reference-docs/speech-to-text/transcribe
# Streaming: https://docs.sarvam.ai/api-reference-docs/api-guides-tutorials/speech-to-text/streaming-api
# Models: https://docs.sarvam.ai/api-reference-docs/getting-started/models/sarvam-105b
```

## v1: Streaming (WebSocket)

Sarvam offers a WebSocket streaming endpoint (`wss://api.sarvam.ai/v1/realtime`) for sub-second
partial transcripts. No official Swift SDK. Requires base64-encoded PCM chunks (512 samples = 32ms
at 16kHz). Defer to v1 (V1-x Sarvam streaming) — out of scope for v0.1. `[decision]`
