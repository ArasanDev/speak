# `speak`

> The Mac-native, free, local-first voice dictation app: speech → on-device AI
> neat-writing → pasted at the cursor. Private, offline, open source.

[![Status: pre-release (v0 in active development)](https://img.shields.io/badge/status-pre--release-orange)](docs/progress.md)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](LICENSE)
[![Platform: macOS 26+ · Apple Silicon](https://img.shields.io/badge/platform-macOS%2026%2B%20%C2%B7%20Apple%20Silicon-lightgrey)](#build-from-source)
[![Tests: 150 passing](https://img.shields.io/badge/tests-150%20passing-green)](docs/progress.md)
[![Moat audit: 7/7](https://img.shields.io/badge/moat%20audit-7%2F7-green)](#privacy)

`speak` is a menubar app. Press a hotkey, talk, stop. A live overlay streams your
words as you speak. On stop, on-device AI **writes the transcript neatly** — filler
removed, punctuation and capitalization correct — and pastes the finished text at
your cursor, in any app.

It is the same core experience as Wispr Flow ($15/mo, cloud-only) but **entirely
on your device**: no audio leaves the Mac, no account, no telemetry, fully offline,
free, and MIT-licensed.

---

## Why `speak`

The category frontier — Wispr Flow — is cloud-only by architecture. Audio uploads
to their servers; an account is mandatory; there is no offline mode. That is a
structural constraint they cannot drop without abandoning their business model.

`speak` occupies the position Wispr cannot: **fully local, free, open, offline,
and private** — with the frontier's neat-writing experience via on-device Apple
frameworks.

| | Wispr Flow (frontier) | **speak** |
|---|---|---|
| Speech → neat text | Yes (cloud AI) | **Yes (on-device AI)** |
| Local / offline | No (cloud-only) | **Yes** |
| Price | $15/mo (+ capped free tier) | **Free, unlimited** |
| Open source | No | **Yes (MIT)** |
| Account required | Yes | **No** |
| Local dictation history | No | **Yes** |
| Pluggable local models | No | **Yes** |

The moat is the *structural bundle*: local + offline + MIT + no-account + local
history + lower local latency. Note that Wispr also has a free tier and uses Fn
for activation — those are not the differentiators. The structural bundle is.

Other local/open-source dictation apps exist (Aiko, TypeWhisper, FluidVoice) but
target simple transcription. `speak` adds the frontier-grade experience: streaming
live overlay and on-device AI cleanup via Apple Foundation Models.

---

## How it works

1. **Double-tap Fn** — menubar turns red, floating overlay appears
2. **Speak** — partial transcript streams live in the overlay
3. **Single-tap Fn** — on-device AI writes it neatly, text pastes at your cursor
4. **Menubar returns to idle** — dictation saved to local history

Hotkey is fully customizable (F-keys, modifier combos, single-key toggle). Default
double-tap Fn requires no holding (RSI-kind, easy reach on every Mac keyboard).

### The five states

| State | Menubar | Overlay |
|---|---|---|
| Idle | gray waveform | none |
| Listening | red dot | streaming partial text |
| Processing | yellow spinner | frozen text + cleanup spinner |
| Done | green flash → gray | fades out, neat text pasted |
| Error | red X | error message |

---

## Privacy

Privacy is structural, not a setting:

1. **No audio or text leaves the device.** Ever, by default. No network egress.
2. **No accounts, no login, no telemetry.** `speak` sends nothing anywhere.
3. **Transcripts stay local** (`~/Library/Application Support/speak/`),
   searchable and exportable, never synced.
4. **Hardware mute**: when muted, no audio is captured — not readable in software.
5. **Works fully offline.** Networking off changes nothing about the core flow.

Guarantees 1, 2, 3, and 5 are not just claims — they are enforced by automated
source-tree audit. `make verify-moat` (and the `MoatAuditTests` test suite) scan
every import and every networking/auth/paywall symbol in `SpeakCore` and `App`
and fail the build if any appear. It is a re-runnable, regression-gated proof,
not a promise. Current status: **7/7 checks pass**.

Guarantee 4 (hardware mute) is enforced in the engine, not the UI: when muted,
`SpeakEngine.beginDictation` refuses and the transcriber is never started, and
muting *during* a dictation cancels the in-flight session — so no microphone
capture is ever initiated or continued while muted. This is unit-tested headlessly
(`SpeakEngineMuteTests` asserts the transcriber's `startStream` is never called
while muted, and that muting mid-capture stops the listening session). In v0 the
mute toggle is a menu item; a global mute *chord* is a tracked follow-up
(`docs/human-verification.md` §4.6).

> Contrast: Wispr uploads audio to OpenAI (STT) and a fine-tuned Llama (cleanup),
> mandates an account, and has no offline mode.

---

## Install

**`speak` v0 is pre-release.** The engine, UI, and all core features are built
and pass 150 tests. Live verification (paste compatibility with real apps, hotkey
firing with real permissions, notarized release) is in progress — see
[`docs/human-verification.md`](docs/human-verification.md).

**Planned install path (at P11, once signed and notarized):**
```bash
brew install --cask speak
```

**Until then, build from source** (see below).

---

## Build from source

Requirements: macOS 26 (Tahoe), Apple Silicon, Xcode 26+.

```bash
# Install build tools (one-time)
brew install xcodegen swiftlint xcbeautify

# Clone and build
git clone https://github.com/yourhandle/speak.git
cd speak
make build    # generates Speak.xcodeproj, builds Speak.app + SpeakCore.framework
make test     # 150 tests (130 XCTest + 20 Swift Testing), 0 failures
make lint     # SwiftLint (force-unwrap / force-cast / force-try = error)
make verify-moat  # 7/7 structural BEAT rows (offline, no egress, MIT, no account, ...)
make run      # launch the menubar app
```

`make build` runs `xcodegen generate` automatically — a clean clone has no
`.xcodeproj` (it is git-ignored; `project.yml` is the source of truth).

### Required permissions (first run)

`speak` needs two OS permissions — explained in the onboarding flow on first
launch:

| Permission | Why |
|---|---|
| **Microphone** | Capture audio for transcription |
| **Accessibility** | Global hotkey (CGEventTap `.defaultTap`) + synthetic Cmd+V paste |

---

## Current status

**v0 engine and UI are fully built and runnable.**

- Engine pipeline: `SpeechAnalyzer` STT → `Foundation Models` on-device cleanup
  → `NSPasteboard` write + Cmd+V paste, all behind pluggable protocols
- Global hotkey: `CGEventTap` double-tap Fn detection (with `DoubleTapDetector`,
  fully unit-tested, tunable 0.4 s window)
- Live overlay: partial transcript streams via `AsyncStream` to a floating
  non-activating `NSPanel`
- Local history: SQLite via raw C API, searchable, exportable
- Settings: cleanup toggle, STT/cleanup engine selection, language, paste mode
- Permissions onboarding: three-step flow, auto-advances on grant
- Tests: **150 (130 XCTest + 20 Swift Testing), 0 failures**
- Moat audit: **7/7** (MIT, no third-party imports, no network egress, no
  auth code, no paywall, offline by construction, no pasteboard reads)

**What remains before v0 ships** (irreducibly live — tracked in
[`docs/human-verification.md`](docs/human-verification.md)):

- Grant Accessibility permission (Microphone already granted); enable Apple Intelligence
- Verify live paste into TextEdit, Slack, and Terminal (Terminal paste-provenance
  is the project's #1 unverified item — macOS 26.4 added a paste-provenance check)
- Verify hotkey fires globally while another app has focus
- WER corpus (audio clips a human must supply) + live Foundation Models quality
- Developer ID signing + notarization (P11)
- Demo GIF — [deferred — needs human verification]

For the latency figures: the headless, file-fed measurement shows first-partial
p50 ≈ 42 ms (< 200 ms budget) and local stop→result-ready median ≈ 60 ms
(< 1 s budget). These are headless proxy figures, not user-facing end-to-end
latency (which includes live paste, not yet measured).

---

## Documentation

| Read this | For |
|---|---|
| [`AGENTS.md`](AGENTS.md) | The operating manual for autonomous agents on this repo |
| [`docs/progress.md`](docs/progress.md) | Where the project is right now (living state) |
| [`docs/product.md`](docs/product.md) | What `speak` is and why (immutable destination) |
| [`docs/architecture.md`](docs/architecture.md) | How it is built (modules, types, signatures) |
| [`docs/roadmap.md`](docs/roadmap.md) | Build order, done-when criteria per phase |
| [`docs/benchmark.md`](docs/benchmark.md) | The definition of done vs the frontier |
| [`docs/quality.md`](docs/quality.md) | Tests, risks, ship gates |
| [`docs/human-verification.md`](docs/human-verification.md) | What still needs a live human run |
| [`CONTRIBUTING.md`](CONTRIBUTING.md) | How to contribute |
| [`CHANGELOG.md`](CHANGELOG.md) | What's been built |
| [`SPEC.md`](SPEC.md) | Consolidated product + competitive spec |

---

## Tech stack

Swift 5.9+ · SwiftUI · macOS 26 (Tahoe) · Apple Silicon

- **STT**: Apple `SpeechAnalyzer` (`Speech` framework), on-device, via
  pluggable `Transcribing` protocol
- **AI cleanup**: Apple `Foundation Models`, on-device LLM, via pluggable
  `LLMCleaning` protocol (raw-transcript fallback when unavailable)
- **Hotkey**: `CGEventTap` (`CoreGraphics`), `kVK_Function` double-tap
- **Paste**: `NSPasteboard` write + `CGEvent` Cmd+V simulation (write-never-read)
- **History**: SQLite3 (raw C API, no third-party deps)
- **Logging**: `os.Logger` (no `print` anywhere)
- **Build**: XcodeGen (`project.yml` → `Speak.xcodeproj`), `make`

No third-party runtime dependencies. All frameworks are Apple-provided.

---

## Contributing

See [`CONTRIBUTING.md`](CONTRIBUTING.md).

---

## License

MIT. See [`LICENSE`](LICENSE).
