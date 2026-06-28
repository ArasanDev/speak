# speak — agent loop prompt

You are an agent running one loop cycle on the `speak` macOS dictation app
(repo dir: `deepvoice/`). speak is a local-first, free, open-source voice
dictation app: speech → AI cleanup → paste at cursor, 100% on-device.

The loop runs until `benchmark.md` §4 MATCH + §3 BEAT + `quality.md` §9 ship
checklist all pass. There is no deadline — only testable done-when criteria.

---

## 0. Load order — every cycle, non-negotiable

1. `AGENTS.md` §0–4 — mission, hard constraints, the loop
2. Last 80 lines of `docs/progress.md` — current state, handoff, what's next
3. `docs/roadmap.md` — find the next undone dependency-ready task
4. The skill(s) from `.claude/skills/` relevant to that task

---

## 1. Stack — know exactly what you're building on

| Layer | Technology | Notes |
|-------|-----------|-------|
| Language | Swift 5.9+ (Xcode 26+) | Swift 6 language mode NOT yet enabled — see §9.4 |
| Platform | macOS 26 (Tahoe), Apple Silicon | Deployment target: arm64-apple-macosx26.0 |
| UI | SwiftUI + AppKit (no UIKit) | MenuBarExtra, NSPanel, NSWindow |
| STT | Apple SpeechAnalyzer (v0 default) | `Transcribing` protocol; WhisperKit is v0.1+ |
| Cleanup | Apple Foundation Models (v0 default) | `LLMCleaning` protocol; Ollama/MLX are v0.1+ |
| Hotkey | CGEventTap | double-tap Fn (or bound key), `@unchecked Sendable` + NSLock |
| Paste | NSPasteboard write + CGEvent Cmd+V | Write-only — never read the pasteboard |
| Storage | SQLite via raw API | `HistoryStore` actor |
| Build | XcodeGen → Speak.xcodeproj | project.yml is canonical; .xcodeproj is git-ignored |
| Formatting | `.swift-format` (Apple container config) | `make fmt` (needs `brew install swift-format`) |
| Linting | `.swiftlint.yml` | `make lint` — 0 serious violations enforced |

---

## 2. Research-first protocol — before writing any code

Your training data is a hypothesis, not a fact, for anything Apple-framework-related
post-2025. The protocol below turns hypotheses into verified knowledge.

### Step 1 — Gap detection

Before touching a file, ask:
- Does this use an Apple framework updated at WWDC26 (SpeechAnalyzer, Foundation
  Models, AppIntents, CoreAI)?
- Does it integrate a third-party package (WhisperKit, MLX, Sarvam, Ollama)?
- Is the relevant skill claim tagged `[inferred]` or `[unverified]`? → verify before use.

If any answer is yes → research before coding. One minute of research saves
two loop cycles debugging a wrong API shape.

### Step 2 — Tool selection

| Need | First tool | Fallback |
|------|-----------|---------|
| Apple framework API shape | `apple-docs` MCP (search by symbol) | `swiftc -typecheck` probe |
| WWDC session content | WebSearch `WWDC26 [Framework] site:developer.apple.com` | WebFetch the session page |
| Swift package API | WebFetch `github.com/<org>/<repo>/blob/main/README.md` at tag | WebSearch `[pkg] [version] swift API` |
| SDK symbol existence | `swiftc -typecheck -sdk "$(xcrun --show-sdk-path)" -target arm64-apple-macosx26.0` | **Ground truth — no web result overrides it** |

### Step 3 — After verifying, update the skill

- `[unverified]` → `[verified via swiftc]` or `[verified from: <URL>]`
- `[inferred]` → `[verified]` if confirmed; add source
- Real API differs from skill → **update the skill first, then write code**

This is compounding. Your verification is a gift to every future agent.

---

## 3. Pick the next task

Lowest-numbered `[ ]` in `docs/roadmap.md` whose dependencies are `[x]`. That
is your task. If `[~]` (in progress), continue it. If multiple tasks are
independent (different seams, no shared files), fan out to specialist agents.

### Specialist team

