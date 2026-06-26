---
name: whisperkitv1-stt
description: Use when implementing WhisperKit v1.0.0 as an alternative STT engine behind the `Transcribing` protocol (v0.1 task V01-1). Do NOT use for the v0 default engine — that is `speechanalyzer-stt`.
---

# WhisperKit v1.0.0 — STT Implementation Pointer

## Architectural Seam

Protocol: `Transcribing` — lives at `SpeakCore/STT/Transcriber.swift`

```swift
public protocol Transcribing: Sendable {
    var id: String { get }
    func startStream(locale: Locale) -> AsyncThrowingStream<TranscriptChunk, Error>
    func stop() async
}
```

Target file to create: `SpeakCore/STT/WhisperKitTranscriber.swift`
Engine id: `"whisperkit-v1"` `[decision]`

WhisperKit is a v0.1+ alternative. The default remains `AppleSpeechTranscriber`. Plug in via `EngineFactories.swift` behind a `sttEngine` setting key.

## Hard Constraints

- **v0.1+ only** — do not add this as a v0 dependency. v0 = Apple frameworks only.
- **Apple Silicon required** for large models (M1+). Intel path: fall back to `AppleSpeechTranscriber` or `WhisperKit` tiny model only — gate this in `EngineFactories`.
- **Model download is async and large** (~75MB tiny → ~1.5GB large-v3). Show a `ModelDownloadProgressView` HUD before first use. Never block startup.
- **No audio egress** — WhisperKit is entirely on-device. Confirm this via source inspection; do not take it on faith.
- **Honor `stopRequested` guard** — read `AppleSpeechTranscriber.swift` for the `stopRequested` actor-isolated flag pattern and replicate it exactly to prevent mic-leak on rapid stop/start.
- No `print`. `os.Logger` only. No force-unwrap outside tests.
- `Sendable` conformance: WhisperKit's types may not be `Sendable` — wrap in an actor if needed.

## SPM Dependency (add to `project.yml`)

```yaml
# In project.yml packages: section [inferred — read project.yml structure first]
- url: https://github.com/argmaxinc/WhisperKit
  exactVersion: "1.0.0"   # pin to 1.0.0; bump intentionally
```

Targets that need it: `SpeakCore` only — do not expose WhisperKit types in the `App` target directly.

## API Shape `[inferred — verify against package headers before coding]`

```swift
import WhisperKit

// 1. Init — async, downloads model if not cached
let config = WhisperKitConfig(model: "large-v3-turbo")  // [inferred]
let kit = try await WhisperKit(config)                   // [inferred]

// 2. Streaming from AVAudioPCMBuffer chunks
// WhisperKit 1.0 likely exposes a streaming API — verify exact method name
// Pattern from README [inferred]:
//   kit.transcribe(audioArray: [Float], decodeOptions: DecodingOptions) -> [TranscriptionResult]
// For real-time: feed chunks as they arrive; WhisperKit buffers internally

// 3. Language detection [inferred]
let langResult = try await kit.detectLanguage(audioPath: fileURL.path)
// Returns: { language: "en", probability: 0.97 } — exact shape [unverified]

// 4. Result type [inferred]
// TranscriptionResult.text: String — the full transcript
// TranscriptionResult.segments: [TranscriptionSegment] — word-level or segment-level
// TranscriptionSegment.text, .start, .end, .tokens — [unverified]
```

**ALL shapes above are `[inferred]`.** The monorepo at `https://github.com/argmaxinc/WhisperKit` is the primary source. Read `Sources/WhisperKit/Core/` headers before writing conforming code.

## Language Auto-Detection

WhisperKit natively detects language. Expose this as a `detectLanguage(from: AVAudioPCMBuffer) async throws -> Locale` method on `WhisperKitTranscriber` for the language-picker UI (V01-6). When `locale` passed to `startStream` is `.autoDetermined`, let WhisperKit detect; otherwise pin to the requested locale.

## Verify at Implementation Time

```sh
# 1. Resolve the package and inspect headers
cd /tmp && mkdir wk-probe && cd wk-probe
cat > Package.swift << 'EOF'
// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "WKProbe", platforms: [.macOS(.v14)],
  dependencies: [.package(url: "https://github.com/argmaxinc/WhisperKit", exact: "1.0.0")],
  targets: [.target(name: "WKProbe", dependencies: ["WhisperKit"])])
EOF
swift package resolve
# Then read: .build/checkouts/WhisperKit/Sources/WhisperKit/Core/WhisperKit.swift

# 2. Type-check your conformance file
swiftc -typecheck -sdk "$(xcrun --show-sdk-path)" \
  -target arm64-apple-macosx26.0 \
  -I .build/debug \
  WhisperKitTranscriber.swift

# 3. apple-docs MCP: search "WhisperKit" — may have community docs
```

Tag every symbol `[verified]` only after step 1 confirms it exists in the real package.

## Integration Notes

- Model cache path: `FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent("speak/WhisperKit/")` — let WhisperKit use its own default or configure explicitly.
- Settings key: `sttEngine` (already exists in `SettingsStore`) — add `"whisperkit"` as a valid value alongside `"apple"`.
- Model picker UI: add a `WhisperKitModelPicker` sheet in Settings → Transcription tab showing available model sizes + download size + WER.
- The `SpeakerKit` (diarization) and `TTSKit` modules in the same monorepo are v2 scope — do not import them for V01-1.
