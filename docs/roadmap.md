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
- [ ] Verify against `architecture.md` §14.1 (re-check SpeechAnalyzer API
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
- [ ] A sample dictation produces **cleaned** output (filler removal,
      punctuation, capitalization) when `cleanupEnabled` is `true` and
      Foundation Models is available
- [ ] With `cleanupEnabled = false`, `cleanedText` is `nil` and raw text is
      pasted — no cleanup path runs
- [ ] When Foundation Models is **unavailable**, session gracefully falls back
      to raw transcript and reaches `done` state (not `error`)
- [ ] `SpeakError.llmCleanupFailed` is surfaced only on a genuine API failure,
      not on unavailability
- [ ] Engine id is stored in `TranscriptionResult.engineId` when cleanup runs
- [ ] No third-party dependencies introduced — Apple Foundation Models only
- [ ] Foundation Models API surface verified against current Apple docs (not
      assumed)

---

## Phase 4 — Partial overlay

**Task**: Floating `NSPanel`/SwiftUI overlay that streams the partial
transcript in real time. Auto-position near cursor or top-right, always-on-top.

**Done when**:
- [ ] Overlay appears when session enters `listening` state
- [ ] Partial transcript text updates live (≤200ms lag — matches
      `benchmark.md` §7 `L_partial`)
- [ ] Overlay hides on `done` / `error`

---

## Phase 5 — Hotkey  ← **CRITICAL PATH**

**Task**: `HotkeyMonitor` using `CGEventTap`. Detect double-tap Fn (400ms
window — `benchmark.md` §7, `[decision]`, tune empirically in P13) → emit
`startCapture`. Detect single-tap Fn after start → emit `stopCapture`. Persist
binding in `UserDefaults`. Default binding:
`HotkeyBinding(keyCode: kVK_Function, modifiers: [], trigger: .doubleTap,
doubleTapWindow: 0.4)`.

**Done when**:
- [ ] Double-tap Fn triggers start while **another app has focus**
- [ ] Single-tap Fn triggers stop while another app has focus
- [ ] First run triggers Accessibility + Input Monitoring permission prompts
- [ ] False-trigger rate < 1 per 30 min in normal typing, tested in Notes
      (single source for `F_rate` in `benchmark.md` §7)

---

## Phase 6 — Paste  ← **CRITICAL PATH**

**Task**: `PasteboardWriter` per `architecture.md` §11 — write to
`NSPasteboard`, simulate `Cmd+V`. Wire to `CaptureSession` state machine:
`processing → clean (if cleanup enabled & available) → paste → done`.

The text pasted is `TranscriptionResult.cleanedText` when cleanup is on and
produced output; otherwise `rawText`. The session must reach `done` in both
cases.

**Done when**:
- [ ] When cleanup is **on**: cleaned text (filler-free, punctuated) pastes
      into the focused app
- [ ] When cleanup is **off** or unavailable: raw transcript pastes instead
- [ ] Final transcript (cleaned or raw) pastes into focused text field in
      **TextEdit, Slack, Terminal** (3 different app categories)
- [ ] No macOS 26.4 paste-protection prompt appears (we write, never read)
- [ ] Paste fails gracefully (error state) in password fields

---

## Phase 7 — Permissions flow

**Task**: Full 3-permission onboarding window. Microphone (runtime prompt),
Accessibility + Input Monitoring (deep-link to
`x-apple.systempreferences:com.apple.preference.security` with the app
selected). Explain *why* each is needed with a screenshot per permission.

**Done when**:
- [ ] A fresh user can grant all 3 permissions and reach a working dictation
      with no confusion (the bar is comprehension, not a stopwatch)
- [ ] Deep-links open the correct System Settings pane
- [ ] Permission revocation mid-session is detected → state moves to error

---

## Phase 8 — Menubar states

**Task**: Menubar icon reflects `CaptureSession.State`: gray waveform (idle),
red dot (listening), yellow spinner (processing), green flash (done), red X
(error).

**Done when**:
- [ ] Icon changes color on every state transition
- [ ] "Done" green flash lasts 600ms then returns to idle

---

## Phase 9 — History

**Task**: `HistoryStore` (SQLite, `~/Library/Application Support/speak/`).
Store `HistoryEntry` (raw + cleaned text, timestamp, engine id). Capacity is a
tunable setting (not a hardcoded constant — see `benchmark.md` §7 "history
size"). Searchable from a History window.

**Done when**:
- [ ] Every completed session writes a `HistoryEntry` (with `cleanedText`
      when cleanup ran, `nil` otherwise)
- [ ] History persists across app launches
- [ ] Search by substring returns matching entries
- [ ] "Clear history" empties the store
- [ ] "Export" produces a readable file (plain text or JSON)

---

## Phase 10 — Settings

**Task**: `SettingsStore` (typed `UserDefaults` wrapper). `Settings` SwiftUI
window: hotkey rebinding, language picker (en-US, en-GB minimum), auto-paste
toggle, paste mode (Cmd+V vs AX), **AI cleanup toggle** (on/off), cleanup
engine selector (Foundation Models default; placeholder for future Ollama/MLX
in v1).

**Done when**:
- [ ] All settings persist across launches
- [ ] User can rebind the hotkey to a custom key/modifier combo
- [ ] Language picker lists at least en-US, en-GB
- [ ] Cleanup toggle is active and functional (toggles the P3.5 path)
- [ ] Cleanup engine selection is present in the UI (Foundation Models selected
      by default; v1 alternatives shown as disabled placeholders)

---

## Phase 11 — Build + sign + notarize + package  ← **CRITICAL PATH**

**Task**: Developer ID code signing, notarization, `.dmg` packaging via
`create-dmg` or similar, Homebrew Cask formula (`dist/speak.cask.rb`).
macOS 26 (Tahoe, shipped Q3 2025) requires Gatekeeper-compliant notarization.
`[verified]`

**Done when**:
- [ ] `make release` produces a signed + notarized `.dmg`
- [ ] `brew install --cask <local-cask>` works on a clean machine
- [ ] Gatekeeper shows "verified" (no "unidentified developer")
- [ ] Cask formula follows the [Cask Cookbook](https://docs.brew.sh/Cask-Cookbook)

---

## Phase 12 — Docs + demo

**Task**: Public-facing `README.md` (what it is, install, privacy section,
hotkey help), screenshots, demo GIF, `CONTRIBUTING.md`, `CHANGELOG.md`.

**Done when**:
- [ ] README answers: what is it, how to install, how to use, privacy stance
- [ ] Privacy section states all 5 guarantees from `product.md` §8
- [ ] Demo GIF shows the headline flow end-to-end (hotkey → overlay → paste)
- [ ] Repo is public-ready

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

v0 ships when **all three** of the following hold — no exceptions:

1. **`benchmark.md` §4 MATCH gate**: all checkboxes pass (accuracy, neat
   writing, latency, live feedback, paste, hotkey, history).
2. **`benchmark.md` §3 BEAT rows**: all seven structural moat rows hold
   (100% local, free, MIT, no account, local history, lower latency, no
   egress).
3. **`quality.md` §9 ship checklist**: build/sign/notarize clean, no `print`,
   no force-unwrap, paste-protection clean, etc.

Tag `v0.0.1` and publish only when all three are verified, measured, not
asserted.

---

## v1 — Attractive & friendly

*Value*: more languages, richer cleanup experience, power-user model choice,
polish and onboarding improvements, CLI access.

- **More languages**: SpeechAnalyzer locales surfaced in the language picker;
  WhisperKit (Argmax) as an optional STT engine for the long tail (99
  languages, MIT). `[verified]`
- **Richer cleanup**: tone and style modes (professional, casual, etc.),
  per-app formatting rules, snippets & custom dictionary, learned vocabulary.
- **Pluggable cleanup models surfaced in UI**: Ollama (Qwen 2.5 3B / Gemma
  3 4B / Phi-4-mini) and MLX models as user-selectable alternatives to
  Foundation Models. Guided setup flow.
- **Onboarding, menubar, and overlay polish**: latency tuning, first-run UX
  improvements, latency/metrics view.
- **CLI shim**: `speak --start`, `speak --stop`, `speak --status`.
- **Intel Mac**: whisper.cpp fallback STT for non-Apple-Silicon machines.

**Done when**: all features above have their own binary done-when checklists
(written at implementation time). No dates.

---

## v2 — Creative & expansive

*Value*: code context awareness, conversational editing via voice, optional
local cross-device continuity.

- **Code-aware mode**: detect code context (editor active, file type), format
  transcript accordingly (identifiers, symbols, structure).
- **Voice editing/commands**: "make this shorter," "fix that sentence" — local
  LLM driven, no cloud.
- **Local cross-device continuity**: history and snippets available on other
  devices via iCloud or local network — **always opt-in, never mandatory,
  never account-gated**.
- **Advanced per-app behaviors**: app-specific paste modes, auto-formatting
  rules.

**Done when**: per-feature binary checklists written at implementation time.
No dates.

---

## v3+ — Frontier & creative

Open-ended directions the product earns as it matures. Scope defined when
v2 is stable and real user patterns are established. No pre-commitment. No
dates.

---

> **Principle** (from `product.md` §9): there is no deadline on any version.
> The loop advances the ladder until the product is whole; each rung's "done"
> is defined by testable criteria, not dates. Later versions make `speak` more
> attractive, friendlier, and more creative — they never backfill missing core.