| Agent | Owns |
|-------|------|
| `builder-engine` | `SpeakCore/Engine/` |
| `builder-audio-stt` | `SpeakCore/Audio/`, `SpeakCore/STT/` |
| `builder-cleanup` | `SpeakCore/Cleanup/` |
| `builder-input` | `SpeakCore/Hotkey/`, `SpeakCore/Paste/`, `SpeakCore/Permissions/` |
| `builder-app` | `App/`, `SpeakCore/Storage/` |
| `builder-release` | `project.yml`, `Makefile`, CI |
| `builder-qa` | `SpeakTests/`, benchmarks, dogfood |

Parallel agents: `git worktree add .wt/<name> -b <branch>` first.
**Never commit from a subagent — orchestrator reviews the diff and commits.**
Load the relevant skill before dispatching each specialist.

---

## 4. Execute

1. Read relevant `docs/` files (`architecture.md` for impl, `quality.md` for verify)
2. Read the skill(s) — verify `[unverified]` claims before using them
3. Read the surrounding source code before writing any new code
4. Implement + tests together — tests are not optional
5. Run all four gates:

```sh
make build        # exit 0, no new warnings
make test         # exit 0, 0 failures
make lint         # exit 0, 0 serious violations
make verify-moat  # 7/7
```

6. Verify the specific `done-when` criterion from `roadmap.md` (binary pass/fail)
7. Update `docs/progress.md`
8. Gates green + done-when met → commit: `git commit -m "[P<N>] <task>: <what changed>"`

---

## 5. Code discipline — the Apple principal developer standard

These conventions are sourced from studying Apple's own open-source projects
(`apple/container`, which shares our exact stack: macOS 26, Xcode 26+, Apple
Silicon, Swift 6.x compiler). Follow them precisely.

### 5.1 File structure

- **One type per file. Filename = type name.** Agents find `HotkeyMonitor` in
  `HotkeyMonitor.swift` without grepping. Never violate this.
- **Extension-per-responsibility.** A 700-line class is wrong. Extract into
  `TypeName+Responsibility.swift` files:
  ```
  DictationController.swift               ← core init, properties
  DictationController+Hotkey.swift        ← hotkey handling
  DictationController+CLI.swift           ← CLI command handling
  DictationController+ErrorHandling.swift ← error routing
  ```
- **Protocol in same module as its primary implementor.** `Transcribing` and
  `AppleSpeechTranscriber` both live in `SpeakCore`. Never split a protocol to
  a `Protocols/` folder — agents lose the context of what the protocol is for.
- **C code in minimal named targets.** Any CGEvent or Core Foundation helpers
  belong in a dedicated C target (e.g. `CSpeakInput/`), never inline in Swift files.

### 5.2 Formatting (`.swift-format` — Apple container config)

Run `make fmt` before committing. Install with `brew install swift-format`.

| Rule | Effect |
|------|--------|
| `lineLength: 180` | Max line length (raised from 120 to match Apple) |
| `indentation: {spaces: 4}` | 4-space indent, never tabs |
| `OrderedImports` | Import statements alphabetical in every file |
| `UseEarlyExits` | `guard` first — never deeply nested `if` |
| `OmitExplicitReturns` | Single-expression functions use implicit `return` |
| `NeverForceUnwrap` | Enforced by formatter, not just linter |
| `NoAccessLevelOnExtensionDeclaration` | Never write `internal extension Foo {}` |
| `UseTripleSlashForDocumentationComments` | `///` for all public API docs |

### 5.3 Naming conventions

- Types: `UpperCamelCase`. File name must match exactly.
- Properties and methods: `lowerCamelCase`.
- Constants: always named. Every constant traces to a measured value, a platform
  constraint, or a `[decision]` in `benchmark.md §7`. No magic numbers.
- Single-char loop vars (`i`, `j`, `n`, `m`) are allowed in algorithm code only.
- `SpeakLog.<category>` for every log call — never `print`. Use the right category:
  - `engine` / `audio` / `stt` / `cleanup` / `hotkey` / `paste`
  - `permissions` / `storage` / `cli` / `app` / `overlay`

### 5.4 Concurrency — Swift 6 patterns from Apple's own code

**`@unchecked Sendable` + `NSLock` for C-backed types:**
```swift
// For CFMachPort, CGEventTapProxy, and any non-Sendable C type
private nonisolated(unsafe) let port: CFMachPort
private let lock = NSLock()
```
Or use `Mutex<T>` from `import Synchronization` for lock-protected value state:
```swift
let state: Mutex<State>
state.withLock { $0.isFinished }
```

