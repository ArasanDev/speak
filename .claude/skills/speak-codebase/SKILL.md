---
name: speak-codebase
description: Complete orientation for any agent starting work on the speak codebase. Covers product identity, full source tree, every key type and its role, the state machine, data flow, hard constraints, build system, testing patterns, and the agent loop protocol. Read this before reading anything else — it replaces an hour of grepping.
---

# speak — Complete Codebase Orientation

Read this once at session start. It encodes everything a fresh agent needs to make a correct
first commit without reading 4,000 lines of history or misidentifying a file.

---

## 0. Product identity (one paragraph)

`speak` is a macOS-native, local-first, free, open-source voice dictation app — speech → on-device
AI neat-writing → pasted at the cursor. It is the private, offline alternative to Wispr Flow
($15/mo, cloud-only). The app lives in the menubar. Double-tap Fn → talk → single-tap Fn →
cleaned text appears in the focused field. 100% Apple frameworks. No accounts, no cloud audio,
no telemetry, works offline. The directory is named `deepvoice` for historical reasons; the
product is `speak`. Do not build anything from `research/sample-ideation.md` — that idea is
abandoned.

**What it is NOT:** a coding agent, chatbot, voice assistant, meeting scribe, or cross-platform app.

---

## 1. Hard constraints (the moat — never trade these away)

Violating any of these is a blocker, not a style issue. `make verify-moat` catches #1–#5 and #7
as static source audits (7/7 must pass before commit).

| # | Constraint | Where enforced |
|---|-----------|----------------|
| 1 | 100% local by default. No cloud audio, no telemetry, no accounts, offline. | `MoatAuditTests.swift` + `verify-moat.sh` |
| 2 | Two OS permissions only: Microphone + Accessibility. No Input Monitoring in v0. | `PermissionTypes.swift`, onboarding flow |
| 3 | Swift 5.9+ / SwiftUI, macOS 26.0 deployment, Apple Silicon only. | `project.yml` deployment target |
| 4 | No third-party deps in v0. Apple frameworks only. Ollama/WhisperKit/MLX are v0.1+ stubs. | `MoatAuditTests`, `project.yml` |
| 5 | Single Swift codebase. No Rust, no FFI, no cross-platform abstraction. | architecture settled |
| 6 | Never read the pasteboard — only write. `PasteboardWriter` is write-only by design. | `MoatAuditTests.testNoPasteboardRead` |
| 7 | Hardware mute: when muted, no audio captured. `SpeakEngine.beginDictation` refuses. | `SpeakEngineMuteTests` |
| 8 | v0 = complete core, not a time-box. Done when `benchmark.md` §4 MATCH + §3 BEAT + `quality.md` §9 all pass. | — |
| 9 | AI neat-writing is core, not optional. Default = Apple Foundation Models (on-device). Pluggable via `LLMCleaning`. | `CaptureSession+Cleanup.swift` |

**Coding rules (each is a build error in `.swiftlint.yml`):**
- No `print` anywhere. Use `SpeakLog.<category>.<level>(...)` — categories defined in `SpeakCore/Logging/SpeakLog.swift`.
- No force-unwrap (`!`), no `try!`, no `as!` in production code. Test files only.
- No global mutable state. State lives in actors or SwiftUI environment.
- Never block the main thread.
- `[weak self]` in all long-lived/escaping closures that capture `self`.

---

## 2. Source tree

The repo has three build targets: `Speak` (app shell), `SpeakCore` (framework), `SpeakTests`.
`Speak.xcodeproj` is git-ignored — generated at build time from `project.yml` by XcodeGen.

### `App/` — UI shell (Speak target)

