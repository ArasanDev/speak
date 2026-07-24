# `speak`

> **Your voice is the new keyboard.** macOS-native, 100% local, free, open-source
> voice dictation with AI neat-writing — speech → on-device AI → pasted at cursor.

[![CI](https://img.shields.io/badge/CI-passing-green)](docs/progress.md)
[![Release](https://img.shields.io/badge/release-v0.0.1-orange)](CHANGELOG.md)
[![Platform](https://img.shields.io/badge/platform-macOS%2026%2B-lightgrey)](#build-from-source)
[![Swift](https://img.shields.io/badge/Swift-5.9%2B-orange)](#tech-stack)
[![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-required-black)](#build-from-source)
[![License](https://img.shields.io/badge/license-MIT-blue)](LICENSE)
[![Moat audit](https://img.shields.io/badge/moat%20audit-7%2F7-green)](#privacy)
[![Discord](https://img.shields.io/badge/Discord-coming%20soon-5865F2)](#contributing)

<!-- Demo GIF coming soon — recording pending human verification of live paste flow. -->
<!-- Replace this comment with: ![speak demo](docs/assets/demo.gif) -->

`speak` is a menubar app. Press a hotkey, talk, stop. On-device AI **writes the
transcript neatly** — filler removed, punctuation correct — and pastes the finished
text at your cursor, in any app. No cloud. No account. No telemetry. Fully offline.

It is the same core experience as Wispr Flow ($15/mo, cloud-only) but **entirely
on your device** — powered by Apple Foundation Models on macOS 26.

---

## Why `speak`?

The voice dictation market is dominated by cloud-only subscriptions ($8–$15/mo) with
serious privacy trade-offs. `speak` occupies the position no competitor can match
without abandoning their business model: **fully local, free, open, and private**.

### The 7-point moat

1. **100% local AI neat-writing** — Apple Foundation Models (AFM 3 MoE), zero API keys
2. **Two OS permissions only** — Microphone + Accessibility. No Input Monitoring, no Screen Recording
3. **Native `speak-mcp` binary** — compiled Swift MCP server for terminal/IDE agents
4. **MIT licensed, free forever** — no accounts, no tracking, no cloud infrastructure
5. **<15MB app payload** — leverages built-in macOS 26 frameworks, no model downloads
6. **Write-only pasteboard** — never reads clipboard history (macOS 26.4 paste-provenance safe)
7. **Hardware mute guard** — when muted, no audio is captured, period

### How it compares

| | Wispr Flow | Superwhisper | FluidVoice | **speak** |
|---|---|---|---|---|
| Price | $15/mo | $8/mo | Free | **Free (MIT)** |
| Architecture | Cloud-only | Local-first | Local | **Native local** |
| Model payload | 0MB (cloud) | 500MB+ | ~460MB | **<15MB** |
| Privacy | Screenshots + cloud audio | Local storage | Local (GPLv3) | **100% local, 2 perms** |
| AI neat-writing | Cloud AI | Local LLM | None | **On-device Apple FM** |
| MCP support | No | No | No | **Native `speak-mcp`** |
| Open source | No | No | GPLv3 | **MIT** |
| Pasteboard | Reads clipboard | Reads clipboard | Reads clipboard | **Write-only** |

---

## Quick start

### Homebrew (recommended)

```bash
brew tap speak-dev/speak
brew install speak
```

> The tap publishes at first tag (`v0.0.1`). Until then, build from source below.

### Build from source

Requirements: macOS 26 (Tahoe), Apple Silicon, Xcode 26+.

```bash
brew install xcodegen swiftlint xcbeautify
git clone https://github.com/speak-dev/speak.git && cd speak
make build     # generates Speak.xcodeproj, builds Speak.app
make test      # full test suite
make run       # launch the menubar app
```

### First run permissions

| Permission | Why |
|---|---|
| **Microphone** | Capture audio for on-device transcription |
| **Accessibility** | Global hotkey (CGEventTap) + synthetic Cmd+V paste |

---

## How it works

```
┌──────────────────────────────────────────────────────────────────────┐
│                         speak pipeline                                │
│                                                                      │
│  ┌─────────┐   ┌─────────┐   ┌──────────┐   ┌─────────┐   ┌─────┐ │
│  │ Hotkey  │──►│   Mic   │──►│   STT    │──►│ Cleanup │──►│Paste│ │
│  │ (Fn×2)  │   │ Capture │   │ Speech   │   │ Apple   │   │Cmd+V│ │
│  │CGEvent  │   │AVAudio  │   │Analyzer  │   │  FM     │   │     │ │
│  └─────────┘   └─────────┘   └──────────┘   └─────────┘   └─────┘ │
│                                                                      │
│  ┌──────────────────────────────────────────────────────────────────┐│
│  │              Local Inference Server (optional)                   ││
│  │  127.0.0.1:11235 — OpenAI + Anthropic + Responses API           ││
│  │  Bearer token auth · loopback only · Apple FM + Ollama + MLX    ││
│  └──────────────────────────────────────────────────────────────────┘│
│                                                                      │
│  ┌──────────────────────────────────────────────────────────────────┐│
│  │              speak-mcp (Model Context Protocol)                  ││
│  │  Native Swift binary · stdio transport · 8 tools                ││
│  │  speak_notify · speak_ask · speak_confirm · speak_request_input ││
│  └──────────────────────────────────────────────────────────────────┘│
└──────────────────────────────────────────────────────────────────────┘
```

1. **Double-tap Fn** — menubar turns red, floating overlay appears
2. **Speak** — partial transcript streams live in the overlay
3. **Single-tap Fn** — on-device AI writes it neatly, text pastes at cursor
4. **Menubar returns to idle** — dictation saved to local history

### The five states

| State | Menubar | Overlay |
|---|---|---|
| Idle | gray waveform | none |
| Listening | red dot | streaming partial text |
| Processing | yellow spinner | frozen text + cleanup spinner |
| Done | green flash → gray | fades out, neat text pasted |
| Error | red X | error message |

---

## Local Inference Server

`speak` includes an optional **loopback-only** HTTP inference gateway that exposes
Apple Intelligence and local LLMs to your developer tools via standard API protocols.

**Security model:**
- Binds strictly to `127.0.0.1` — kernel rejects non-loopback connections (`NWParameters.acceptLocalOnly`)
- Every request requires a Bearer token stored in macOS Keychain
- No TLS needed (loopback traffic never leaves the machine)

### Supported protocols

| Protocol | Endpoint | Compatible with |
|---|---|---|
| OpenAI Chat Completions | `POST /v1/chat/completions` | OpenAI SDK, Cursor, Continue |
| Anthropic Messages | `POST /v1/messages` | Anthropic SDK, Claude Code |
| OpenAI Responses | `POST /v1/responses` | OpenAI Responses API |
| Model listing | `GET /v1/models` | Any OpenAI-compatible client |
| Health check | `GET /health` | Load balancers, monitoring |

### Quick test

```bash
# Start the server from the dashboard (Inference pane → Start)
# Then test with curl:
curl http://localhost:11235/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer sk-speak-<your-key>" \
  -d '{"model": "speak-default", "messages": [{"role": "user", "content": "Hello!"}]}'
```

### Connect your tools

The Inference pane in the dashboard provides copy-paste snippets for:
- Python (OpenAI SDK / Anthropic SDK)
- cURL
- Cursor (`settings.json`)
- Claude Code (`settings.json`)
- Environment variables (`.zshrc`)

### Discovered backends

The server auto-discovers available local inference backends:
- **Apple SystemLanguageModel** (AFM 3 Core) — always available on macOS 26
- **Ollama** — probed at `127.0.0.1:11434`
- **MLX LM Server** — probed at `127.0.0.1:8080`

---

## MCP Setup

`speak-mcp` is a native Swift binary that serves the Model Context Protocol over
stdio for any MCP-capable agent (Claude Code, Cursor, Windsurf).

### Claude Code

Add to your Claude Code MCP settings:

```json
{
  "mcpServers": {
    "speak": {
      "command": "/usr/local/bin/speak-mcp",
      "args": []
    }
  }
}
```

### Available tools

| Tool | Description |
|---|---|
| `speak_register_session` | Bind an agent session to the speak daemon |
| `speak_notify` | Visual HUD alert + auditory tone |
| `speak_say` | Read text aloud via speech synthesis |
| `speak_ask` | Prompt user with spoken question, capture voice response |
| `speak_confirm` | Binary Yes/No voice/HUD confirmation |
| `speak_request_input` | Trigger dictation to gather developer prompt text |
| `speak_status` | Return current state machine phase |
| `speak_submit_call` / `speak_get_call` | Async function call dispatch |

---

## Privacy

Privacy is structural, not a setting:

1. **No audio or text leaves the device.** Ever, by default. No external network egress.
2. **No accounts, no login, no telemetry.** `speak` sends nothing anywhere.
3. **Transcripts stay local** (`~/Library/Application Support/speak/`),
   searchable and exportable, never synced.
4. **Hardware mute**: when muted, no audio is captured — not readable in software.
5. **Works fully offline.** Networking off changes nothing about the core flow.
6. **No external network listener.** The optional inference server binds strictly
   to `127.0.0.1` (loopback) and requires Bearer token auth. It is unreachable
   from any external network interface — enforced at the kernel level via
   `NWParameters.acceptLocalOnly`.

Guarantees 1, 2, 3, and 5 are not just claims — they are enforced by automated
source-tree audit. `make verify-moat` (and the `MoatAuditTests` test suite) scan
every import and every networking/auth/paywall symbol in `SpeakCore` and `App`
and fail the build if any appear. It is a re-runnable, regression-gated proof,
not a promise. Current status: **7/7 checks pass**.

Guarantee 4 (hardware mute) is enforced in the engine, not the UI: when muted,
`SpeakEngine.beginDictation` refuses and the transcriber is never started, and
muting *during* a dictation cancels the in-flight session — so no microphone
capture is ever initiated or continued while muted.

Guarantee 6 (loopback-only server) is enforced at two levels: the kernel rejects
non-loopback TCP connections (`acceptLocalOnly = true`), and every request must
present a valid Bearer token stored in the macOS Keychain.

> Contrast: Wispr uploads audio to OpenAI (STT) and a fine-tuned Llama (cleanup),
> mandates an account, screenshots active windows, and has no offline mode.

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
- Local inference server: loopback HTTP gateway with OpenAI + Anthropic protocols
- MCP bridge: native Swift `speak-mcp` binary with 8 tools
- Settings: cleanup toggle, STT/cleanup engine selection, language, paste mode
- Permissions onboarding: three-step flow, auto-advances on grant
- Moat audit: **7/7** (MIT, no third-party imports, no network egress, no
  auth code, no paywall, offline by construction, no pasteboard reads)

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
| [`CONTRIBUTING.md`](CONTRIBUTING.md) | How to contribute |
| [`CHANGELOG.md`](CHANGELOG.md) | What's been built |

---

## Tech stack

Swift 5.9+ · SwiftUI · macOS 26 (Tahoe) · Apple Silicon

- **STT**: Apple `SpeechAnalyzer` (`Speech` framework), on-device, via
  pluggable `Transcribing` protocol
- **AI cleanup**: Apple `Foundation Models`, on-device LLM, via pluggable
  `LLMCleaning` protocol (raw-transcript fallback when unavailable)
- **Inference server**: `Network` framework (`NWListener`), loopback-only HTTP,
  OpenAI + Anthropic + Responses protocol handlers
- **Hotkey**: `CGEventTap` (`CoreGraphics`), `kVK_Function` double-tap
- **Paste**: `NSPasteboard` write + `CGEvent` Cmd+V simulation (write-never-read)
- **History**: SQLite3 (raw C API, no third-party deps)
- **MCP**: Native Swift binary, stdio JSON-RPC transport
- **Logging**: `os.Logger` (no `print` anywhere)
- **Build**: XcodeGen (`project.yml` → `Speak.xcodeproj`), `make`

No third-party runtime dependencies. All frameworks are Apple-provided.

---

## Contributing

See [`CONTRIBUTING.md`](CONTRIBUTING.md). We welcome:
- Bug reports and feature requests (GitHub Issues)
- Pull requests (see CONTRIBUTING.md for the branch/commit convention)
- Test coverage improvements
- Documentation fixes

---

## License

MIT. See [`LICENSE`](LICENSE).
