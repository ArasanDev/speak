---
name: speechanalyzer-stt
description: Use when implementing or modifying the Apple SpeechAnalyzer speech-to-text transcription layer in SpeakCore — specifically AppleSpeechTranscriber, the Transcribing protocol, or streaming transcript chunk handling.
---

# SpeechAnalyzer STT — Implementation Pointer

## WWDC26: Three Modules — Use `DictationTranscriber` `[inferred from official sources]`

SpeechAnalyzer ships three distinct modules as of macOS 26:

- **`DictationTranscriber`** — short utterances, push-to-talk dictation. **This is speak's correct module.**
- **`SpeechTranscriber`** — long-form audio (meetings, lectures, multi-speaker). Future meeting-capture mode.
- **`SpeechDetector`** — voice activity detection (VAD). Must be paired with a transcriber.

**Action**: Verify which module `AppleSpeechTranscriber.swift` currently instantiates via
`apple-docs` MCP or `swiftc -typecheck`. If it uses the wrong module, the streaming
behavior and accuracy characteristics may differ from expectations.

Performance: SpeechAnalyzer is 2.2× faster than Whisper Large V3 Turbo on Apple Silicon. `[inferred from WWDC26]`

---

## ⚠️ Critical: Custom Vocabulary Gap `[inferred from WWDC26 search — verify before V01-1]`

The new `DictationTranscriber` and `SpeechTranscriber` modules may **NOT** support Custom
Vocabulary. Only the legacy `SFSpeechRecognizer` is confirmed to support `contextualStrings`.

Our H4 seam in `AppleSpeechTranscriber.swift` uses `AnalysisContext.contextualStrings[.general]`
to inject vocabulary hints. This **MUST** be verified before V01-1 (WhisperKit) work begins:

1. Use `apple-docs` MCP: look up `DictationTranscriber` + "vocabulary" / "contextualStrings"
2. Run `swiftc -typecheck` probe: try `AnalysisContext(contextualStrings:)` with `DictationTranscriber`
3. If `contextualStrings` NOT supported on new modules:
   - Vocabulary hints must route to WhisperKit (`vocabulary` param on `WhisperKit.transcribe`) or Sarvam STT (`model` + `language_code` hints) instead
   - Remove `contextualStrings` injection from `AppleSpeechTranscriber` to avoid silent no-op

Until verified: tag `customVocabulary` in `AppleSpeechTranscriber` as `[unverified in DictationTranscriber context]`.

This is tracked as Open Question V3 in `docs/progress.md`.

---

## Architectural Seam

Protocol: `Transcribing` — lives at `SpeakCore/STT/Transcriber.swift`

```swift
public protocol Transcribing: Sendable {
    var id: String { get }
    func startStream(locale: Locale) -> AsyncThrowingStream<TranscriptChunk, Error>
    func stop() async
}
```

The v0 concrete implementation is `AppleSpeechTranscriber`, backed by Apple's **SpeechAnalyzer** framework (macOS 26, on-device only). It emits `TranscriptChunk(text: String, isFinal: Bool, timestamp: Date)` values through the stream. The engine `id` for this implementation is `"apple-speech-en-US"`.

## Hard Constraints

- **100% on-device.** No audio leaves the device. Do not use any cloud speech API.
- **Apple frameworks only in v0.** SpeechAnalyzer is an Apple framework and is permitted. Whisper, WhisperKit, and any third-party STT are v0.1+ alternatives — never default dependencies.
- Use `os.Logger` for all logging. No `print`. No force-unwrap. No `try!`. No `as!` outside tests.
- Do not block the main thread. The `AsyncThrowingStream` must be produced off-thread.

## Roadmap P3 Done-When

- Spoken audio produces streaming PARTIAL transcripts during capture (intermediate `isFinal: false` chunks arrive in real time).
- A FINAL transcript (`isFinal: true`) is emitted when the session ends.
- Engine `id` is `"apple-speech-en-US"`.
- Unit tests in `SpeakCoreTests/STT/` cover at least: stream-starts, chunk-emission, stop-terminates-stream, locale-passthrough.

## Verify at Implementation Time

**Do not rely on recalled SpeechAnalyzer API surface.** The streaming API shape — how you obtain an analyzer instance, how you feed audio buffers, and how results arrive — must be ground-truthed against current Apple documentation before writing any code.

Use the `apple-docs-mcp` MCP server (if available in this session) to look up `SpeechAnalyzer` directly. Otherwise, fetch from `https://developer.apple.com/documentation/speech`. Additionally, `swiftc -typecheck -sdk "$(xcrun --show-sdk-path)" -target arm64-apple-macosx26.0 <file>` is now the strongest available local check for symbol resolution — use it to confirm any API symbol claim (note: it confirms symbol availability, not full streaming-method signatures). Tag every API claim: `[verified]` when confirmed from docs, headers, or swiftc probe, `[inferred]` when extrapolated, `[unverified]` when untested. If a verified fact contradicts a prior claim, stop and surface it before continuing.

Architecture detail for this surface lives in `docs/architecture.md` §10.2 (API shape), §14 (day-0 verification).