```
SpeakApp.swift                  # AppDelegate + MenuBarExtra root. Single-instance guard.
DictationController.swift       # @Observable. Top-level coordinator: owns SpeakEngine,
                                #   drives icon, overlay, and paste. App lifetime.
DictationController+CLI.swift   # CLI command handler (cliBeginDictation / cliEndDictation).
DictationController+ErrorHandling.swift  # beginDictation / endDictation error routing.

Overlay/
  OverlayController.swift       # Shows/hides TranscriptOverlayPanel on state changes.
  TranscriptOverlayPanel.swift  # NSPanel (non-activating, always-on-top).
  TranscriptOverlayView.swift   # SwiftUI view inside the panel. Streams partial text.

History/
  HistoryView.swift             # SwiftUI list: search, clear, export. Bound to HistoryViewModel.
  HistoryViewModel.swift        # @Observable. Mediates between HistoryView and HistoryStore.
  HistoryWindowController.swift # NSWindowController that presents HistoryView.

Onboarding/
  OnboardingView.swift          # Three-step permission grant flow (mic → accessibility → done).
  OnboardingViewModel.swift     # @Observable. Owns OnboardingStateMachine.
  OnboardingWindowController.swift

Settings/
  SettingsView.swift            # TabView: General / Transcription / AI Cleanup / Shortcuts.
  HotkeyRecorderView.swift      # Records a key combo for hotkey rebinding.
  OllamaSetupSheet.swift        # Sheet for configuring the Ollama endpoint (v0.1 stub UI).

Dashboard/
  DashboardView.swift           # Full-window navigation shell (pane switcher).
  DashboardWindowController.swift
  DashboardContext.swift        # @Observable context threaded to all panes.
  DashboardSection.swift        # Enum of navigation sections.
  PaneScaffold.swift            # Reusable pane layout chrome.
  Panes/
    HomePaneView.swift          # Welcome + quick stats.
    HistoryPaneView.swift       # History tab inside the dashboard.
    DictionaryPaneView.swift    # Custom vocabulary list.
    SnippetsPaneView.swift      # Text expansion snippet editor.
    InsightsPaneView.swift      # Word count / WPM trends.
    StylePaneView.swift         # Cleanup style + level picker.
    ScratchpadPaneView.swift    # Ephemeral text scratchpad.
    TransformsPaneView.swift    # Placeholder for V1-3 transforms.

CommandMode/
  AccessibilitySelection.swift  # Reads selected text from frontmost app via AX API.
  CommandModeController.swift   # Orchestrates Command Mode (select text → voice transform).

Components/
  CleanupDiffView.swift         # Shows before/after diff of cleanup with [Accept]/[Revert].
  KeyCapView.swift              # Visual key-cap widget for the Settings/Shortcuts tab.

Theme/
  SpeakTheme.swift              # Monaco font + colors. The locked design system.

Scratchpad/
  Scratchpad.swift              # Lightweight ephemeral text store (not persisted to DB).

WindowPresenter.swift           # @MainActor. Utility for opening/closing named NSWindows.

Debug/
  DebugLaunchDispatcher.swift   # Routes --debug-open flags for dev/test launches.
```

### `SpeakCore/` — Framework (SpeakCore target)

