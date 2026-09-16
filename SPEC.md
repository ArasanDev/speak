# SPEC.md — speak product specification

Consolidated product + competitive reference. Read for: positioning, why-speak, moat claims.

Authority: docs/product.md (vision) · docs/benchmark.md (done-condition) · specs/verification-ledger.md (verified claims)

Date: 2026-06-30.

---

## What speak is

speak is a macOS-native, local-first, free, open-source AI voice dictation app.

Press a hotkey → speak → stop. A floating overlay streams your words live as you speak. On stop, on-device AI cleans the transcript (filler removed, punctuation correct, formatted to context). The finished text pastes at the cursor in any app.

Speech → transcript → on-device AI neat-writing → paste at cursor. That is the entire product.

- Hotkey: double-tap Fn or right command or any key that user to start; single-tap the same to stop and paste. Fully customizable. `[verified]`
- STT: `SpeechAnalyzer` (Apple, on-device, macOS 26, Apple Silicon). `[verified]`
- AI cleanup: `Foundation Models` (Apple, on-device LLM, macOS 26, Apple Silicon). `[verified]`
- Paste: `NSPasteboard` write + simulated Cmd+V. Write-never-read. `[verified in headless]`; Terminal paste-provenance bypass `[unverified — P6 live gate]`
- History: every dictation stored in local SQLite, searchable, exportable.
- 100% local. Offline. Free. MIT. No account. No telemetry. No third-party deps.

speak is deliberately small and opinionated: one thing, done privately, locally, for free.

---

## Why speak / the gap

Wispr Flow is the category frontier and advancing aggressively: Android, Transforms, Command Mode, 100+ languages, Scratchpad, Admin Portal — all in 2026. `[verified]` speak does **not** win on breadth.

The structural window: Wispr is cloud-only. Audio uploads to OpenAI (STT) and a fine-tuned Llama (cleanup). `[verified]` Account is mandatory. No offline mode. `[verified]`

Wispr **cannot** become local, free, open-source, or offline without abandoning its subscription + cloud business model. The window does not close when Wispr ships features. The constraint is architectural.

The on-device stack is now good enough. Apple shipped `SpeechAnalyzer` (macOS 26, on-device STT) and `Foundation Models` (macOS 26, on-device LLM) — both native, free, Neural Engine-accelerated. `[verified]` A category-leading dictation experience can now run entirely locally.

speak occupies the one position the incumbent structurally cannot: **fully local + free + open + offline + private + no-account.**

---

## The moat (structural bundle)

Five properties speak holds simultaneously. No competitor holds all five. Each is a BEAT row in `benchmark.md`.

1. **100% local** — audio + AI cleanup never leave the device. `[verified]`
2. **Fully offline** — all core flows work with networking disabled. Wispr requires cloud. `[verified]`
3. **MIT open source** — community moat; more permissive than VoiceInk's GPL. `[verified]`
4. **No account, no cap** — Wispr free tier caps at 2k words/wk. speak has no tier, no cap. `[verified]`
5. **Local persistent history** — Wispr has none found. `[unverified]` speak owns this gap as a built guarantee.

These must hold for v0 to ship. They are the reason speak exists.

---

## Product version ladder

| Version | Theme | Core deliverable |
|---|---|---|
| **v0** | Complete core | Local STT + AI cleanup + hotkey + overlay + paste + history |
| **v1** | Attractive & friendly | More languages; pluggable models UI; per-app context; CLI shim; Intel via whisper.cpp |
| **v2** | Creative & expansive | Code-aware mode; voice editing; opt-in cross-device continuity (never mandatory) |
| **v3+** | Frontier | Open-ended directions earned as the product matures. No pre-commitment. |

v0 is the complete core — not an MVP. v1–v3+ are additive; they never backfill missing core.

---

## Tech stack

- **Language**: Swift 5.9+, SwiftUI. macOS 26 (Tahoe, shipped Sept 15 2025). `[verified]`
- **Hardware target**: Apple Silicon only; macOS 26.0 deployment. No Intel in v0. `[verified]`
- **App structure**: `Speak.app` (SwiftUI `MenuBarExtra`) embedding `SpeakCore.framework` (headless engine seam).
- **STT**: `SpeechAnalyzer` (`Speech` framework), pluggable via `Transcribing` protocol. `[verified]`
- **Cleanup**: `Foundation Models` framework, pluggable via `LLMCleaning` protocol; raw fallback when unavailable. `[verified]`
- **Hotkey**: `CGEventTap` (`.defaultTap`), requires Accessibility permission only — not Input Monitoring. `[verified]`
- **Paste**: `NSPasteboard` write-never-read + `CGEvent` Cmd+V simulation. `[verified]`
- **History**: SQLite via `HistoryStore`; stored in `~/Library/Application Support/speak/`.
- **State machine**: `CaptureSession` actor — idle → listening → processing → done | error.
- **Logging**: `os.Logger` only. No `print`. Enforced by `.swiftlint.yml`. `[hard rule]`
- **Build**: XcodeGen + Makefile. `Speak.xcodeproj` is git-ignored; `make build` regenerates it.
- **No third-party deps in v0.** No Rust. No FFI. No cross-platform layer.

---

## Done condition (v0)

v0 ships when **all three** hold — measured, not asserted:

1. **MATCH gate** (`benchmark.md` §4): en-US WER ≤ Wispr + 3 pts on the fixed corpus; cleanup on-device and togglable with raw fallback; stop→paste (incl. cleanup) < 2.0s median; first volatile overlay result < 200ms; paste works in ≥ 13/16 apps zero-prompt; hotkey global and rebindable; local history search/clear/export works.

2. **BEAT rows** (`benchmark.md` §3): all structural moat rows hold — offline functional, price $0, MIT repo public, no account required, local history built, latency < Wispr's ~700ms–2s cloud path, no audio/text egress.

3. **Ship checklist** (`quality.md` §9): build/sign/notarize clean; no `print`; no force-unwrap / `try!` / `as!` outside tests; no global mutable state; pasteboard write-only; no third-party deps; `brew install --cask speak` works on a clean machine; dogfood pass; tests green.

---

## Privacy guarantees

Enforced structurally; auditable via `make verify-moat`. `[verified]`

- No audio or text leaves the device. No network egress. Ever, by default.
- No account, no login, no telemetry. speak sends nothing anywhere.
- Transcripts stored locally (`~/Library/Application Support/speak/`). Never synced without explicit opt-in.
- Works fully offline. Disabling networking changes nothing about the core flow.
- Pasteboard: write-never-read — speak never reads pasteboard contents. `[verified in headless]`; Terminal paste-provenance bypass (macOS 26.4 check) `[unverified — empirical test required at P6]`

Contrast: Wispr uploads audio to OpenAI (STT) + a fine-tuned Llama (cleanup), mandates an account, and has no offline mode. `[verified]`
