# Changelog

All notable changes to `speak` are documented here.

Format: [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).
`speak` does not yet follow semantic versioning — v0 is the first complete
release. The version ladder (v0 → v3+) is defined in `docs/product.md` §9.

---

## [Unreleased] — v0

> **Status**: Engine and UI are fully built and pass 143 tests (123 XCTest +
> 20 Swift Testing). Live-gated verification (paste into real apps, hotkey with
> real permissions, Developer ID notarization) is in progress. See
> [`docs/human-verification.md`](docs/human-verification.md) for what remains
> before v0 ships.

### Build system (P0)

- XcodeGen-based build: `project.yml` → `Speak.xcodeproj` (git-ignored);
  `make build` regenerates from a clean clone
- Three targets: `Speak.app` (application), `SpeakCore.framework` (portability
  seam), `SpeakTests` (unit-test bundle)
- `Makefile` with `build` / `test` / `lint` / `run` / `clean` / `verify-moat`
  / `release` targets
- `.swiftlint.yml` — `force_unwrap`, `force_cast`, `force_try` are errors
- GitHub Actions CI (`.github/workflows/ci.yml`) — `xcodebuild build` +
  `swiftlint` on every push

### App shell (P1)

- `MenuBarExtra`-based menubar app (`LSUIElement` — no Dock icon)
- Links `SpeakCore.framework`; logs on launch via `os.Logger`

### Engine core (P0 foundation)

- `SpeakError` — typed error hierarchy
- `Transcribing` protocol + `TranscriptChunk` / `TranscriptionResult` value
  types
- `LLMCleaning` protocol + `CleanupMode`
- `SpeakLog` — `os.Logger` categories (`engine`, `audio`, `stt`, `cleanup`,
  `paste`, `hotkey`, `history`, `settings`, `permissions`)

### Audio capture (P2)

- `AudioCapture` — `AVAudioEngine` mic pipeline, 16 kHz mono PCM,
  `AsyncStream<AVAudioPCMBuffer>`
- `PermissionManager` — microphone permission state machine
- `NSMicrophoneUsageDescription` in app plist

### Speech-to-text (P3)

- `AppleSpeechTranscriber : Transcribing` — Apple `SpeechAnalyzer` (macOS 26+,
  on-device, Apple Silicon); volatile + finalized result streaming
- `AudioBufferProducing` protocol — injects `LiveAudioCapture` in production,
  `FixtureAudioProducer` in tests
- `AVAudioConverter` bridge: SpeechAnalyzer 16 kHz Int16 interleaved ← P2
  Float32 non-interleaved
- `AssetInventory` / `SpeechTranscriber.supportedLocale` / `isAvailable` gate
- Test fixture: `SpeakTests/Fixtures/hello_speech.caf` (16 kHz mono Float32,
  1.3 s)

### On-device AI cleanup (P3.5)

- `FoundationModelsCleaner : LLMCleaning` — Apple `Foundation Models` on-device
  LLM; `isAvailable` check; graceful raw-transcript fallback when unavailable
  or toggled off
- `CaptureSession` actor — full state machine: idle → listening → processing →
  done | error; wires transcriber + cleaner + inserter; exports `partials()`
  `AsyncStream` for the overlay
- `SpeakEngine` actor — assembles the full pipeline; `beginDictation` /
  `endDictation` / `cancelDictation`; history save is best-effort (failure
  does not fail the dictation)

### Global hotkey (P5)

- `HotkeyMonitor` — `CGEventTap`-based global Fn detection; spawns a private
  CFRunLoop thread; emits `HotkeyEvent` (`startCapture` / `stopCapture`) via
  `AsyncStream`
- `DoubleTapDetector` — pure value-type double-tap state machine; timestamps
  injected for full testability; 0.4 s default window (tunable)
- `HotkeyBinding : Codable` — custom Codable for `CGEventFlags`; persisted via
  `UserDefaultsBindingStore`
- Default binding: double-tap `kVK_Function` (0x3F) = start, single-tap = stop

### Paste at cursor (P6)

- `TextInserting` protocol — the paste-seam abstraction; `CaptureSession`
  calls it; tests inject a mock
- `PasteboardWriter : TextInserting` — `NSPasteboard.general.clearContents()`
  + `setString(_:forType:.string)` (write-only; never reads) + `CGEvent`
  Cmd+V simulation via `.cghidEventTap`

### Local history (P9)

- `HistoryEntry` — `Sendable, Identifiable, Equatable` value type; raw text,
  cleaned text, timestamp, engine ID, locale