```
Engine/
  SpeakEngine.swift             # actor. Top-level facade: beginDictation / endDictation / cancelDictation.
  CaptureSession.swift          # actor. Owns one dictation: state machine, STT stream consumption.
  CaptureSession+Cleanup.swift  # runCleanup() — the LLM cleanup pipeline step.
  CaptureSession+Paste.swift    # runPaste() — the paste delivery step (calls inserter).
  EngineFactories.swift         # defaultTranscriber(for:) / defaultCleaner(for:) — factory fns.
  SpeakError.swift              # enum SpeakError — all error cases with .code + .recoverySuggestion.
  TranscriptionResult.swift     # struct. Output of a completed session: rawText, cleanedText?, engineId.
  OverlayText.swift             # OverlayTextAccumulator — merges partial + final chunks for overlay.
  MenubarIcon.swift             # enum MenubarIcon: maps CaptureSession.State → SF symbol name.
  LatencyRecord.swift           # struct. stop→paste latency breakdown (L_e2e measurement).

STT/
  Transcriber.swift             # protocol Transcribing + struct TranscriptChunk. The STT seam.
  AppleSpeechTranscriber.swift  # Conformer: Apple SpeechAnalyzer. The v0 default STT engine.
  AudioCaptureProviding.swift   # protocol AudioCaptureProviding — testability seam for AudioCapture.
  SpeechPrewarmer.swift         # Warms up the SpeechAnalyzer session before first use.
  LocaleSupport.swift           # Enumerates SpeechAnalyzer installed locales.

Cleanup/
  Cleaner.swift                 # protocol LLMCleaning + enum CleanupMode / CleanupStyle / CleanupLevel.
  FoundationModelsCleaner.swift # Conformer: Apple Foundation Models (on-device, v0 default).
  OllamaCleaner.swift           # Stub conformer: always isAvailable=false in v0.
  MLXCleaner.swift              # Stub conformer: always isAvailable=false in v0.

Audio/
  AudioCapture.swift            # actor. AVAudioEngine tap → AsyncStream<AVAudioPCMBuffer>.
                                #   Also emits AsyncStream<Double> for RMS level (overlay meter).

Hotkey/
  HotkeyMonitor.swift           # @unchecked Sendable + NSLock. CGEventTap. Detects double-tap Fn.
  HotkeyDetection.swift         # DoubleTapDetector: pure timestamp logic (testable, no OS).
  HotkeyBinding.swift           # struct HotkeyBinding: keyCode, modifiers, trigger, doubleTapWindow.
  BindingStore.swift            # protocol BindingStoring + UserDefaultsBindingStore.

Paste/
  PasteboardWriter.swift        # Writes to NSPasteboard then simulates Cmd+V. NEVER reads.
  TextInserting.swift           # protocol TextInserting. The paste seam injected into CaptureSession.
  StreamingTextInserting.swift  # protocol StreamingTextInserting (for real-time chunk insertion).
  SecureFieldDetector.swift     # Detects secure text fields via AX. Blocks paste into password fields.

Permissions/
  PermissionManager.swift       # Checks + requests Microphone and Accessibility permissions.
  PermissionTypes.swift         # enum PermissionKind (microphone, accessibility) + PermissionState.
  OnboardingState.swift         # OnboardingStateMachine: 14-state machine for the onboarding flow.

Storage/
  SettingsStore.swift           # @Observable + @unchecked Sendable. Typed UserDefaults wrapper.
                                #   Owns: STTEngine, CleanupEngine, PasteMode, language, hotkey, vocab, etc.
  HistoryStore.swift            # actor. SQLite3 (raw C API). Stores HistoryEntry records.
  HistoryStoring.swift          # protocol HistoryStoring — testability seam for HistoryStore.
  HistoryEntry.swift            # struct. One dictation record: rawText, cleanedText?, timestamp, engineId.

Snippets/
  Snippet.swift                 # struct Snippet: trigger + expansion.
  SnippetStore.swift            # @Observable. In-memory store for text expansion snippets.
  SnippetExpander.swift         # protocol SnippetExpanding. Expands triggers in raw transcript.

Insights/
  InsightsStats.swift           # Word count, WPM, session count stats derived from HistoryEntry[].
  LatencyStats.swift            # Latency percentile stats derived from LatencyRecord[].

Overlay/
  LevelMath.swift               # RMS→normalized level math for the overlay waveform meter.

Diff/
  TextDiff.swift                # Word-level diff between rawText and cleanedText (for CleanupDiffView).

Vocabulary/
  CustomVocabulary.swift        # Helpers for the custom vocabulary list injected into SpeechAnalyzer.

CLI/
  CLIContract.swift             # CLIRequest / CLIReply types shared by CLI client + server.
  CLIPortServer.swift           # CFMessagePort server in the app; routes start/stop commands.

CommandMode/
  CommandModeService.swift      # Orchestrates voice-command mode: read selection → clean → replace.

Logging/
  SpeakLog.swift                # All os.Logger categories: engine/audio/stt/cleanup/hotkey/paste/etc.

Debug/
  FixtureAudioProducer.swift    # Produces audio from .caf fixture files for headless tests.
```

### `SpeakTests/` — Test suite (SpeakTests target)

