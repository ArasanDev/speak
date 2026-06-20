# `speak` — Quality, Risks & Ship Gates (VERIFY)

> **Status**: How to verify the work. Every roadmap task gets test coverage
> here. The ship checklist is the binary gate for v0.
>
> **Depends on**: `roadmap.md`, `architecture.md`, `benchmark.md`.

---

## 0. Principle

**Code is not done when it's written. Code is done when it's verified.**
Before marking any roadmap task complete, run the relevant test category
below and confirm the done-when criterion from `roadmap.md` is satisfied.

---

## 1. Unit tests (`SpeakTests/`, XCTest)

By module:

### AudioCapture
- Sample rate = 16kHz, channels = 1 (mono).
- Format: PCM Float32 or Int16 (document which).
- Callback timing: buffers emit at expected cadence.
- Tap removed cleanly on stop (no zombie callbacks).

### HotkeyMonitor
- Single-tap within window → no start (single-tap is stop-only).
- Double-tap within 400ms → `startCapture`.
- Two taps > 400ms apart → no start.
- Modifier combos (`Cmd+Shift+X`) register correctly.
- External keyboard: Fn behavior documented (may not fire — handle gracefully).
- Binding persists across launches (`UserDefaults` round-trip).

### SpeechTranscriber
- Against a `MockTranscriber` (contract test): partial chunks before final.
- Engine id correct (`"apple-speech-en-US"`).
- Locale passed through correctly.
- Stream closes cooperatively on `stop()`/`cancel()`.
- Transcriber crash → `SpeakError.transcriberUnavailable`.

### PasteboardWriter
- **Mocked paste**: verify the *write* path runs; verify it never reads.
- Cmd+V simulation posts a keyDown + keyUp with `.maskCommand`.
- Pasteboard busy → `SpeakError.pasteboardBusy`.

### PermissionManager
- Full state machine: notDetermined → requesting → granted/denied/restricted.
- Per-kind: microphone, accessibility, inputMonitoring.
- Re-detection after user toggles in System Settings (poll or notification).

### HistoryStore
- CRUD: insert, read-by-id, update, delete.
- Search by substring (case-insensitive).
- last-50 limit: 51st insert evicts oldest.
- Clear empties store.
- Persists across process restart (real SQLite file).

### SettingsStore
- Persistence round-trip (write, relaunch, read).
- Validation: invalid hotkey binding rejected.
- Defaults applied when key absent.

### LLMCleanup (v0 — real tests, default engine: Apple on-device Foundation Models)
- Filler removal: "um", "uh", "like", false starts stripped from test inputs.
- Punctuation and capitalization: raw mid-sentence input → correctly punctuated and capitalized output.
- Formatting: multi-sentence dictation formatted as expected (paragraph breaks, sentence spacing).
- `CleanupMode` passed through correctly to the cleanup engine.
- Engine unavailable (Foundation Models not present / entitlement missing) → raw transcript pasted, no crash.
- Cleanup toggle OFF → raw transcript pasted unchanged (cleanup engine not invoked).

---

## 2. Integration tests (real macOS + mic)

- **End-to-end dictation** in 5 app categories: native macOS (TextEdit),
  Electron (Slack/VS Code), browser (Safari/Chrome text field), IDE (Xcode),
  Terminal.
- **Cleanup end-to-end**: a real dictation session (with filler words and
  missing punctuation) produces *cleaned* text pasted at the cursor — not the
  raw transcript. Verified in at least TextEdit and VS Code. Cleanup
  correctness (filler removal, punctuation, capitalization, formatting quality)
  is a component of the v0 MATCH gate defined in `benchmark.md` §4 — this
  integration test must pass for the neat-writing row to be checked off.
- **Multi-language round-trip** (v0.1): en-US, en-GB, hi-IN.
- **Long session**: 5 min continuous capture — no leak, no crash, no audio
  drift.
- **Background app**: capture continues correctly when `speak` is hidden.

---

## 3. Cross-app compatibility matrix (manual; v0 ship gate)

Test paste + hotkey + **no 26.4 paste prompt** in each. Record pass/fail:

| App | Paste works | Hotkey fires | No 26.4 prompt | Notes |
|---|---|---|---|---|
| TextEdit | | | | |
| Notes | | | | |
| Mail | | | | |
| Messages | | | | |
| Safari (text field) | | | | |
| Chrome (text field) | | | | |
| VS Code | | | | |
| Cursor | | | | |
| Terminal | | | | different paste handling |
| iTerm2 | | | | different paste handling |
| Slack | | | | |
| Discord | | | | |
| Zoom chat | | | | |
| Notion | | | | |
| Linear | | | | |
| GitHub web | | | | |

**Ship gate**: ≥ 13/16 apps pass all three columns. Known-broken (Electron
focus, password fields) documented in README.

---

## 4. Performance benchmarks (XCTest performance tests)

Assert against `architecture.md` §12 budgets:

- First-partial-result latency (p50 < 100ms, p95 < 200ms)
- End-to-end dictation latency for 10s / 30s / 60s speech (p50 < 2s for 30s)
- CPU usage during capture (< 5% p50, < 12% p95)
- Memory footprint idle / listening (< 60MB / < 120MB)
- Battery drain over 1h continuous (< 8%)
- Hotkey press → listening state (< 50ms p50)

