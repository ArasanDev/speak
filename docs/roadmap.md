# `speak` — Build Roadmap (ORDER)

> **Status**: The execution sequence. Ordered by **dependency**, not date.
> "Done when" criteria are **testable** (binary pass/fail). There are no effort
> sizes, no dates, and no time estimates anywhere in this file — the build loop
> runs until the product is whole.
>
> **Depends on**: `product.md`, `architecture.md`. **Depended on by**:
> `quality.md`, `progress.md`. **Updated**: 2026-06-20.

---

## 0. How to use this doc

- **Every session**: read `progress.md` first, then find the lowest-numbered
  undone task whose dependencies are met. That's your next task.
- **Done-when**: must be binary testable. If you can't prove it, it's not done.
- **Critical path**: P0 → P2 → P3 → P3.5 → P5 → P6 → P11 → P13. (P1, P4, P7,
  P8, P9, P10, P12 can parallelize once their own dependencies are met.)
- Update `progress.md` after each task. Commit per task.

---

## Phase 0 — Repo setup

**Task**: `git init`, Xcode project (app + `SpeakCore.framework` + `SpeakTests`),
directory layout per `architecture.md` §5, `README.md` skeleton, `LICENSE`
(MIT), `.gitignore` (Xcode/Swift/macOS), `.swift-version` (5.9+),
`Makefile`/`justfile` for common tasks, GitHub Actions CI (build + lint).

**Done when**:
- [x] `make build` produces a runnable `.app` from a clean clone ✓ (XcodeGen →
      `xcodebuild`; verified `make clean && make build`)
- [x] `SpeakCore.framework` is a separate build target (the portability seam) ✓
- [~] CI runs on every push: `xcodebuild build` + `swiftlint` — workflow authored
      (`.github/workflows/ci.yml`); **[unverified]** until repo has a remote + push
- [x] `LICENSE` is MIT; `.gitignore` covers `DerivedData/`, `.build/`,
      `*.xcuserstate`, `DS_Store` ✓

---

## Phase 1 — Menubar scaffold

**Task**: `SpeakApp.swift` with `MenuBarExtra` (idle icon) + "About" panel.
Inject an empty `SpeakEngine` into the SwiftUI environment.

**Done when**:
- [x] `speak` shows in the menubar on launch ✓ (waveform icon; launched + verified)
- [x] Clicking the icon opens a menu with an "About…" item ✓
- [x] App runs as a `LSUIElement` (no dock icon, menubar only) ✓

---

## Phase 2 — Audio capture  ← **CRITICAL PATH**

**Task**: `PermissionManager` (microphone state) + `AudioCapture`
(`AVAudioEngine`, 16kHz mono PCM). Stream raw PCM buffers to an `AsyncStream`.

**Done when**:
- [ ] First run triggers the microphone permission prompt
- [ ] Speaking into the mic logs PCM buffer stats (sample rate, length) via
      `os.Logger` — no `print`
- [ ] Audio stops cleanly on session cancel (no zombie taps)

---

## Phase 3 — SpeechAnalyzer  ← **CRITICAL PATH**

**Task**: Define the `Transcribing` protocol. Implement
`AppleSpeechTranscriber` against Apple `SpeechAnalyzer` (macOS 26+, Apple
Silicon). `[verified]` Feed PCM buffers in, emit `TranscriptChunk` (partial
+ final).

**Done when**:
- [ ] Spoken audio produces **partial** transcripts (streaming, live)
- [ ] Spoken audio produces a **final** transcript at session end
- [ ] Engine id is `"apple-speech-en-US"`
- [ ] Verify against `architecture.md` §10.2 (re-check SpeechAnalyzer API
      surface vs current Apple docs before coding)

---

## Phase 3.5 — LLM cleanup pipeline  ← **CRITICAL PATH**

**Task**: Define the `LLMCleaning` protocol (verbatim signature from
`architecture.md` §6). Implement `FoundationModelsCleaner` — the Apple
on-device Foundation Models framework. `[verified]` This is an Apple framework
and does **not** violate the no-third-party-deps rule (`AGENTS.md` §2.9).

Wire cleanup into `CaptureSession`'s `processing` state:
`stop() → finalize transcript → clean (if enabled & available) → result`.
`TranscriptionResult.cleanedText` is `String?` — `nil` when cleanup is off or
the engine is unavailable. When the engine is unavailable, fall through to raw
paste and reach `done`; do not enter `error` state solely due to cleanup
failure.

Implement a `cleanupEnabled: Bool` setting (persisted in `SettingsStore`) and
the engine-availability check. Verify the Foundation Models API surface against
Apple docs before coding; tag any inference `[inferred]`.

**Depends on**: P3 (transcript available), P10 (settings toggle) — P10 may be
stubbed for the toggle; fully wired in P10 proper.

**Done when**:
- [x] A sample dictation produces **cleaned** output when `cleanupEnabled` is
      `true` and Foundation Models is available — `[verified]` via the
      `CaptureSession` orchestration against a mock cleaner
      (`testStopWithCleanerAvailableProducesCleanedText`); **live cleanup
      quality stays `[inferred]`** until P13 dogfood on a Mac with Apple
      Intelligence enabled (gated off on the dev Mac as of 2026-06-20).
- [x] With `cleanupEnabled = false`, `cleanedText` is `nil` and raw text is
      pasted — `cleanedText == nil` and `engineId == STT id` verified
      (`testStopWithCleanerNilHasCleanedTextNil`); the *paste* half is P6.
- [x] When Foundation Models is **unavailable**, session gracefully falls back
      to raw transcript and reaches `done` state (not `error`) — verified
      (`testStopWithCleanerUnavailableFallsBackToRawNoError`).
