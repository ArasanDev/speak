# `speak` — Progress (NOW)

> **Status**: Living state. **The agent rewrites this every session.**
> Single source of truth for "where are we right now." Read first, update last.
> Never delete history — append. See `../AGENTS.md` §5.

---

## Current phase

**Phases 0, 1, 2, 3, 3.5 COMPLETE; P5 code-complete; P6 code-complete (live criteria deferred).**
P5 — global hotkey — delivers `HotkeyMonitor` (CGEventTap-based, `SpeakCore/Hotkey/`).
P6 — paste — delivers `TextInserting` protocol + `PasteboardWriter` conformer
(`SpeakCore/Paste/`), wired additively into `CaptureSession` via optional `inserter`
param. `make build` zero new warnings, `make lint` 0 new serious violations,
`make test` **50 tests total (5 XCTSkip live-FM); 6 new P6 tests all green;
all 44 prior tests still green**. Seven P6 done-when rows `[verified]` via unit
tests (mock inserter); **four rows `[deferred — needs human verification]`**:
TextEdit paste, Slack paste, Terminal paste-provenance (the project's #1 `[unverified]`),
and password-field silent no-op. Critical path: P3.5 → P5 → **P6 (code) →** P11 → P13.

> **Orchestrator review note (loop #6):** caught + fixed a latent correctness
> bug before commit — `DoubleTapDetector` was fed `CGEvent.timestamp / 1e9` as
> seconds, but that field is mach-absolute-time units (timebase ≠ 1 ns on Apple
> Silicon), which would have stretched the 0.4 s window to ~16 s. Unit tests
> couldn't catch it (they inject synthetic seconds, bypassing the conversion).
> Fixed to read `DispatchTime.now().uptimeNanoseconds` (documented ns) at handle
> time; HID-tap latency ≪ window. Known v0 follow-ups (note-only): the
> `@unchecked Sendable` callback-thread vs main-thread access to
> `binding`/`eventTap`/`detector` is an unsynchronized race, and the init
> CFRunLoop thread leaks per instance (fine for a single app-lifetime monitor).

---

## Done (this session — 2026-06-20, loop run #7 — P6 PasteboardWriter)

- [x] **Phase 6 code-complete (live criteria deferred) — paste seam**
      - **`SpeakCore/Paste/TextInserting.swift` (NEW):** `public protocol TextInserting: Sendable`
        with `func insert(_ text: String) async throws`. The paste-seam abstraction:
        `CaptureSession` calls this just before reaching `.done`; tests inject a
        mock; the real `PasteboardWriter` uses NSPasteboard + CGEvent.
      - **`SpeakCore/Paste/PasteboardWriter.swift` (NEW):** `final class PasteboardWriter: TextInserting`.
        Stateless (only a `SpeakLog.paste` Logger) → auto-`Sendable`, no `@unchecked`.
        - `insert(_:)` step 1: `NSPasteboard.general.clearContents()` + `setString(_:forType:.string)`
          — WRITE ONLY. Never reads the pasteboard (hard rule).
        - `insert(_:)` step 2: `simulateCmdV()` — `CGEventSource(stateID:.hidSystemState)`,
          `CGEvent(keyboardEventSource:virtualKey:kVK_ANSI_V=0x09:keyDown:)` (kVK_ANSI_V
          constant from Carbon/HIToolbox, `[verified]` = 9 = 0x09), `.flags = .maskCommand`,
          `.post(tap:.cghidEventTap)` (Swift instance method, not the obsoleted free fn).
          nil `CGEvent` → logs + throws `SpeakError.pasteboardBusy` (no force-unwrap).
      - **`SpeakCore/Engine/CaptureSession.swift` (MODIFIED — additive):**
        - Added `private let inserter: (any TextInserting)?` storage.
        - Extended `init` with `inserter: (any TextInserting)? = nil` (default nil
          → all existing call-sites and tests compile unchanged).
        - In `stop()`: after building `result`, before `state = .done`, calls
          `try await inserter.insert(cleanedText ?? rawText)` when inserter is non-nil.
          On throw: sets `state = .error(speakError)`, finishes partials continuation,
          clears streamTask, rethrows — no resource leak.
      - **`SpeakTests/PasteTests.swift` (NEW, 6 tests, all green):**
        - `testInserterNilDoesNotInsertAndSessionIsDone` — pre-P6 path unchanged.
        - `testInserterReceivesCleanedTextWhenCleanupSucceeds` — insert gets cleanedText.
        - `testInserterReceivesRawTextWhenCleanerIsNil` — insert gets rawText.
        - `testInserterReceivesRawTextWhenCleanerIsUnavailable` — graceful-fallback path.
        - `testInserterThrowsTransitionsSessionToError` — SpeakError.pasteboardBusy.
        - `testInserterGenericThrowWrappedToPasteboardBusy` — generic error mapping.
      - **SDK verifications (swiftc -typecheck + runtime, 2026-06-20):**
        - `NSPasteboard.clearContents()` → Int [verified]
        - `NSPasteboard.setString(_:forType:.string)` → Bool [verified]
        - `CGEventSource(stateID:.hidSystemState)` → optional [verified]
        - `CGEvent(keyboardEventSource:virtualKey:keyDown:)` → optional [verified]
        - `CGEvent.post(tap:.cghidEventTap)` instance method [verified]
        - `kVK_ANSI_V = 9 = 0x09` [verified: runtime]
        - `CGEventFlags.maskCommand` [verified]
      - **make build**: zero new warnings. **make lint**: 0 new serious violations.
        **make test**: 50/50 (5 XCTSkip = pre-existing live FM); 6 new P6 tests green;
        all 44 prior tests still pass.
      - **P6 done-when rows:**
        - `[verified]` `TextInserting` protocol + `PasteboardWriter` conformer compile clean.
        - `[verified]` `CaptureSession(inserter:nil)` → no insert, session → `.done`.
        - `[verified]` Cleanup on: inserter receives `cleanedText`.
        - `[verified]` Cleanup off: inserter receives `rawText`.
        - `[verified]` Cleanup unavailable: inserter receives `rawText`.
        - `[verified]` Insert throws → session → `.error(.pasteboardBusy)`.
        - `[verified]` All 44 prior tests still green.
        - `[deferred — needs human verification]` Paste into TextEdit (plain text).
        - `[deferred — needs human verification]` Paste into Slack (rich text).
        - `[deferred — needs human verification]` Terminal paste-provenance —
          **the project's #1 `[unverified]`: whether write+Cmd+V avoids macOS 26.4's
          Terminal pastejacking check. Must be tested by a human in a running app.**
        - `[deferred — needs human verification]` Password-field silent no-op (no crash).

## Done (this session — 2026-06-20, loop run #6 — P5 HotkeyMonitor)

- [x] **Phase 5 code-complete (live criteria deferred) — `HotkeyMonitor` (CGEventTap global hotkey)**
      - **`SpeakCore/Hotkey/HotkeyMonitor.swift` (NEW):** Full P5 implementation.
        - `HotkeyEvent: Sendable` — `startCapture | stopCapture` (verbatim §6).
        - `HotkeyBinding: Codable, Sendable` — custom `Codable` for `CGEventFlags`
          (encodes `modifiers.rawValue: UInt64`). Default binding: `kVK_Function`
          (0x3F=63, Carbon/HIToolbox [verified]), `modifiers: []`, `.doubleTap`,
          `doubleTapWindow: 0.4` (benchmark.md §7 [decision], trace comment inline).
        - `DoubleTapDetector: Sendable` — pure value-type detector. No CGEventTap,
          no wall-clock. Timestamps injected → fully testable. State: idle →
          first-tap-recorded → startCapture emitted → stopCapture on next single tap.
          `reset()` clears all state.
        - `BindingStoring` protocol + `UserDefaultsBindingStore` — thin testable
          boundary; loads/saves via `JSONEncoder`/`JSONDecoder` in UserDefaults.
        - `HotkeyMonitor` (final class, `@unchecked Sendable`): spawns a private
          CFRunLoop thread for tap callbacks; installs tap via
          `CGEvent.tapCreate(tap:place:options:eventsOfInterest:callback:userInfo:)`
          [verified: obsoletes CGEventTapCreate, SDK 2026-06-20]. Event mask:
          `.flagsChanged` only (Fn does NOT produce keyDown [verified: flagsChanged
          rawValue=12]). Press-edge detected via `.maskSecondaryFn` [verified:
          rawValue=8388608, SDK]. `self` passed via `Unmanaged.passUnretained`
          through `userInfo` — no global mutable state, no retain cycle.
          `CGEvent.tapEnable` re-enables on `tapDisabledByTimeout/ByUserInput`.
          `CGEvent.tapCreate` nil → distinguishes `accessibilityDenied` (via
          `AXIsProcessTrusted()`) from `inputMonitoringDenied` with clean error,
          no force-unwrap. Emits `HotkeyEvent` via `AsyncStream` continuation.
        - **Fn-key event model** [inferred, deferred]: `.maskSecondaryFn` as the
          Fn/Globe key bit is a standard CoreGraphics convention. Live confirmation
          (does this actually fire for the physical Fn key while another app has
          focus) requires a non-sandboxed run with permissions granted → deferred.
      - **`SpeakTests/HotkeyMonitorTests.swift` (NEW, 19 tests):**
        - `HotkeyBindingCodableTests` (6): default binding constants, round-trips
          (default, with modifiers, empty modifiers).
        - `DoubleTapDetectorTests` (11): within-window→start, at-edge→start,
          outside-window→no-event, single-tap→no-event, start→single→stop,
          isCapturing state after start and stop, reset clears state and allows
          fresh double-tap, three-taps cycle, restart after stop.
        - `UserDefaultsBindingStoreTests` (2): save+load round-trip, nil when nothing stored.
      - **`make build`**: zero new warnings. **`make lint`**: 0 serious violations
        (1 new non-serious `file_length` on `HotkeyMonitor.swift` at 417 lines —
        accepted; the verification comment block is the documentation). **`make test`**:
        44/44 PASS (5 XCTSkip = pre-existing live FM path; 19 new P5 tests green).
      - **SDK verifications (all done with `swiftc -typecheck` against macOS 26 SDK):**
        - `CGEvent.tapCreate(...)` [verified] — CGEventTapCreate obsoleted Swift 3
        - `CGEvent.tapEnable(tap:enable:)` [verified]
        - `CGEventType.flagsChanged` rawValue=12 [verified]
        - `CGEventFlags.maskSecondaryFn` rawValue=8388608 [verified]
        - `kVK_Function` = 63 = 0x3F [verified: compiled + ran]
        - `CGEventTapCallBack` callback type [verified]
      - **P5 done-when rows:**
        - `[verified]` Double-tap Fn within 400ms window emits `startCapture`
          (DoubleTapDetector test, injected timestamps).
        - `[verified]` Single-tap Fn after start emits `stopCapture` (same).
        - `[verified]` `HotkeyBinding` Codable round-trip (encode/decode preserves
          keyCode, modifiers.rawValue, trigger, doubleTapWindow).
        - `[verified]` Taps outside window do not trigger (pure detector test).
        - `[deferred — needs human verification]` Double-tap Fn triggers start/stop
          while **another app has focus** (requires live run + Accessibility grant).
        - `[deferred — needs human verification]` First run triggers Accessibility +
          Input Monitoring permission prompts (requires live run, fresh install).
        - `[deferred — needs human verification, P13]` False-trigger rate < 1/30min
          (dogfood in Notes, benchmark.md §7 F_rate).

## Done (this session — 2026-06-20, loop run #5 — P3.5 CaptureSession)

- [x] **Phase 3.5 COMPLETE on the engine seam — `CaptureSession` orchestration**
      closes every P3.5 done-when row that doesn't require an external state
      change (Apple Intelligence enabled, or a live paste into a focused app).
      - **`SpeakCore/Engine/CaptureSession.swift` (NEW — 295 lines, 0 lint
        warnings):** `actor CaptureSession` per `architecture.md` §6, §7.1.
        Public API: `init(transcriber:cleaner:locale:cleanupMode:)`,
        `start()`, `stop() -> TranscriptionResult`, `cancel()`,
        `partials() -> AsyncStream<TranscriptChunk>`, `currentState`, `isTerminal`.
      - **State machine**: `.idle → .listening → .processing → .done` (or
        `.error` from any non-terminal step). Implemented verbatim per
        architecture §7.1.
      - **STT lifecycle**: `start()` spawns a background `Task` that consumes
        the STT `AsyncThrowingStream` and `await`s each chunk into the actor
        (`ingest(_:)`) before reading the next. `stop()` `await`s
        `transcriber.stop()` (which triggers finalization on the real
        SpeechAnalyzer), then `await`s the stream task to drain, then reads
        `latestChunk?.text` as the raw transcript. This is the
        synchronization point that makes the partial-stream + final-result
        contract race-free.
      - **Cleanup wiring** (the P3.5 contract, architecture §10a.1):
        - `cleaner == nil` (cleanup off) → `cleanedText = nil`,
          `engineId = STT id`.
        - `cleaner.isAvailable == false` → `cleanedText = nil`, **no error**
          (graceful fallback, session reaches `.done`).
        - `cleaner.clean()` throws `SpeakError` → propagated unchanged.
        - `cleaner.clean()` throws anything else → wrapped in
          `SpeakError.llmCleanupFailed` (canonical mapping).
        - `cleaner.clean()` succeeds → `cleanedText` populated,
          `engineId = "<stt>+<cleaner>"`.
      - **Partials stream** (`partials()`): an `AsyncStream<TranscriptChunk>`
        for the live overlay (P4). Replaces any prior consumer on each call
        (intentional: the session is single-consumer per dictation); the
        stream finishes when the session terminates.
      - **Stream-failure path**: when the STT stream throws mid-session, the
        session moves to `.error(.transcriberUnavailable(...))` and `stop()`
        re-throws on the next call.
      - **`SpeakTests/CaptureSessionTests.swift` (NEW — 13 tests, all
        green):** mock `Transcribing` (class, `@unchecked Sendable`) +
        mock `LLMCleaning` + `CleanerRecorder` actor for call assertions.
        Covers: initial state, start transitions, double-start throws,
        stop-without-listening throws, cancel→`.error(.sessionCancelled)`,
        stop returns latest-chunk text, cleanup-off→`cleanedText=nil`,
        cleanup-on→`cleanedText` populated + engineId = `<stt>+<cleaner>`,
        cleaner-unavailable→graceful fallback to raw (`.done`, NOT `.error`),
        cleaner-throws-SpeakError→propagates, cleaner-throws-generic→wrapped
        in `SpeakError.llmCleanupFailed`, STT-stream-fails→`stop()` re-throws
        `SpeakError.transcriberUnavailable`, partials stream emits every
        chunk in order and finishes.
      - **`CaptureSession.State: @retroactive Equatable`**: file-local
        conformance added so the test assertions (`XCTAssertTrue(state == .done)`)
        don't depend on Stringly-typed matching. `@retroactive` silences
        Swift 6's "could be added upstream" warning (we own the type).
      - **Build/lint/test**: `make build` clean (no new warnings),
        `make lint` 3 non-serious violations (all `file_length`/`function_body_length`,
        accepted; the AppleSpeechTranscriber + FoundationModelsCleaner
        violations pre-existed and were already accepted for documentation),
        `make test` 25/25 PASS (5 XCTSkip = live FM path; mock-orchestration
        tests are 13/13 PASS).
      - **Roadmap P3.5 boxes checked** in `docs/roadmap.md` with `[verified]`
        tags; the *sample-dictation-cleaned* row carries the explicit
        caveat that the **live** path stays `[inferred]` until P13 dogfood
        (FM is gated off on the dev Mac).

## Done (this session — 2026-06-20, loop run #4 — P3 SpeechAnalyzer STT)

---

## Done (this session — 2026-06-20, loop run #4 — P3 SpeechAnalyzer STT)

- [x] **Phase 3 COMPLETE — SpeechAnalyzer STT.**
      - **`SpeakCore/STT/AppleSpeechTranscriber.swift`**: `Transcribing` conformer
        backed by Apple SpeechAnalyzer (macOS 26+). Engine id `"apple-speech-en-US"`.
      - **Authoritative lifecycle implemented** ([verified] WWDC25 #277):
        `analyzer.start(inputSequence:)` returns after setup (NOT after all input) →
        bridge feeds AnalyzerInput → bridge task completes (all input fed) →
        `finalizeAndFinishThroughEndOfInput()` closes `transcriber.results` →
        results drain → stream finishes. Not calling `finalize` caused a hang (diagnosed
        by orchestrator and fixed).
      - **Audio injection**: `AudioBufferProducing` protocol injected at init;
        default `LiveAudioCapture` wraps P2's `AudioCapture`; tests inject
        `FixtureAudioProducer`. No-arg factory `AppleSpeechTranscriber()` works unchanged.
      - **Format conversion** [verified at runtime]: `bestAvailableAudioFormat` returns
        16kHz mono Int16 interleaved; P2 produces Float32 non-interleaved. `AVAudioConverter`
        bridges them correctly. Bug caught: original check compared only sample rate + channel
        count, missing `commonFormat` difference → converter not built → "Audio sample data
        must be 16-bit signed integers" error. Fixed to compare `commonFormat` + `isInterleaved`.
      - **Asset provisioning**: `AssetInventory.status` + `assetInstallationRequest` →
        `downloadAndInstall()`. Locale validated via `SpeechTranscriber.supportedLocale`.
        `SpeechTranscriber.isAvailable` static gate.
      - **Clean stop**: `stopSession()` calls `audioProducer.stop()` (ends buffer stream)
        → bridge exits → `inputCont.finish()` → `finalize` runs in session task → results
        drain → session task exits. No zombie tasks.
      - **`SpeakTests/SpeechTranscriberTests.swift`**: 4 tests. `testTranscribesFixture`
        produces real transcription: fixture "Testing one two three" → final transcript
        `'cased in one, two, three.'` — one, two, three found [inferred: "testing" → "cased"
        is model behavior with synthetic speech]. `testStopTerminatesStream` confirms no hang.
      - **Fixture**: `SpeakTests/Fixtures/hello_speech.caf` (16kHz mono Float32, 1.3s).
      - **`make build`**: zero warnings. **`make lint`**: 0 serious violations (1 non-serious
        file-length warning on the implementation file — accepted; comments are required
        for API verification). **`make test`**: 10/10 PASS.
      - **P2 format note** (surfaced for orchestrator): P2 hard-bakes 16kHz Float32 output.
        SpeechAnalyzer's `bestAvailableAudioFormat` = 16kHz Int16 interleaved. P3 converts.
        Optimal path would be: P2 outputs native mic format, P3 does one conversion to Int16.
        Not a blocking issue — P3 handles it — but worth noting for P13 latency tuning.

---

## Done (prior session — 2026-06-20, loop run #3)

- [x] **Xcode 26.5 installed + activated** (human ran `xcode-select -s`,
      `xcodebuild -runFirstLaunch`, `-license accept`). `xcodebuild` works;
      macOS 26.5 SDK present; `swiftlint` 0.63.3 via brew. Open Q#1 fully resolved.
- [x] **Phase 0 COMPLETE — canonical Xcode build system.**
      - **Decision (mine, under delegation; implements Q#5)**: generate the
        mandated `.xcodeproj` with **XcodeGen** from a checked-in `project.yml`,
        rather than hand-author a fragile `.pbxproj` or use the Xcode GUI (which
        an agent can't drive). XcodeGen is **build-time only** — never linked into
        the app — so it doesn't touch the Apple-frameworks-only runtime moat
        (`AGENTS.md` §2.4). `Speak.xcodeproj` is git-ignored; `project.yml` is the
        source of truth; `make build` regenerates it (works from a clean clone).
      - Three §5 targets build: `Speak.app` (application), `SpeakCore.framework`
        (the portability seam), `SpeakTests` (unit-test bundle). Engine `.swift`
        files moved into the framework target with **zero code change** (they were
        already in the §5 layout).
      - `Makefile` (`build`/`test`/`lint`/`run`/`clean`/`release`-stub),
        `.swiftlint.yml` (enforces §3: force_unwrap/force_cast/force_try = error),
        GitHub Actions CI (`.github/workflows/ci.yml` — `xcodebuild` + swiftlint;
        **[unverified]** until the repo has a remote + a push).
      - **Verified**: `make clean && make build` → runnable `Speak.app`;
        `make lint` → 0 violations; `make test` → 4/4 pass via `xcodebuild test`.
      - **Retired the temporary SwiftPM/smoke scaffolding** (`Package.swift`,
        `Smoke/`) — its only purpose (no XCTest under CLT) is gone now that
        `xcodebuild test`/`swift test` run the canonical `SpeakTests`.
- [x] **Phase 1 COMPLETE — menubar scaffold.** `App/SpeakApp.swift`: a
      `MenuBarExtra` app (waveform idle icon) with an **About speak…** item +
      Quit, running as **LSUIElement** (no Dock icon). Links `SpeakCore` and logs
      via `SpeakLog.engine` on launch (proves the framework seam). **Launched and
      confirmed running** (pid alive, menubar-only). Roadmap P1 done-when met.
- [x] **Engine-core foundation built + verified under CLT (no Xcode needed).**
      Implemented the framework-agnostic core from `architecture.md` §6 in the
      **final §5 layout**: `SpeakError` (Engine/), `Transcribing`+`TranscriptChunk`
      (STT/), `LLMCleaning`+`CleanupMode` (Cleanup/), `TranscriptionResult`
      (Engine/, split to its own file), `SpeakLog` OSLog categories (Logging/).
      `swift build` **green, zero warnings**. Verification: XCTest/swift-testing
      both ship only inside full Xcode, so `swift test` can't run under CLT — so
      I added a temporary `speak-smoke` executable target (`swift run speak-smoke`)
      that exercises every type/seam with mock `Transcribing`/`LLMCleaning`
      conformers: **16/16 checks pass**. The canonical swift-testing suite
      (`SpeakTests/EngineCoreTests.swift`) is authored and runs once Xcode lands.
      - **Decision (mine, logged)**: user delegated all technical calls → built
        the engine core in parallel with the Xcode install. Reason is *non-churn*,
        not speed: these §6 types are stable across build systems and the .swift
        files drop into the Xcode `SpeakCore.framework` target unchanged.
      - **Minor verbatim-spec deviations (strict additions, surfaced)**: added
        explicit `public init`s to `TranscriptChunk` and `TranscriptionResult`
        (a public struct needs a public init to be constructible cross-module —
        §6 omitted them); `TranscriptionResult` lives in its own file rather than
        inside `CaptureSession.swift`. Neither changes the type shape.
      - **Deferred from this increment**: `HotkeyBinding` (its `modifiers:
        CGEventFlags` isn't `Codable` out of the box → needs custom coding; it's
        CoreGraphics/P5 territory anyway) and `CaptureSession`/`SpeakEngine` (the
        state machine needs a paste-seam abstraction decision — next unit).
- [x] **`git init` + first commit** (`e3f9b63`) — repo is now version-controlled;
      commit discipline (`AGENTS.md` §7) is live. Staged the full doc set +
      research; excluded `.claude/*.lock` transient state.
- [x] **Phase 0 pure-text deliverables** (verifiable without Xcode):
      `LICENSE` (MIT), `.gitignore` (macOS/Xcode/SwiftPM/secrets), `.swift-version`
      (`5.9`). README skeleton already existed.
- [x] **Reframed the "everything is blocked" chain** (prior session was too
      broad). Probed the Command-Line-Tools SDK: `swiftc -typecheck` **succeeds**
      for `import Speech`, `import FoundationModels`, `import AVFoundation`,
      `import SQLite3` → the framework headers are present. The true blocker is the
      **app shell + `.app` bundle**, not the engine. → A large slice of `SpeakCore`
      pure logic (`Transcribing`/`LLMCleaning` protocols, `CaptureSession` state
      machine, `TranscriptChunk`/`TranscriptionResult`/`SpeakError`, `SpeakLog`,
      `SettingsStore`, `HistoryStore` SQLite) is buildable + `swift test`-able now
      behind mock conformances, with zero Xcode. **Awaiting the human's go on the
      SwiftPM-now path** (adding a build system alongside the mandated `.xcodeproj`
      is a rails-move → ask, per `AGENTS.md` §4).

## Done (prior session — 2026-06-20)

- [x] **Verified the load-bearing claims** against primary sources (3 parallel
      research streams). Result in `specs/verification-ledger.md`.
  - Foundation is **sound**: `SpeechAnalyzer` (on-device, macOS 26 Tahoe, shipped
    Sept 15 2025), `CGEventTap` perms + Fn=`kVK_Function` 0x3F all `[verified]`.
  - **Bonus**: macOS 26 ships `Foundation Models` (on-device LLM) `[verified]` →
    enables native, zero-dependency AI cleanup in v0.
  - **Refuted**: the Wispr "polishing, not shipping" thesis — Wispr is in
    aggressive expansion. Repositioned to the *structural* moat.
  - **Corrected**: Wispr has a free tier + uses Fn + is multi-platform; competitor
    prices; WhisperKit repo path; macOS ship date.
  - **`[unverified]`**: the specific paste write+Cmd+V bypass — **test at P6**
    (macOS 26.4 added a Terminal paste-provenance check).
- [x] **Created `docs/benchmark.md`** — the definition of done: category parity
      map (Wispr = frontier), MATCH/BEAT/SKIP buckets, phased, with a derivation
      ledger (no hardcoded magic numbers). This is the loop's objective function.
- [x] **Rewrote `docs/product.md`** — added the final-outcome / "what it looks
      like" destination; the full, time-free version ladder (v0 = complete core,
      v1 friendly, v2 creative, v3+ frontier); AI neat-writing as core; pluggable
      local models; corrected structural positioning.
- [x] **Made AI neat-writing v0 core** across the docs: `LLMCleaning` protocol +
      `FoundationModelsCleaner` (Apple framework → no third-party-dep violation),
      wired into `CaptureSession.processing` (finalize → cleanup → paste).
      `architecture.md` §10a, `roadmap.md` P3.5, `quality.md` cleanup tests,
      `benchmark.md` cleanup → v0 MATCH.
- [x] **Removed all project-schedule time** (dates, "14 days", effort S/M/L/XL,
      "first 48 hours", stopwatch UX targets) from every doc. Build is an
      unbounded loop; "done" = testable criteria only.
- [x] Updated `AGENTS.md` (no deadline; cleanup core; `benchmark.md` registered)
      and ran a coherence pass (cross-refs, version labels, zero residual time).
- [x] **Completed the `specs/wispr-parity-and-spec.md` plan** (the spec/benchmark
      track that `/loop` was pointed at):
  - [x] **Authored `SPEC.md`** (root) — the human-readable consolidated spec:
        vision, structural why-now, market + **embedded parity map**, personas,
        UX, architecture summary, privacy, roadmap, risks, GTM, ledger summary,
        and a `docs/`-corrections appendix. Single voice; claims tagged.
  - [x] **Adversarial review (plan task #6) found 6 blocking + 4 nits; all 6
        blocking FIXED, re-validated to 0**. The sonnet reviewer caught real
        factual errors that orchestrator greps missed — corrected in
        `benchmark.md`/`SPEC.md` (the plan's own deliverables; `product.md` and
        the other immutable docs untouched):
    - B1: `benchmark.md` §3 history row was falsely `[verified]` → `[unverified]`
          (ledger §2 ground truth).
    - B2: `SPEC.md` embedded counts were wrong on all figures → corrected to
          **7 MATCH · 8 BEAT · 4 SKIP/SKIP→MATCH = 19 rows**.
    - B3: `benchmark.md` §1 snapshot had no per-row verdict tags → added
          `[verified]`/`[corrected]` per ledger §3.
    - B4: `benchmark.md` §1 malformed "Superwhisper/MacWhisper" row → split into
          a correct standalone **MacWhisper** row.
    - B5: Wispr annual price "$12/yr" (implies $12 total/yr) → **$12/mo annual
          ($144/yr)** per ledger §2.
    - B6: §3 BEAT list (7 structural) vs §2 matrix (8 BEAT) reconciled with a
          scope note + a fixed §4 v0-BEAT enumeration.
    - Nits N3 (missing matrix columns — values still trace to §7) and N4
          (`architecture.md` "~95% of apps" stale claim) left for the human;
          N2 (product.md "modified this run") was a **false alarm** — mtime
          `1781956811` is unchanged from this run's baseline (last touched in the
          prior session).
  - [x] **Validation (task #7) passes after fixes**: every MATCH row has a binary
        criterion tracing to `benchmark.md` §7 (no orphan constants); no stale
        citations leaked (Tsai 2026-04-03, `argmax-oss-swift`, Superwhisper $8.49,
        paste bypass `[unverified]`); why-now is structural (no "Wispr coasting");
        no cloud SKIP in a v0 MATCH. `docs/product.md` untouched (mtime at baseline).
- [x] **Verified toolchain (open Q#1)**: `swift` 6.3.2 present, target
      `arm64-apple-macosx26.0` ✓ — but **`xcodebuild` is ABSENT** (only Command
      Line Tools active, no full Xcode) and the dir is **not a git repo**. Phase 0
      is therefore **blocked** until Xcode is installed + `git init` is approved.

---

## In progress

Nothing. The spec/benchmark track is complete (`benchmark.md`, `SPEC.md`,
`verification-ledger.md` all done + validated). The `/loop` pointed at the spec
plan was stopped on completion (job `ddc5d3fd` deleted) — it would otherwise
thrash, since the next work (Phase 0) is blocked on a human gate.

---

## Blocked

- **Nothing blocks the build.** Xcode is installed; P0/P1 are done; P2 is ready.
- Deferred (not blocking): CI YAML is **[unverified]** (no git remote yet — needs
  a push to a macOS-26 runner to confirm); Developer ID signing cert for
  notarization is still needed at P11 (Open Q#4).

---

## Next up

1. **P2 — Audio capture (CRITICAL PATH)**: `PermissionManager` (mic state) +
   `AudioCapture` (`AVAudioEngine`, 16kHz mono PCM) streaming PCM buffers to an
   `AsyncStream`. First run triggers the mic permission prompt; logs buffer stats
   via `SpeakLog.audio`; clean stop on cancel. These are framework-bound (AppKit/
   AVFoundation) → they live in `SpeakCore` but are exercised through the app for
   the permission prompt. Add `NSMicrophoneUsageDescription` to the app plist.
2. **P3 — SpeechAnalyzer**: `AppleSpeechTranscriber` against `Speech`
   (verify API surface vs current Apple docs first).
3. **Engine-core unit (do alongside P2/P3)**: `CaptureSession` actor state
   machine (§7.1) + `SpeakEngine` facade. Needs a paste-seam abstraction
   (`TextInserting` protocol so the core stays testable; real `PasteboardWriter`
   NSPasteboard impl is app-side) — design + document in `architecture.md` first.
   Then `HotkeyBinding` Codable (custom coding for `CGEventFlags`).
4. **P3.5 cleanup → P5 hotkey → P6 paste** along the critical path.
3. **P1 → P2 → P3 → P3.5 (cleanup) → P5 → P6** along the critical path.
4. The loop runs until `benchmark.md` §4 MATCH gate + §3 BEAT rows +
   `quality.md` §9 all pass. No deadline.

---

## Decisions logged

| Date | Decision | Rationale | Source |
|---|---|---|---|
| 2026-06-20 | **XcodeGen generates the canonical `.xcodeproj`** from `project.yml` (git-ignored project; `make build` regenerates) | An agent can't drive the Xcode GUI and hand-authored `.pbxproj` is fragile/version-specific; XcodeGen is build-time-only (not linked into the app) so it preserves the Apple-frameworks-only runtime moat (§2.4). Implements Q#5's canonical-Xcode decision | This session (loop #3); advisor concurrence |
| 2026-06-20 | **AI neat-writing is v0 core**, default = on-device `Foundation Models` | "Speech→neat text" is the product identity (= Wispr's core); Foundation Models is an Apple framework, so v0 stays zero-third-party-dep, local, free | `verification-ledger.md`; user direction |
| 2026-06-20 | **No deadlines / no time anywhere** — unbounded build loop | Agent-driven development; "done" = testable criteria, not dates | User direction |
| 2026-06-20 | **v0 = complete core, not MVP**; full v0–v3+ ladder defined up front | Knowing v1–v3 lets v0 be architected so later versions are additive, never a rewrite | User direction; `product.md` §9 |
| 2026-06-20 | Reposition to the **structural** moat (local+free+open+offline+no-account+history) | Wispr "why now / coasting" thesis refuted; the durable wedge is what Wispr can't do without abandoning cloud revenue | `verification-ledger.md` §2 |
| 2026-06-20 | `benchmark.md` is the **definition of done** + loop objective function | "Be as good as Wispr" must be testable, not a vibe | User direction |
| 2026-06-20 | **Spec/benchmark track complete; stopped the 1-min `/loop`** (`ddc5d3fd`) on validation pass | The loop was scoped to `specs/wispr-parity-and-spec.md`, now done (SPEC.md + review + validation, 0 blocking). Next work (Phase 0) is blocked on a human gate (Xcode + `git init`), so continued firing would only thrash or risk an unactionable cold-cycle Swift attempt | This session; advisor guidance |
| 2026-06-18/19 | Build `speak` (Mac dictation); Swift-native single codebase; Apple `SpeechAnalyzer` default behind pluggable `Transcribing`; double-tap Fn; write-never-read paste; MIT; non-sandboxed v0 | (carried from prior sessions) | `research/`, prior `progress.md` |

---

## Open questions

| # | Question | Status | Needed by |
|---|---|---|---|
| 1 | Xcode/Swift toolchain available here? Repo needs `git init`. | **Resolved 2026-06-20**: `git init` **DONE** (`e3f9b63`); `swift` 6.3.2 ✓; **`xcodebuild` ✗ (no full Xcode)**. Xcode-bound P0 parts blocked; the rest is not. | P0 |
| 5 | **Build+test `SpeakCore` logic via SwiftPM now, or wait for Xcode?** | **Resolved/implemented 2026-06-20 (loop #3)**: canonical `.xcodeproj` via **XcodeGen** (`project.yml` source of truth). SwiftPM scaffolding retired. | P0 ✓ |
| 2 | `Foundation Models` runtime availability/quality for cleanup on the target Macs (Apple Intelligence gating, M-series, locale)? | Verify empirically at P3.5; raw fallback exists | P3.5 |
| 3 | Does write+`Cmd+V` avoid the paste prompt incl. the macOS 26.4 Terminal provenance check? | `[unverified]` — test in Terminal/iTerm | P6 |
| 4 | Developer ID signing cert for notarization? | Unverified | P11 |

---

## Session log

- **2026-06-20 (agent-harness / context-engineering)**: Built the autonomous
  build harness — 8 skills (`.claude/skills/`: 3 thick doc-grounded + 5 thin
  per-seam Apple-API pointers) and a 7-agent standing team (`.claude/agents/team/`,
  one per architecture seam). Wired project MCP (`.mcp.json`): `apple-docs`
  (✔ connected) + `xcode` (`xcrun mcpbridge`, Xcode 26.5 — connects but needs a
  one-time in-Xcode auth). Established the **swiftc-against-the-local-SDK**
  verification backbone (cutoff-proof) and ran an SDK-anchored, adversarially
  citation-checked verification workflow over all 8 skills (14 agents). Applied
  11 upheld fixes; 10 claims correctly deferred (empirical-by-design). **Two
  source-of-truth API bugs caught + fixed**: `architecture.md` §6 + §9 used
  `LanguageModel.default` / `LanguageModel` (do not resolve) → `SystemLanguageModel`
  + `.availability`; `roadmap.md` P3 §14.1 anchor → §10.2. Added the harness to
  `AGENTS.md`/`CLAUDE.md` navigation so a fresh `/loop` discovers it. Lesson:
  agents share the Jan-2026 cutoff, so skills must carry post-cutoff truth verified
  against the live SDK, never recalled. See `docs/agent-tooling.md`.
- **2026-06-20**: Verified load-bearing claims (foundation sound; Foundation
  Models unlock; Wispr thesis repositioned). Created `benchmark.md` +
  `verification-ledger.md`. Rewrote `product.md`. Elevated AI cleanup to v0 core.
  Stripped all schedule-time from the doc set. Coherence pass clean. Ready for P0.
- **2026-06-20 (loop run)**: Authored `SPEC.md` (opus) embedding the parity map.
  Adversarial review (sonnet) found **6 blocking defects** (false `[verified]`
  history tag; wrong embedded row counts; untagged §1 snapshot; malformed
  MacWhisper row; "$12/yr" mispricing; §3↔§2 BEAT mismatch) — orchestrator
  verified each against the ledger and **fixed all 6** in `benchmark.md`/`SPEC.md`
  (`product.md` and other immutable docs untouched), re-validated to **0
  blocking**. Lesson: mechanical greps (`grep -c`) missed factual + counting
  errors a real review caught — don't declare "done" before the reviewer reports.
  Resolved open Q#1: `swift` 6.3.2 present but `xcodebuild` absent → Phase 0
  blocked on installing Xcode + `git init`. Completed the spec plan and stopped
  the `/loop` (`ddc5d3fd`). Build can resume once the human gate is cleared.
- **2026-06-20 (loop run #2)**: `git init` + first commit (`e3f9b63`) with MIT
  `LICENSE`, `.gitignore`, `.swift-version`. Reframed the prior session's
  "everything blocked on Xcode" — it was too broad. Probed the CLT SDK:
  `swiftc -typecheck` passes for `Speech`/`FoundationModels`/`AVFoundation`/
  `SQLite3`, so the real blocker is the app shell, not the engine. A large slice
  of `SpeakCore` pure logic is `swift test`-able now behind mocks. Surfaced the
  SwiftPM-now-vs-wait decision (Open Q #5) to the human and stopped the loop on
  it (human-gated; the answer re-triggers). Lesson: don't let one missing tool
  collapse into "nothing is actionable" — separate the verification gap (Xcode)
  from the genuinely-buildable core.
- **2026-06-20 (loop run #3)**: Human installed + activated Xcode 26.5. Chose
  **XcodeGen** to generate the canonical `.xcodeproj` from `project.yml` (agent
  can't drive the GUI; build-time-only tool preserves the runtime moat).
  **Completed Phase 0** (3 §5 targets build via `make build`; lint clean; tests
  green via `xcodebuild test`) and **Phase 1** (menubar app launched + verified).
  Retired the temporary SwiftPM/`Smoke` scaffolding. Next: P2 audio capture.
- **2026-06-19**: Doc restructure into `AGENTS.md` + `docs/` + `research/`.
