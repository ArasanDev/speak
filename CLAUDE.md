# CLAUDE.md — `speak`
macOS-native, local-first, free, open-source AI voice dictation: speech → AI-cleaned text → pasted at cursor, 100% on-device.

This file is the CC harness entry point. Read `AGENTS.md` next — it is the operating manual.

---

## Read first — every session
1. `AGENTS.md` — operating manual, hard rules, routing, the loop
2. `docs/progress.md` — current state; **rewrite last**
3. `docs/roadmap.md` — pick lowest-numbered dependency-ready task
4. `docs/benchmark.md` — the done-condition (objective function)

Load task-specific docs per the task: `docs/architecture.md` to implement, `docs/quality.md` to verify, `docs/product.md` for destination. `research/` is read-only evidence — never build direction from it. Verified facts: `specs/verification-ledger.md`.

---

## Commands
```
make build        # xcodegen generate → xcodebuild build
make test         # full suite (XCTest + Swift Testing)
make lint         # SwiftLint; force-unwrap/cast/try = errors
make verify-moat  # structural BEAT audit; no Xcode needed; re-runnable in CI
make run          # build then launch menubar app
make lsp          # configure buildServer.json for SDK-correct Swift semantics
make release      # sign + notarize + .dmg + Homebrew cask (stubbed until P11)
```

One test: `xcodebuild test -project Speak.xcodeproj -scheme Speak -derivedDataPath build/DerivedData -only-testing:SpeakTests/<Suite>/<testMethod>`

`Speak.xcodeproj` is git-ignored; `make` regenerates it via XcodeGen from `project.yml`.

