# `speak`

> The Mac-native, free, local-first voice dictation app for people who don't
> want their audio in someone else's cloud.

[![Status: pre-build](https://img.shields.io/badge/status-pre--build-orange)](docs/progress.md)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](LICENSE)
[![Platform: macOS 26+](https://img.shields.io/badge/platform-macOS%2026%2B-lightgrey)](#)

`speak` is a menubar app that captures your microphone on a hotkey, transcribes
speech **on-device** with Apple `SpeechAnalyzer`, optionally cleans it with a
local LLM, and pastes the result at your cursor. The free, private alternative
to Wispr Flow ($15/mo, cloud-only).

**Status**: pre-build. Documentation complete; no code yet. See
[`docs/progress.md`](docs/progress.md).

---

## Why

- **Local-first.** No audio leaves your device. Ever. No accounts, no login,
  no telemetry.
- **Free + open source (MIT).** The only 2026 Mac dictation app that is
  local-only, free, AND open source.
- **Apple SpeechAnalyzer first.** Fastest on Apple Silicon, no model download,
  no cloud, improves with OS updates.
- **Developer-first UX.** Double-tap Fn to start, single-tap Fn to stop & paste.
  Customizable. Scriptable CLI coming in v0.1.

---

## Quickstart (when v0 ships)

```bash
brew install --cask speak
# double-tap Fn, speak, single-tap Fn → text pastes at cursor
```

Until then, see the [build roadmap](docs/roadmap.md).

---

## The signature flow

1. **Double-tap Fn** → menubar turns red, overlay appears
2. **Speak** → partial transcript streams live
3. **Single-tap Fn** → text pastes at your cursor

---

## Privacy

1. No audio leaves the device. (Cloud is opt-in, v1+.)
2. No accounts, login, or telemetry.
3. Transcripts stay local in `~/Library/Application Support/speak/`.
4. Hardware mute — when muted, no audio is captured, period.
5. History is yours: clearable, exportable, never synced.

Full details: [`docs/product.md` §7](docs/product.md).

---

## Documentation

This repo is structured for **autonomous agent operation** as much as human
reading. Start here:

| Read this | For |
|---|---|
| [`AGENTS.md`](AGENTS.md) | The operating manual — how any agent works on this repo |
| [`docs/progress.md`](docs/progress.md) | Where the project is *right now* (living state) |
| [`docs/product.md`](docs/product.md) | What `speak` is and why (immutable truth) |
| [`docs/architecture.md`](docs/architecture.md) | How it's built (modules, types, signatures) |
| [`docs/roadmap.md`](docs/roadmap.md) | Build order (phased plan, done-when criteria) |
| [`docs/quality.md`](docs/quality.md) | How to verify (tests, risks, ship gates) |
| [`research/`](research/) | Raw research archive (evidence, not direction) |

---

## Tech stack

Swift 5.9+ · SwiftUI · Apple `SpeechAnalyzer` · `AVAudioEngine` · `CGEventTap`
· `NSPasteboard` · SQLite · `os.Logger` · MIT · Homebrew Cask + `.dmg`.

macOS 26+, Apple Silicon only in v0.

---

## License

MIT. See [`LICENSE`](LICENSE).