**`AsyncStream` bridges over callbacks — never completion handlers:**
```swift
// Bridge AVAudioEngine tap or CGEventTap to AsyncStream
let stream = AsyncStream<PCMBuffer> { cont in
    engine.installTap { buffer, _ in cont.yield(buffer) }
}
for await buffer in stream { ... }  // cancellation-safe, testable
```
`AudioCapture` already does this. Apply the same pattern to any new callback API.

**`actor` for stateful services.** `SpeakEngine`, `HistoryStore` are actors.
Never use `@unchecked Sendable final class` for a type with mutable state —
use `actor` and get data-race safety without manual locking.

**`withCheckedThrowingContinuation` to bridge legacy async callbacks:**
```swift
let result = try await withCheckedThrowingContinuation { cont in
    legacyAPI.doSomething { value, error in
        if let error { cont.resume(throwing: error) } else { cont.resume(returning: value) }
    }
}
```

**`@MainActor` over `DispatchQueue.main.async`.** Any class that drives SwiftUI
state should be `@MainActor`. Never write `DispatchQueue.main.async {}` in new code.

### 5.5 Audio pipeline — verified stream composition patterns

`AsyncSequence` has **no built-in fan-out**. A single `AsyncStream` cannot be
consumed by two tasks simultaneously — doing so corrupts or crashes. speak's
two-stream design (`AsyncStream<AVAudioPCMBuffer>` + parallel `AsyncStream<Double>`
for RMS) is the correct approach: two separate streams from one tap callback.

**Session orchestration with `withThrowingTaskGroup`:**
```swift
// The correct pattern — three concurrent consumers, one cancellation scope
try await withThrowingTaskGroup(of: Void.self) { group in
    group.addTask { /* feed loop: tap → broadcaster */ }
    group.addTask { /* STT consumer: sttStream → TranscriptChunk */ }
    group.addTask {
        // RMS → UI, throttled — swift-async-algorithms combinator
        for await level in rmsStream.throttle(for: .milliseconds(50), clock: .continuous, reducing: { $0 }) {
            await MainActor.run { overlayViewModel.level = level }
        }
    }
    try await group.waitForAll()
}
```

**`throttle` from `swift-async-algorithms`** — rate-limits the RMS stream to the
overlay. 50ms is enough for a smooth waveform meter. Install via SPM if needed:
`apple/swift-async-algorithms`.

**`AsyncChannel<T>` for backpressure** — if `SpeechAnalyzer` falls behind under
load, swap the STT input from `AsyncStream` to `AsyncChannel`. `send(_:)` suspends
the producer until the consumer calls `next()`, preventing buffer growth.

**Fan-out actor broadcaster** — if a future seam requires N consumers of the same
buffer stream, hand-roll an `actor AudioBroadcaster` that holds N continuations
and yields to all of them. There is no library primitive for this.

### 5.6 `@Observable` — the current standard (macOS 14+, available now)

Six classes still use `ObservableObject` + `@Published`. That is the old pattern.
The current Apple standard is `@Observable` (`import Observation`, not SwiftUI —
legal in `SpeakCore`).

**Migration order:**

| Class | File | Priority |
|-------|------|----------|
| `SettingsStore` | `SpeakCore/Storage/SettingsStore.swift:86` | First — everything reads this |
| `SnippetStore` | `SpeakCore/Snippets/SnippetStore.swift:18` | Same layer |
| `HistoryViewModel` | `App/History/HistoryViewModel.swift:30` | App layer |
| `OnboardingViewModel` | `App/Onboarding/OnboardingViewModel.swift:32` | App layer |
| `OverlayViewModel` | `App/Overlay/TranscriptOverlayView.swift:45` | Performance-critical |
| `DictationController` | `App/DictationController.swift:68` | Last — eliminates Combine subscription |

**Pattern:**
```swift
// Before
public final class SettingsStore: ObservableObject, @unchecked Sendable {
    @Published public var cleanupEnabled: Bool { ... }
}

// After
@Observable
public final class SettingsStore: @unchecked Sendable {
    public var cleanupEnabled: Bool { ... }
}
```
Call sites drop `@ObservedObject` → plain `let`. `@Bindable` for two-way bindings.
The Combine `.receive(on: DispatchQueue.main).sink` subscriptions in `DictationController:249`
go away entirely — `@Observable` tracks property access automatically.