```
Support/
  TestStorage.swift             # TestStorage.tempDatabaseURL() + withTempDir{} — use instead of
                                #   ad-hoc UUID temp files. 14 files still use the old pattern.

CaptureSessionTests.swift       # State machine + cleanup contract
EngineCoreTests.swift           # SpeakEngine begin/end/cancel paths
SpeakEngineIntegrationTests.swift  # Real components, temp DB, end-to-end result
SpeakEngineLanguageTests.swift  # Language setting propagation
SpeakEngineMuteTests.swift      # Hardware mute blocks transcriber start
SpeakEngineCleanupLevelTests.swift  # CleanupLevel.none fast path

HistoryStoreTests.swift         # SQLite round-trip, persistence, search, export
SettingsStoreTests.swift        # UserDefaults round-trip for every property
SettingsStoreRoundTripTests.swift

HotkeyMonitorTests.swift        # CGEventTap integration + DoubleTapDetector
CommandChordDetectorTests.swift  # Command mode chord detection
MoatAuditTests.swift            # Source-level moat: no egress, no third-party, no auth
PasteTests.swift                # PasteboardWriter + TextInserting injection
OverlayTextTests.swift          # OverlayTextAccumulator partial/final merge
OverlayDurationTests.swift      # Overlay show/hide timing
OverlayControllerTests.swift    # OverlayController state-driven show/hide
OverlayLevelTests.swift         # RMS level math

OnboardingFlowTests.swift       # OnboardingStateMachine 14-state path
OnboardingViewModelLifecycleTests.swift
OnboardingViewModelDoublePromptTests.swift
PermissionTests.swift           # PermissionManager states
TranscriptOverlayPanelTests.swift  # NSPanel creation + wiring (H2 test host)
WindowPresenterTests.swift

MenubarIconTests.swift          # MenubarIcon(for: state) → SF symbol (parameterized Swift Testing)
InsightsStatsTests.swift        # Word count / WPM calculations
LatencyRecordTests.swift        # LatencyRecord arithmetic
LatencyAndAccuracyTests.swift   # Headless latency proxy measurements

StyleModeTests.swift            # CleanupStyle / CleanupLevel picker coverage
TextDiffTests.swift             # Word-level diff correctness
FoundationModelsCleanerTests.swift  # 5 XCTSkip (live Foundation Models path)
SpeechTranscriberTests.swift    # AppleSpeechTranscriber (some XCTSkip)
InputValidationFixTests.swift   # Edge cases for input validation
CLIContractTests.swift          # CLIRequest/CLIReply encode/decode
CustomVocabularyTests.swift     # Custom vocab injection into SpeechAnalyzer context
SnippetTests.swift              # SnippetExpander trigger matching
ScratchpadTests.swift           # Scratchpad store behaviour
CommandModeServiceTests.swift   # CommandModeService orchestration
SessionIntegrityTests.swift     # Cross-cutting session integrity assertions
PhaseARearmTests.swift          # Hotkey rearming after a dictation
```

---

## 3. Key types and relationships

### The two core protocols (the pluggability seams)

```swift
// SpeakCore/STT/Transcriber.swift
public protocol Transcribing: Sendable {
    var id: String { get }
    func startStream(locale: Locale) -> AsyncThrowingStream<TranscriptChunk, Error>
    func stop() async
}
// v0 conformer: AppleSpeechTranscriber (SpeechAnalyzer)
// v0.1 planned: WhisperKitTranscriber | SarvamSpeechTranscriber

// SpeakCore/Cleanup/Cleaner.swift
public protocol LLMCleaning: Sendable {
    var id: String { get }
    var isAvailable: Bool { get async }
    func clean(_ text: String, mode: CleanupMode) async throws -> String
}
// v0 conformer: FoundationModelsCleaner
// v0 stubs (always isAvailable=false): OllamaCleaner, MLXCleaner

// SpeakCore/Paste/TextInserting.swift
public protocol TextInserting: Sendable {
    func insert(_ text: String) async throws
}
// v0 conformer: PasteboardWriter (write-only, never reads)
```

### State machine (`CaptureSession.State`)

```
idle ──start()──► listening ──stop()──► processing ──► done
  ▲                  │                     │
  │                  │ cancel()            │ cleanup fails (only genuine error)
  └──────────────────┴─────────────────────┴──► error(SpeakError)
```

Key contract: cleanup **unavailability** (`isAvailable == false`) is NOT an error — it falls
back to raw transcript and still reaches `.done`. Only a genuine API failure (`clean()` throws)
becomes `.error(.llmCleanupFailed)`.

### Actor hierarchy

```
DictationController (@Observable, @MainActor)
  └── SpeakEngine (actor)
        └── CaptureSession (actor, one per dictation)
              ├── any Transcribing       — injected (AppleSpeechTranscriber in v0)
              ├── (any LLMCleaning)?     — injected (FoundationModelsCleaner or nil)
              ├── (any TextInserting)?   — injected (PasteboardWriter in live app, nil in tests)
              └── (any SnippetExpanding)? — injected (SnippetExpander or nil)
```

### Factory functions (not methods — avoids layering inversion)

```swift
// SpeakCore/Engine/EngineFactories.swift
func defaultTranscriber(for settings: SettingsStore) -> any Transcribing
func defaultCleaner(for settings: SettingsStore) -> (any LLMCleaning)?
```