---

## 5. Edge & failure cases

- Empty audio (immediate stop) → no crash, no paste.
- Utterance < 1s → handled (maybe no final transcript).
- Utterance > 5 min → no memory leak, transcript complete.
- Background noise → STT degrades gracefully (partial results only).
- Multiple speakers → best-effort (single-user by design; document).
- Accented English → note accuracy; WhisperKit fallback in v0.1.
- **Network offline → must work** (local-only is the moat).
- No microphone / permission denied → clear error, no hang.
- **Permission revoked mid-session** → session aborts cleanly, error state.
- Transcriber crash → caught, fallback or error.
- Pasteboard busy → retry once, then error.
- Hotkey conflict with another app → detect + warn.

---

## 6. Permission flow tests

- Clean install: all notDetermined.
- All denied: app explains each, offers deep-links.
- All granted: full flow works.
- Partial (mic yes, accessibility no): gates correctly.
- Revoked during use: detected, error state.
- macOS upgrade (Tahoe → next): permissions re-check, re-prompt if needed.

---

## 7. Failure-mode tests

- STT engine crash → `transcriberUnavailable`, user notified.
- Microphone disconnected mid-session → session aborts, error.
- LLM server down (v0.1) → raw text pasted, cleanup skipped.
- Pasteboard busy → retry/error.
- Accessibility permission revoked mid-session → hotkey stops, error.
- Hotkey conflict with another app → detection + warning.

---

## 8. Risk register (each risk has a decision rule)

| # | Risk | L | I | Mitigation | Decision rule ("if X, do Y") |
|---|---|---|---|---|---|
| 1 | SpeechAnalyzer quality worse than Wispr in noise | M | H | WhisperKit fallback (v0.1); document noise limits | If word-error-rate > Wispr's by >5pts in quiet tests, ship WhisperKit as default |
| 2 | Fn key is OS-controlled, conflicts vary | H | M | Customizable hotkey from v0; document Fn vs F-key | If >10% users report Fn doesn't fire, promote a non-Fn default |
| 3 | macOS 26.4 paste protection breaks Cmd+V `[unverified]` | L | H | We write, never read pasteboard — but write+Cmd+V bypass is unverified; **test paste in Terminal/iTerm early (P6), before relying on it** | If Cmd+V prompts in any top-20 app, switch that app to AX paste |
| 4 | 3-permission onboarding drops 30%+ | H | H | Streamlined flow, deep-links, video walkthrough | If dropoff >25%, add a "skip and configure later" path |
| 5 | Local LLM adds 1–2s latency | M | M | Streaming UI; per-session disable | If median cleanup >2.5s, default cleanup OFF |
| 6 | Apple closes/changes SpeechAnalyzer access | L | H | Pluggable protocol; WhisperKit ready as fallback | If API deprecated, ship WhisperKit as default in next minor |
| 7 | Wispr Flow copies local-first model | L (2026) | H | Open source + community + MIT moat | Compete on free + open + dev UX, not feature parity |
| 8 | Ollama install friction (non-devs) | H (non-dev) | M | Apple Intelligence in v1 removes the dep | If v0.1 LLM adoption <20%, prioritize Apple Intelligence for v1 |
| 9 | App Store sandboxing blocks hotkeys/paste | H | M | v0 is non-sandboxed (Homebrew only); MAS in v1 reduced-scope | If MAS rejection, ship Homebrew-only indefinitely |
| 10 | Single-maintainer bus factor | H | M | Clean docs, tests, modular `SpeakCore`; MIT invites contributors | If no commits for 30 days, write a "maintainer needed" issue |
| 11 | Mic hardware quality variance | M | L | Document supported devices; allow input-device picker | If specific device >15% error, add device-selection UI |
| 12 | Apple-Silicon-only limits GTM | Certain | M | Intel support (whisper.cpp) in v1 | Not a v0 risk; revisit at v1 launch |

**L** = likelihood, **I** = impact. Every row has an explicit "if X, do Y" —
no "we'll monitor."

---

## 9. v0 ship checklist (binary gate — all must pass)

Before tagging `v0.0.1`:

- [ ] `make build` produces a runnable `.app` from a clean clone
- [ ] Onboarding: a fresh user completes all 3 permissions and reaches a working test dictation without confusion (per `product.md` §7.3)
- [ ] Stop→paste yields cleaned text via on-device Foundation Models (filler removed, punctuated, capitalized)
- [ ] Cleanup toggle OFF → raw transcript pasted; engine-unavailable → raw transcript fallback, no crash
- [ ] Paste works in ≥ 13/16 apps in the compatibility matrix (§3)
- [ ] No `print` in codebase (OSLog only)
- [ ] No force-unwraps / `try!` / `as!` outside tests
- [ ] No global mutable state
- [ ] Never reads the pasteboard (write-only)
- [ ] No third-party dependencies (Apple frameworks only)
- [ ] Signed + notarized; `brew install --cask speak` works on a clean machine
- [ ] 4h dogfood done (P13); top-3 bugs fixed (P14)
- [ ] Performance budgets met (§4) or deviations documented
- [ ] README + privacy section + demo GIF public (P12)
- [ ] All `SpeakTests` green; no skipped tests without a documented reason