**Performance win on the overlay:** `@Observable` re-renders only the view that
reads a changed property, not all views that observe the object. Critical for
`TranscriptOverlayPanel` which redraws on every transcript chunk.

### 5.6 Error handling — structured, logged by code

`SpeakError` now has a `.code` computed property (machine-readable string per case).
Always log errors with it:
```swift
// Required pattern
SpeakLog.engine.error("failed: \(error.code, privacy: .public) — \(error.localizedDescription, privacy: .public)")

// Never
print(error)
logger.error("\(error)")  // leaks private data; no code for filtering
```

### 5.7 Protocol-first design

- One protocol, one primary concrete implementor per seam.
- Protocol and implementor always in the same module — never a separate `Protocols/` folder.
- Alternative engines (WhisperKit, Ollama, MLX) add a new conforming type; they
  never modify the protocol.
- Use a route-table (`[String: Handler]`) for dispatch, not giant `switch` statements.

---

## 6. Testing discipline

### 6.1 Three-tier structure (Apple container model)

| Tier | Location | What | Speed |
|------|----------|------|-------|
| Unit | `SpeakTests/` | Pure types, actors, parsers — no daemons | < 1s each |
| Integration | `SpeakTests/` (tagged) | Live engine, SQLite, real audio | < 30s |
| Dogfood | P13 human gate | Live paste in 3 apps, latency measured | Manual |

### 6.2 Swift Testing — all new tests use this

3 files use Swift Testing today. 36 use XCTest. **All new tests must use Swift
Testing.** Migrate existing tests as you touch each file.

Easy first migrations (pure value-type tests):
`MenubarIconTests` → `OverlayTextTests` → `TextDiffTests` → actor/async tests last.

**Parameterized tests — use for repetitive cases:**
```swift
@Test("MenubarIcon maps CaptureSession.State", arguments: [
    (CaptureSession.State.idle,       MenubarIcon.idle),
    (.listening,  .listening),
    (.processing, .processing),
    (.done,       .done),
    (.error,      .error),
])
func iconMapping(state: CaptureSession.State, expected: MenubarIcon) {
    #expect(MenubarIcon(for: state) == expected)
}
```

**`#expect` / `#require` over `XCTAssert*`:**
```swift
#expect(result.cleanedText == "Hello, world.")
#require(result.error == nil)  // stops test on failure, like XCTUnwrap
```

### 6.3 Shared fixtures — `TestStorage` (not ad-hoc UUID)

14 test files still use `addTeardownBlock` + manual UUID temp dirs. Use `TestStorage`:
```swift
// Old (HistoryStoreTests.swift and 13 others)
private func tempDatabaseURL() -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("test-\(UUID().uuidString).sqlite")
    addTeardownBlock { try? FileManager.default.removeItem(at: url) }
    return url
}

// New — one line, guaranteed cleanup even on throw
let url = TestStorage.tempDatabaseURL()

// Or scoped
try await TestStorage.withTempDir { dir in
    let store = try HistoryStore(databaseURL: dir.appendingPathComponent("h.sqlite"))
    // dir is removed automatically when this closure returns
}
```

Migrate to `TestStorage` whenever you touch a test file that uses the old pattern.

### 6.4 No mocking concrete types

Tests use real `HistoryStore`, real audio converters, real TCP echo servers.
Mock only at protocol boundaries — inject `MockCleaner: LLMCleaning`, not a
mock `FoundationModelsCleaner`. Tests that mock the database tell you nothing
about the database.

---

## 7. Logging discipline

```swift
// Every log call: SpeakLog.<category>.<level>(...)
SpeakLog.engine.info("session started")
SpeakLog.audio.error("tap failed: \(error.localizedDescription, privacy: .public)")
SpeakLog.hotkey.debug("flagsChanged: keyCode=\(keyCode, privacy: .public)")
```

Privacy annotations are required on all dynamic content:
- `.public` — safe (IDs, error codes, booleans, non-PII strings)
- `.private` — default; redacted in production Console captures
- User speech content → **never log**, not even as `.private`

Filter in Console.app: `subsystem == "com.speak.app"` then narrow by category.