- [x] `SpeakError.llmCleanupFailed` is surfaced only on a genuine API
      failure, not on unavailability — verified (SpeakError path + generic
      Error→SpeakError mapping + unavailable-doesn't-throw path).
- [x] Engine id is stored in `TranscriptionResult.engineId` when cleanup
      runs — verified (`engineId == "<stt>+<cleaner>"`).
- [x] No third-party dependencies introduced — Apple Foundation Models only.
- [x] Foundation Models API surface verified against current Apple docs
      (SDK-anchored, see comments at the top of
      `SpeakCore/Cleanup/FoundationModelsCleaner.swift`).

---

## Phase 4 — Partial overlay

**Task**: Floating `NSPanel`/SwiftUI overlay that streams the partial
transcript in real time. Auto-position near cursor or top-right, always-on-top.

**Done when**:
- [~] Overlay appears when session enters `listening` state — `[verified]` the
      wiring (`DictationController` shows the panel on `.listening`, hides on
      `.done`/`.error`); **live appearance** `[deferred — visual]` (§4.3)
- [~] Partial transcript text updates live (≤200ms lag — `benchmark.md` §7
      `L_partial`) — `[verified]` accumulation logic (`OverlayTextAccumulator`,
      11 tests) + drains `currentPartials()`; **live lag** `[deferred — visual]`
      (headless proxy ≈ 42 ms p50; live includes mic + SpeechAnalyzer overhead)
- [~] Overlay hides on `done` / `error` — `[verified]` the hide wiring;
      **live** `[deferred — visual]`

---

## Phase 5 — Hotkey  ← **CRITICAL PATH**

**Task**: `HotkeyMonitor` using `CGEventTap`. Detect double-tap Fn (400ms
window — `benchmark.md` §7, `[decision]`, tune empirically in P13) → emit
`startCapture`. Detect single-tap Fn after start → emit `stopCapture`. Persist
binding in `UserDefaults`. Default binding:
`HotkeyBinding(keyCode: kVK_Function, modifiers: [], trigger: .doubleTap,
doubleTapWindow: 0.4)`.

**Done when**:
- [~] Double-tap Fn triggers start while **another app has focus** —
      `[verified]` pure detector logic (DoubleTapDetector tests, injected
      timestamps); `[deferred — needs human verification]` live OS + other-app
      focus with Accessibility granted
- [~] Single-tap Fn triggers stop while another app has focus —
      `[verified]` pure detector logic; `[deferred — needs human verification]` live OS
- [~] First run triggers Accessibility permission prompt (Microphone handled separately) —
      `[deferred — needs human verification]` (requires live non-sandboxed run)
- [ ] False-trigger rate < 1 per 30 min in normal typing, tested in Notes
      (single source for `F_rate` in `benchmark.md` §7) — P13 dogfood

---

## Phase 6 — Paste  ← **CRITICAL PATH**

**Task**: `PasteboardWriter` per `architecture.md` §11 — write to
`NSPasteboard`, simulate `Cmd+V`. Wire to `CaptureSession` state machine:
`processing → clean (if cleanup enabled & available) → paste → done`.

The text pasted is `TranscriptionResult.cleanedText` when cleanup is on and
produced output; otherwise `rawText`. The session must reach `done` in both
cases.

**Done when**:
- [~] When cleanup is **on**: cleaned text (filler-free, punctuated) pastes
      into the focused app — `[verified]` selection logic (`CaptureSession`
      hands `cleanedText` to the inserter, `testInserterReceivesCleanedText…`);
      `[deferred — needs human verification]` the actual live paste
- [~] When cleanup is **off** or unavailable: raw transcript pastes instead —
      `[verified]` selection logic (inserter receives `rawText` in both the
      `cleaner=nil` and unavailable paths); `[deferred]` live paste
- [ ] Final transcript (cleaned or raw) pastes into focused text field in
      **TextEdit, Slack, Terminal** (3 different app categories) —
      `[deferred — needs human verification]`
- [ ] No macOS 26.4 paste-protection prompt appears (we write, never read) —
      `[deferred — needs human verification]` (**project's #1 `[unverified]`**:
      the Terminal paste-provenance check; test in Terminal/iTerm first)
- [ ] Paste fails gracefully (error state) in password fields —
      `[deferred — needs human verification]`

---

## Phase 7 — Permissions flow

**Task**: Full 2-permission onboarding window. Microphone (runtime prompt),
Accessibility (deep-link to `x-apple.systempreferences:com.apple.preference.security`
with the app selected). Explain *why* each is needed with a screenshot per permission.
Input Monitoring removed in v0.2 — `.defaultTap` is Accessibility-gated only.

**Done when**:
- [~] A fresh user can grant both permissions and reach a working dictation
      with no confusion — `[verified]` the step-state machine
      (`OnboardingStateMachine`, 14 tests) + mic/accessibility status backends;
      **the rendered flow + comprehension** `[deferred — visual]`
      (§4.4)
- [~] Deep-links open the correct System Settings pane — `[verified]` the
      deep-link URLs are wired; **that they open the right pane** `[deferred —
      needs human verification]`
- [~] Permission revocation mid-session is detected → state moves to error —
      `[verified]` the wiring (`showOnboardingIfNeeded()` re-surfaces on
      permission-denied catches; monitor-start failure → `permissionsNeeded`);
      **live revocation behavior** `[deferred — visual]`

---

## Phase 8 — Menubar states

**Task**: Menubar icon reflects `CaptureSession.State`: gray waveform (idle),
red dot (listening), yellow spinner (processing), green flash (done), red X
(error).

**Done when**:
- [~] Icon changes on every state transition — `[verified]` the wiring:
      `MenuBarLabel` renders a distinct SF Symbol per `MenubarIcon`
      (idle/listening/processing/done/error, `MenubarIconTests`), `DictationController`
      drives idle→listening→**processing**→done→idle. **Distinct *color*** (red/
      yellow/green vs monochrome SF Symbols) + the live visual `[deferred — visual]`.
- [~] "Done" green flash lasts 600ms then returns to idle — `[verified]` the
      600 ms timing in `DictationController.endDictation` (single-sourced to this
      row); the live visual flash `[deferred — visual]`.

---

## Phase 9 — History

**Task**: `HistoryStore` (SQLite, `~/Library/Application Support/speak/`).
Store `HistoryEntry` (raw + cleaned text, timestamp, engine id). Capacity is a
tunable setting (not a hardcoded constant — see `benchmark.md` §7 "history
size"). Searchable from a History window.

**Done when**:
- [x] Every completed session writes a `HistoryEntry` (with `cleanedText`
      when cleanup ran, `nil` otherwise) — `[verified]` `HistoryStore.save()`
      round-trips both `cleanedText`-present and `nil` (`testNilCleanedTextRoundTrips`),
      **and the end-to-end wiring is now in place**: `SpeakEngine.endDictation`
      builds a `HistoryEntry` from the result and calls `history.save(_:)`
      (best-effort: logged + swallowed so a DB failure never fails a dictation
      whose text already pasted). Verified by `SpeakEngineIntegrationTests`
      (exactly one entry after a real-component dictation).
- [x] History persists across app launches — `[verified]`
      (`testSaveAndReopenPersistence`: a second `HistoryStore` on the same file
      reads back saved entries)
- [x] Search by substring returns matching entries — `[verified]` (matches in
      both `rawText` and `cleanedText`; empty on no match)
- [x] "Clear history" empties the store — `[verified]` (`testClearEmptiesStore`)
- [x] "Export" produces a readable file (plain text or JSON) — `[verified]`
      (JSON, ISO-8601 dates; `testExportContainsEntriesText`)
- [~] **History window (UI)** — search/clear/export surfaced in a SwiftUI
      window — `[verified]` the wiring: `HistoryView` + `HistoryWindowController`
      (opened from the "History…" menu item) bind to a `HistoryViewModel` that
      reads the shared `historyStore` via `recent`/`search`/`clear`/`export`;
      the **rendered window + NSSavePanel** are `[deferred — visual]`
      (human-verification.md §4.5).

---

## Phase 10 — Settings

**Task**: `SettingsStore` (typed `UserDefaults` wrapper). `Settings` SwiftUI
window: hotkey rebinding, language picker (en-US, en-GB minimum), auto-paste
toggle, paste mode (Cmd+V vs AX), **AI cleanup toggle** (on/off), cleanup
engine selector (Foundation Models default; placeholder for future Ollama/MLX
in v1).

**Done when**:
- [x] All settings persist across launches — `[verified]` (`SettingsStoreTests`:
      every property + enum encodings round-trip on a fresh store)
- [~] User can rebind the hotkey to a custom key/modifier combo — `[verified]`
      binding persistence (`UserDefaultsBindingStore`, P5); **live rebind UX**
      (record a key combo in the window) `[deferred — visual]`
- [~] Language picker lists at least en-US, en-GB — `[verified]` store holds the
      locale (en-US/en-GB); **the picker rendering** `[deferred — visual]`
- [~] Cleanup toggle is active and functional (toggles the P3.5 path) —
      `[verified]` the gating logic: `defaultCleaner(for:)` returns `nil` when
      `cleanupEnabled == false`, and `SpeakEngine.newSession()` re-reads it so the
      toggle applies per-dictation; **the live UI toggle** `[deferred — visual]`
- [~] Cleanup engine selection is present in the UI (Foundation Models default;
      v1 alternatives as disabled placeholders) — built; `[deferred — visual]`

---

## Phase 11-a — Build-from-source install  ← **CRITICAL PATH (unblocked)**

**Research finding [verified 2026-06-28]:** Gatekeeper targets `.app` bundles
(casks), not CLI binaries built locally. A Homebrew formula that builds from
source on the user's machine never triggers Gatekeeper — no Developer ID cert
required. Apple Silicon also requires at minimum ad-hoc signing (`codesign -s -`)
for any binary; a completely unsigned `.app` is rejected by the kernel.
`make dev-cert` (self-signed identity) already satisfies this.

**Two v0 distribution paths (no cert required):**
1. **Homebrew formula in custom tap** — `brew tap speak-dev/speak && brew install speak`
   clones + builds on the user's machine. Gatekeeper never fires. Requires Xcode +
   xcodegen (fine for the developer persona).
2. **GitHub Release + ad-hoc signing + xattr** — `codesign -s - --deep --force Speak.app`,
   zip, publish. Users run `xattr -dr com.apple.quarantine Speak.app` once.
   Right-click → Open is the GUI alternative.

**Done when**:
- [x] `make dev-cert` creates a stable local signing identity (self-signed)
- [x] `make build` produces a runnable `Speak.app` from a clean clone `[verified]`
- [ ] `make install` copies `Speak.app` to `/Applications/` (add this target)
- [ ] `make github-release` ad-hoc signs, zips, and produces a release artifact
- [ ] `dist/speak.rb` Homebrew formula (custom tap, build-from-source) created
- [ ] `README.md` install section covers both paths with exact commands

---

## Phase 11-b — Developer ID sign + notarize + Homebrew Cask  ← **TIME-SENSITIVE**

**Hard deadline: September 1, 2026** — Homebrew ends support for casks that
fail Gatekeeper checks on that date. Official `homebrew-cask` tap requires
notarization after that deadline. Custom taps are exempt but limit discoverability.
This is **65 days from 2026-06-28** — enroll in Apple Developer Program promptly.

**Depends on**: Developer ID Application certificate ($99/yr via developer.apple.com).
Does NOT block v0 ship — blocks only official Homebrew Cask and zero-friction install
for non-developer users.

**Task**: Developer ID signing, notarization, `.dmg`, official Homebrew Cask.
Full `make release` implementation already in `Makefile` and `docs/release.md`.
Nothing to build — only the credential is missing.

**Done when** (execute once cert is enrolled):
- [ ] `make release` produces a signed + notarized `.dmg`
- [ ] `brew install --cask speak` works on a clean machine (official tap)
- [ ] Gatekeeper shows "verified" (no "unidentified developer")
- [ ] `dist/speak.cask.rb` sha256 updated post-release

---

## Phase 12 — Docs + demo

**Task**: Public-facing `README.md` (what it is, install, privacy section,
hotkey help), screenshots, demo GIF, `CONTRIBUTING.md`, `CHANGELOG.md`.

**Done when**:
- [x] README answers: what is it, how to install, how to use, privacy stance —
      `[verified]` (full rewrite; build-from-source path; honest pre-release status)
- [x] Privacy section states all 5 guarantees from `product.md` §8 — `[verified]`
      (all 5 listed; #1/#2/#3/#5 cite the `make verify-moat` automated proof;
      #4 hardware-mute framed as design posture, not yet implemented)
- [ ] Demo GIF shows the headline flow end-to-end (hotkey → overlay → paste) —
      `[deferred — needs human verification]` (requires a live recorded run; §5)
- [~] Repo is public-ready — docs in place; gated on the live-verification pass
      + P11 notarized release before a public tag

---

## Phase 13 — Dogfood  ← **CRITICAL PATH**

**Task**: Sustained real use across Slack, code comments, terminal, email.
Log: latency (raw and with cleanup), false triggers, missed words, permission
edge cases, cleanup quality. File bugs. The double-tap window (400ms) is
confirmed or tuned here (`benchmark.md` §7, `[decision]`). WER tolerance
`T_wer` is evaluated here (`benchmark.md` §7, revisit if SpeechAnalyzer fails
the MATCH gate).

**Done when**:
- [ ] Real-use dogfood notes logged in `progress.md` covering all four
      contexts (Slack, code, terminal, email)
- [ ] Top 3 bugs filed with repro steps
- [ ] Latency measured: median stop→paste (raw only) and stop→paste
      (with cleanup); both logged against `benchmark.md` §7 targets

---

## Phase 14 — Fix top 3 dogfood issues

**Task**: Close the top 3 bugs from P13.

**Done when**:
- [ ] Median stop→paste (raw, no cleanup) < 1.0s (benchmark `L_e2e` raw path)
- [ ] Median stop→paste (with on-device cleanup) < 2.0s (benchmark `L_e2e`
      incl. cleanup)
- [ ] No false triggers in normal typing
- [ ] No permission edge cases: revocation, re-grant, and OS-upgrade scenarios
      tested

---

## v0 ship gate (after P14)

v0 ships when **all four** of the following hold — no exceptions:

1. **`benchmark.md` §4 MATCH gate**: all checkboxes pass (accuracy, neat
   writing, latency, live feedback, paste, hotkey, history).
2. **`benchmark.md` §3 BEAT rows**: all seven structural moat rows hold
   (100% local, free, MIT, no account, local history, lower latency, no
   egress).
3. **`quality.md` §9 ship checklist**: build/sign/notarize clean, no `print`,
   no force-unwrap, paste-protection clean, etc.
4. **P11-a done**: `make install` works from a clean clone; README install
   section accurate.

**v0 does NOT require P11-b** (Developer ID cert). v0 ships as a
build-from-source developer preview, same model as `apple/container`.
P11-b gates the Homebrew Cask and public tag — that is v0.1 distribution.

Tag `v0.0.1` and publish only when all four are verified, measured, not
asserted.

---

## v0.1 — Language, Engine & Intelligence

*Value*: pluggable STT engines, real Ollama cleanup, per-app context awareness,
and multi-binding hotkeys. All are additive — the v0 moat is untouched.

Each task below is an independently shippable unit with a binary gate.
**Prerequisite: v0 ships (`benchmark.md` §4 + §3 + `quality.md` §9 all pass).**

---

### V01-0 — Coding agent integration (Agent Mode)

**Task**: When the frontmost app is a coding agent terminal (Claude Code CLI,
Cursor, VS Code integrated terminal, Terminal.app, iTerm2), `speak` activates
**Agent Mode** automatically. In Agent Mode: the cleanup prompt is replaced with
an imperative technical-task formatter (preserves exact variable names / file paths /
technical terms; rephrases as clear imperative instructions; removes filler and
conversational phrasing); the overlay shows an `[Agent Mode]` badge; an optional
auto-submit fires a simulated Return key after paste so the prompt goes immediately
to the agent without a keypress.

Detection uses `NSWorkspace.shared.frontmostApplication?.bundleIdentifier` matched
against a configurable list. Default list (these are `[unverified]` — confirm bundle
IDs with `osascript -e 'id of app "Claude"'` before shipping):
- `com.anthropic.claudecode` (Claude Code CLI wrapper)
- `com.todesktop.230313mzl4w4u92` (Cursor)
- `com.microsoft.VSCode`
- `com.apple.Terminal`
- `com.googlecode.iterm2`
- `dev.zed.zed`

Settings › Transcription: "Agent apps" section with user-editable bundle ID list
(add / remove; resets to default on button). Auto-submit toggle, default off.

Files: `SpeakCore/Context/AgentModeDetector.swift` (new), extend
`AppContextDetector.swift` (or share the `AppContext` seam from V01-3),
`SpeakCore/Cleanup/CleanupPromptBuilder.swift` (inject agent-mode clause),
`App/Overlay/OverlayView.swift` (badge), `App/Settings/SettingsView.swift`,
`SettingsStore.swift` (`agentBundleIDs: [String]`, `agentAutoSubmit: Bool`).

**Depends on**: v0 ship gate. Shares the `AppContext` bundle-ID detection seam
with V01-3 (per-app context awareness) — implement V01-0 and V01-3 in the same
sprint or extract the detection logic so both tasks build on it. Either order is
fine; V01-0 is listed first because its user-felt impact is highest.

**Done when**:
- [ ] Frontmost app = Claude Code CLI (or Terminal.app) → overlay shows
      `[Agent Mode]` badge within 200 ms of dictation start
- [ ] Same 50-word casual speech dictated in Agent Mode vs TextEdit produces
      noticeably more imperative, technical-term-preserving output (manual verify)
- [ ] Agent Mode + auto-submit OFF → no Return key simulated after paste
- [ ] Agent Mode + auto-submit ON → Return key simulated after paste (verify in
      Terminal.app without causing unintended command execution in test)
- [ ] Settings › Transcription shows "Agent apps" list; adding/removing bundle IDs
      persists across launch; default list restores on Reset
- [ ] Bundle IDs verified against running apps via `osascript` — tag claims `[verified]`
- [ ] `make test` 0 failures; new `AgentModeTests` suite: bundle ID detection
      (match / no-match / custom list), prompt injection present, auto-submit toggle
      (mock paste recorder), badge visibility
- [ ] `make verify-moat` 7/7 (AX read of frontmost app is allowed; no network egress)

---

### V01-1 — WhisperKit STT engine

**Task**: Wire WhisperKit v1.0.0 (Argmax, MIT, `argmax-oss/argmax-oss-swift`) as
a real `Transcribing` conformer behind `EngineFactories.defaultTranscriber(for:)`.
Add a model picker in Settings › Transcription (SpeechAnalyzer default / WhisperKit
base / WhisperKit large-v3-turbo). Implement a guided first-run model-download sheet
(~2 GB for large-v3-turbo; async with progress bar; cancellable). Wire language
auto-detection: when `settings.language == "auto"`, pass `nil` locale to WhisperKit
and surface the detected language in the overlay. Files touched:
`SpeakCore/STT/WhisperKitTranscriber.swift` (new), `EngineFactories.swift`,
`SettingsStore.swift` (add `sttModelVariant`), `App/Settings/SettingsView.swift`.

**Depends on**: V0 shipped; P3 (`Transcribing` protocol); P10 (settings seam).

**Done when**:
- [ ] `WhisperKitTranscriber` compiles and passes lint + moat (no new non-Apple SPM
      deps in the moat-scanned dirs — WhisperKit lives in a `SpeakLLM`-style
      sub-module or is moat-exempted with a `[decision]` comment)
- [ ] WhisperKit transcribes the `hello_speech.caf` fixture with WER ≤ 3%
- [ ] Model picker in Settings shows the three options; selection persists across launches
- [ ] First-run download sheet appears when `WhisperKit large-v3-turbo` is selected
      and the model file is absent; shows progress; completes without crash
- [ ] `settings.language == "auto"` uses WhisperKit language detection; overlay shows
      detected language badge
- [ ] All 4 gates green: `make build` / `make test` / `make lint` / `make verify-moat`
- [ ] `benchmark.md` Languages row updated: v0.1 SpeechAnalyzer installed locales ✓;
      v1 WhisperKit 99-lang ✓

---

### V01-2 — Universal OpenAI-compatible LLM cleanup engine

**Task**: Rename `SpeakCore/Cleanup/OllamaModelCleaner.swift` → `OpenAICompatibleCleaner.swift`
and generalize it into a single `URLSession`-based `LLMCleaning` conformer that works with any
OpenAI-compatible endpoint. Ships with 6 built-in presets:

| Preset | Base URL | Auth | Default model |
|--------|----------|------|---------------|
| `.ollama` | `http://127.0.0.1:11434/v1` | none (loopback) | `qwen2.5:3b` |
| `.sarvamLLM` | `https://api.sarvam.ai/v1` | `api-subscription-key` | `sarvam-30b` |
| `.openAI` | `https://api.openai.com/v1` | Bearer | `gpt-4o-mini` |
| `.groq` | `https://api.groq.com/openai/v1` | Bearer | `llama3-8b-8192` |
| `.openRouter` | `https://openrouter.ai/api/v1` | Bearer | (user sets) |
| `.custom(url, authStyle, model)` | user-entered | user-sets | user-sets |

Endpoint: `POST <baseURL>/chat/completions` (standard OpenAI chat completions format). Auth
style is per-preset: Bearer header OR `api-subscription-key` header (Sarvam). API keys stored
in Keychain (`kSecClassGenericPassword`). Zero new Swift package dependencies — pure URLSession +
Codable. Foundation Models remains the default; this engine is opt-in. Files touched:
`SpeakCore/Cleanup/OpenAICompatibleCleaner.swift` (renamed from OllamaModelCleaner),
`EngineFactories.swift`, `App/Settings/CleanupEngineSheet.swift` (new), `SettingsStore.swift`.

See `openai-compatible-cleanup` skill for full API shapes, error handling, and curl tests.

**Depends on**: V0 shipped; P3.5 (`LLMCleaning` protocol); P10.

**Done when**:
- [ ] `OpenAICompatibleCleaner.clean(_:mode:)` returns cleaned text from Ollama running
      `qwen2.5:3b` for a 50-word raw transcript in ≤ 3 s on M2 or later
- [ ] Sarvam preset: same clean() call with `api-subscription-key` auth header and
      `sarvam-30b` model returns cleaned text (requires API key)
- [ ] `isAvailable` returns `false` when Ollama preset and Ollama is not running;
      cloud presets return `true` when API key is non-empty
- [ ] Settings → AI Cleanup: engine picker (On-device / Local server / Cloud), preset
      dropdown, URL/key/model fields, green/red availability dot; persists across launches
- [ ] API keys stored in Keychain; Settings field is `SecureField`; no key in UserDefaults
- [ ] Moat: `testNoNetworkEgress` still passes; Ollama = loopback `[decision]`-tagged;
      cloud = explicit user config; `make verify-moat` 7/7
- [ ] `OpenAICompatibleCleanerTests`: Ollama request shape, Sarvam auth header present,
      response parse, fallback to FoundationModels on error — 4+ tests; 0 failures
- [ ] Foundation Models remains default engine; OpenAI-compatible is opt-in only

---

### V01-3 — Per-app context awareness

**Task**: At dictation start, read the frontmost application's bundle ID via
`NSWorkspace.shared.frontmostApplication?.bundleIdentifier`. Map the bundle ID to
an `AppContext` enum: `.codeEditor` (Xcode, Cursor, VS Code, Zed), `.email` (Mail,
Airmail, Spark), `.workMessaging` (Slack, Teams, Discord), `.personalMessaging`
(Messages, WhatsApp, Telegram), `.aiTool` (Claude.app, ChatGPT.app), `.browser`
(Safari, Chrome, Firefox — further classify by page title if AX permits), `.other`.
Inject the context into `CleanupMode` at `CaptureSession` init time so the cleanup
prompt adapts: code editors → camelCase-friendly, no filler removal, preserve
symbols; email → formal tone, read recipient from AX if available; messaging → casual;
AI tools → no formatting adjustment. Add per-app override settings (Settings › AI
Cleanup › Per-App Context) and a global toggle. `AppContextDetector` is a new type in
`SpeakCore/Engine/`, keeping all AX reads on `@MainActor`. No context data is stored
or transmitted — it is read once per dictation and injected into the prompt only.

**Depends on**: V0 shipped; P3.5 (`CleanupMode`); P10.

**Done when**:
- [ ] Dictating "let me add a new variable called user name" in Xcode produces
      `let userName` (or `let user_name`) in the cleaned output — confirmed by a
      `[verified]` live test logged in `progress.md`
- [ ] Dictating the same phrase in Messages produces casual unformatted output
- [ ] Global context awareness toggle in Settings disables the behavior (output matches
      the no-context baseline)
- [ ] `AppContextDetector` is a pure `@MainActor` type; no background-thread AX reads
- [ ] No app context data written to history, logs, or any file — confirmed by
      `MoatAuditTests` grep pass
- [ ] All 4 gates green

---

### V01-3s — Sarvam STT engine (Saaras v3, 23 Indian languages)

**Task**: Implement `SarvamSpeechTranscriber` conforming to `Transcribing`. Sends audio to
`POST https://api.sarvam.ai/speech-to-text` as `multipart/form-data`. Default mode: `codemix`
— handles Tamil+English ("Tanglish"), Hindi+English ("Hinglish") and 23 Indian languages
natively. This is the **India-first moat**: no local STT model handles code-switching this well.

**30-second chunking**: Sarvam REST API accepts max 30s of audio per request. Record continuously;
detect silence boundaries (RMS < threshold for 0.5s) to split at ≤ 25s; force-split at 25s if no
silence. Send chunks sequentially via `URLSession`; concatenate `transcript` fields with `" "`.
Emit `TranscriptChunk(isFinal: false)` per chunk; final chunk emits `isFinal: true`.

API key stored in Keychain only. Fallback: if no network, no key, or Privacy Mode on → use
`AppleSpeechTranscriber` silently. Language: user selects from 23 Indian languages + Auto-detect
(`language_code: "unknown"`) in Settings → Transcription.

See `sarvam-stt` skill for exact API shape, language codes table, mode options, error handling,
curl tests, and pricing reference.

Files touched: `SpeakCore/STT/SarvamSpeechTranscriber.swift` (new), `EngineFactories.swift`,
`SettingsStore.swift` (add `sttEngine`, `sarvamLanguage`, `sarvamMode`),
`App/Settings/SettingsView.swift` (Transcription tab: STT picker + language + mode).

**Depends on**: V0 shipped; V01-1 (establishes transcriber-swap pattern); V01-3 (AppContext
can feed detected language hint to Sarvam for better auto-detect).

**Done when**:
- [ ] `SarvamSpeechTranscriber` compiles and passes lint; engine id `"sarvam-saaras-v3"`
- [ ] Audio recorded as 16kHz mono WAV and sent as multipart; `transcript` field extracted
- [ ] `codemix` mode is default when language is Indian or `"unknown"`; user can switch to
      `transcribe` / `verbatim` in Settings
- [ ] 30s chunking: a 90-second recording generates 4 sequential requests; transcripts joined
      correctly — verified by `SarvamSpeechTranscriberTests.testChunkingOf90sAudio`
- [ ] Language picker lists all 23 Sarvam languages + "Auto-detect"; persists across launches
- [ ] API key stored in Keychain (`SecureField` in Settings); absent key → silent fallback
- [ ] Privacy Mode on → zero audio sent to Sarvam; `MoatAuditTests` confirms no egress path
- [ ] No-network → fallback to `AppleSpeechTranscriber`; HUD: "Using on-device STT"
- [ ] `SarvamSpeechTranscriberTests`: multipart field names correct, response parse, chunking
      logic (mock 90s audio → 4 chunks), fallback on 401 and no-network — 4+ tests, 0 failures
- [ ] `make verify-moat` 7/7; Sarvam audio path only active when user has explicitly configured key

---

### V01-4 — Auto-dictionary learning from corrections

**Task**: After every successful paste, register a one-shot `NSPasteboard` change
observer (or poll at 200ms intervals for 5 s via a `Task.sleep` loop) on
`NSPasteboard.general`. If the pasteboard content changes within 5 s (user copied
corrected text), diff the pasted text vs the new clipboard content using
`SpeakCore/Diff/TextDiff.swift` to extract changed words. For each substituted word
(e.g. "Widl" → "Widdle"), show a non-intrusive `NSUserNotification`-style HUD in the
overlay: "Add 'Widdle' to your dictionary? [Add] [Skip]". On [Add], append to
`SettingsStore.customVocabulary`. Cap auto-proposals at 3 per session to avoid
notification fatigue. `[decision]` Note: never read the pasteboard for dictated content
— this reads only the *new* clipboard value that the user *explicitly* copied
post-correction, which does not violate the no-pasteboard-read rule.

**Depends on**: V0 shipped; P6 (`PasteboardWriter`); P10 (`customVocabulary` seam H4).

**Done when**:
- [ ] After a paste, user copies corrected text; overlay HUD appears within 6 s
      proposing the substituted word
- [ ] Tapping [Add] adds the word to `SettingsStore.customVocabulary`; confirmed by
      next session injecting it into `SpeechAnalyzer` contextualStrings
- [ ] Tapping [Skip] dismisses with no side effect
- [ ] Max 3 proposals per session — 4th correction in same session produces no HUD
- [ ] `testNoPasteboardRead` still passes (the read is of user-copied content, not
      `speak`-written content — moat comment documents the distinction)
- [ ] All 4 gates green

---

### V01-5 — Multiple hotkey bindings per action + mouse buttons

**Task**: Extend `HotkeyBinding` and `HotkeyMonitor` to support up to 4 simultaneous
key bindings per action (start/stop, command mode). Each binding is an independent
`CGEventTap` filter or a shared tap with an extended match set. Add mouse button
support for dictation trigger: extend the event tap to include
`CGEventType.otherMouseDown` (middle click) and custom high-button events (buttons
4–10) via `CGEvent.getIntegerValueField(.mouseEventButtonNumber)`. Persist the full
binding set in `BindingStore`. Update Settings › Shortcuts to show up to 4 rows per
action with [+] / [−] controls.

**Depends on**: V0 shipped; P5 (`HotkeyMonitor`, `HotkeyBinding`); P10.

**Done when**:
- [ ] User binds both Right-Command and middle-click to start dictation; both fire
      correctly in a live test logged in `progress.md`
- [ ] Binding a 4th shortcut is permitted; attempting a 5th shows an error in the UI
- [ ] Removing a binding updates live behavior without app restart
- [ ] `HotkeyMonitorTests` cover multi-binding dispatch (injected synthetic events)
- [ ] All 4 gates green

---

### V01-6 — Language auto-detection + quick language picker

**Task**: Expose language auto-detection in the overlay and Settings. When WhisperKit
is the active STT engine and `settings.language == "auto"`, surface a language badge
in the overlay (e.g. "🇪🇸 ES detected"). Add a quick-switch language pill to the
overlay toolbar (equivalent of Wispr's Flow Bar language picker): tapping it cycles
through `SpeechAnalyzer` installed locales or the top-5 WhisperKit languages. The
selection persists in `SettingsStore.language`. SpeechAnalyzer path: enumerate
`SpeechTranscriber.installedLocales` (already in `LocaleSupport.swift`) and present a
compact picker in the overlay's bottom bar.

**Depends on**: V01-1 (WhisperKit); P3 (SpeechAnalyzer locale seam already wired).

**Done when**:
- [ ] Dictating in Spanish with WhisperKit auto-detect produces Spanish text; overlay
      shows "ES" language badge
- [ ] Language pill in overlay taps through 3+ languages; next dictation uses the
      selected language
- [ ] Selection persists across app restart
- [ ] All 4 gates green

---

## v1 — Power User & Polish

*Value*: in-process MLX engine, English-accuracy Parakeet, Transforms, code-aware
mode, quiet mode, auto-segmentation, course correction, dictation recovery, and
enhanced stats. All additive; no moat changes.

**Prerequisite: v0.1 complete.**

---

### V1-0a — Core AI architecture research + migration plan

**Task**: WWDC26 introduced `import CoreAI` as the successor to CoreML for LLM and
generative AI workloads. Before implementing V1-1 (MLX), V1-2 (Parakeet), and V1-13
(Foundation Models provider API), verify whether these should target Core AI rather than
raw CoreML. Core AI natively supports LLMs, streaming generation, tool calling, and
third-party model plugins; it also provides dynamic routing (on-device / Private Cloud
Compute / user extension). `[inferred from official sources]`

This is a **research-only task** — output is documentation and skill updates, no
production code. Use `apple-docs` MCP + `swiftc -typecheck` to explore the Core AI API
surface, then write a verdict in `docs/progress.md` so all subsequent v1 engine tasks
can proceed from a verified foundation.

**Depends on**: v0.1 complete (stable pipeline; no file conflicts)

**Done when**:
- [ ] `apple-docs` MCP lookup of `CoreAI` (or `import CoreAI`) returns valid type
      definitions; module confirmed present in local macOS 26 SDK
- [ ] Written verdict in `docs/progress.md` open questions: "V1 engines should use
      Core AI because X" OR "Core AI is not the right layer for WhisperKit/MLX because
      Y — use CoreML / third-party SDK directly"
- [ ] `apple-native-ecosystem` skill updated: Core AI section upgraded from
      `[inferred from official sources]` to `[verified]` with confirmed import name and
      at least one concrete type name from the SDK
- [ ] If Core AI confirmed: `mlx-swift-cleanup` and `whisperkitv1-stt` skills each
      receive a one-paragraph "Core AI integration note" section
- [ ] If Core AI NOT yet in local SDK: logged as `[unverified — not in SDK <version>]`
      in progress.md; V1-1 and V1-2 proceed with CoreML/third-party SDK path

---

### V1-0b — AppIntents: StartDictationIntent + Siri integration

**Task**: SiriKit was deprecated at WWDC26. Implement AppIntents so users can say
"Hey Siri, start dictating" or trigger speak via the Shortcuts app. AppIntents uses
App Schemas — no hardcoded trigger phrases required; Siri understands the intent
schema naturally. `[inferred from WWDC26]`

Three intents: `StartDictationIntent` (fires `SpeakEngine.startSession()`),
`StopDictationIntent` (fires `stopSession()`), `GetLastTranscriptIntent` (returns
last `HistoryEntry.cleanedText`). All placed in `App/Intents/DictationIntents.swift`.
No cloud egress — AppIntents dispatch is local.

**Depends on**: V01-0 (agent mode code path is the same `startSession()` call;
intent can reuse it without duplication)

**Done when**:
- [ ] `StartDictationIntent: AppIntent` in `App/Intents/DictationIntents.swift`
      compiles and fires `SpeakEngine.startSession()` on invoke
- [ ] `StopDictationIntent` fires `SpeakEngine.stopSession()`
- [ ] `GetLastTranscriptIntent` returns the most recent `HistoryEntry.cleanedText`
      as `IntentResult`
- [ ] speak appears in the Shortcuts app listing all 3 intents with display names
- [ ] "Start dictating" (or similar) said to Siri launches a dictation session
      (manual verification — document result in progress.md)
- [ ] `make test` 0 failures; `AppIntentsTests.swift` uses AppIntents Testing
      framework: intent validation, parameter type checks, result type checks (3+ tests)
- [ ] `make verify-moat` 7/7 — AppIntents add no network egress

---

### V1-0c — Live Activity during dictation

**Task**: Show a Live Activity on macOS while dictation is active — waveform animation,
elapsed time (mm:ss), and approximate word count ticking up live. A cancel button in
the Live Activity fires `SpeakEngine.stopSession()`. Implemented with `ActivityKit`
on macOS 26, which confirmed Live Activity support at WWDC26. `[inferred from official sources]`

Files: `SpeakCore/LiveActivity/DictationLiveActivity.swift` (new) for the
`ActivityAttributes` conformance; updated `DictationController.swift` to
start/update/end the activity alongside the dictation session.

**Depends on**: Core pipeline stable (after validation phase)

**Done when**:
- [ ] `DictationLiveActivity: ActivityAttributes` defined; `ContentState` includes
      `elapsedSeconds: Int` and `wordCount: Int`
- [ ] Live Activity appears the moment dictation starts; disappears on stop/cancel
- [ ] `elapsedSeconds` and `wordCount` update at ≤1s intervals during dictation
- [ ] Tapping the cancel region in the Live Activity fires `SpeakEngine.stopSession()`
- [ ] `make test` 0 failures; `LiveActivityTests` mock the `Activity<>` API to verify
      start/update/end calls (3+ tests)
- [ ] `make verify-moat` 7/7 — ActivityKit is local; no network egress

---

### V1-1 — MLX Swift cleanup engine

**Task**: Implement `MLXCleaner` in `SpeakCore/Cleanup/MLXCleaner.swift` as a real
`LLMCleaning` conformer using the `ml-explore/mlx-swift` + `mlx-swift-lm` Swift
packages (`[decision]`: SPM dependency exempted in the same `SpeakLLM` module as
WhisperKit — no moat violation for opt-in power-user engines). Expose two model
presets: `qwen3-0.6b` (speed, ~500ms for 200 words on M3+) and `qwen3-1.7b` (quality,
~1.5s). Models download on first use to `~/Library/Application Support/speak/models/`.
`isAvailable` returns `true` only when the model file is present. Wire into
`EngineFactories` and Settings › AI Cleanup engine selector.

**Depends on**: V0 shipped; V01-2 (Ollama engine as reference implementation).

**Done when**:
- [ ] `MLXCleaner` cleans a 100-word transcript in ≤ 2 s on M2 or later (qwen3-0.6b)
- [ ] First-run download sheet appears; model downloads to the correct path; progress shown
- [ ] `isAvailable` returns `false` if model file absent; graceful fallback to raw
- [ ] Engine selector in Settings shows MLX option; selection persists
- [ ] All 4 gates green

---

### V1-2 — Parakeet/FluidAudio STT engine

**Task**: Integrate Parakeet TDT 0.6B via the FluidAudio Swift SDK (CoreML, Neural
Engine, Apache 2.0, `[verified]` production-proven in VoiceInk and 20+ apps) as an
optional `Transcribing` conformer `ParakeetTranscriber` in `SpeakCore/STT/`. Wire into
`EngineFactories` and the STT engine picker in Settings. Position as "English accuracy
champion" (~2.5% WER, ~80ms latency). Model is ~2–4 GB CoreML bundle; guided download.
English-only; language selector shows a note when Parakeet is active.

**Depends on**: V0 shipped; V01-1 (WhisperKit as reference for the engine-picker UX).

**Done when**:
- [ ] `ParakeetTranscriber` transcribes `hello_speech.caf` with WER ≤ 3%
- [ ] Latency (fixture file, not real-time): transcript result arrives in ≤ 300ms
      after audio completes
- [ ] Engine picker in Settings shows Parakeet option with "English only" badge
- [ ] All 4 gates green

---

### V1-3 — Transforms (highlight text → local LLM rewrite)

**Task**: Extend the existing `CommandModeService` + `AccessibilitySelection` seam to
support *Transforms*: user selects text in any app, presses a transform shortcut,
selected text is read via AX, sent to the active cleanup LLM with a transform-specific
prompt, and the result replaces the selection via AX write + paste. Built-in presets:
**Polish** (concise and clear), **Expand** (more detail), **Summarize** (one sentence),
**Prompt Engineer** (restructure as a well-formed AI prompt). Custom transforms: name +
system-level prompt, stored in `SettingsStore.transforms: [Transform]` (new). Up to 8
transforms get individual hotkey slots (extend V01-5 binding set). After transform runs,
show the `CleanupDiffView` diff overlay (already built) with [Accept]/[Revert] controls.
Auto-transform mode: optionally run a selected transform automatically after every
dictation. Dashboard › Transforms pane (already scaffolded) surfaces the preset list and
custom-transform editor.

**Depends on**: V0 shipped; existing `CommandModeService`, `AccessibilitySelection`,
`CleanupDiffView`; V01-2 or V1-1 (a real cleanup LLM must be available).

**Done when**:
- [ ] Selecting a 100-word paragraph and triggering Polish shortcut replaces it with
      a cleaner version in ≤ 3 s via the active local LLM
- [ ] All 4 built-in presets produce distinct outputs on the same input
- [ ] Custom transform: user defines name + prompt; shortcut binding works; persists
      across launches
- [ ] Diff overlay appears after every transform; [Accept] keeps result; [Revert]
      restores original
- [ ] Auto-transform mode: a per-dictation transform runs without a shortcut press
- [ ] All 4 gates green

---

### V1-4 — Code-aware dictation mode

**Task**: Extend the per-app context awareness from V01-3 with code-specific
formatting intelligence. When `AppContext == .codeEditor`, apply: (1) a `codeMode`
cleanup prompt clause that preserves symbol casing (snake_case vs camelCase
user-preference, stored in `SettingsStore.codeNamingConvention`); (2) suppression of
filler removal (developers voice-dictate identifiers, not prose); (3) filename tag
injection — if AX can read the current file's name from the editor title, mention it
in the cleanup prompt so the LLM knows the file context; (4) special vocabulary for
common code tokens (`func`, `var`, `let`, `const`, `async`, `await`, `import`).

**Depends on**: V01-3 (per-app context); V01-2 or V1-1 (LLM cleanup).

**Done when**:
- [ ] Dictating "open paren new variable equals" in Xcode with camelCase setting
      produces `(newVariable =` in cleaned output
- [ ] Dictating "function handle event colon" in VS Code produces `func handleEvent:`
- [ ] Filler removal is suppressed: "um add a func uh handleEvent" →
      `func handleEvent` (fillers removed), NOT `um add a func uh handleEvent`
      — wait, filler removal should still work but identifier handling improves.
      Clarify: fillers still removed; identifier casing is improved
- [ ] camelCase vs snake_case toggle in Settings works; persists
- [ ] All 4 gates green

---

### V1-5 — Quiet mode / noise suppression

**Task**: Add an `AVAudioEngine` preprocessing stage between `AudioCapture` and
`AppleSpeechTranscriber` (or WhisperKit). Implement a noise gate using
`AVAudioUnitEQ` (high-pass filter at 80Hz to cut rumble + presence boost at 3kHz for
voice clarity) and a sensitivity boost (adjustable gain, default +6dB, range 0–+12dB,
stored in `SettingsStore.quietModeSensitivity: Float`). Enable via a toggle in Settings
› Transcription › "Quiet Mode". When enabled, apply the processing chain before
buffering to `SpeechAnalyzer`. A live level meter in the overlay shows the boosted
signal.

**Depends on**: V0 shipped; P2 (`AudioCapture` + `AVAudioEngine`).

**Done when**:
- [ ] With Quiet Mode on, whispered speech at ≈30cm from the built-in mic transcribes
      the `hello_speech.caf` fixture phrase at ≥ 85% word accuracy (live test, logged
      in `progress.md`)
- [ ] Sensitivity slider changes gain in real time (no restart needed)
- [ ] Quiet Mode off: behavior byte-for-byte identical to v0 baseline
      (`make test` still passes all existing audio tests)
- [ ] All 4 gates green

---

### V1-6 — Auto-segmentation for messaging

**Task**: When `AppContext == .workMessaging` or `.personalMessaging`, optionally
auto-submit after a configurable silence threshold. Implement a silence detector in
`CaptureSession`: track RMS level from the audio stream; if RMS < `silenceThreshold`
for > `silenceDurationMs` ms (default 1500ms, range 500–3000ms, stored in
`SettingsStore`), fire `stopCapture` automatically. After paste, if the target app is a
messaging app and `autoSegmentSendOnPause` is enabled, simulate a Return key event
(`kVK_Return`, `CGEventType.keyDown`/`keyUp` via `.cghidEventTap`) so each thought
auto-submits. User-configurable toggle in Settings › General › Auto-Segmentation.

**Depends on**: V01-3 (AppContext); P2 (audio level stream, already in `AudioCapture`).

**Done when**:
- [ ] Dictating three distinct sentences with > 2s pauses in Messages sends each as a
      separate message automatically — live test logged in `progress.md`
- [ ] Auto-segmentation off: single long dictation pastes as one block (no regression)
- [ ] Silence threshold slider in Settings changes behavior; persists
- [ ] `kVK_Return` verified against local SDK via `swiftc -typecheck` `[verified]` tag
- [ ] All 4 gates green

---

### V1-7 — Course correction ("wait no" detection)

**Task**: In `CaptureSession.ingest(_:)`, scan each finalized transcript chunk for
correction markers: `["wait no", "wait, no", "i mean", "actually,", "scratch that",
"never mind"]` (case-insensitive). On detection, trim `finalizedText` back to the
position just before the correction marker and reset the accumulator to continue from
that point. Inject a `courseCorrection: true` flag into `CleanupMode` so the LLM
knows the input may have already-trimmed back-tracking. The list of markers is stored
in `SettingsStore.correctionMarkers: [String]` with the above defaults.

**Depends on**: V0 shipped; P3 (`CaptureSession.ingest`).

**Done when**:
- [ ] Integration test: feed a two-chunk fixture where chunk 1 = "let's meet Tuesday"
      and chunk 2 = "wait no Friday" → `stop()` returns raw text = "let's meet Friday"
      (Tuesday trimmed)
- [ ] Marker list is user-editable in Settings; adding a custom marker works
- [ ] Course correction disabled: original accumulation behavior unchanged (regression
      test passes)
- [ ] All 4 gates green

---

### V1-8 — Dictation recovery

**Task**: At `CaptureSession.start()`, open a temp audio buffer file at
`~/Library/Application Support/speak/recovery/<UUID>.caf`. Feed each `AVAudioPCMBuffer`
to both `SpeechAnalyzer` and this file handle in parallel. On clean `stop()` or
`cancel()`, delete the file. On app launch, scan for orphaned `.caf` files in the
recovery directory (created > 10s ago, indicating a crash). If found, show a HUD
banner: "Interrupted dictation recovered — [Retry Cleanup] [Discard]". [Retry Cleanup]
reads the `.caf`, re-runs it through `AppleSpeechTranscriber` + the active cleaner, and
pastes. [Discard] deletes the file. `[decision]`: storing audio to disk is the first
time audio touches storage — add a note to the Privacy tab that recovery files are
local-only and auto-deleted on clean exit.

**Depends on**: V0 shipped; P2 (`AudioCapture`); P3 (`AppleSpeechTranscriber`).

**Done when**:
- [ ] Force-quit during a 5-second dictation → relaunch shows recovery HUD banner
- [ ] [Retry Cleanup] produces a pasted result equivalent to the interrupted dictation
- [ ] [Discard] deletes the file; no HUD on next launch
- [ ] Clean session exit: no recovery file exists after `stop()` completes
- [ ] Privacy tab updated with recovery-file note
- [ ] All 4 gates green

---

### V1-9 — Inline history retry

**Task**: In the History pane (`App/History/HistoryView.swift`), add a "Retry"
contextual button (toolbar or swipe action) on each `HistoryEntry`. Tapping it
re-runs `entry.rawText` through the current cleanup engine + current `CleanupMode`
settings, producing a new `HistoryEntry` with `parentId: entry.id`. Show a before/after
diff using `CleanupDiffView` (already built). Options: [Replace] (overwrite the entry's
`cleanedText`), [Append] (add as a new entry), [Cancel]. This lets users improve old
dictations after upgrading to a better cleanup model.

**Depends on**: V0 shipped; P9 (`HistoryStore`, `HistoryEntry`); P3.5 (`LLMCleaning`).

**Done when**:
- [ ] Tapping Retry on a history entry with raw text "um i think we should uh meet"
      produces cleaned output and shows diff overlay
- [ ] [Replace] updates `cleanedText` in the DB; re-queried entry shows new text
- [ ] [Append] adds a new entry; original untouched
- [ ] All 4 gates green

---

### V1-10 — Streak tracking + enhanced stats

**Task**: Add a `streakDays: Int` field to `HistoryStore` (new SQLite column via
migration — increment pattern: if last dictation was on the previous calendar day,
`streak += 1`; if today, no change; if gap > 1 day, reset to 1). Expose via a new
`HistoryStoring` method `currentStreak() async -> Int`. Show streak in the Home pane
header ("🔥 12-day streak") and in the Insights pane. Add a daily word-count history
chart in Insights using SwiftUI `Charts` (Apple framework, not third-party): bar chart
of words/day for the last 30 days, colored by cleanup engine. WPM trending: 7-day
rolling average, shown as a line overlay.

**Depends on**: V0 shipped; P9 (`HistoryStore`).

**Done when**:
- [ ] Dictating on two consecutive days shows streak = 2 in Home pane
- [ ] Missing a day resets streak to 1 on next dictation (confirmed by unit test with
      injected `Date` values)
- [ ] 30-day word-count chart renders in Insights with correct daily totals
- [ ] `Charts` import appears in moat allowlist (Apple framework); `make verify-moat` passes
- [ ] All 4 gates green

---

### V1-11 — Personal writing style samples

**Task**: Add a `writingStyleSamples: [String]` field (up to 5 entries, 50–500 words
each) to `SettingsStore`. In `FoundationModelsCleaner.clean(_:mode:)` (and other LLM
cleaners), inject the samples into the system prompt as few-shot examples: "Write in
the same voice as these samples: [sample1] [sample2] ...". Add a "My Style" section in
Settings › AI Cleanup with a list of samples and an [Add Sample] sheet (multi-line text
field, 50–500 word validation). Empty samples list → no injection, output matches the
v0 baseline byte-for-byte. `[decision]`: 50-word minimum prevents noise; 500-word cap
keeps the prompt size predictable (max ~2,500 tokens of samples).

**Depends on**: V0 shipped; P3.5 (`FoundationModelsCleaner`); P10.

**Done when**:
- [ ] Adding a 100-word formal writing sample changes cleanup output toward a more
      formal register (live test, logged in `progress.md`)
- [ ] Empty samples list: output identical to v0 baseline on the same input
      (`testFoundationModelsCleaner` baseline still passes)
- [ ] Word-count validation: < 50 words → [Add] button disabled; > 500 words → truncate
      warning shown
- [ ] All 4 gates green

---

### V1-12 — Clamshell mode + microphone auto-selection

**Task**: Subscribe to `NSWorkspace.shared.notificationCenter` for
`NSWorkspace.screensDidSleepNotification` and `didWakeNotification`. On wake, query
`AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone], mediaType: .audio,
position: .unspecified).devices` to find the highest-priority available microphone (USB
external > Bluetooth > built-in). If the Mac is in clamshell mode (detected via
`IOServiceMatching("AppleSmartBattery")` lid-closed key or display count = 0) and the
selected mic is the built-in, show a warning HUD: "Built-in mic active — attach an
external mic for best quality." Auto-switch to the first available external mic if
`SettingsStore.autoMicSelection == true` (default on).

**Depends on**: V0 shipped; P2 (`AudioCapture` — mic selection at session start).

**Done when**:
- [ ] Plugging in a USB mic while Speak is running → next dictation uses the USB mic
      automatically (live test logged in `progress.md`)
- [ ] Closing lid with only built-in mic → warning HUD appears
- [ ] `autoMicSelection = false` → mic never changes automatically
- [ ] `AVCaptureDevice` API verified against local SDK `[verified]`
- [ ] All 4 gates green

---

### V1-13 — WWDC26 Foundation Models provider integration

**Task**: Explore the WWDC26 `LanguageModelSession` provider API — which allows
Anthropic, Google, and MLX models to work behind the same `LanguageModelSession` Swift
call. `[decision]`: `FoundationModelsCleaner` should require **zero code changes** for
provider swap; the provider is injected at `LanguageModelSession` init time. Add a
"Model Provider" picker in Settings › AI Cleanup for power users: Apple (default), MLX
(via provider), Anthropic (user-supplied API key stored in Keychain — this is the first
and only credential the app ever handles; clearly opt-in; audio never leaves the
device). Document the provider API shape against the local macOS 26 SDK
(`swiftc -typecheck` `[verified]`). MLX provider: no API key, in-process.
Anthropic provider: cloud cleanup only (audio stays local; only the *cleaned text*
request goes out); this is the first v1+ *optional* cloud feature — surfaced honestly
in the Privacy tab.

**Depends on**: V0 shipped; V1-1 (MLX); P3.5 (`FoundationModelsCleaner`).

**Done when**:
- [ ] `FoundationModelsCleaner` compiles and passes tests unchanged after provider API
      exploration (no regression)
- [ ] MLX provider: `LanguageModelSession` with MLX provider produces cleaned output
      (live test, logged in `progress.md`)
- [ ] Provider picker in Settings shows Apple / MLX / Anthropic options
- [ ] Anthropic provider: API key stored in Keychain (`SecItemAdd`); key never logged;
      `testNoAccountOrAuthCode` moat test updated to explicitly allow opt-in keychain
      usage (with `[decision]` comment: "opt-in cloud cleanup only, not mandatory")
- [ ] Privacy tab updated: "Optional Anthropic cleanup: text only, no audio leaves device"
- [ ] All 4 gates green

---

### V1-14 — iOS app foundation

**Task**: Extract `SpeakCore` as a standalone Swift Package Manager package
(`Package.swift` root alongside the existing `project.yml`; the Xcode target continues
to embed it via XcodeGen, and the SPM package is the new canonical form). Add an iOS
18+ app target in `project.yml`: `SpeakiOS` — a minimal `SpeechAnalyzer` +
`Foundation Models` dictation flow with no `CGEventTap` (iOS doesn't support global
hotkeys; in-app tap replaces it). Implement a Custom Keyboard Extension target
(`SpeakKeyboard`) so the user can trigger dictation from any app's keyboard. The iOS
app shares `SpeakCore` engine, `HistoryStore` (separate DB file), and `SettingsStore`
(separate UserDefaults).

**Depends on**: V0 shipped; V2-2 (iCloud sync is the bridge between iOS and Mac data).

**Done when**:
- [ ] `swift build` on the SPM `SpeakCore` package compiles cleanly on macOS
- [ ] iOS `SpeakiOS` target builds in Xcode for an iOS 18 simulator
- [ ] Keyboard extension activates and shows a microphone button in the system keyboard
- [ ] Tapping the mic button in the keyboard extension starts a dictation session and
      inserts the result into the focused text field
- [ ] All 4 gates green on macOS (iOS simulator tests are separate)

---

## v2 — Platform & Expansion

*Value*: full iOS app, iCloud sync, diarization, team features.
**Prerequisite: v1 complete.**

---

### V2-1 — iOS app complete

**Task**: Build out the full iOS dictation experience on the `SpeakiOS` foundation from
V1-14. Full flow: keyboard extension mic button → overlay (SwiftUI in-process overlay
within the extension) → SpeechAnalyzer → Foundation Models cleanup → text inserted at
cursor. **Dynamic Island live activity** during dictation showing elapsed time and
partial text (via `ActivityKit`). **Lock Screen widget** for word-count and streak
(via `WidgetKit`). **Action Button shortcut**: register a `SpeakIntent` for the Action
Button on iPhone 15 Pro+. iPhone keyboard, iPad keyboard extension, and Action Button
all share the same `SpeakCore` engine instance via actor isolation.

**Depends on**: V1-14; V2-2 (iCloud sync for history continuity).

**Done when**:
- [ ] Dictating in any iOS app via the keyboard extension pastes cleaned text
- [ ] Dynamic Island shows live partial transcript during dictation
- [ ] Lock Screen widget shows today's word count and current streak
- [ ] Action Button on iPhone 15 Pro+ triggers dictation
- [ ] History from iOS sessions appears in Mac history (via iCloud, V2-2)

---

### V2-2 — iCloud sync (opt-in, no account)

**Task**: Sync dictionary, snippets, and settings across devices using the user's own
iCloud (`NSUbiquitousKeyValueStore` for small data; `CloudKit` for history entries if
user opts in to history sync). Sync is **opt-in** and **requires no speak account** —
it uses the user's existing iCloud account entirely. Toggle in Settings › Privacy ›
"Sync via iCloud". Conflict resolution: last-write-wins with a `modifiedAt` timestamp.
History sync is a separate sub-toggle (history entries can be large; default off).
Custom dictionary and snippets default to sync-on when iCloud toggle is enabled.

**Depends on**: V1-14 (iOS target exists); V0 shipped.

**Done when**:
- [ ] Adding a dictionary word on Mac appears on iPhone within 60 s with iCloud sync on
- [ ] iCloud sync off: no `NSUbiquitousKeyValueStore` or CloudKit calls made —
      confirmed by `make verify-moat` (add CloudKit to the moat exemption list with
      `[decision]` tag: "opt-in sync only")
- [ ] History sync off by default; toggling it on syncs last 100 entries
- [ ] Conflict resolution: last-write-wins verified by unit test with injected timestamps

---

### V2-3 — Speaker diarization

**Task**: Use WhisperKit's `SpeakerKit` (part of the `argmax-oss-swift` monorepo,
already a dependency from V01-1) to identify speaker turns in a multi-speaker
recording. In `HistoryEntry`, add `speakerLabels: [SpeakerSegment]?` (new SQLite
column). `SpeakerSegment` carries `speakerId: Int`, `startMs: Int`, `text: String`.
In `HistoryView`, render diarized entries with interleaved "Speaker 1:" / "Speaker 2:"
labels in Monaco font. Enable via toggle in Settings › Transcription › "Identify
speakers".

**Depends on**: V01-1 (WhisperKit already integrated); V0 shipped.

**Done when**:
- [ ] Recording a two-person conversation produces a history entry with ≥ 2 speaker
      segments labeled "Speaker 1:" and "Speaker 2:" (live test logged in `progress.md`)
- [ ] Single-speaker sessions: `speakerLabels == nil`; History view unchanged
- [ ] Diarization off: no `SpeakerKit` calls — `make verify-moat` still passes
- [ ] All 4 gates green

---

### V2-4 — Team features without a server

**Task**: Share dictionary and snippets across a small team using iCloud folder sharing
(no speak server). The "team owner" creates a shared iCloud folder (`FileManager +
NSMetadataQuery`). Members add the folder path in Settings › Team. The shared folder
contains `team-dictionary.json` and `team-snippets.json`. Conflict resolution: union
merge (no deletion propagation — a member can always add, never remove another's entries
remotely). Local entries take precedence over team entries for the same trigger phrase.

**Depends on**: V2-2 (iCloud baseline).

**Done when**:
- [ ] Team owner adds a word to the team dictionary; team member's Speak picks it up
      within 60s via shared iCloud folder
- [ ] Conflict: both members add "tps" → both definitions appear in the member's
      dictionary (union merge confirmed by unit test)
- [ ] No speak server involved — confirmed by `make verify-moat`

---

### V2-5 — Android / Windows

Scope defined when v2 iOS is stable. Outside Apple framework constraint — requires
platform seam extraction decision. No pre-commitment. `[decision]`: deferred.

---

## v3+ — Enterprise & Frontier

*Scope defined when v2 is stable and real user patterns are established.*

---

### V3-1 — HIPAA BAA documentation + compliance export

**Task**: No code change. Produce a HIPAA Business Associate Agreement template that
documents `speak`'s architecture: no audio or text egress, no account, all processing
on-device. Add an "Export Compliance Docs" button in Settings › About that generates
a PDF summary of the app's privacy architecture (`WKWebView` print-to-PDF of a
templated HTML, local only). The automated `make verify-moat` output (7/7 pass) serves
as the technical evidence appendix.

**Done when**:
- [ ] PDF export works and contains the 5 privacy guarantees from `product.md` §8
- [ ] BAA template is in `docs/compliance/hipaa-baa-template.md`
- [ ] All 4 gates green (PDF export uses local WebKit only — no egress)

---

### V3-2 — Enterprise MDM profile

**Task**: Produce a macOS Configuration Profile (`.mobileconfig`) that IT admins can
deploy to enforce: Privacy Mode on, iCloud sync off, shared dictionary endpoint (local
path), dictation history retention policy. Read these values at launch via
`UserDefaults(suiteName: "managed")` (the MDM-managed domain). No speak server.

**Done when**:
- [ ] `.mobileconfig` installs via System Settings › Profiles
- [ ] Managed preferences override user settings silently (no UI conflict)
- [ ] Unmanaged install: behavior unchanged

---

### V3-3 — Advanced voice editing (multi-turn)

**Task**: Extend Command Mode to support multi-turn conversational editing. After a
transform or command, the user can say a follow-up command ("now make it shorter" /
"revert last change") within a 30-second window. Maintain an edit stack (max 5 levels)
with undo. Powered by the active local LLM (Foundation Models, MLX, or Ollama). The
conversation history stays in-process and is discarded after the window closes.

**Done when**:
- [ ] Two consecutive voice edits on the same text both apply correctly
- [ ] "Revert" restores the previous version
- [ ] Edit stack limited to 5; oldest discarded on overflow
- [ ] 30s window expires: conversation state cleared; next trigger starts fresh

---

### V3-4 — Developer API / SDK

**Task**: Publish `SpeakCore` (from V1-14's SPM package) as a documented public API.
Write Swift DocC documentation for all public types. Add a sample macOS CLI app in
`Examples/speak-cli-example/` showing dictation integration in 50 lines. Publish the
SPM package URL in README.

**Done when**:
- [ ] `swift package generate-documentation` produces a DocC archive with no warnings
- [ ] Example CLI app compiles and runs a 5-second dictation session
- [ ] `SpeakCore` SPM URL documented in README

---

> **Principle** (from `product.md` §9): there is no deadline on any version.
> The loop advances the ladder until the product is whole; each rung's "done"
> is defined by testable criteria, not dates. Later versions make `speak` more
> attractive, friendlier, and more creative — they never backfill missing core.
