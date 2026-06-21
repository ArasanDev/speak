# Next-Iteration Plan — speak (post-v0-core UI/UX + reliability push)

**Status:** DRAFT contract, awaiting orchestrator go + the Wave-1 live gate.
**Author:** orchestrator (Opus), 2026-06-21.
**Grounding:** competitor research (`speak-competitor-research` workflow, 5 apps + trends
sweep) + current-state inventory (Explore agent). Sources cited inline below.

This plan is the execution contract between planning and `build`. It is research-grounded,
not memory-based. Every wave names its owning team agent and model tier.

---

## 0. The decisive findings (why this plan looks the way it does)

1. **VoiceInk is our architectural twin** (open-source GPLv3, native macOS, local Whisper,
   `Cmd+V` paste, CGEventTap hotkey). Its recorder HUD is a complete, copyable blueprint:
   a **15-bar live waveform driven by `audioMeter.averagePower`**, idle/recording/
   transcribing/enhancing states, a live streaming-transcript panel that expands the pill,
   an in-HUD record + mode button, and **Escape-to-cancel**. It also ships a **40 ms Fn
   debounce** to filter the spurious `flagsChanged` events macOS emits for its own
   Fn-dictation. (github.com/Beingpax/VoiceInk)

2. **The contested-Fn problem is industry-wide, and the two most deliberate players dodged
   it with a non-Fn default**: Superwhisper → **Option+Space**; MacWhisper → **double-Option**.
   Aqua keeps Fn but documents disabling Apple dictation. This validates our decision to
   switch `speak`'s default off Fn.

3. **Our moat is structural and uncopyable by the funded field** (trends sweep
   "opportunitiesForSpeak"): every leader is a paid subscription (Wispr $15/mo, Superwhisper
   $8.49/mo, Aqua $8/mo) and most are cloud-only (audio + on-screen context leave the device
   every dictation). `speak` = SpeechAnalyzer + Foundation Models, **zero cost, no account,
   no egress, works offline**, MIT, Homebrew. No VC-backed competitor can match "truly free,
   local forever" without breaking their unit economics. **First mover on the full
   SpeechAnalyzer + Foundation Models stack** — Superwhisper users are *requesting* it; nobody
   funded ships it yet.

4. **The emerging transparency pattern is our natural home**: the market is converging on
   **4-level cleanup intensity (None/Light/Medium/High) + an "undo AI edit" / diff view** that
   shows exactly what the AI changed. Power users' top complaint about cloud apps is
   "mystery-box over-editing." A local-first app showing raw-vs-cleaned side by side is the
   honest answer — and it aligns with our existing `cleanupLevel`/`cleanupStyle` seams.

---

## 1. THE HARD GATE (blocks the HUD wave only)

The core loop **has never been observed to fire** on a real machine — `progress.md:913` and
`human-verification.md:83` still mark the Fn event-model `[unverified]`. Disabling macOS
system dictation is necessary but is **not** proof the loop works.

**Wave-1 exit criterion (human-only, the one thing no agent can do):** one confirmed
`double-tap → overlay appears → speech → text pasted` cycle, witnessed in the
`com.speak.core` log stream. Until that is green:
- Waves 1, 3, 4 (hotkey, Settings, transparency/history) **may build** — they don't depend on it.
- **Wave 2 (HUD polish) does NOT fan out.** No point polishing a HUD the user can't trigger.

---

## 2. The default-trigger decision (locks everything downstream)

**Corrected event model** (the grounding agent's "Right-Command = keyDown/keyUp" claim is
wrong and must NOT be coded from): all modifier keys — ⌘/⌥/⌃/⇧/Fn — emit
`CGEventType.flagsChanged`, never keyDown/keyUp. Left vs right is the **keycode on that
flagsChanged event** (`kVK_RightCommand = 54`, left = 55; `kVK_Function = 63`). So the tap
**already listens to the right event type** — we match keycode + the modifier-down edge,
exactly as it does for Fn today. `[unverified → confirm empirically in W1.0]`

**Recommendation: double-tap Right-Command (keycode 54 specifically).**
- No character output (unlike Option+Space, which inserts a non-breaking space if not suppressed).
- **Right**-Command specifically is rarely used in chords (Cmd+C/V/etc. are struck with the
  left ⌘), so matching keycode 54 — not "either Command" — keeps false-triggers low.