### `SpeakError` — the one error type

All engine errors go through `SpeakError`. Always log with `.code`:
```swift
SpeakLog.engine.error("failed: \(error.code, privacy: .public) — \(error.localizedDescription, privacy: .public)")
```
The app shell has specific catches for `.microphoneMuted` (stay idle), `.pasteRequiresAccessibility`
(route text to Scratchpad + set permissionsNeeded), and `.pasteIntoSecureField` (route to Scratchpad).
Generic `.error` path shows the menubar error icon.

### `SettingsStore` — the settings hub

`@Observable` + `@unchecked Sendable`. Key properties:
- `cleanupEnabled: Bool` — whether to run the LLM pass
- `cleanupLevel: CleanupLevel` — none/light/medium/high (`.none` skips the cleaner entirely)
- `cleanupStyle: CleanupStyle` — default/professional/casual/code/email
- `sttEngine: STTEngine` — appleSpeech (v0) / whisperKit / whisperCpp (stubs)
- `cleanupEngine: CleanupEngine` — foundationModels (v0) / ollama(model:) / mlx(model:) (stubs)
- `language: String` — locale string, e.g. `"en-US"`
- `pasteMode: PasteMode` — cmdV (v0) / accessibility (v1 stub)
- `customVocabulary: [String]` — injected into SpeechAnalyzer contextualStrings
- `cleanupEnabled: Bool` driven by `cleanupLevel != .none` as the primary source

**Read at `newSession()` time** — not baked into `SpeakEngine.init`. Changes take effect on the
next dictation with no restart.

### Logging

```swift
SpeakLog.engine      SpeakLog.audio      SpeakLog.stt        SpeakLog.cleanup
SpeakLog.hotkey      SpeakLog.paste      SpeakLog.permissions SpeakLog.storage
SpeakLog.cli         SpeakLog.app        SpeakLog.overlay
```
Filter in Console.app: `subsystem == "com.speak.app"`.

---

## 4. Data flow (a complete dictation)

```
1. User double-taps Fn
   HotkeyMonitor (CGEventTap) → DoubleTapDetector.didDoubleTap()
   → DictationController.handleHotkey()

2. DictationController.beginDictation()
   → SpeakEngine.beginDictation()
   → SpeakEngine.newSession() reads SettingsStore: locale, cleanupEnabled, style/level, vocab
   → CaptureSession(transcriber:cleaner:inserter:expander:) constructed
   → CaptureSession.start()

3. Audio + STT pipeline
   AudioCapture (AVAudioEngine tap) → AsyncStream<AVAudioPCMBuffer>
   → AppleSpeechTranscriber.startStream(locale:) → AsyncThrowingStream<TranscriptChunk>
   → CaptureSession consumes chunks:
       isFinal=false → OverlayTextAccumulator.ingest() → overlay updates
       isFinal=true  → finalizedText appended

4. User single-taps Fn
   → DictationController.endDictation()
   → SpeakEngine.endDictation()
   → CaptureSession.stop()

5. Processing phase
   → CaptureSession.runCleanup() (CaptureSession+Cleanup.swift)
       if cleaner != nil && cleaner.isAvailable → cleaned = try await cleaner.clean(raw, mode)
       else → cleaned = nil (graceful fallback)
   → CaptureSession.runPaste() (CaptureSession+Paste.swift)
       text = cleanedText ?? rawText
       → inserter.insert(text) → PasteboardWriter.insert()
           NSPasteboard.general.setString(text)
           CGEvent Cmd+V simulation

6. Done
   → TranscriptionResult(rawText:cleanedText?:duration:engineId:latency:) returned
   → SpeakEngine.endDictation saves to HistoryStore (best-effort, never fails the call)
   → DictationController drives menubar icon: .done (green flash 600ms) → .idle
```

---

## 5. Build system

The canonical build is XcodeGen → Xcode:

```bash
make build          # xcodegen generate → xcodebuild build (Debug)
make test           # xcodebuild test (481 tests, 0 failures as of loop #35)
make lint           # swiftlint (force-unwrap/cast/try = build errors)
make verify-moat    # bash scripts/verify-moat.sh — 7/7 structural checks
make run            # build + open Speak.app
make install        # build + cp -r Speak.app /Applications/
make github-release # build Release + ad-hoc sign + ditto zip → build/release/Speak.zip
make dev-cert       # ONE-TIME: create speak-local-codesign cert (TCC grants persist)
make reset-permissions  # clear TCC grants (after identity change)
make lsp            # configure buildServer.json for SourceKit-LSP
make fmt            # swift-format (brew install swift-format)
make release        # Developer ID sign + notarize + .dmg (needs DEV_ID + NOTARY_PROFILE)
```

**XcodeGen:** `project.yml` is canonical. `Speak.xcodeproj` is git-ignored and generated by
`make build` automatically. A clean clone needs `brew install xcodegen` first.

**Targets:**
- `Speak` — app bundle (`App/` sources, links `SpeakCore.framework`)
- `SpeakCore` — framework (`SpeakCore/` sources)
- `SpeakTests` — test host (`SpeakTests/`, TEST_HOST=Speak for integration tests)

**CI check:** `make build` → `make test` → `make lint` → `make verify-moat` — all four must pass
before any commit. A partial-green commit is not done.

---

## 6. Testing patterns

### Use Swift Testing for all new tests

38 files use XCTest. New tests use Swift Testing (`@Test`, `#expect`, `#require`). Migrate old
files as you touch them — pure value-type tests first.

```swift
// Parameterized — use instead of N individual test functions
@Test("MenubarIcon maps state", arguments: [
    (CaptureSession.State.idle, MenubarIcon.idle),
    (.listening, .listening),
])
func iconMapping(state: CaptureSession.State, expected: MenubarIcon) {
    #expect(MenubarIcon(for: state) == expected)
}
```

### TestStorage for temp files

```swift
// Old (13 files still use this — migrate when you touch them)
let url = FileManager.default.temporaryDirectory.appendingPathComponent("test-\(UUID().uuidString).sqlite")
addTeardownBlock { try? FileManager.default.removeItem(at: url) }

// New — always use this
let url = TestStorage.tempDatabaseURL()
try await TestStorage.withTempDir { dir in ... }
```

### Mock only at protocol boundaries

Tests use real `HistoryStore`, real `AudioCapture`, real `SettingsStore(defaults: freshSuite)`.
Never mock concrete types. Mock only by injecting a protocol conformer:
```swift
// ✓ Inject a mock at the LLMCleaning seam
let session = CaptureSession(transcriber: realTranscriber, cleaner: MockCleaner(), ...)
// ✗ Don't mock HistoryStore — it's a thin SQLite actor; use a real one on a temp file
```

### XCTSkip patterns

5 tests use `XCTSkip` on the Foundation Models live path (Apple Intelligence must be enabled).
All 5 are in `FoundationModelsCleanerTests.swift` and `SpeechTranscriberTests.swift`. These are
intentional — they require a Mac with Apple Intelligence active.

---

## 7. Concurrency patterns

**Actors for stateful services:** `SpeakEngine`, `CaptureSession`, `AudioCapture`, `HistoryStore`
are all actors. New stateful services should be actors, not `@unchecked Sendable final class`.

**`@unchecked Sendable` + `NSLock` only for C-backed types** (CFMachPort, CGEventTapProxy):
```swift
private nonisolated(unsafe) let port: CFMachPort
private let lock = NSLock()
```

**`AsyncStream` bridges over callbacks:**
```swift
let stream = AsyncStream<AVAudioPCMBuffer> { cont in
    engine.installTap { buffer, _ in cont.yield(buffer) }
}
```

**`@MainActor` over `DispatchQueue.main.async`** everywhere new.

**`@Observable` (not `ObservableObject`)** for all `@MainActor` view models. Migration complete
as of loop #33 — all 6 classes migrated. Call sites use plain `let` (no `@ObservedObject`),
`@Bindable` for two-way bindings.

---

## 8. File / naming conventions

- **One type per file. Filename = type name.** `HotkeyMonitor` lives in `HotkeyMonitor.swift`.
- **Extension-per-responsibility:** `CaptureSession.swift` (core) + `CaptureSession+Cleanup.swift`
  + `CaptureSession+Paste.swift`. Large types split this way; don't let a file exceed ~400 lines.
- **Protocol in same module as primary implementor.** `Transcribing` and `AppleSpeechTranscriber`
  are both in `SpeakCore/STT/`. Never a separate `Protocols/` folder.