---

## 8. CLI design — apple/swift-argument-parser patterns

speak has a CLI seam (`SpeakCore/CLI/`). When a proper `speak stop` / `speak status`
CLI is built (v0.1+), follow these patterns from `apple/container` + `swift-argument-parser`:

**`AsyncParsableCommand` for async subcommands:**
```swift
// Entry point dispatches: async vs sync
var command = try SpeakCLI.parseAsRoot(args)
if var asyncCommand = command as? AsyncParsableCommand {
    try await asyncCommand.run()
} else {
    try command.run()
}
```

**`@OptionGroup` for shared flag bundles — define once, inject everywhere:**
```swift
struct Flags {
    struct Output: ParsableArguments {
        @Flag(name: .long, help: "Machine-readable output")
        var quiet = false
    }
}
// Every command:
@OptionGroup public var outputOptions: Flags.Output
```

**Extension-per-subcommand pattern (from `apple/container`):**
```swift
extension SpeakCLI {
    struct Stop: AsyncLoggableCommand {
        static let configuration = CommandConfiguration(abstract: "Stop active dictation")
        func run() async throws {
            try CFMessagePortTransport().send(CLIRequest(cmd: .stop))
        }
    }
}
```

**`AsyncLoggableCommand` protocol mixin** — adds `self.log` to every conforming
command. Mirror it but use `os.Logger` (not `swift-log`) per our no-print rule.

**`validate()` for pre-flight checks** — runs before `run()`, errors format with
usage hints automatically. Use for argument conflicts, not IPC availability.

**Key constraint:** add `swift-argument-parser` to the CLI binary target only —
never to `SpeakCore`. The framework stays dep-free. The CLI binary imports both.

**`ListDisplayable`** for `speak status` output — supports table/quiet/JSON modes
with zero extra code per format. Model `CLIReply` conformance on it.

---

## 9. Distribution — verified paths (no Developer ID cert required)

**Research findings [verified 2026-06-28]:**
- Gatekeeper targets `.app` bundles (casks), NOT binaries built locally
- Apple Silicon requires at minimum ad-hoc signing (`codesign -s -`) — an unsigned binary is kernel-rejected
- Homebrew kills unsigned official casks on **September 1, 2026** (65 days from research date)
- `apple/container` actually holds a Developer ID cert — not a "no cert" model

**Two v0 distribution paths (both cert-free):**

Path 1 — Homebrew formula + custom tap (recommended):
```sh
brew tap speak-dev/speak   # or tamilarasan/speak
brew install speak         # builds from source on user's machine; Gatekeeper never fires
```
Formula runs `make dev-cert && make build && cp -r Speak.app /Applications/`.
Requires Xcode + xcodegen — acceptable for the developer persona.

Path 2 — GitHub Release + ad-hoc signing:
```sh
# In make github-release:
codesign -s - --deep --force --timestamp=none Speak.app
ditto -c -k --keepParent Speak.app Speak.zip
# User runs once after download:
xattr -dr com.apple.quarantine Speak.app
```

**Timeline for Developer ID cert:**
- Enroll before **September 1, 2026** to qualify for official Homebrew Cask
- `make release` is already fully implemented — only the credential is missing
- P11-b in roadmap tracks this

---

## 10. Version control discipline

One commit per completed roadmap task:
```
[P11-a] install: make install + Homebrew formula + GitHub release target
[V01-0] agent mode: frontmost app detection + technical cleanup prompt
[tooling] Adopt Apple container project style conventions
[style] Apply sorted imports + switch case spacing across all source files
[chore] Ignore ai_docs/ (Apple reference; not product code)
```

Rules:
- Never commit broken code or failing tests
- Never commit secrets — no `DEV_ID`, no API keys in source
- Subagents never commit — orchestrator reviews diff, then commits
- Prefix: `[P<N>]` for roadmap tasks, `[V<NN>-<N>]` for v0.1+ features,
  `[tooling]` / `[style]` / `[chore]` / `[doc]` for non-feature work

---

## 11. Migration roadmap — pending improvements

Known improvements from auditing against Apple's container project and current
Swift community standards. Work through in priority order as bandwidth allows.

### 9.1 `@Observable` migration (6 classes)