- Same `flagsChanged` mechanism as Fn → smallest, lowest-risk change.
- **Alternative on the table:** Option+Space (Superwhisper's choice) — zero double-tap
  false-trigger risk, but needs event suppression to avoid typing nbsp. Decide before W1.1.
- Fn stays a *selectable* binding (with the 40 ms debounce), never the default.

---

## 3. The waves

Team agents (per `.claude/agents/team/`): builder-input, builder-app, builder-audio-stt,
builder-engine, builder-cleanup, builder-qa, builder-release.

### WAVE 1 — Make the loop fire reliably  *(critical path; build now)*

| # | Task | Owner | Tier |
|---|------|-------|------|
| W1.0 | **Verify the Right-Command event model empirically** before any code: confirm a right-⌘ press arrives as `flagsChanged` carrying keycode 54 + a `maskCommand` down-edge (`swiftc`/live `log` probe). Gate W1.1 on the result. | builder-input | Sonnet |
| W1.1 | Switch `HotkeyBinding.defaultBinding` to double-tap Right-Command (keycode 54). Match keycode on the existing `flagsChanged` path — **do NOT** widen the tap to keyDown/keyUp. Keep Fn selectable; add VoiceInk's **40 ms Fn debounce** for when Fn is chosen. `DoubleTapDetector`/Codable/`BindingStore` unchanged. | builder-input | Sonnet |
| W1.2 | Onboarding: detect macOS system-dictation conflict and guide the user to disable it; add a **live "Try it now" hotkey test** (pill turns green on trigger — VoiceInk/Wispr pattern); implement the missing **auto-close on the Done step**. | builder-app | Sonnet |
| W1.3 | **[HUMAN GATE]** Confirm one real `double-tap → overlay → speech → paste` cycle in the `com.speak.core` log. Unblocks Wave 2. | (user) | — |

### WAVE 2 — Active-dictation HUD → native-Apple quality  *(blocked on W1.3)*

The "popup UI" the user cares about. Today: 3 states, **stubbed level meter (idle breathing,
no live mic feed)**, system font (not Monaco), no error state, no controls.

| # | Task | Owner | Tier |
|---|------|-------|------|
| W2.1 | Wire **live mic RMS → `OverlayViewModel.level`** (the missing link): AVAudioEngine tap → averagePower → 0…1, published to the HUD. This is what turns the meter real. | builder-audio-stt + builder-engine | Sonnet |
| W2.2 | Rebuild `TranscriptOverlayView` to VoiceInk-grade: **reactive 15-bar waveform** (driven by W2.1), **Monaco theme tokens** (replace magic numbers/system font), an **error state** (red pill + retry, replacing today's silent hide), honest **"Pasting…" vs "Cleaning up…"** copy keyed on whether cleanup is on, **Reduce-Motion** + **VoiceOver** announcements, and an in-HUD **Escape-to-cancel** affordance. | builder-app | Sonnet |
| W2.3 | Menubar polish: `mic.slash.fill` **muted icon state**, a **Start/Stop Dictation** item that reacts to listening, live duration/word-count in the status line. | builder-app | Haiku |

### WAVE 3 — Settings screen redesign  *(research-driven; build now)*

Today: 4-section `Form`, hotkey shown **read-only**, `cleanupStyle`/`cleanupLevel`/
`customVocabulary` stored but absent from Settings. Target the cross-competitor consensus IA
with **progressive disclosure** (simple defaults up front, advanced one tap away — the
explicit winning pattern from the trends sweep).

| # | Task | Owner | Tier |
|---|------|-------|------|
| W3.1 | New sidebar/tabbed Settings IA (Monaco design language): **General · Shortcuts · Transcription · AI Cleanup · Dictionary · Snippets · Pasting · Privacy · Audio · About.** Wire the already-stored-but-hidden settings (`cleanupStyle`, `cleanupLevel`). | builder-app | Sonnet |
| W3.2 | **Hotkey recorder sheet** (record-a-combo, the #1 missing Settings affordance) + per-binding **Toggle / Push-to-Talk / Hybrid** mode picker (Hybrid = VoiceInk's short-press-toggle / long-press-PTT). | builder-input + builder-app | Sonnet |
| W3.3 | **Privacy section as a first-class moat surface**: "100% on-device / no account / no egress" badge, transcript **auto-delete** policy (Immediately/1h/1d/7d), audio-retention policy. (VoiceInk/Wispr both ship this; it's our strongest story.) | builder-app | Sonnet |
| W3.4 | **Restore-clipboard-after-paste** toggle (VoiceInk "Keep Clipboard Content", with restore-delay) — wire into the paste pipeline. | builder-input | Sonnet |

### WAVE 4 — Transparency & power-user moat  *(differentiation; build now, lower priority)*

| # | Task | Owner | Tier |
|---|------|-------|------|
| W4.1 | **4-level cleanup intensity (None/Light/Medium/High)** mapped onto `cleanupLevel` + a **raw-vs-cleaned diff view** ("see exactly what the AI changed") — the transparency feature the market is only now adding; our natural home. | builder-cleanup + builder-app | Sonnet |
| W4.2 | History: **full-text search**, **retry/reprocess** a past dictation through current settings, **re-paste original vs cleaned** (separate actions). | builder-app | Sonnet |
| W4.3 | **Transcripts-as-local-JSON** export for automation (Raycast/Keyboard Maestro/shell) — a local-first capability cloud apps structurally cannot offer. | builder-app + builder-engine | Sonnet |

### Deferred to a later iteration (named so they're not lost)
Per-app / context-aware cleanup style; Notch recorder style (VoiceInk dual-style); confidence-
colored partial text; edit-before-paste HUD expansion; voice commands ("Send It"); agentic
voice→agent piping; additional STT/cleanup engines (WhisperKit/Ollama) in the picker.

---

## 4. Execution model

- **Parallelizable now (W1, W3, W4):** independent seams → fan out with `isolation: worktree`,
  one agent per task, orchestrator reviews each diff and owns the merge + commit.
- **W2 stays parked** behind the W1.3 human gate.
- Every task ends green on `make build` + `make test` + `make lint` + `make verify-moat`
  before merge. builder-qa authors/extends tests per wave.
- Hard rules unchanged: 100% local, Apple-frameworks-only (v0), no pasteboard *read*,
  `os.Logger` only, no force-unwrap, no magic numbers, tag every claim.
