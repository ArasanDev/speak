# speak — UI Foundations

> **Purpose**: Design-system reference — tokens, motion grammar, accessibility, i18n rules for all SwiftUI work. · **Audience**: contributor, AI agent (implementing any UI surface) · **Status**: living — authority for tokens; code is the implementation of record · **Last reviewed**: 2026-06-30 (git log)

> Design-system reference for all SwiftUI work. Read when: adding a new surface or component. Authority: this file defines tokens; code is the implementation.

---

## App surface map

`speak` is an `LSUIElement` (accessory) app — no Dock icon, no app menu.

| Surface | Summoned by | Focus model |
|---|---|---|
| Menubar item | always present | — |
| Menubar dropdown | click icon | takes focus |
| Recording HUD | double-tap Fn | **never steals focus** [hard constraint] |
| Dashboard window | `Open speak…` in menubar | takes focus [implemented] |
| Onboarding window | first launch / perm revoke | takes focus (justified) |
| Settings window | `Settings…` in menubar | takes focus |
| History window | `History…` in menubar | takes focus |
| Permission recovery banner | on perm denied | non-focus |
| About / Help | menubar `About` | takes focus |
| Conversation overlay | agent bridge call | non-activating panel [implemented] |
| Voice Desktop Pet | setting toggle | non-activating, draggable [spec'd: `specs/frontend-identity.md` §5 — not yet shipped] |
| Snippet editor | menubar `Snippets…` | takes focus [planned: v1] |
| Custom-vocab editor | settings row | takes focus [planned: v1] |
| Mode editor | settings row | takes focus [planned: v1] |
| AI Commands popover | menubar `Commands…` | takes focus [planned: v2] |

```
                   ┌──────────────────────────────────────────┐
                   │            macOS Menubar                  │
                   │   [wifi][battery][clock]  [⊏  ⏺  ⊐]    │  ← speak icon
                   └────────────────────┬─────────────────────┘
                                        │ click → dropdown
                                        ▼
   ┌────────────────────────────────────────────────────────────────┐
   │  speak — ready (double-tap Fn to start)                        │
   │  [● Start Dictation]         ⌥⌘Space                           │
   │  [🔇 Mute Microphone]                                          │
   │  [History…]  [Settings…]                                       │
   │  [About speak…]                                                │
   │  [Quit speak]                                                   │
   └────────────────────────────────────────────────────────────────┘

   Double-tap Fn ──────────────────────────────► HUD at bottom-center
   ┌──────────────────────────────────────────────┐
   │  ▌▌▌▌▌  LISTENING · 0:12                      │  ← near-rect panel
   └──────────────────────────────────────────────┘    560–760 × 64–88 (3 sizes),
        micro-curved corners (r14 continuous)           non-activating NSPanel
```

---

## 1. Mac-native idiom [decision]

`speak` must feel like a Mac app first, dictation app second.

Use **SF Symbols** for every icon. No custom icon fonts.
Use **system colors** (`Color.accentColor`, `.primary`, `.secondary`, `.tertiary`). No hard-coded hex except the level meter.
Use **system materials** (`.hudWindow` for the HUD; `.regularMaterial` for sheets). Auto-adapts to Light/Dark.
Use **system font** (SF Pro): 13 pt body, 12 pt secondary, 11 pt tertiary caption.
Use **native form controls**: `Form(.grouped)` in Settings, native `List` for History.
Use `.borderedProminent` / `.bordered` / `.plain` / `.borderless` button styles. Three custom styles max in the entire app.

Anti-pattern: bespoke icons + custom buttons + heavy shadows → looks like Electron.

---

## 2. Design tokens [decision]

**Rule:** every constant lives in `App/DesignSystem/` (or `App/Theme/SpeakTheme.swift`
for the content voice). No magic numbers in views; every value is `[decision]`-tagged.

The real token files — there is **no** `Tokens.swift`; the design system is a set of
SwiftUI extensions:

| File | Owns |
|---|---|
| `App/DesignSystem/SpeakColors.swift` | `Color.speak*` — the two-temperature palette (warm = human, cool = agent), `onAir`/`delivered`/`error`/`warning`/`ok` status roles, surface tokens (`speakInk`/`speakInk2`/`speakBone`/`speakMica`), workspace tokens (`speakSidebarBg`/`speakWindowCanvas`/`speakCardCanvas`/`speakCardBorder`), and the flow-border spectra. All theme-resolved via `SpeakThemeRuntime`. |
| `App/DesignSystem/SpeakTypography.swift` | `Font.speak*` — New York serif display / SF Pro body / SF Mono transcript faces; 11/13/15/20/28 scale; regular + semibold only. |
| `App/Theme/SpeakTheme.swift` | `Font.speakMono*` — the Monaco content voice (history rows, timestamps, keycaps). The one file that names the family. |
| `App/DesignSystem/SpeakMotion.swift` | `SpeakMotion.micro/state/idleBreath` — 120 ms / 320 ms / spring(0.35, 0.8); all Reduce-Motion-aware. |
| `App/DesignSystem/SpeakCard.swift` | `speakCard()` (r16 raised card) / `speakInset()` (r8 recessed well) — the only two container primitives. |
| `App/Overlay/HUDLaneViews.swift` | `HUDLane.panelShape` / `panelCornerRadius` (14, continuous) — the near-rect HUD silhouette shared by clip, wash, hairline, and border layers. |

**Shape language** (see `philosophy.md` §3): near-rect 14 = a *surface*; card 16 = a *group*;
well 8 = a *recess*; capsule = a *label* only, never a panel.

**Channel colors** (load-bearing semantics — a theme may change hue, never meaning):
`speakHumanAmber` = the human is acting · `speakAgentViolet` = an agent is acting ·
`speakOnAir` = mic is capturing (**iff** — tally-light hard rule) · `speakDelivered` =
terminal success only · `speakVoiceBlue` = fixed functional voice blue (theme-independent).

---

## 3. Motion grammar [decision]

**The HUD is the only continuously-animated surface.** Every other surface animates only on show/hide.

The canonical constants live in `SpeakMotion` (`App/DesignSystem/SpeakMotion.swift`):

| Constant | Value | Use |
|---|---|---|
| `microDuration` | 120 ms | hover, tap feedback, level-meter tween |
| `stateDuration` | 320 ms | state transitions (idle → listening → processing → done) |
| `stateSpring` | spring(0.35, 0.8) | panel show/hide, state changes |
| `idleBreathCycle` | 4 s | the one licensed idle animation |

**Respect Reduce Motion** — `SpeakMotion.micro(reduceMotion:)` /
`state(reduceMotion:)` / `idleBreath(reduceMotion:)` already encode the
fallbacks: crossfades replace movement, breath becomes a slow opacity pulse.

No animation exceeds ~600 ms except the "done" hold.
No rotation, bounce, or parallax. These read as toy-like on Mac.
Every animation maps to a real signal (audio level, state transition,
attention request) — if it doesn't read from a signal, cut it
(motion charter, `specs/frontend-identity.md` §4).

Reference: Superwhisper's HUD has the cleanest motion. Wispr's top-pill HUD is the cautionary tale — too much motion.

---

## 4. Accessibility [non-negotiable]

Add **VoiceOver labels** to every interactive element.
Support **Reduce Motion** (see §3).
**Increase Contrast**: level meter and recording states need luminance contrast ≥ 4.5:1.
**Keyboard navigation**: every form is tab-navigable. The HUD never appears in the tab order.
Respect **system font size** — Settings respects `NSFont`. Do not force a font size except on the level meter.
Post `NSAccessibility` announcements when dictation starts/stops ("Recording" / "Stopped").

---

## 5. Internationalization

Every visible string goes in `Localizable.strings` (en first).
HUD strings ("Listening…" / "Cleaning up…" / "Done") are localized.
Date formats in History: `entry.createdAt.formatted(date: .abbreviated, time: .shortened)` — respects user locale.
Hotkey labels use standard macOS key glyphs ("Fn", "Globe", "⌘", "⌥").

---

## 6. Menubar icon states [implemented]

Mapping: `SpeakCore/Engine/MenubarIcon.swift` (state → case) →
`StatusBarController.iconPresentation` (case → symbol + tint). `[verified]` by `MenubarIconTests`.

| State | SF Symbol | Color | Rendering |
|---|---|---|---|
| idle | `waveform` | secondary label | template (auto-invert) |
| listening | `waveform.circle.fill` | systemRed | tinted |
| processing | `hourglass` | systemYellow | tinted |
| done | `checkmark.circle` | systemGreen | tinted, hold 600 ms → idle |
| error | `xmark.circle` | systemRed | tinted |
| muted | `mic.slash.fill` | gray | static [planned: v0.1] |