- `HistoryStore` actor — SQLite3 via raw C API; `save` / `recent(limit:)` /
  `search(_:)` / `clear()` / `export()` all `async throws`; capacity-trimming
  with `defaultHistoryMaxEntries = 10_000`

### Settings (P10)

- `SettingsStore` — typed, observable `UserDefaults` wrapper; injectable
  defaults for test isolation; `cleanupEnabled`, `cleanupEngine`, `sttEngine`,
  `language`, `pasteMode`, `hasCompletedOnboarding`
- `EngineFactories` — `defaultTranscriber(for:)` / `defaultCleaner(for:)`
  per architecture §10.1; unbuilt engines log + fall back gracefully
- Settings window (SwiftUI) — cleanup toggle, engine/language/paste-mode
  pickers, hotkey display; wired into the menu

### Partial-transcript overlay (P4)

- `TranscriptOverlayPanel` (`NSPanel`, `.nonactivatingPanel` + `.floating`,
  all-spaces, never steals focus)
- `OverlayTextAccumulator` — pure value type; newest-non-empty chunk wins
- Wired to `DictationController`: shows on `.listening`, hides on
  `.done` / `.error`

### Menubar states (P8)

- `MenubarIcon` — pure enum; reactive label reflecting all four states
  (idle → listening → processing → done flash → idle)
- `DictationController` sets `.processing` before `endDictation` so all
  four transitions surface visually

### Permissions onboarding (P7)

- `OnboardingStateMachine` — pure, headless `evaluate(...)` function; 6-step
  enum (`welcome` / `microphone` / `accessibility` / `inputMonitoring` /
  `hotkey` / `done`)
- `OnboardingViewModel` — `@MainActor ObservableObject`; polls TCC at 1.5 s;
  auto-advances on grant
- `OnboardingView` — SwiftUI flow with per-step states (loading, needs-grant,
  granted); "Skip for now" footer
- `OnboardingWindowController` — `NSWindow + NSHostingView`; auto-close 1.5 s
  after `.done`
- `PermissionManager.inputMonitoring` wired via
  `IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)` (IOKit.hid)
- Revocation path: `showOnboardingIfNeeded()` called at start and in every
  permission-denied catch block

### App-shell wiring (P10 end-to-end)

- `DictationController` (`@MainActor ObservableObject`) — builds the
  production `SpeakEngine`, owns `HotkeyMonitor`, drives the full
  dictation → overlay → paste → history loop
- Graceful degradation: `HistoryStore` failure → `NullHistoryStore` (dictation
  unaffected); permission-denied → `permissionsNeeded` flag + System Settings
  deep-link, no crash

### Structural moat audit (P11 prerequisite)

- `MoatAuditTests` (9 XCTest tests) — permanent regression guard on the seven
  BEAT moat rows: MIT license, Apple-only imports, no network egress, no
  auth/account code, no paywall/wordcap, offline by construction, no pasteboard
  reads, no bare `print`, no force-unwrap in production code
- `scripts/verify-moat.sh` + `make verify-moat` — standalone shell audit;
  7/7 checks; runs without Xcode; re-runnable in CI as a pre-build step

### Latency and accuracy harness (P11 prerequisite)

- `LatencyAndAccuracyTests` — headless latency: first-partial p50 ≈ 42 ms,
  p95 ≈ 43 ms (budget < 200 ms); local stop→result-ready median ≈ 60 ms
  (budget < 1 s). File-fed proxy figures; live paste latency is deferred.
- `WERHarnessTests` — WER harness correctness (8 tests); corpus is a human
  data dependency

---

## Upcoming

### v0 (ship gate — all must pass before release)

Tracked in [`docs/human-verification.md`](docs/human-verification.md):
- Live paste into TextEdit, Slack, and Terminal (Terminal paste-provenance)
- Global hotkey with Accessibility permission granted
- Apple Intelligence / Foundation Models live cleanup quality
- WER corpus (~20 clips, human-supplied)
- Developer ID signing + notarization (`make release`)
- Demo GIF — `[deferred — needs human verification]`

### v1 (planned)

More languages (SpeechAnalyzer locales; WhisperKit for the long tail); richer
cleanup (tone/style modes, per-app formatting, custom dictionary/snippets);
pluggable models surfaced in UI (Ollama/WhisperKit); onboarding/overlay polish;
latency tuning; Intel Mac via whisper.cpp.

### v2 (planned)

Voice editing/commands via local LLM; code-aware mode; local cross-device
continuity (opt-in, never account-mandatory).