- **No magic numbers.** Every constant traces to a measured value, a platform constraint, or a
  `[decision]` in `benchmark.md §7`.

---

## 9. Tagging convention (critical for multi-agent trust)

Every Apple API claim must be tagged:

| Tag | Meaning | Trust |
|-----|---------|-------|
| `[verified via swiftc]` | Confirmed against local macOS 26 SDK via `swiftc -typecheck` | Ground truth |
| `[verified from: <URL>]` | Confirmed from official docs/source at that URL | High |
| `[verified]` | Confirmed, source cited elsewhere in same file | High |
| `[inferred]` | Derived by reasoning from verified facts — verify before shipping | Low |
| `[unverified]` | Needs verification before relying on it | Do not use |
| `[decision]` | A product/design choice, not an empirical fact | Trust as design |

If a `[verified]` claim contradicts a primary source: **stop and surface it** — do not paper over.

**Before using any Apple framework API:** run
```sh
swiftc -typecheck -sdk "$(xcrun --show-sdk-path)" -target arm64-apple-macosx26.0 probe.swift
```

---

## 10. Current state (as of loop #35, 2026-06-28)

**All gates green:** build ✅ lint ✅ moat 7/7 ✅ tests 481/0 ✅

**What is fully built and verified (code-level):**
- Core pipeline: AudioCapture → AppleSpeechTranscriber → FoundationModelsCleaner → PasteboardWriter
- Hotkey: CGEventTap double-tap Fn detection (pure logic tested, live deferred)
- Overlay: partial transcript streaming via AsyncStream → NSPanel
- History: SQLite actor, search, export, round-trip
- Settings: all properties persisted, `@Observable` migration complete
- Permissions: OnboardingStateMachine (14 states, 14 tests)
- Dashboard: full-window navigation with all panes scaffolded
- CLI: CFMessagePort IPC (start/stop from command line)
- Command Mode: voice-command select+transform via AX
- Snippets, Custom Vocabulary, Scratchpad, Insights, TextDiff, CleanupDiff — all built + tested

**What is deferred (needs human/live environment):**
- Live paste into TextEdit, Slack, Terminal — **Terminal paste-provenance is #1 unverified item**
- Live hotkey firing while another app has focus
- Live Foundation Models cleanup quality (requires Apple Intelligence enabled)
- Live onboarding visual flow
- Demo GIF
- P11-b: Developer ID cert (blocks official Homebrew cask; not a v0 blocker)
- P13 dogfood (human sustained-use with latency measurement)
- P14 top-3 dogfood bug fixes

**Next agent-executable tasks:**
- P12 remaining item: Demo GIF (needs live run by human — then agent can update README)
- V01-0: Agent Mode (V0 ship gate is pre-requisite — human-gate items must close first)

---

## 11. Agent loop protocol

Every cycle:
1. Read `docs/progress.md` (last 80 lines) — current state
2. Read `docs/roadmap.md` — lowest-numbered `[ ]` with met dependencies
3. Load the relevant skill(s) from `.claude/skills/` for that seam
4. **Research first:** verify any `[inferred]`/`[unverified]` API claim via `swiftc -typecheck`
   or `apple-docs` MCP before writing code
5. Implement + tests together (never one without the other)
6. Run all four gates: `make build` · `make test` · `make lint` · `make verify-moat`
7. Update `docs/progress.md` — mark done, note what's next
8. Commit: `git commit -m "[P<N>] <task>: <what changed>"`

**Specialist routing (never commit from a subagent — orchestrator commits):**

| Agent | Seam |
|-------|------|
| `builder-engine` | `SpeakCore/Engine/` |
| `builder-audio-stt` | `SpeakCore/Audio/`, `SpeakCore/STT/` |
| `builder-cleanup` | `SpeakCore/Cleanup/` |
| `builder-input` | `SpeakCore/Hotkey/`, `SpeakCore/Paste/`, `SpeakCore/Permissions/` |
| `builder-app` | `App/`, `SpeakCore/Storage/` |
| `builder-release` | `project.yml`, `Makefile`, CI |
| `builder-qa` | `SpeakTests/`, benchmarks |

If the same agent fails 3× on the same task: STOP. Rewrite the context (brief/skill), not the
prompt. The problem is always context, never retries.

---

*End of codebase orientation. Load a seam-specific skill next if implementing a specific area.*
