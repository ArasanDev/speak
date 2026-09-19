# speak — v0 UI Surfaces

> **Purpose**: v0 surface-by-surface UI catalog (onboarding, settings, history, overlay, menubar). · **Audience**: contributor, AI agent (implementing/modifying a v0 UI surface) · **Status**: living — REVISION blocks are locked design, earlier sections are exploration · **Last reviewed**: 2026-06-30 (git log)

> v0 surface catalog. Read when: implementing or modifying any UI surface. Authority: the REVISION blocks are the locked design; earlier sections are exploration.

All surfaces below are built or partially built in v0. See `docs/ui/foundations.md` for tokens, motion, and accessibility rules.

---

## 2.1 Onboarding window [implemented]

**Hard constraint:** modal-ish (takes focus). Shown on first launch + permission revoke. Target: user reaches working dictation in ≤90 s.

**Status:** Built — Welcome → Microphone → Accessibility → Hotkey → Done (P7, loop #16). Input Monitoring step was removed in v0.2; `.defaultTap` is Accessibility-gated only.

Current step list: **Welcome → Microphone → Accessibility → Hotkey → Done** (5 steps).

### Step 1 — Welcome [implemented]

```
┌────────────────────────────────────────────────┐
│ ● ○ ○ ○ ○                                      │  ← progress dots
│         ┌────────────────────┐                  │
│         │   ⏺  waveform icon │                  │  64 pt SF Symbol, .tint
│         └────────────────────┘                  │
│        Welcome to speak                         │  22 pt bold
│   speak turns your voice into polished          │  13 pt secondary, max-width 340
│   text, entirely on your Mac.                   │
│   Nothing leaves your device.                   │
│         ┌──────────────┐                        │  borderedProminent, large
│         │  Get Started  │                       │
│         └──────────────┘                        │
│  Skip for now                        ● ○ ○ ○ ○  │  caption, bottom-left
└────────────────────────────────────────────────┘
                                           480×400
```

`Get Started` → step 2. `Skip for now` → sets `hasCompletedOnboarding = true`, opens System Settings Accessibility. `Cmd+.` / close → same as Skip.

### Step 2 — Microphone [implemented]

States: `notRequested` (blue mic icon, primary button "Grant Microphone Access") → `inFlight` (spinner) → `granted` (green check + "Continue") → `denied` (red "xmark" + "Open System Settings").

`Grant` triggers `AVAudioApplication.requestRecordPermission`. `Open System Settings` deep-links `x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone`.

Privacy badge: `🔒 Audio never leaves this Mac` (small, secondary).

### Step 3 — Accessibility [implemented]

Same layout as Step 2. Icon: `hand.point.point.up.left.fill`.

Body copy: "speak uses Accessibility in two ways: (1) detect your hotkey while another app is focused, and (2) paste text at your cursor."

Polling via `OnboardingViewModel.startPolling` (1.5 s interval). Flip to `granted` within ~2 s of user toggling.

Deep-link anchor `?Privacy_Accessibility` — `[verified]` macOS 13+, `[unverified]` macOS 26 Tahoe; verify on first run.

### Step 4 — Hotkey [implemented]

Current copy: "Double-tap the Fn key to start dictating. Tap it once to stop." User can change in Settings.

**v0.1 addition [design-exploration]:** "Try it now" mini-test pill (44×24) at bottom. Listens for Fn tap; turns green on detection.

### Step 5 — Done [implemented]

Big green `checkmark.seal.fill` (48–64 pt). "You're all set." Auto-close after ~1.5 s.

Edge case: if Mic not yet granted → body copy changes to "Grant Microphone in System Settings to enable dictation."

---

## 2.2 Menubar item + dropdown [implemented]

**Hard constraint:** non-activating. The icon is the only always-present element.

### Dropdown layout (v0)

```
speak — ready (double-tap Fn to start)     ← status line, secondary
─────────────────────────────────────
▶  Start Dictation                ⌥⌘Space
🔇 Mute Microphone
─────────────────────────────────────
History…
Settings…                              ⌘,
─────────────────────────────────────
About speak…
─────────────────────────────────────
Quit speak                          ⌘Q
```

**While listening:** replace "Start Dictation" with "■ Stop Dictation" (red).
**While muted:** show "Muted — dictation disabled" (secondary, disabled tone) below mute row.
**Missing permission:** show "Accessibility Permission Required" row above mute row.
**First run incomplete:** show "Resume Setup…" row.

Modes submenu, Languages submenu, Engine submenu → [planned: v1].

---

## 2.3 Recording HUD [implemented — unified near-rect panel]

**Hard constraint:** `NSPanel`, `NSNonActivatingPanelMask`. Never steals focus. Never shown in idle.

**Constraint:** bottom-center position only. Top-center is explicitly rejected — it steals attention from the dictating app.

**Silhouette:** one shared shape — `HUDLane.panelShape` = `RoundedRectangle(cornerRadius: 14, style: .continuous)` — a near-rectangle with micro-curved corners. The same constant drives clip, state wash, the 1 pt `speakCardBorder` hairline, and the opt-in animated borders, so layers cannot disagree. (Owner direction 2026-09-17: square-ish, not capsule.)

**Sizes:** `OverlayPanelSize` in `SettingsStore` — compact 560×64 / standard 640×76 / wide 760×88, anchored ~24 pt from the screen bottom.

**Anatomy (one frame, all four states):** leading slot (morphs by state — waveform/voice animation → progress → ✓ → ⚠) · header line carrying phase + inline timer (`LISTENING · 0:12`) · transcript lane (`model.windowText`) · quiet controls. No dividers, no icon tiles, no timer endcap. State is conveyed by the leading-slot symbol + a faint phase-colored wash over frosted glass — the frame never reshapes.

### Listening [implemented]

Voice animation in the leading slot (style + color configurable in Settings → Overlay: spectrum bars / sonar / ring gauge), `LISTENING` header with live timer, streaming partial text in the lane.

### Processing [implemented]

Leading slot morphs to a progress indicator; header reads the processing phase; lane shows the captured transcript settling. Panel held for the full cleanup duration. Cleanup failure falls back to raw transcript and still reaches `.done` (fallback is invisible by design).

### Done [implemented]

Leading slot shows a delivered checkmark; `delivered`-role wash. Held ~600 ms, then the panel hides.

Edge case: paste silently lost (e.g., secure field) → show "Done — text on clipboard" for 1.5 s + "Copy" button [planned: v0.1].

### Error [implemented]

Leading slot shows an error symbol with the error wash; lane carries the short message + next action ("Mic permission is off — open System Settings"). Instrument-voice copy (see `philosophy.md` §4 never-list).

**Opt-in border animation [implemented]:** Settings → Overlay offers none / full glow / edge-flow, with tint, speed, and light-count controls. Default is `none` — the static hairline is the shipped look. When enabled, the animation follows `panelShape` and honors the signal rule (the `onAir` spectrum shows only while the mic is capturing).

### Edit-before-paste [planned: v1]

After stop, HUD expands to ~480×120:
```
┌──────────────────────────────────────────────────────────┐
│  "the quick brown fox jumps over the lazy dog"            │
│              [Cancel]              [Paste]                │
└──────────────────────────────────────────────────────────┘
```
Auto-paste countdown visible. Tap text to pause countdown. `⌘↩` to paste, `Esc` to cancel.

### Modes indicator [planned: v2]

```
┌──────────────────────────────────────────────────┐
│  [Code]  ▌▌▌▌▌  "function take returns int"       │
└──────────────────────────────────────────────────┘
```
Small mode chip (11 pt, secondary) in top-left. Hidden when mode is "Default".

---

## 2.4 Settings window [implemented]

**Hard constraint:** takes focus. Use `Form(.grouped)`, `Section`, native `Picker`, `Toggle`. No custom form controls.

Current: 4 sections — Activation, Transcription, AI Cleanup, Text Insertion.

```
┌────────────────────────────────────────────────────┐
│ speak Settings                              ⊕ ⊗    │
├────────────────────────────────────────────────────┤
│  Activation                                        │
│  ○ Double-tap Fn (toggle)                          │
│  ○ Hold Fn (push-to-talk)                          │
│  Tap Fn twice to start; tap once to stop.          │
│                                                    │
│  Transcription                                     │
│  Language:        [English (US)         ▾]         │
│  Speech Engine:   [Apple Speech         ▾]         │
│                                                    │
│  AI Cleanup                                        │
│  ☐ Enable AI neat-writing                          │
│  Cleanup Engine:  [Foundation Models    ▾]         │
│                                                    │
│  Text Insertion                                    │
│  Paste Mode:      [Cmd+V (default)      ▾]         │
└────────────────────────────────────────────────────┘
                                              420×380
```

### Activation section [implemented]

Trigger mode: `.doubleTap` / `.hold` (inline picker, built Phase B).
Hotkey display: shows current binding + **Record…** button. Record UI is [planned: v0.1].

**Hotkey recorder (v0.1):**
```
┌────────────────────────────────────────────────────┐
│  Hotkey:                                            │
│  ┌──────────────────────────────────────┐          │
│  │ Press the keys you want to use…      │          │  ← record card, modal sheet
│  │   ⌥⌘Space                           │          │  ← live preview
│  └──────────────────────────────────────┘          │
│  [Cancel]                              [Save]       │
└────────────────────────────────────────────────────┘
                                           440×200
```
`HotkeyMonitor.updateBinding` is already wired (P5); only the capture UI is missing.

External keyboards without Fn: show footnote explaining hotkey change in v0.1.

### Transcription section [implemented]

Language: en-US, en-GB in v0; +fr-FR, +de-DE, +es-ES [planned: v1].
Speech engine: Apple Speech in v0; WhisperKit [planned: v0.1]; whisper.cpp [planned: v1].

**v0.1 addition [design-exploration]:** "Test transcription" button — 3 s sample dictation shows partial result inline.

### AI Cleanup section [implemented]

`Enable AI neat-writing` toggle. Cleanup engine picker (Foundation Models v0; Ollama [planned: v0.1]).

**v0.1 addition [design-exploration]:** "Engine status" row — "Apple Intelligence is ON" / "OFF — using raw transcript". Polled on window appear and every 30 s from `FoundationModelsCleaner.isAvailable`.

### Text Insertion section [implemented]

Paste mode: Cmd+V (v0); Accessibility API [planned: v1].

**v0.1 addition [design-exploration]:** "Restore clipboard after paste" toggle. Default OFF. Warning: "When ON, speak reads the pasteboard — may trigger macOS 26.4 paste-protection prompts."

### History section [planned: v1]

Max entries slider: 100 / 1,000 / 10,000 (default) / 50,000. Mirrors `HistoryStore.maxEntries`. "Clear All History…" destructive button. "Export History…" button.

### Privacy section [planned: v1]

"Audio never leaves this Mac" badge (green check, read-only, prominent). "Telemetry: Disabled — speak sends nothing anywhere" (read-only, locked). History retention picker.

---

## 2.5 History window [implemented]

**Hard constraint:** takes focus. No pasteboard reads — only writes (on Copy/Re-paste).

**Status:** Built P9, loop #16. Search, Clear, Export, empty state, cleaned/raw + timestamp + engine.

```
┌────────────────────────────────────────────────────────┐
│ speak — Dictation History                       ⊕ ⊗    │
├────────────────────────────────────────────────────────┤
│ 🔍 Search dictations                                   │
├────────────────────────────────────────────────────────┤
│ ┌──────────────────────────────────────────────────┐  │
│ │ Hello world, this is a test.                     │  │  lineLimit 3
│ │ Jun 21, 2026 at 10:32 AM · apple-speech+fm      │  │  caption secondary
│ ├──────────────────────────────────────────────────┤  │
│ │ This is a longer dictation that wraps to multi…  │  │
│ │ Jun 21, 2026 at 10:30 AM · apple-speech+fm      │  │
│ └──────────────────────────────────────────────────┘  │
├────────────────────────────────────────────────────────┤
│ [Export…]                              [Clear History] │
└────────────────────────────────────────────────────────┘
                                                  520×460
```

**v0.1 per-row actions [planned: v0.1]:** hover reveals Copy, Paste, Delete. "Paste" simulates Cmd+V (same as live paste path). Delete: 5-second undo toast.

**v0.1 live refresh [planned: v0.1]:** on new dictation, `NotificationCenter` event (`speak.history.didAppend`) triggers animated row insertion at top.

**v1 multi-select [planned: v1]:** `Cmd+A` selects all; floating toolbar shows Copy N / Delete N / Export N.

**v1 detail view [planned: v1]:** 2-pane layout — list left, detail right. Detail shows full text, per-word timestamps, duration, engine, Copy/Re-paste/Delete.

---

## 2.6 Permission recovery surface [partially implemented]

**Status:** Menubar shows "Grant Accessibility Permission" row when `controller.permissionsNeeded == true`. Onboarding re-shows on relaunch if denied.

**v0.1 proposed banner [design-exploration]:**
```
┌────────────────────────────────────────────────────────┐
│  ⚠  speak — Microphone permission required             │
│     [Open System Settings]   [Dismiss]                 │
└────────────────────────────────────────────────────────┘
```
40 pt tall, top of screen, 8 s auto-hide. Non-focus-stealing NSPanel. Triggered when `PermissionManager.status()` returns `.denied`.

Alternative: small badge on menubar icon opens a popover with same content. Test in dogfood — the banner may be too intrusive.

---

## 2.7 About / Help panel [partially implemented]

**Status:** `NSApplication.shared.orderFrontStandardAboutPanel(nil)` wired in menubar. Default macOS panel only.

**v1 custom panel [planned: v1]:**
```
┌────────────────────────────────────────────────────┐
│                                          ⊗         │
│         ⏺  (80pt SF Symbol, .tint)                 │
│              speak  v0.1.0                         │  22 pt bold
│         Built locally. Used privately.              │  13 pt secondary
│  ─────────────────────────────────────────────     │
│  Made by [Your Name] · MIT License                  │  hyperlink
│  [github.com/speak/speak]                          │
│  Audio engine:  Apple SpeechAnalyzer               │
│  AI cleanup:    Apple Foundation Models             │
│  Storage:       ~/Library/Application Support/speak/│
│  ─────────────────────────────────────────────     │
│  [View on GitHub]  [Report an issue]  [Quit speak] │
└────────────────────────────────────────────────────┘
                                                440×400
```

---

## 3. Component catalog (v0)

Extract to `App/UIComponents/` in v0.1 refactor.

### 3.1 Buttons

Use `Button(.borderedProminent)` for primary actions ("Get Started", "Grant Microphone", "Finish Setup"). Use `Button(.bordered)` for secondary ("Open System Settings", "Export…"). Use `Button(role: .destructive)` for destructive ("Clear History", "Delete"). Use `Button(.plain)` with secondary foreground for ghost buttons ("Skip for now", "Cancel").

Never use bare `Button()` — context style is inconsistent across surfaces.

### 3.2 Status icon [implemented]

`MenubarStatusIcon(state: MenubarIcon)` — wraps `systemImage(for:)` mapping in `SpeakApp.swift`. See `foundations.md` §6 for state matrix.

### 3.3 Level meter [implemented]

`LevelMeterView(level: Double, isActive: Bool)` — in `Overlay/`. 5 bars, cosine envelope, breathing when inactive.

Variants: Compact (24×16) for in-menubar; Standard (27×20) for HUD; Large (60×40) for detail view [planned: v1].

### 3.4 Empty state

`EmptyStateView(icon: String, title: String, subtitle: String?)`. Use in: History, Snippets, Vocabulary, Modes. Layout: centered icon (40–60 pt), 15 pt semibold title, 13 pt secondary subtitle, optional CTA button.

### 3.5 Loading indicators

`ProgressDots(currentStep: Int, totalSteps: Int)` — onboarding footer dots, in `OnboardingView.swift`.
`SpinningIndicator()` — 16 pt ProgressView, scale 0.7. HUD processing state.

### 3.6 Form rows

`SettingRow<Content>(title:, description:, content:)` — wraps `LabeledContent`.
`SettingToggle(title:, description:, isOn:)` — title + description + native toggle.
`SettingPicker<T>(title:, selection:, options:)` — title + native menu picker.

### 3.7 Cards / Pills

`Card<Content>(content:)` — rounded rect, 14 pt radius, `.regularMaterial`, 16 pt padding.
`Pill(label:, systemImage:, color:)` — status chips (e.g., mode indicator in HUD).

### 3.8 Toast / banner

`Toast(message:, systemImage:, duration:)` — top-of-screen transient banner. Permission recovery, errors, "Copied to clipboard".

### 3.9 Transcript view

`TranscriptTextView(text:, confidence: [Double]?)` — partial or final transcript, optional per-word confidence coloring.

### 3.10 Permission row [implemented]

`PermissionRow(kind:, status:, isLoading:, onAction:)` — core of onboarding permission steps, in `OnboardingView.swift`.

### 3.11 Hotkey recorder [planned: v0.1]

`HotkeyRecorderSheet()` — Settings → Record… modal. Includes live-preview record card (§2.4.2).

### 3.12 Search field

`SearchField(text:, placeholder:)` — magnifier + plain `TextField` + clear button. Use in History, Snippets, Vocabulary, Modes.

---

## 4. UX flows

### 4.1 First launch → working dictation (target: ≤90 s)

```
[Install] → [Launch]
    │
    ▼
Onboarding: Welcome (5 s read) → "Get Started"
    │
    ▼
Onboarding: Microphone (10 s; tap "Grant" + system dialog)  → auto-advance
    │
    ▼
Onboarding: Accessibility (15 s; "Open Settings" + manual toggle)  → poll detects → auto-advance
    │
    ▼
Onboarding: Hotkey (5 s read) → "Finish Setup"
    │
    ▼
Onboarding: Done (1.5 s) → auto-close
    │
    ▼
Menubar appears, idle
    │ user double-taps Fn in any app
    ▼
HUD appears, "Listening…"
    │ user speaks 5 s, single-taps Fn
    ▼
HUD: "Cleaning up…" (200–800 ms) → paste
    ▼
HUD: "Done" (600 ms) → hide
    ▼
Menubar → idle, history updated
```

### 4.2 Revoked permission → recovery

```
[User revokes Mic in System Settings]
    │
    ▼
Next dictation fails (.microphoneDenied)
    │
    ▼
HUD shows "⚠ Mic permission denied — open System Settings" (4 s)
    │
    ▼
Menubar shows "Permissions Required" row
    │ user clicks "Open System Settings"
    ▼
System Settings → Privacy_Microphone → user re-grants
    │
    ▼
Next double-tap Fn works normally
```

Red dot on menubar icon is **persistent** until permission is granted.

### 4.3 Mute → unmute

```
[User clicks "Mute Microphone"]
    │
    ▼
Menubar: "🔇 Mute" → "🎙 Unmute"; subtitle: "Muted — dictation disabled"
    │ user double-taps Fn → nothing happens (logged: "muted")
    │ user unmutes
    ▼
Subtitle disappears, Fn works again
```

Global mute chord → [planned: v1].

### 4.4 Engine fallback (Apple Intelligence OFF)

```
[FoundationModelsCleaner.isAvailable returns false]
    │
    ▼
Cleanup skipped (not failed). Raw transcript pasted. HUD shows "Done" normally.
```

Fallback is **invisible to the user** by design. Settings → AI Cleanup shows live status row for users who look.

---

## 6. Open design questions (require human input)

1. **Brand color.** Current: `.tint` (system accent). v1: add `Brand.accent` token.
2. **Hotkey default.** Double-tap Fn (signature UX) vs. Opt+Space (familiar to users of other dictation tools). Proposal: default double-tap Fn; offer Opt+Space as 1-click alternative in hotkey step.
3. **Edit-before-paste toggle default.** Proposal: OFF by default; ON for users migrating from review-before-paste tools, behind a Settings toggle.
4. **First-run tooltip.** Show 1-time toast over menubar icon: "Double-tap Fn to start." Proposal: yes, 6 s auto-dismiss with "Don't show again."
5. **History: window vs. popover.** Proposal: window in v0, evaluate popover in v1.
6. **Brand name + icon.** `speak` is the codename. Final name and icon need a designer.

---

## 7. Authority boundary

This file is **design reference**, not a contract. Active contracts:
- `docs/product.md` — destination
- `docs/architecture.md` — types and seams
- `docs/roadmap.md` — build order
- `docs/quality.md` — test plan
- `docs/benchmark.md` — definition of done

---

## 8. External landscape

Product and competitor analysis lives in `docs/competitors.md` and
`specs/verification-ledger.md`. This document describes only what `speak`
ships — design decisions stand on their own rationale, not on imitation.
