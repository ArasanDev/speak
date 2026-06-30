> Design-system reference for all SwiftUI work. Read when: adding a new surface or component. Authority: this file defines tokens; code is the implementation.

# speak — UI Foundations

---

## App surface map

`speak` is an `LSUIElement` (accessory) app — no Dock icon, no app menu.

| Surface | Summoned by | Focus model |
|---|---|---|
| Menubar item | always present | — |
| Menubar dropdown | click icon | takes focus |
| Recording HUD | double-tap Fn | **never steals focus** [hard constraint] |
| Onboarding window | first launch / perm revoke | takes focus (justified) |
| Settings window | `Settings…` in menubar | takes focus |
| History window | `History…` in menubar | takes focus |
| Permission recovery banner | on perm denied | non-focus |
| About / Help | menubar `About` | takes focus |
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
   │  ▌▌▌▌▌  Listening…                            │  ← 340×80, non-activating NSPanel
   └──────────────────────────────────────────────┘
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

**Rule:** every constant lives in `SpeakCore/UI/Tokens.swift`. No magic numbers in views.

```swift
// SpeakCore/UI/Tokens.swift
public enum Tokens {
    public enum Radius {
        public static let card: CGFloat   = 14   // HUD, settings card
        public static let pill: CGFloat   = 999  // full-pill (menubar split, status chips)
        public static let sheet: CGFloat  = 18   // window sheets
        public static let button: CGFloat = 8    // form buttons
    }

    public enum Spacing {
        public static let xxs: CGFloat = 2
        public static let xs:  CGFloat = 4
        public static let s:   CGFloat = 8
        public static let m:   CGFloat = 12
        public static let l:   CGFloat = 16
        public static let xl:  CGFloat = 24
        public static let xxl: CGFloat = 32
    }

    public enum Sizing {
        public static let menubarIcon:     CGFloat = 18  // logical pt
        public static let hudWidth:        CGFloat = 340 // [decision: 60 chars @ 13pt]
        public static let hudHeight:       CGFloat = 80  // [decision: 3 lines + meter]
        public static let hudYFromBottom:  CGFloat = 24  // [decision]
        public static let levelBars:       Int     = 5
        public static let levelBarW:       CGFloat = 3
        public static let levelBarGap:     CGFloat = 3
        public static let levelBarMin:     CGFloat = 3
        public static let levelBarMax:     CGFloat = 20
    }

    public enum Motion {
        public static let fast:        Double = 0.12  // bar/level meter tween
        public static let normal:      Double = 0.18  // panel show/hide
        public static let slow:        Double = 0.36  // state change, accent pulse
        public static let flash:       Double = 0.6   // "done" green flash
        public static let breathCycle: Double = 1.2   // idle breathing
    }

    public enum Opacity {
        public static let idle:   Double = 0.45
        public static let active: Double = 0.85
        public static let peak:   Double = 1.0
    }

    public enum State {
        public static let idle       = Color.secondary
        public static let listening  = Color.red
        public static let processing = Color.orange
        public static let done       = Color.green
        public static let error      = Color.red
        public static let muted      = Color.gray
    }
}
```

---

## 3. Motion grammar [decision]

**The HUD is the only continuously-animated surface.** Every other surface animates only on show/hide.

Use `.easeInOut` for state transitions. Use `.spring(response: 0.3, dampingFraction: 0.8)` for show/hide of small panels. Use `.linear` for the level meter.

**Respect Reduce Motion** (`NSWorkspace.accessibilityDisplayShouldReduceMotion`):
- Replace idle "breathing" bars with static dim bars.
- Replace show/hide spring with a quick fade (0.12 s).
- Disable the "done" green flash; show checkmark directly.

State transitions (idle → listening → processing → done): use `Motion.slow` (0.36 s). Level meter transitions: use `Motion.fast` (0.12 s).

No animation exceeds 600 ms except the "done" hold.
No rotation, bounce, or parallax. These read as toy-like on Mac.

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

| State | SF Symbol | Color | Animation |
|---|---|---|---|
| idle | `waveform` | primary | — |
| listening | `waveform.circle.fill` | red | slow pulse (Reduce Motion: static) |
| processing | `hourglass` | orange | rotate |
| done | `checkmark.circle.fill` | green | hold 600 ms → idle |
| error | `exclamationmark.triangle.fill` | red | static |
| muted | `mic.slash.fill` | gray | static [planned: v0.1] |