**Dev-loop gotchas:**
- A clean clone has no `.xcodeproj` — `make build` generates it from `project.yml`. `project.yml` is the source of truth, never hand-edit the project.
- `speak` is a menubar `LSUIElement` app: `open` does **not** relaunch a running instance — a plain `open` after a rebuild silently keeps the stale binary. Use `make run` (kills first, then launches fresh) or `make relaunch`. Run `make doctor` if a rebuild seems ignored — it compares built-binary mtime against the running PID.
- `make generate` only re-runs xcodegen when `project.yml` or the project is missing — **new `.swift` files under globbed source dirs silently miss the target** ("cannot find X in scope" at build). Run `xcodegen generate` (or `make generate-force`) after adding files.
- `make test`/`test-fast` depend on `kill` — they stop a running Speak first (a live instance blocks the `TEST_HOST` launch; without the kill the suite "fails" at launch then self-heals on retry).
- `make gates` runs build → test → lint → verify-moat in order (the merge gate).
- Ground truth for Apple-API claims is `swiftc -typecheck` against the local **macOS 26** SDK (AGENTS.md §3) — `FoundationModels` / `SpeechAnalyzer` only resolve there.
- Live logs: `make logs` (streams `os.Logger`; `.info`/`.debug` are **not** persisted, so `log show` won't see the dictation flow — stream it live). Inspect dictations: `make history`.

---

## Hard rules (full list: `AGENTS.md §2–3`)
- **100% local.** No cloud audio, no telemetry, no accounts, works offline.
- **v0 = Apple frameworks only.** No third-party deps. `SpeechAnalyzer` + `Foundation Models` are Apple → allowed.
- **Never read the pasteboard** — only write (+ simulate Cmd+V).
- `os.Logger` only — no `print`. No force-unwrap / `try!` / `as!` outside tests. No global mutable state. Never block main thread.
- Tag claims `[verified]` / `[inferred]` / `[decision]` / `[unverified]`. Never tag an Apple-API claim `[verified]` from memory — confirm with `swiftc -typecheck` against local macOS 26 SDK.

---

## Stack
Swift 5.9+ / SwiftUI · macOS 26 (Tahoe) · Apple Silicon · not sandboxed in v0.
`SpeechAnalyzer` (STT) + `Foundation Models` (cleanup), both pluggable via `Transcribing` / `LLMCleaning`.
`CGEventTap` hotkey (double-tap Fn) · `NSPasteboard` write + Cmd+V · SQLite history · `os.Logger`.
Engine logic in `SpeakCore.framework`; App target is the SwiftUI shell. Full map: `docs/architecture.md`.
Tooling: Xcode 26+ · `xcodegen` + `swiftlint` via Homebrew. Agent team + skills: `docs/agent-tooling.md`.

### Targets & IPC topology (from `project.yml`)
The Xcode scheme builds **four products** from four source folders, wired by XcodeGen from `project.yml` (the project's source of truth — never hand-edit `Speak.xcodeproj`):

| Target | Product | Source | Role |
|---|---|---|---|
| `Speak` | `Speak.app` (bundle, `LSUIElement` menubar) | `Speak/App` | SwiftUI shell — `@main` `SpeakApp`, `MenuBarExtra`, onboarding, settings, overlay, pet, dashboard panes. Embeds `SpeakCore` + `SpeakLLM`. |
| `SpeakCore` | `SpeakCore.framework` | `Speak/SpeakCore` | Headless engine: session lifecycle (`SpeakEngine`/`CaptureSession` actors), state machine, error model, `Transcribing`/`LLMCleaning` seams, hotkey, paste, permissions, SQLite history, the agent-bridge protocol layer, voice-out TTS. **Zero target dependencies** — no `SpeakLLM` link; the `SpeakLLM`-backed `OpenAICompatibleCleaner` + `defaultCleaner(for:)` factory live in `App/Cleanup/`. |
| `SpeakLLM` | `SpeakLLM.framework` | `Speak/SpeakLLM` | The **one** sanctioned exception to "no networking symbols in production": the opt-in OpenAI-compatible cleanup client (`URLSession` + Keychain) and local inference server. Isolated in its own target so `verify-moat` can honestly assert `SpeakCore`/`App`/`CLI` have zero networking/auth symbols. Links `SpeakCore` for the shared `LLMAuthStyle` settings type. |
| `SpeakTests` | unit-test bundle | `Speak/Tests/SpeakTests` | XCTest + Swift Testing. `TEST_HOST` is `Speak.app`, so App-shell types are unit-testable via `@testable import Speak`. |

Two command-line tools (separate `SWIFT_MODULE_NAME`s to avoid APFS case-insensitive collision with `Speak.swiftmodule`):

- **`speak`** (`SpeakCLI`, `Speak/CLI/main.swift`) — drives the *running* menubar app over CFMessagePort IPC (`CLIContract` constants live in `SpeakCore`).
- **`speak-mcp`** (`SpeakMCP`, `Speak/MCP/main.swift`) — stdio MCP server (`SpeakCore/AgentBridge/`): JSON-RPC → the app's existing IPC. Owns no audio/UI. Install with `make install-mcp-user`; register with `claude mcp add` / `codex mcp add` (see README §"Voice for coding agents").

The `Eval` scheme is `Speak` with `SPEAK_EVAL=1` baked into the test action (`make eval` / `make study` run the live Foundation-Models scoring harness — these hit a real model, not headless).

### Engine pipeline (the core loop)
`HotkeyMonitor` (CGEventTap) → `SpeakEngine.beginDictation()` → `CaptureSession` actor (`idle → listening → processing → done | error`) → `AudioCapture` (AVAudioEngine 16 kHz mono) → `AppleSpeechTranscriber` (`Transcribing`, streaming partials via `AsyncStream`) → overlay (MainActor) → on stop: `FoundationModelsCleaner` (`LLMCleaning`, raw-transcript fallback if unavailable/off) → `PasteboardWriter` (NSPasteboard **write** + Cmd+V, never read) → `HistoryStore` (SQLite). `PermissionManager` gates Microphone + Accessibility (`CGEventTap .defaultTap` → Accessibility only, not Input Monitoring). Hard rule: hardware mute refuses/cancels capture — `SpeakEngineMuteTests` pins that `startStream` is never called while muted.

### Agent interaction domain (v0.1+ layer, built atop the core)
`SpeakCore/AgentBridge/` is a protocol-independent interaction runtime: agent sessions (`AgentSessionRegistry`), durable calls (`AgentCallStore` SQLite, CAS state machine with expiry), human responses, and a speech queue — exposed to MCP agents via `speak_register_session` / `speak_request_input` / `speak_submit_call` / `speak_get_call` / `speak_notify` / `speak_say` / `speak_ask` / `speak_confirm`. `speak` owns representation & delivery; the agent owns reasoning. No adapter gets ambient mic, dictation history, pasteboard, files, or screen. Design: `specs/agent-voice-bridge.md`, `specs/horizon-voice-os.md`, `specs/avb7-durable-calls-design.md`.

### App shell layout (`Speak/App/`)
`SpeakApp.swift` (`@main`, `MenuBarExtra`, DI) · `DictationController.swift` (+`+CLI`/`+ErrorHandling`/`+Knobs`/`+LivePanel`/`+Pet`/`+VoiceOut` extensions) · `Cleanup/` (`OpenAICompatibleCleaner`, `defaultCleaner(for:)` factory — the `SpeakLLM`-backed provider surface, above the `LLMCleaning` seam) · `Overlay/` (streaming `TranscriptOverlayPanel` + unified `TranscriptOverlayView` HUD) · `Pet/` (Pip, `PetState.resolve()` single source of truth) · `Dashboard/` (multi-pane window, `Panes/`) · `Onboarding/` · `Settings/` · `DesignSystem/` (`SpeakColors`/`SpeakTypography`/`SpeakMotion`). `SpeakCore/Storage/` owns `HistoryStore`, `SettingsStore`, `AgentCallStore`.

---

## Done condition
v0 complete when: `benchmark.md §4` MATCH gate + `§3` BEAT rows + `quality.md §9` ship checklist all pass.
v0 = complete core (incl. AI neat-writing), not an MVP. v1/v2/v3+ = attractive/friendly/creative (`product.md §9`).

---

## Commit
`[P<N>] <task>: <what changed>` — one commit per completed roadmap task. Full rules: `AGENTS.md §7`.

## CI
Local is the validation gate — `.github/workflows/ci.yml` is **release-time only**, not per-push:
- **`moat-audit`** (ubuntu) — `make verify-moat`, runs on `pull_request` only (guards external contributions; ~30s, free).
- **`build-test-lint`** (`macos-26` image — must pin, `FoundationModels`/`SpeechAnalyzer` only resolve on the macOS 26 SDK) — `workflow_dispatch` only; trigger it manually from the Actions tab when cutting a release, after `make gates` is green locally.

## Privacy is structural, not a setting — enforced by audit
"100% local, no egress, no accounts, no third-party deps, no pasteboard reads, no `print`" is not a claim but a **regression-gated proof**: `scripts/verify-moat.sh` + `SpeakTests/MoatAuditTests.swift` grep every import and networking/auth/paywall symbol in `SpeakCore`/`App`/`CLI` and fail the build if any appear. `SpeakLLM` (opt-in cloud cleanup) is deliberately its own target *outside* the audited directories so the audit's assertion stays honest while still allowing explicitly user-configured cloud cleanup. Don't add `URLSession`/`SecItem*`/`print`/force-unwrap to audited targets — the build will break.
