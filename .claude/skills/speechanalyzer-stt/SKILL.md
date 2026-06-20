---
name: speechanalyzer-stt
description: Use when implementing or modifying the Apple SpeechAnalyzer speech-to-text transcription layer in SpeakCore — specifically AppleSpeechTranscriber, the Transcribing protocol, or streaming transcript chunk handling.
---

# SpeechAnalyzer STT — Implementation Pointer

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
