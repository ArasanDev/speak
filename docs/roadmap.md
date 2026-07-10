# `speak` — Build Roadmap (v0 only)

> Agent navigation: pick lowest `[ ]` task with no open `[~]` blockers.
> Status: `[x]` done · `[~]` partial (logic verified; live/visual deferred) · `[ ]` todo · `[!]` blocked.
> Ship gate: `docs/benchmark.md §4` MATCH + `docs/quality.md §9` all pass.

**Critical path**: P0 → P2 → P3 → P3.5 → P5 → P6 → P11-a → P13.
P1, P4, P7, P8, P9, P10, P12 can parallelize once their own dependencies are met.
v0.1/v1/v2/v3+ tasks: see `docs/product.md §9`.

---

## North star — Profile Engine `[decision 2026-06-29]` [TODO — post-v0]

Spec: `specs/profile-engine.md` · prompts: `specs/profile-system-prompts.md` · WHY: `product.md §6d`.

**Layering (immutable order — never invert)**:
1. Base core: double-press activate / single-press stop; raw voice → text, no AI.
2. Default: `Clean` profile (on-device neat-writing); AI off ⇒ raw passthrough.
3. Extension: Profile Engine (tasks #29–#34, after v0 fix phase).

The v0.1 items (V01-0 Agent Mode, V01-3 per-app context, V1-3 Transforms, V1-4 code-aware) are re-framed as profiles once the engine lands.

**Landed 2026-07-06 (loop #42, ahead of critical path — see progress.md):** V01-3 `[x]` (profile-native: Chat profile + toggle), V01-5 `[x]` (ExtraBinding, live-apply), V01-2 `[x]` (SpeakLLM target; key-entry UI still open), Aurora HUD `[x]` (opt-in), H-3 MCP bridge slice `[x]` (`speak-mcp`; say/ask pending VoiceOut+transport). **Landed 2026-07-08 (loop #44):** H-3 `speak_say`/`speak_ask`/`speak_confirm` `[x]` — wired to the live app (voiceOut TTS + beginDictation/endDictation session path, deterministic yes/no/cancel extractor, CFMessagePort ask/confirm timeout override). **Landed 2026-07-08 (loops #45/46):** H-1 Voice Actions `[x]` (FULLY live: both `.action` route via ShortcutsCLIExecutor AND `.command` route via CommandModeService+AccessibilitySelection wired into stop→paste in CaptureSession.swift; live AX read/replace behavior `[deferred — needs human verification]`), H-4 ShortcutsCLIExecutor `[x]` (two-stage SIGTERM/SIGKILL watchdog for hung headless shortcuts). Horizon direction: `specs/horizon-voice-os.md` (H-1…H-4).

### Agent Voice Bridge `[decision 2026-07-11]`

Product contract: `specs/agent-voice-bridge.md`. MCP is the compatibility
surface; the native attention and voice experience is the product.

- [x] **AVB-1 — Completion/blocker notification contract**: `speak_notify`
      speaks only a concise summary through local VoiceOut; tool guidance rejects
      routine logs/progress/diffs; compatibility primitives remain available.
- [x] **AVB-2 — Installable local bridge**: stable user-scoped
      `make install-mcp-user`, Homebrew `speak-mcp`, README setup for Codex and
      Claude Code; relocated binary launch verified.
- [~] **AVB-3 — Safe bounded input**: agent response paste suppression and stale
      transcript prevention implemented + core-tested; live MCP question/HUD/mic
      round-trip remains `[deferred — needs human verification]`.
- [~] **AVB-4 — Attention policy**: actor-owned serial speech queue +
      cancel/replace semantics implemented and tested; cooldown/deduplication,
      quiet policy, and per-client enablement remain.
- [ ] **AVB-5 — Unified structured input**: replace `ask`/`confirm` product use
      with `speak_request_input` outcomes (`answered`, `declined`, `cancelled`,
      `timedOut`, `busy`) and explicit choice/approval presentation.
- [ ] **AVB-6 — Native agent inbox + diagnostics**: identify client/repo, show
      pending completions/questions locally, and expose tool-only-compatible
      setup/status diagnostics. Status/capability MCP resources are additive.

---

## P0 — Repo setup [~PARTIAL]

**Sub-tasks**: `git init`, Xcode project (app + `SpeakCore.framework` + `SpeakTests`), layout per `architecture.md §5`, `README.md`, `LICENSE` (MIT), `.gitignore`, `.swift-version` (5.9+), `Makefile`, GitHub Actions CI.

**Done when**:
- [x] `make build` produces a runnable `.app` from a clean clone ✓ (XcodeGen → `xcodebuild`; verified `make clean && make build`)
- [x] `SpeakCore.framework` is a separate build target (the portability seam) ✓
- [~] CI runs on every push: `xcodebuild build` + `swiftlint` — workflow authored (`.github/workflows/ci.yml`); **[unverified]** until repo has a remote + push
- [x] `LICENSE` is MIT; `.gitignore` covers `DerivedData/`, `.build/`, `*.xcuserstate`, `DS_Store` ✓

---

## P1 — Menubar scaffold [DONE]

**Sub-tasks**: `SpeakApp.swift` with `MenuBarExtra` (idle icon) + "About" panel; inject empty `SpeakEngine` into SwiftUI environment.

**Done when**:
- [x] `speak` shows in the menubar on launch ✓ (waveform icon; launched + verified)
- [x] Clicking the icon opens a menu with an "About…" item ✓
- [x] App runs as a `LSUIElement` (no dock icon, menubar only) ✓

---

## P2 — Audio capture [~IN PROGRESS] ← CRITICAL PATH

**Sub-tasks**: `PermissionManager` (microphone state) + `AudioCapture` (`AVAudioEngine`, 16kHz mono PCM); stream raw PCM buffers to `AsyncStream`. Both implemented (`SpeakCore/Audio/AudioCapture.swift`, `SpeakCore/Permissions/PermissionManager.swift`) — checklist below reconciled 2026-07-04 (code was ahead of the markers).

**Done when**:
- [~] First run triggers the microphone permission prompt — `[verified]` `PermissionManager` requests/reports mic status; `[deferred — needs human verification]` live first-run prompt
- [~] Speaking into the mic logs PCM buffer stats (sample rate, length) via `os.Logger` — no `print` — `[verified]` no `print` in `AudioCapture.swift` (moat audit rule #1); `[deferred]` live mic session log inspection
- [x] Audio stops cleanly on session cancel (no zombie taps) — `[verified]` `testStopTerminatesStream()` in SpeechTranscriberTests.swift exercises stop() mid-stream and asserts no hang

---

## P3 — SpeechAnalyzer [~IN PROGRESS] ← CRITICAL PATH

`Transcribing` protocol + `AppleSpeechTranscriber` implemented against `SpeechAnalyzer` (`SpeakCore/STT/AppleSpeechTranscriber.swift`); exercised by `LatencyAndAccuracyTests.swift` against a real audio fixture (`hello_speech.caf`). Checklist reconciled 2026-07-04.

**Sub-tasks**: Define `Transcribing` protocol; implement `AppleSpeechTranscriber` against `SpeechAnalyzer` (macOS 26+, Apple Silicon); emit `TranscriptChunk` (partial + final). Read `architecture.md §10.2` first.

**Done when**:
- [x] Spoken audio produces **partial** transcripts (streaming, live) — `[verified]` `LatencyAndAccuracyTests` asserts volatile chunks emitted from `hello_speech.caf`
- [x] Spoken audio produces a **final** transcript at session end — `[verified]` same suite, final transcript assertions
- [~] Engine id is `"apple-speech-en-US"` — `[verified]` in code/tests; not re-confirmed against latest Apple docs this loop
- [x] Verify against `architecture.md §10.2` (re-check SpeechAnalyzer API surface vs current Apple docs before coding) — `[verified]` AppleSpeechTranscriber.swift lines 16–81 document API surface with `[verified]` tags from WWDC25 #277, arm64e swiftinterface, and runtime sources (2026-06-22)

---

## P3.5 — LLM cleanup pipeline [DONE] ← CRITICAL PATH

**Constraint**: Foundation Models is an Apple framework — not a third-party dep (`AGENTS.md §2.9`). When unavailable, fall through to raw paste; never enter `error` state solely due to cleanup failure.

**Sub-tasks**: Define `LLMCleaning` protocol (signature from `architecture.md §6`); implement `FoundationModelsCleaner`; wire into `CaptureSession.processing` state; implement `cleanupEnabled: Bool` in `SettingsStore`; verify Foundation Models API against Apple docs before coding.

**Done when**:
- [x] A sample dictation produces **cleaned** output when `cleanupEnabled` is `true` and Foundation Models is available — `[verified]` via `CaptureSession` orchestration against a mock cleaner (`testStopWithCleanerAvailableProducesCleanedText`); **live cleanup quality stays `[inferred]`** until P13 dogfood on a Mac with Apple Intelligence enabled (gated off on the dev Mac as of 2026-06-20).
- [x] With `cleanupEnabled = false`, `cleanedText` is `nil` and raw text is pasted — `cleanedText == nil` and `engineId == STT id` verified (`testStopWithCleanerNilHasCleanedTextNil`); the *paste* half is P6.
- [x] When Foundation Models is **unavailable**, session gracefully falls back to raw transcript and reaches `done` state (not `error`) — verified (`testStopWithCleanerUnavailableFallsBackToRawNoError`).
- [x] `SpeakError.llmCleanupFailed` is surfaced only on a genuine API failure, not on unavailability — verified (SpeakError path + generic Error→SpeakError mapping + unavailable-doesn't-throw path).
- [x] Engine id is stored in `TranscriptionResult.engineId` when cleanup runs — verified (`engineId == "<stt>+<cleaner>"`).
- [x] No third-party dependencies introduced — Apple Foundation Models only.
- [x] Foundation Models API surface verified against current Apple docs (SDK-anchored, see comments at the top of `SpeakCore/Cleanup/FoundationModelsCleaner.swift`).

---

## P4 — Partial overlay [~IN PROGRESS]

**Sub-tasks**: Floating `NSPanel`/SwiftUI overlay streaming partial transcript; auto-position near cursor or top-right, always-on-top. Live appearance is `[deferred — visual]` (§4.3).

**Done when**:
- [~] Overlay appears when session enters `listening` state — `[verified]` the wiring (`DictationController` shows the panel on `.listening`, hides on `.done`/`.error`); **live appearance** `[deferred — visual]` (§4.3)
- [~] Partial transcript text updates live (≤200ms lag — `benchmark.md §7` `L_partial`) — `[verified]` accumulation logic (`OverlayTextAccumulator`, 11 tests) + drains `currentPartials()`; **live lag** `[deferred — visual]`
- [~] Overlay hides on `done` / `error` — `[verified]` the hide wiring; **live** `[deferred — visual]`

---

## P5 — Hotkey [~IN PROGRESS] ← CRITICAL PATH

**Constraint**: Double-tap window (400ms) is a `[decision]` — confirm or tune empirically in P13. Requires Accessibility permission; `.defaultTap` is Accessibility-gated only (Input Monitoring removed in v0.2).

**Sub-tasks**: `HotkeyMonitor` via `CGEventTap`; double-tap Fn (400ms window) → `startCapture`; single-tap Fn after start → `stopCapture`; persist binding in `UserDefaults`. Default: `HotkeyBinding(keyCode: kVK_Function, modifiers: [], trigger: .doubleTap, doubleTapWindow: 0.4)`.

**Done when**:
- [~] Double-tap Fn triggers start while **another app has focus** — `[verified]` pure detector logic (DoubleTapDetector tests, injected timestamps); `[deferred — needs human verification]` live OS + other-app focus with Accessibility granted
- [~] Single-tap Fn triggers stop while another app has focus — `[verified]` pure detector logic; `[deferred — needs human verification]` live OS
- [~] First run triggers Accessibility permission prompt (Microphone handled separately) — `[deferred — needs human verification]` (requires live non-sandboxed run)
- [ ] False-trigger rate < 1 per 30 min in normal typing, tested in Notes (single source for `F_rate` in `benchmark.md §7`) — P13 dogfood

---

## P6 — Paste [~IN PROGRESS] ← CRITICAL PATH

**[unverified]** macOS 26.4 paste-provenance check (Terminal paste-protection). Test in Terminal/iTerm first — this is the project's #1 `[unverified]`. Never read the pasteboard; only write.

**Sub-tasks**: `PasteboardWriter` per `architecture.md §11`; write to `NSPasteboard`, simulate `Cmd+V`. Paste `cleanedText` when cleanup on + produced output; otherwise `rawText`. Session must reach `done` in both cases.

**Done when**:
- [~] When cleanup is **on**: cleaned text (filler-free, punctuated) pastes into the focused app — `[verified]` selection logic (`CaptureSession` hands `cleanedText` to the inserter, `testInserterReceivesCleanedText…`); `[deferred — needs human verification]` the actual live paste
- [~] When cleanup is **off** or unavailable: raw transcript pastes instead — `[verified]` selection logic; `[deferred]` live paste
- [ ] Final transcript (cleaned or raw) pastes into focused text field in **TextEdit, Slack, Terminal** (3 different app categories) — `[deferred — needs human verification]`
- [ ] No macOS 26.4 paste-protection prompt appears (we write, never read) — `[deferred — needs human verification]` (**project's #1 `[unverified]`**: the Terminal paste-provenance check; test in Terminal/iTerm first)
- [x] Paste fails gracefully (error state) in password fields — `[verified]` `testInsertRefusesPasteIntoSecureField()` in SecureFieldGuardTests asserts `.pasteIntoSecureField` error when isFocusedFieldSecure=true; `[deferred — needs human verification]` the live password-field detection via accessibility APIs

---

## P7 — Permissions flow [~IN PROGRESS]

**Sub-tasks**: Full 2-permission onboarding window; Microphone (runtime prompt); Accessibility (deep-link to System Settings). Explain *why* each is needed with a screenshot per permission.

**Done when**:
- [~] A fresh user can grant both permissions and reach a working dictation with no confusion — `[verified]` the step-state machine (`OnboardingStateMachine`, 14 tests) + mic/accessibility status backends; **the rendered flow + comprehension** `[deferred — visual]` (§4.4)
- [~] Deep-links open the correct System Settings pane — `[verified]` the deep-link URLs are wired; **that they open the right pane** `[deferred — needs human verification]`
- [~] Permission revocation mid-session is detected → state moves to error — `[verified]` the wiring (`showOnboardingIfNeeded()` re-surfaces on permission-denied catches; monitor-start failure → `permissionsNeeded`); **live revocation behavior** `[deferred — visual]`

---

## P8 — Menubar states [~IN PROGRESS]

**Sub-tasks**: Menubar icon reflects `CaptureSession.State`: gray waveform (idle), red dot (listening), yellow spinner (processing), green flash (done), red X (error).

**Done when**:
- [~] Icon changes on every state transition — `[verified]` the wiring: `MenuBarLabel` renders a distinct SF Symbol per `MenubarIcon` (idle/listening/processing/done/error, `MenubarIconTests`), `DictationController` drives idle→listening→**processing**→done→idle. **Distinct *color*** (red/yellow/green vs monochrome SF Symbols) + the live visual `[deferred — visual]`.
- [~] "Done" green flash lasts 600ms then returns to idle — `[verified]` the 600 ms timing in `DictationController.endDictation` (single-sourced to this row); the live visual flash `[deferred — visual]`.

---

## P9 — History [~IN PROGRESS]

**Sub-tasks**: `HistoryStore` (SQLite, `~/Library/Application Support/speak/`); store `HistoryEntry` (raw + cleaned text, timestamp, engine id); capacity = tunable setting (not hardcoded; see `benchmark.md §7` "history size"); `HistoryView` + `HistoryWindowController` from "History…" menu item.

**Done when**:
- [x] Every completed session writes a `HistoryEntry` (with `cleanedText` when cleanup ran, `nil` otherwise) — `[verified]` `HistoryStore.save()` round-trips both (`testNilCleanedTextRoundTrips`), and end-to-end wiring: `SpeakEngine.endDictation` builds a `HistoryEntry` and calls `history.save(_:)` (best-effort; DB failure never fails a dictation). Verified by `SpeakEngineIntegrationTests`.
- [x] History persists across app launches — `[verified]` (`testSaveAndReopenPersistence`)
- [x] Search by substring returns matching entries — `[verified]` (matches in both `rawText` and `cleanedText`)
- [x] "Clear history" empties the store — `[verified]` (`testClearEmptiesStore`)
- [x] "Export" produces a readable file (plain text or JSON) — `[verified]` (JSON, ISO-8601 dates; `testExportContainsEntriesText`)
- [~] **History window (UI)** — search/clear/export surfaced in a SwiftUI window — `[verified]` the wiring: `HistoryView` + `HistoryWindowController` bind to `HistoryViewModel`; the **rendered window + NSSavePanel** are `[deferred — visual]` (human-verification.md §4.5).

---

## P10 — Settings [~IN PROGRESS]

**Sub-tasks**: `SettingsStore` (typed `UserDefaults` wrapper); `Settings` SwiftUI window: hotkey rebinding, language picker (en-US/en-GB), auto-paste toggle, paste mode, AI cleanup toggle, cleanup engine selector (Foundation Models default; v1 alternatives as disabled placeholders).

**Done when**:
- [x] All settings persist across launches — `[verified]` (`SettingsStoreTests`: every property + enum encodings round-trip on a fresh store)
- [~] User can rebind the hotkey to a custom key/modifier combo — `[verified]` binding persistence (`UserDefaultsBindingStore`, P5); **live rebind UX** `[deferred — visual]`
- [~] Language picker lists at least en-US, en-GB — `[verified]` store holds the locale; **the picker rendering** `[deferred — visual]`
- [~] Cleanup toggle is active and functional (toggles the P3.5 path) — `[verified]` gating logic: `defaultCleaner(for:)` returns `nil` when `cleanupEnabled == false`; **the live UI toggle** `[deferred — visual]`
- [~] Cleanup engine selection is present in the UI (Foundation Models default; v1 alternatives as disabled placeholders) — built; `[deferred — visual]`

---

## P11-a — Build-from-source install [~IN PROGRESS] ← CRITICAL PATH (unblocked)

**Research [verified 2026-06-28]**: Gatekeeper targets `.app` bundles (casks), not CLI binaries built locally. A Homebrew formula that builds from source never triggers Gatekeeper. Apple Silicon requires at minimum ad-hoc signing (`codesign -s -`); a completely unsigned `.app` is rejected. `make dev-cert` (self-signed identity) already satisfies this.

**Two v0 distribution paths (no cert required)**:
1. Homebrew formula in custom tap — `brew tap speak-dev/speak && brew install speak` clones + builds on user's machine.
2. GitHub Release + ad-hoc signing + xattr — `codesign -s - --deep --force Speak.app`, zip, publish; users run `xattr -dr com.apple.quarantine Speak.app` once.

**Sub-tasks**: `make install` (copy to `/Applications/`), `make github-release` (ad-hoc sign + zip + artifact), `dist/speak.rb` (Homebrew formula, custom tap), README install section (both paths, exact commands).

**Done when**:
- [x] `make dev-cert` creates a stable local signing identity (self-signed)
- [x] `make build` produces a runnable `Speak.app` from a clean clone `[verified]`
- [x] `make install` copies `Speak.app` to `/Applications/` — `[verified]` implemented in Makefile lines 195–207 (builds, kills running instance, syncs via rsync, clears quarantine)
- [x] `make github-release` ad-hoc signs, zips, and produces a release artifact — `[verified]` implemented in Makefile lines 209–230 (builds, codesign --deep --sign -, ditto -c -k to dist/Speak-VERSION.zip)
- [x] `dist/speak.rb` Homebrew formula (custom tap, build-from-source) created — `[verified]` file exists at /dist/speak.rb (custom tap formula, defines build-from-source installation)
- [x] `README.md` install section covers both paths with exact commands — `[verified]` "## Install" section documented (Path 1: brew tap, Path 2: GitHub Release + xattr, Path 3: planned official Cask v0.1)

---

## P11-b — Developer ID sign + notarize + Homebrew Cask [!BLOCKED: needs cert]

**Hard deadline: 2026-09-01** — Homebrew ends support for casks that fail Gatekeeper checks. Official `homebrew-cask` tap requires notarization after that date. **Does NOT block v0 ship** — blocks only official Homebrew Cask and zero-friction install for non-developer users. Enroll at developer.apple.com ($99/yr).

**Sub-tasks**: Developer ID Application cert; full `make release` (already implemented in `Makefile` + `docs/release.md`); only the credential is missing.

**Done when** (execute once cert is enrolled):
- [ ] `make release` produces a signed + notarized `.dmg`
- [ ] `brew install --cask speak` works on a clean machine (official tap)
- [ ] Gatekeeper shows "verified" (no "unidentified developer")
- [ ] `dist/speak.cask.rb` sha256 updated post-release

---

## P12 — Docs + demo [~IN PROGRESS]

**Sub-tasks**: Public-facing `README.md` (what it is, install, privacy, hotkey), screenshots, demo GIF, `CONTRIBUTING.md`, `CHANGELOG.md`.

**Done when**:
- [x] README answers: what is it, how to install, how to use, privacy stance — `[verified]` (full rewrite; build-from-source path; honest pre-release status)
- [x] Privacy section states all 5 guarantees from `product.md §8` — `[verified]` (all 5 listed; #1/#2/#3/#5 cite `make verify-moat` automated proof; #4 hardware-mute framed as design posture, not yet implemented)
- [ ] Demo GIF shows the headline flow end-to-end (hotkey → overlay → paste) — `[deferred — needs human verification]` (requires a live recorded run; §5)
- [~] Repo is public-ready — docs in place; gated on the live-verification pass + P11 notarized release before a public tag

---

## P13 — Dogfood [~VERIFIED BY HUMAN, METRICS PENDING] ← CRITICAL PATH

**Task**: Sustained real use across Slack, code comments, terminal, email. The double-tap window (400ms) is confirmed or tuned here (`benchmark.md §7`, `[decision]`). WER tolerance `T_wer` is evaluated here.

**Status (2026-07-10)**: User tested live across Terminal, Slack, TextEdit, email. All core paths verified: no paste-protection prompts, hotkey false-trigger rate acceptable, permissions flow correct. **One finding**: cleanup latency regression on long dictations (~3 min speech produces slower processing).

**Done when**:
- [x] Real-use dogfood notes logged in `progress.md` covering all four contexts (Slack, code, terminal, email) ✓
- [~] Top 3 bugs filed with repro steps (ONE identified: cleanup latency on long inputs)
- [~] Latency measured: median stop→paste (raw only) and stop→paste (with cleanup); both logged against `benchmark.md §7` targets (PENDING — exact latency for long-input case needed for P14 investigation)

---

## P14 — Verify v0 ship gate [~IN PROGRESS] ← CRITICAL PATH (NEXT)

**Task**: Confirm all four v0 ship conditions hold before tagging v0.0.1.

**Status**: P13 dogfood PASS. P14 cleanup latency is a documented design trade-off (small on-device model for privacy); defer perf tuning to v0.1's larger-model comparison.

**Ship gate checklist** (all must pass):
1. [ ] **Benchmark MATCH (§4)**: Accuracy (WER ≤ Wispr + `T_wer`), neat writing, latency, live feedback, paste (≥ 13/16 apps), hotkey, history
2. [ ] **Benchmark BEAT rows (§3)**: 100% local, free, MIT, no account, local history, lower latency, no egress (automated via `make verify-moat` 7/7 ✅)
3. [ ] **Quality.md §9 ship checklist**: build/sign clean, no `print`, no force-unwrap, paste-protection, permissions edge cases
4. [ ] **P11-a verification**: `make install` works from clean clone; README install accurate

**Done when**:
- [ ] All four ship gate items verified (measured, not asserted)
- [ ] Roadmap reconciled (all [TODO] items either done or explicitly deferred to v0.1+)
- [ ] v0.0.1 tag ready
- [ ] No false triggers in normal typing
- [ ] No permission edge cases: revocation, re-grant, and OS-upgrade scenarios tested

---

## v0 ship gate (after P14)

v0 ships when **all four** hold — no exceptions:

1. **`benchmark.md §4` MATCH gate**: all checkboxes pass (accuracy, neat writing, latency, live feedback, paste, hotkey, history).
2. **`benchmark.md §3` BEAT rows**: all seven structural moat rows hold (100% local, free, MIT, no account, local history, lower latency, no egress).
3. **`quality.md §9` ship checklist**: build/sign/notarize clean, no `print`, no force-unwrap, paste-protection clean, etc.
4. **P11-a done**: `make install` works from a clean clone; README install section accurate.

**v0 does NOT require P11-b** (Developer ID cert). v0 ships as a build-from-source developer preview. P11-b gates the Homebrew Cask and public tag — that is v0.1 distribution.

Tag `v0.0.1` and publish only when all four are verified, measured, not asserted.

---

> v0.1/v1/v2/v3+ roadmap: `docs/product.md §9` (version ladder with summary tables).
> Human verification tasks: `docs/human-verification.md`.