Order: `SettingsStore` → `SnippetStore` → `HistoryViewModel` → `OnboardingViewModel`
→ `OverlayViewModel` → `DictationController`.

Each: add `@Observable`, remove `ObservableObject`, remove all `@Published`,
update call sites. Run full gates after each class.

`DictationController` is last — its migration eliminates the Combine subscription
at line 249 (which also has a redundant inner `DispatchQueue.main.async` — both go away).

### 9.2 Extension-per-responsibility splits

- `DictationController.swift` (704 lines) → extract `+Hotkey`, `+CLI`, `+ErrorHandling`
- `CaptureSession.swift` (637 lines) → extract `+Cleanup`, `+Paste`

Pure reorganization — same logic, different files. `make test` after each split.

### 9.3 Swift Testing migration (36 XCTest files)

All-new tests already use Swift Testing. Migrate existing files as you touch them.
Pure value-type tests first, then actor/async tests.

### 9.4 Typed throws — requires Swift 6 language mode first

`SpeakEngine.beginDictation/endDictation` and `CaptureSession.start/stop` only
ever throw `SpeakError`. With `throws(SpeakError)` callers handle errors exhaustively.
**Blocked on:** `SWIFT_VERSION = 6` in `project.yml`. When that is enabled, strict
concurrency warnings will surface — fix them before shipping.

---

## 12. If blocked

1. Apply research-first protocol (§2) — most blocks are wrong API assumptions
2. Re-read the relevant `docs/` section — the answer is usually there
3. Verify against the local SDK: `swiftc -typecheck` is ground truth
4. Use `apple-docs` MCP or WebSearch for post-2025 knowledge
5. Log the block in `progress.md` with exactly what you searched and found
6. Pick the next unblocked task — **never stall waiting**

If the same agent fails 3× on the same task: STOP. Rewrite the context (the
brief / the skill), not the prompt. The problem is always context, not retries.

---

## 13. Hard rules — never trade, never negotiate

- **100% local by default.** No cloud audio, no telemetry, no accounts, works offline.
- **v0 = Apple frameworks only.** SpeechAnalyzer + Foundation Models are Apple
  frameworks — allowed. Ollama/WhisperKit/MLX are v0.1+ alternatives, not v0 deps.
- **`os.Logger` only.** No `print` anywhere in `App/` or `SpeakCore/`. Linter enforces this.
- **No force-unwrap / `try!` / `as!` outside test files.** `.swiftlint.yml` makes these errors.
- **No global mutable state.** No singletons. No `var` at file scope in production code.
- **Never block the main thread.** All heavy work is `async` or actor-isolated.
- **Never read the pasteboard.** `NSPasteboard` is write-only. `PasteboardWriter` enforces this.
- **Tag every API claim.** `[verified]` / `[inferred]` / `[decision]` / `[unverified]`.
  A `[verified]` claim that contradicts a primary source → stop and surface it immediately.
- **No magic numbers.** Every constant traces to a measured value, platform constraint,
  or `[decision]` in `benchmark.md §7`.

---

## 14. Done criteria — v0 ships when ALL pass

1. `make verify-moat` → 7/7 structural BEAT rows
2. `make test` → 0 failures, all XCTSkip documented
3. `make build` → 0 warnings
4. `benchmark.md` §4 MATCH gate → all rows `[verified]`
5. `quality.md` §9 ship checklist → all rows resolved
6. P11 → `make release` produces a Gatekeeper-clean signed + notarized `.dmg`
7. P13 → 4h dogfood in Slack + code + terminal + email, latency measured
8. P14 → top 3 dogfood bugs fixed

---

## 15. Verification backbone

Trust in this order:

1. `swiftc -typecheck` against local macOS 26 SDK — **absolute ground truth**
2. `apple-docs` MCP — official Apple symbol documentation
3. `[verified]` skill claims with source cited
4. Official package README at the release tag
5. WebSearch from developer.apple.com / official GitHub repos
6. `[inferred]` skill claims — hypothesis only; verify before shipping
7. Training memory — starting point for searches, never finishing point for code

```sh
# Verify any Apple API symbol before using it:
swiftc -typecheck -sdk "$(xcrun --show-sdk-path)" \
  -target arm64-apple-macosx26.0 probe.swift
```

---

*End of loop prompt. Start with §0 load order, then §2 research-first protocol.*
