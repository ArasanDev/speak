# `speak` — UI / UX Frontend Ideation

> **Status:** Ideation artifact. **Additive — does NOT modify `product.md` /
> `architecture.md` / `roadmap.md` / `progress.md`.** This is a design
> exploration that grounds the *complete* UI/UX surface (v0 ship + v1/v2/v3
> ladder) in the leading dictation apps of 2026, then maps it back to the
> moat-locked product shape. Treat it as a **design reference** the build
> loop can pull from — not a contract yet.
>
> **Audience:** the autonomous build loop, the human designer, and future
> contributors who want the *what does the whole app look like* view.
>
> **Scope of this document:**
> 1. The **foundations** (design tokens, motion, accessibility, idiom).
> 2. **Every UI surface** — onboarding, menubar, recording HUD, settings,
>    history, hotkey recorder, permission recovery, and the v1+ surfaces
>    (modes, snippets, custom dictionary, per-app profiles, voice commands,
>    code mode, AI transforms).
> 3. **Component catalog** — every reusable visual unit.
> 4. **UX flows** — first launch, successful dictation, error, mute, revoke.
> 5. **Open design questions** — items that need human input.
>
> **How to read:** each surface section uses the same template so the
> orchestrator can extract a per-screen build brief. Reference patterns
> cite the real apps that set the bar (Wispr Flow as the frontier;
> MacWhisper / Superwhisper / VoiceInk / FluidVoice as the design language
> references; Aiko / Talon as power-user outliers).

---

## 0. The shape of `speak`'s frontend

`speak` is an **LSUIElement (accessory) macOS app** — no Dock icon, no main
window, no menu bar app menu at the system bar except the **menubar item**.
Every surface is summoned by:

| Surface | How it's summoned | Lifetime | Focus model |
|---|---|---|---|
| Menubar item | always present | app lifetime | — |
| Menubar dropdown menu | click on menubar icon | transient | takes focus |
| Recording HUD (overlay) | double-tap Fn / push-to-talk | per-dictation | **never steals focus** |
| Onboarding window | first launch + perm revoke | modal-ish | takes focus (justified) |
| Settings window | `Settings…` in menubar | user-dismissed | takes focus |
| History window | `History…` in menubar | user-dismissed | takes focus |
| Hotkey recorder | `Record…` in Settings | ephemeral | takes focus (justified) |
| Permission recovery banner | on perm denied | app-lifetime until resolved | non-focus |
| About / Help | menubar `About` | ephemeral modal | takes focus |
| Snippet editor (v1) | menubar `Snippets…` | user-dismissed | takes focus |
| Custom-vocab editor (v1) | settings row | user-dismissed | takes focus |
| Mode editor (v1) | settings row | user-dismissed | takes focus |
| AI Commands popover (v2) | menubar `Commands…` | transient | takes focus |

**The only ever-present element is the menubar icon.** Every other surface is
either (a) per-dictation (the HUD), (b) first-run (onboarding), or
(c) user-invoked (settings, history, modals). This is the **right** shape for
a tool the user summons in 99% of cases and dismisses immediately.

### What this looks like as a "map" of the app

```
                       ┌──────────────────────────────────────────┐
                       │            macOS Menubar Bar             │
                       │   [wifi][battery][clock]  [⊏  ⏺  ⊐]   │  ← speak icon
                       └────────────────────┬─────────────────────┘
                                            │ click → dropdown
                                            ▼
   ┌────────────────────────────────────────────────────────────────┐
   │  speak — ready (double-tap Fn to start)                         │
   │  ─────────────────────────────────                              │
   │  [●  Start Dictation]       ⌘⌥Space (default double-tap Fn)   │
   │  [🔇 Mute Microphone]                                         │
   │  ────────────────                                             │
   │  [History…]  [Settings…]  [Modes…] [Snippets…]   (v1+)         │
   │  ────────────────                                             │
   │  [About speak…]                                               │
   │  [Quit speak]                                                  │
   └────────────────────────────────────────────────────────────────┘

   User double-taps Fn (in any app) ─────►  HUD appears at bottom-center
   ┌──────────────────────────────────────────────┐
   │  ▌▌▌▌▌  Listening…                            │   ← 340 × 80, bottom-center
   └──────────────────────────────────────────────┘
   User speaks  →  partials stream in
   User single-taps Fn  →  "Cleaning up…"  →  paste + fade
```

---

## 1. Foundations

### 1.1 Mac-native idiom (decisions, not optional)

`speak` should *feel* like a Mac app first, a dictation app second. That
means — explicit choices:

- **SF Symbols** for every icon. No custom icon font, no third-party set. Maps
  1:1 with macOS appearance (Light / Dark / Increase Contrast / Reduce
  Transparency). Free with the platform.
- **System colors** (`Color.accentColor`, `.primary`, `.secondary`,
  `.tertiary`) for all text and chrome. No hard-coded hex (except the level
  meter which is purely visual).
- **System materials** (`.hudWindow` VisualEffect material for the recording
  HUD; `.regularMaterial` for sheets/panels). Auto-adapts to Light/Dark and to
  the user's transparency preference.
- **System font** (`.system` / SF Pro) at **13 pt body, 12 pt secondary,
  11 pt tertiary caption**. SF Pro Rounded only on hero numbers (the level
  meter readout if we add one).
- **Native form controls**: `Form` with `.grouped` style in Settings; native
  `List` for History; `TextField(.plain)` for search; native `Picker` for
  menu / inline / segmented choices. Do not rebuild what SwiftUI gives you
  for free.
- **No custom buttons** unless the system `.borderedProminent` /
  `.bordered` / `.plain` / `.borderless` do not fit. Three custom button
  styles in the app at most.

**Reference pattern (VoiceInk / MacWhisper / Superwhisper):** the
*best-in-class* Mac dictation apps use SF Symbols and system controls almost
exclusively. They look native because they are. **Anti-pattern (some
chat-bot-driven tools):** bespoke icons + custom buttons + heavy shadows
→ looks like a cross-platform Electron port.

### 1.2 Design tokens (the single source)

> **Rule:** every constant in this section lives in **`SpeakCore/UI/Tokens.swift`**
> (new file) and is referenced from every view. No magic numbers in views.
> This mirrors `benchmark.md` §7's "no magic numbers" rule.

```swift
// SpeakCore/UI/Tokens.swift  (new — the design-system seam)
public enum Tokens {
    public enum Radius {
        public static let card: CGFloat        = 14    // HUD, settings card
        public static let pill: CGFloat        = 999   // full-pill (menubar split, status chips)
        public static let sheet: CGFloat       = 18    // window sheets (>= macOS 13)
        public static let button: CGFloat      = 8     // form buttons
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
        public static let menubarIcon:  CGFloat = 18  // logical pt; system scales
        public static let hudWidth:     CGFloat = 340 // [decision: 60 chars @ 13pt]
        public static let hudHeight:    CGFloat = 80  // [decision: 3 lines + meter row]
        public static let hudYFromBottom: CGFloat = 24 // [decision: spec §4]
        public static let levelBars:    Int     = 5
        public static let levelBarW:    CGFloat = 3
        public static let levelBarGap:  CGFloat = 3
        public static let levelBarMin:  CGFloat = 3
        public static let levelBarMax:  CGFloat = 20
    }

    public enum Motion {
        public static let fast:    Double = 0.12  // bar/level meter tween
        public static let normal:  Double = 0.18  // panel show/hide
        public static let slow:    Double = 0.36  // state change, accent pulse
        public static let flash:   Double = 0.6   // "done" green flash
        public static let breathCycle: Double = 1.2 // idle breathing
    }

    public enum Opacity {
        public static let idle:    Double = 0.45
        public static let active:  Double = 0.85
        public static let peak:    Double = 1.0
    }

    public enum State {
        // Semantic state colors — semantic first, color second.
        public static let idle       = Color.secondary
        public static let listening  = Color.red                  // recording dot, mic dot
        public static let processing = Color.orange               // spinner
        public static let done       = Color.green                // checkmark
        public static let error      = Color.red
        public static let muted      = Color.gray
    }
}
```

### 1.3 Motion grammar (the rules)

Motion is information, not decoration. The rules:

1. **The HUD is the only continuously-animated surface.** Every other surface
   animates only on show/hide. This is deliberate: continuous animation on
   anything else would compete with the HUD for attention.
2. **Reuse platform easings** wherever possible: `.easeInOut` for state
   transitions, `.spring(response: 0.3, dampingFraction: 0.8)` for show/hide
   of small panels, `.linear` for the level meter.
3. **Respect Reduce Motion** (NSWorkspace `accessibilityDisplayShouldReduceMotion`):
   - Replace the idle "breathing" bars with static dim bars.
   - Replace the show/hide spring with a quick fade (0.12 s).
   - Disable the "done" green flash; show the checkmark directly.
4. **State transitions** (idle → listening → processing → done) take
   `slow` (0.36 s). The level meter transitions take `fast` (0.12 s).
5. **No animation > 600 ms** except the "done" hold (600 ms total).
6. **No rotation, no bounce, no parallax.** Mac dictation apps that use these
   (e.g., older Electron-y tools) feel toy-like.

**Reference:** Superwhisper's HUD has the cleanest motion grammar in the
category — subtle, never attention-stealing. MacWhisper's is similarly
restrained. Wispr's HUD has more motion (the pill pulses, the waves animate)
which is the cautionary tale referenced in `dictation-flow.md` §4.

### 1.4 Accessibility (non-optional)

- **VoiceOver** labels for every interactive element.
- **Reduce Motion** support (see §1.3).
- **Increase Contrast** — the level meter and recording states must remain
  distinguishable at full contrast (use a luminance contrast ≥ 4.5:1 for
  state icons, not just color).
- **Keyboard navigation** — every form is tab-navigable; the recording HUD
  does not appear in the tab order (it's not focusable).
- **System font size** — Settings respects the user's `NSFont` choice; we do
  not force a font size except on the level meter readout.
- **State announcements** — when dictation starts/stops, post a `NSAccessibility`
  announcement so VoiceOver users hear "Recording" / "Stopped".

### 1.5 Internationalization

- Every visible string in `Localizable.strings` (en first; v1: ship with
  `en` and `Base`).
- The HUD's "Listening…" / "Cleaning up…" / "Done" strings are localized.
- Date formats in History use `entry.createdAt.formatted(date: .abbreviated,
  time: .shortened)` (respects user locale).
- Hotkey labels are localized (e.g., "Fn", "Globe", "⌘", "⌥") via the
  standard macOS key glyphs.

---

## 2. Surfaces — screen-by-screen ideation

> Each surface uses the same template:
> **Goal** → **Status** (built / deferred / future) → **Reference patterns** →
> **Layout** → **Components used** → **States** → **Interactions** →
> **Edge cases** → **Open questions**.

### 2.1 Onboarding window

**Goal:** Get a fresh install to a working dictation in ≤90 seconds, with full
understanding of *why* each of the three permissions is needed. Onboarding
drop-off is the #1 risk (per `product.md` §7.3) — every step must earn its
60 seconds.

**Status:** **Built** (5 steps + done, P7, loop #16). The logic is
unit-tested; rendered behavior is `[deferred — human verification: §4.4]`.
The current built step list is: **welcome → microphone → accessibility →
input monitoring → hotkey → done**. This ideation refines the copy and
adds (v1): a "Privacy" interlude and a "Test dictation" step.

**Reference patterns:**
- **Wispr Flow onboarding:** 4-card scroller, full-screen, hero illustration
  per card, deep-link buttons. Heavy but welcoming.
- **MacWhisper:** 3-step modal (model download, mic, hotkey). No "why"
  copy; assumes power-user audience.
- **VoiceInk:** Welcome → Mic → Accessibility → Hotkey test. Most
  comparable to ours; ours differs by being (a) more privacy-explicit, (b)
  including Input Monitoring as a separate, explained step.

#### 2.1.1 Step 1 — Welcome

**Layout:**

```
┌────────────────────────────────────────────────┐
│ ● ○ ○ ○ ○                                       │  ← progress dots
│                                                │
│                                                │
│           ┌────────────────────┐               │
│           │   ⏺  waveform icon  │               │  64 pt SF Symbol, .tint
│           └────────────────────┘               │
│                                                │
│          Welcome to speak                      │  22 pt bold
│                                                │
│   speak turns your voice into polished         │  13 pt secondary
│   text, entirely on your Mac.                  │  max-width 340, centered
│   Nothing leaves your device.                  │
│                                                │
│           ┌──────────────┐                     │  borderedProminent, large
│           │ Get Started   │                    │
│           └──────────────┘                     │
│                                                │
│                                                │
│  Skip for now                       ● ○ ○ ○ ○  │  caption, bottom-left
└────────────────────────────────────────────────┘
                                              480 × 400
```

**Components:** `Image`, `Text`, `Button(.borderedProminent)`, progress dots,
`Skip` ghost button (footer-left).

**States:** `default` (above). `pressed` = button briefly inverts. No
`loading` (instant).

**Interactions:** `Get Started` → step 2. `Skip for now` (footer-left) →
sets `hasCompletedOnboarding = true`, closes window, opens System Settings
to Accessibility for convenience. `Cmd+.` or close (red) → same as Skip.

**Edge cases:**
- If the user has Accessibility + Mic already granted (e.g., they
  pre-granted), step 2/3 still display but with the "granted" state
  (checkmark + Continue). They can move through quickly.
- If locale is not en-US, "Get Started" / "Continue" / etc. are localized.

**Open question (defer to v1):** show a 3-bullet value-prop instead of a
single sentence? e.g., "• 100% on your Mac • Free & open • Hotkey in any app."

#### 2.1.2 Step 2 — Microphone

**Layout:**

```
┌────────────────────────────────────────────────┐
│ ● ● ○ ○ ○                                       │
│                                                │
│   ┌──────┐                                     │
│   │ 🎤    │   Microphone Access                 │  icon-left, title-right
│   └──────┘                                     │
│                                                │
│   speak captures your voice to transcribe it.  │  13 pt
│   Audio is processed on-device and never        │
│   sent anywhere.                               │
│                                                │
│   [Privacy badge: 🔒 Audio never leaves this Mac]│  small, secondary
│                                                │
│            ┌────────────────────────┐          │
│            │  Grant Microphone       │          │  borderedProminent
│            └────────────────────────┘          │
│                                                │
│   (or, if denied:)                             │
│            ┌────────────────────────┐          │
│            │  Open System Settings  │          │  bordered
│            └────────────────────────┘          │
│                                                │
│  Skip for now                       ● ● ○ ○ ○  │
└────────────────────────────────────────────────┘
```

**States:**
- `notRequested`: blue mic icon, primary button "Grant Microphone Access"
- `inFlight`: spinner inside button, disabled
- `granted`: green check, "Permission granted" line, "Continue" button
- `denied`: red "xmark" icon, "Permission denied" line, "Open System
  Settings" + "Skip for now" link

**Components:** icon, title, body copy, primary/secondary button, privacy
badge, deep-link row.

**Interactions:** tap `Grant` → triggers `AVAudioApplication.requestRecordPermission`.
On result, transition state. `Open System Settings` → opens
`x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone`.

**Edge cases:**
- If the user denies *and* has a hotkey that won't work without Mic, the
  Done step tells them they need to grant Mic in System Settings before
  dictation can work.
- VoiceOver: the icon has label "Microphone icon, permission not yet
  granted."

#### 2.1.3 Step 3 — Accessibility

**Layout:** same shape as 2.1.2.

**Body copy (current):**
> speak needs Accessibility access to simulate the Cmd+V keystroke that
> pastes your transcribed text at the cursor.

**Body copy (proposed v0.1):**
> speak uses Accessibility in two ways: (1) to detect your hotkey while
> another app is focused, and (2) to paste finished text at your cursor.
> The system requires you to enable this manually.

**Components:** same as 2.1.2, with icon `hand.point.point.up.left.fill` (already
in code).

**States:** same as 2.1.2 (the polling loop is what flips to `granted`).

**Edge cases:**
- The user toggles Accessibility on in System Settings; the polling task
  (1.5 s interval, `OnboardingViewModel.startPolling`) picks it up. UX
  must feel responsive (badge → checkmark within ~2 s). **Open question
  (refine):** can we observe `com.apple.accessibility.api` and react
  immediately? `dictation-flow.md` §2 mentions this; if it works, drop the
  poll interval to 2 s but react to the notification for the ~instant flip.
- Deep-link anchor (`?Privacy_Accessibility`) — `[verified]` for macOS 13+
  but `[unverified]` for macOS 26 Tahoe; verify on first run.

#### 2.1.4 Step 4 — Input Monitoring

**Layout:** same as 2.1.2, icon `keyboard.fill`.

**Body copy (current):**
> Input Monitoring lets speak detect your double-tap Fn hotkey so it can
> start listening while another app has focus.

**Body copy (proposed v0.1):**
> Input Monitoring lets speak see your Fn key (or any hotkey you bind).
> You'll enable it in System Settings — this is a one-time grant.

**States:** same. **Edge case:** this is the one permission that does NOT
block the app; even if denied, Accessibility is enough to fire a
`CGEventTap` (per `dictation-flow.md` §2). The UX should communicate that
this is a *quality* permission, not a *gate* — if denied, show a "won't
detect Fn reliably" warning but still let the user proceed.

**Open question:** should we still show this step if Accessibility is
granted and the user picked a non-Fn hotkey (e.g., Cmd+Shift+Space)? In
that case Input Monitoring is unnecessary. **v0:** keep it simple, always
show the step. **v1:** skip-if-not-needed.

#### 2.1.5 Step 5 — Hotkey

**Layout:** mirror of Step 1 (no buttons other than "Finish Setup" +
explainer card).

**Copy (current):**
> Your Hotkey: Double-tap Fn
> Double-tap the Fn key to start dictating. Tap it once to stop.
> speak listens while you work in any app — no need to switch focus.
> You can change the hotkey in Settings at any time.

**Proposed v0.1 addition:** add a small **"Try it now" mini-test** at the
bottom of the step: a tiny pill (44 × 24) labeled "Test" that listens
for the next Fn tap. If it sees one, the pill briefly turns green. This
catches 80% of "my hotkey doesn't work" issues right at the point of
permission grant.

**Open question (v1):** in the hotkey step, let the user *record* their
hotkey here (not just at Settings), so the on-screen pill is whatever
they bind. This is the **deferred hotkey-rebind-UI** tracked in
`human-verification.md`.

#### 2.1.6 Step 6 — Done

**Layout:** mirror of Step 1. Big green checkmark seal; "You're all set."
"Double-tap Fn to start dictating. speak will paste polished text wherever
your cursor is." Auto-close after ~1.5 s.

**Component:** `Image(systemName: "checkmark.seal.fill")` in green,
48–64 pt.

**Edge case:** if Mic is still not granted at this point (user skipped),
the body copy changes: "Grant Microphone in System Settings to enable
dictation. speak will keep trying."

#### 2.1.7 (v1) Step — Privacy

A new step between Welcome and Microphone: a 3-row icon-list explaining
the three promises ("Audio never leaves your Mac", "No account, no
telemetry", "You can export or delete your history at any time"). This
front-loads the moat, which is `speak`'s only durable marketing
differentiator.

**Open question:** should this be a 1-card "Privacy" step or a footer
that lives on the Welcome step? Test in dogfood.

#### 2.1.8 (v1) Step — Test dictation

After the Done step, auto-open the recording HUD with a "Say something"
placeholder and a green "Save & finish" button. On save, the user has
seen the HUD, knows the hotkey works (because the test listens for it),
and has experienced the cleaned-text paste at the cursor. This catches
the "I finished setup but my hotkey doesn't work" cluster at first run.

**Open question:** if a user's mic is in a quiet environment, the test
might not capture audio. Should we use the file-fed proxy (already in
`human-verification.md` §6) so the test is always passable?

---

### 2.2 Menubar item + dropdown menu

**Goal:** One-tap access to (a) start/stop dictation, (b) mute, (c)
history, (d) settings, (e) about, (f) quit. Visible 100% of the time the
app is running.

**Status:** **Built** (menubar `MenuBarExtra` + 5-state icon, `SpeakMenu`).

**Reference patterns:**
- **Wispr Flow menubar:** large icon, status, dictation count, full
  drop-down with: "Start Dictation", "Modes (submenu)", "Languages
  (submenu)", "Snippets", "History", "Settings", "Account", "Quit".
  Heavy but feature-rich.
- **MacWhisper menubar:** small icon, simpler dropdown: "Start",
  "Settings", "Quit".
- **Superwhisper menubar:** small icon, status line, dropdown with
  "Modes (submenu)" + Settings + Quit.
- **VoiceInk menubar:** moderate dropdown with: Start, Mute, Modes
  (submenu), Snippets, History, Settings, Quit.

The **ideal shape for `speak`** is closer to Superwhisper/VoiceInk: lean
dropdown, modes/snippets behind a submenu, no top-level "Account" (we
have none).

#### 2.2.1 Menubar icon (5 states)

**Built icons (current):**
- `idle`: `waveform` (system symbol, monochrome)
- `listening`: `waveform.circle.fill` (filled, .tint)
- `processing`: `hourglass` (secondary)
- `done`: `checkmark.circle` (green, 600 ms)
- `error`: `exclamationmark.triangle` (red)

**Proposed refinements (v0.1):**
- Add a **muted** state: `mic.slash` (gray), shown when hardware mute is on.
- Add a **per-app indicator** (v1): a small dot in the corner if the user
  has set a per-app profile for the frontmost app.

**States matrix (final):**

| State | SF Symbol | Color | Animation |
|---|---|---|---|
| idle | `waveform` | primary | — |
| listening | `waveform.circle.fill` | red | slow pulse (Reduce Motion: static) |
| processing | `hourglass` | orange | rotate |
| done | `checkmark.circle.fill` | green | hold 600 ms → idle |
| error | `exclamationmark.triangle.fill` | red | static |
| muted | `mic.slash.fill` | gray | static |

#### 2.2.2 Dropdown menu (v0)

**Layout:**

```
speak — ready (double-tap Fn to start)        ← status line, secondary
─────────────────────────────────────
▶ Start Dictation                  ⌥⌘Space   ← Cmd+Opt+Space = same as double-tap Fn
🔇 Mute Microphone                              ← toggles, label flips to "Unmute"
─────────────────────────────────────
History…
Settings…                              ⌘,
─────────────────────────────────────
About speak…
─────────────────────────────────────
Quit speak                          ⌘Q
```

**Components:** native `Menu` items, `Divider`, `SettingsLink`, `Button`.

**Edge cases:**
- **While listening:** replace "Start Dictation" with "■ Stop Dictation"
  (red), so the user can manually stop from the menu.
- **While muted:** show "Muted — dictation disabled" (secondary, disabled
  tone) under the mute row.
- **While a permission is missing:** show an "Accessibility Permission
  Required" or "Microphone Permission Required" row above the mute row
  (current behavior, `controller.permissionsNeeded`).
- **First run (hasCompletedOnboarding == false):** show "Resume Setup…"
  row that re-opens the onboarding window.

**Open question (v1):** add a submenu for "Modes" (Default / Code /
Email / Custom) — this is the **single most-requested feature** in
reviews of every competitor. Ship it at v1, not v0.

**Open question (v1):** add a submenu for "Languages" — this is the
WISPR FLOW parity move (`benchmark.md` MATCH row). v0 ships en-US/en-GB;
v1 ships 5+; v2 ships 30+ via WhisperKit.

#### 2.2.3 Status line

The first row of the dropdown shows the current state in a friendly way
(current behavior). **v0.1 refinement:** show a richer status when
listening, e.g., "Listening — 3.2 s", or a live word count. The status
must be terse — this is a menubar dropdown, not a dashboard.

---

### 2.3 Recording HUD (the overlay)

**Goal:** Subtle, non-focus-stealing, real-time feedback during
dictation. The HUD is the user's "I am being heard" affordance — it must
be present enough to confirm activity, quiet enough to not compete with
the dictating app for attention.

**Status:** **Built** (3 states — listening / processing / done — bottom-center
position, 340×80, level meter + partial text, Phase C). The `done` and
`error` states appear in the current code; `error` hides the HUD
immediately. **Phase C additions:** hidden during idle; appears on `.listening`.

**Reference patterns:**
- **Wispr Flow HUD:** top-center *expanding pill* — first a small
  pill, then expands to show partial text on stop (so the user can edit
  before paste). The "expanding pill" is the **cautionary tale**:
  `dictation-flow.md` §4 explicitly calls it out. The expansion
  *does* steal attention. **We are explicitly not doing that.**
- **Superwhisper HUD:** bottom-center pill, single state (recording),
  beautiful sound wave animation. The **best-in-class** example. ~340×60.
- **MacWhisper HUD:** floating window, larger (shows the full transcript
  scrolling, with model + language in the title bar). More information
  density, less subtle.
- **VoiceInk HUD:** bottom-center, 3 states (idle/recording/processing),
  sound wave. Closest to what we've built.
- **FluidVoice HUD:** bottom-center, minimal, single state. The simplest.

**The `speak` HUD shape** should land between Superwhisper and VoiceInk:
bottom-center, 340×80, three states, sound wave, partial text. The
**edit-before-paste** affordance (Wispr's killer feature) is a **v1
consideration** — see §2.3.5.

#### 2.3.1 Idle (hidden)

The HUD is **not shown at all** in the idle state. The menubar icon
shows the current state; opening the dropdown is how the user gets
verbose state.

**v1 idea:** show a 1-line "last transcript" toast for 4 s after dictation
ends (above the cursor, 2 s fade) — so the user has a glance-able record
of what was just pasted, in case the paste was wrong. This is a separate
surface (a transient NSToast), not the HUD.

#### 2.3.2 Listening (built)

**Layout (current):**

```
┌──────────────────────────────────────────────────┐
│ ▌▌▌▌▌  Listening…  (or partial text here)        │  ← 340 × 80, bottom-center
└──────────────────────────────────────────────────┘
   ↑   ↑                                            ↑
   ↑   ↑       text area (left-aligned, 3 lines, 13 pt)
   ↑   ↑                                            ↑
   ↑   5 vertical bars, 3 pt wide, 3 pt gap, opacity 0.6
   ↑                                                ↑
   y=24pt from screen bottom
```

**Components:**
- `LevelMeterView` (5 bars, 3–20 pt height, cosine envelope, breathing
  animation when `isActive = false`, real level when `isActive = true`).
- `Text` showing either the live partial transcript or "Listening…"
  placeholder.
- Frosted glass background (`.hudWindow` material).
- 14 pt corner radius.

**States (current):**
- `partialText == ""`: "Listening…" placeholder
- `partialText != ""`: live partial text, lineLimit 3

**Proposed v0.1:**
- Add a **confidence-colored transcript** (low-confidence words in
  secondary, high-confidence in primary) — `TranscriptionResult.confidence`
  is exposed by `SpeechAnalyzer`. Subtle, but a Wispr-style UX tell.
- Add a **live duration readout** in the right corner (`0:04`), 11 pt
  secondary. Discreet but informative.

**v2:**
- A **word-level correction** affordance: tap a misheard word in the
  partial, get a "did you mean…" popover. This is the **MacWhisper
  killer feature** for power users.

#### 2.3.3 Processing (built)

**Layout:**

```
┌──────────────────────────────────────────────────┐
│ ⏳  Cleaning up…                                  │
└──────────────────────────────────────────────────┘
```

**Components:** small `ProgressView` (scale 0.7) + "Cleaning up…" text.
Same panel size; text is secondary.

**State transitions:** appears on `.processing`; freezes the partial text
on screen. Lasts 200–1500 ms typically; the panel is held for the full
duration so the user sees something is happening.

**Edge cases:**
- Cleanup failure (`SpeakError.llmCleanupFailed`): the panel shows
  "Cleanup failed — pasting raw transcript" for 1.2 s, then transitions
  to `done`.
- Cleanup disabled: the processing state is **bypassed entirely** (text
  goes directly from listening → done), to avoid the impression that
  something is being processed when nothing is. The current code shows
  "Cleaning up…" briefly in this case — **proposed fix (v0.1):** show
  "Pasting…" instead, or skip to `done` faster.

#### 2.3.4 Done (built)

**Layout:**

```
┌──────────────────────────────────────────────────┐
│ ✓  Done                                           │
└──────────────────────────────────────────────────┘
```

**Components:** green `checkmark.circle.fill` (15 pt) + "Done" text.

**State transitions:** appears on `.done`; held for 600 ms; then panel
hides. The "done flash" is the one moment the HUD is celebratory; it
should feel snappy and final, not bouncy.

**Edge cases:**
- If a permission error caused the `done` state (e.g., paste silently
  succeeded but cleanup was disabled), the message is the same: "Done".
  The text was delivered; that's what matters.
- If the engine reached `done` but paste was silently lost (write
  succeeded but Cmd+V was rejected, e.g., secure field), the panel
  shows "Done — text on clipboard" for 1.5 s, with a "Copy" button. **v0.1.**

#### 2.3.5 Edit-before-paste (v1)

This is **the** Wispr Flow signature feature. The current build pastes
immediately on stop; Wispr shows a 2-second "review window" with an
inline editor before pasting. The user can correct words, then tap
"Paste" or hit Enter.

**Our v1 design:**

```
┌──────────────────────────────────────────────────────────┐
│  ▌▌▌▌▌  "the quick brown fox jumps over the lazy dog"    │
│                                                          │
│              [Cancel]              [Paste]               │
└──────────────────────────────────────────────────────────┘
```

The HUD grows to ~480×120. "Cancel" is plain (escapable, no paste). "Paste"
is borderedProminent (default action). Both buttons appear after ~50 ms
of inactivity (so a fluent user who says "the quick brown fox jumps over
the lazy dog. send." doesn't see the buttons — the period triggers
paste, the trailing word is the implicit command).

**Open question:** is "edit-then-paste" the right v0.5 feature, or is it
a v2? Trade-off: edit-then-paste breaks the "feels like the cursor typed
it" magic that makes `speak` a productivity multiplier. Maybe the right
answer is a **toggle** in Settings: "Edit before paste" (off by default,
on for Wispr migrants).

#### 2.3.6 Error (built — implicit)

The current code hides the HUD immediately on `.error`. The user only
sees the error in the menubar (red triangle icon).

**Proposed v0.1:**

```
┌──────────────────────────────────────────────────┐
│ ⚠  Mic permission denied — open System Settings  │
└──────────────────────────────────────────────────┘
```

A short, dismissable error pill (340×60) that lasts 4 s. A "Details…"
button opens the relevant Settings pane. This is **far better UX** than
silently hiding.

**v1:** add a "Retry" button for transient errors (pasteboard busy, STT
hiccup).

#### 2.3.7 (v2) Modes indicator

When the user has set a per-app or global mode (Code / Email / Casual),
the HUD shows a small mode chip in the top-left:

```
┌──────────────────────────────────────────────────┐
│ [Code]  ▌▌▌▌▌  "function take returns int"        │
└──────────────────────────────────────────────────┘
```

A 1-line label, 11 pt, secondary, ~40 pt wide. Disappears when mode
is "Default".

---

### 2.4 Settings window

**Goal:** Expose every user-tunable in a discoverable, native
`Form` with grouped sections. The settings *taxonomy* is the IA: the
shape of the sections tells the user *what kinds of things they can
change*.

**Status:** **Built** (4 sections: Activation, Transcription, AI Cleanup,
Text Insertion; v0 Phase B added the trigger mode picker). **Defer to
v1:** Advanced, Privacy, Models, About-pane.

**Reference patterns:**
- **Wispr Flow settings:** 5 tabs (General, Modes, Languages, Snippets,
  Account). Each tab is a tall scrolling list. Native SwiftUI form look.
- **Superwhisper settings:** 4 sections (Modes, Snippets, Sounds, Hotkey).
  Single window, scrollable.
- **MacWhisper settings:** 5 sections (Models, Transcription, Behavior,
  Shortcuts, About). Each with a brief description.
- **VoiceInk settings:** 6 sections (Hotkey, Model, Language, Processing,
  Storage, About). Power-user density.

**Our IA** (v0): single window, 4 sections. **v1:** grow to 6 (add
"History" + "Privacy"). **v2:** add "Modes", "Snippets", "Vocabulary".

#### 2.4.1 Layout (current)

```
┌────────────────────────────────────────────────────┐
│ speak Settings                              ⊕ ⊗    │  macOS window chrome
├────────────────────────────────────────────────────┤
│                                                    │
│  Activation                                        │  section header
│  ○ Double-tap Fn (toggle)                          │  inline picker (Phase B)
│  ○ Hold Fn (push-to-talk)                          │
│  Tap Fn twice to start recording; tap once to stop.│  contextual caption
│                                                    │
│  Transcription                                     │
│  Language:           [English (US)        ▾]       │  menu picker
│  Speech Engine:      [Apple Speech        ▾]       │
│                                                    │
│  AI Cleanup                                        │
│  ☐ Enable AI neat-writing                          │  toggle
│  Cleanup Engine:     [Foundation Models   ▾]       │
│                                                    │
│  Text Insertion                                    │
│  Paste Mode:         [Cmd+V (default)     ▾]       │
│                                                    │
└────────────────────────────────────────────────────┘
                                              420 × 380
```

**Components:** `Form(.grouped)`, `Section`, `Picker(.menu | .inline)`,
`Toggle`, contextual captions.

#### 2.4.2 Section: Activation (built, Phase B)

- Trigger mode picker: `.doubleTap` / `.hold`. Inline picker.
- Hotkey display: shows current binding label ("Double-tap Fn") + a
  **Record…** button. **v0 ships the read-only display**;
  the **record-UI is deferred to v0.1** (per `human-verification.md`
  §4.1).
- Press-and-hold duration slider: 0.1–1.0 s (advanced; v0.1).

**Edge case:** external keyboards without Fn — show a footnote
"External keyboards may not have an Fn key. Pick a different hotkey in
v0.1."

**v0.1 — Hotkey recorder UX (the deferred part):**

```
┌────────────────────────────────────────────────────┐
│  Hotkey:                                            │
│   ┌──────────────────────────────────────┐         │
│   │ Press the keys you want to use…       │         │  ← record card
│   │   ⌥⌘Space                            │         │  ← live preview
│   └──────────────────────────────────────┘         │
│   [Cancel]                              [Save]      │
└────────────────────────────────────────────────────┘
```

A modal sheet over Settings, ~440×200, with a single record card. The
user presses the desired combination; the live preview shows the
glyphs. `Save` writes the binding; `Cancel` discards. The
`HotkeyMonitor.updateBinding` path is already wired (P5); only the
capture UI is missing.

#### 2.4.3 Section: Transcription (built)

- Language menu (en-US, en-GB in v0; +fr-FR, +de-DE, +es-ES in v1).
- Speech engine picker (Apple Speech in v0; WhisperKit in v0.1;
  whisper.cpp in v1 — disabled rows already show).

**v0.1 addition:** a "Test transcription" button that runs a 3-second
sample dictation and shows the partial result inline. Catches 80% of
"my engine doesn't work" issues.

#### 2.4.4 Section: AI Cleanup (built)

- `Enable AI neat-writing` toggle.
- Cleanup engine picker (Foundation Models in v0; Ollama in v0.1).

**v0.1 addition:** an "Engine status" row showing live availability
("Apple Intelligence is ON" / "Apple Intelligence is OFF — using raw
transcript" / "Ollama is running on localhost:11434"). The status row
is the user's at-a-glance "is the cleanup going to work right now?"
indicator. The data is from `FoundationModelsCleaner.isAvailable` polled
on window appear and every 30 s.

#### 2.4.5 Section: Text Insertion (built)

- Paste mode picker (Cmd+V in v0; Accessibility API in v1).

**v0.1 addition:** a "Restore clipboard after paste" toggle (the
**deferred clipboard-restore decision** from `dictation-flow.md` §5).
Default OFF — the hard rule says "never read the pasteboard" — but
opt-in for power users who want it. With a clear warning: "When ON,
speak reads the pasteboard to restore it after pasting. This may
trigger macOS 26.4 paste-protection prompts in some apps."

#### 2.4.6 (v1) Section: History

- Max entries slider: 100 / 1,000 / 10,000 (default) / 50,000. Mirrors
  `HistoryStore.maxEntries` init param. **Provenance:**
  `benchmark.md` §7 "history size" decision.
- "Clear All History…" destructive button.
- "Export History…" button (already in the History window, mirrored here
  for discoverability).
- "Open History Window" button.

#### 2.4.7 (v1) Section: Privacy

- **"Audio never leaves this Mac"** badge (green check) with a 1-line
  explanation. Read-only, prominent.
- **"Show offline status in menubar"** toggle. When ON, a small dot
  appears next to the menubar icon when the Mac is offline.
- **"Telemetry"** row: `Disabled — speak sends nothing anywhere` (read-only,
  locked). This is a marketing feature, not a setting — but it
  communicates the moat clearly.

#### 2.4.8 (v1) Section: Models (Advanced)

A power-user section. Collapsed by default (`DisclosureGroup`).

- Speech engine model picker (per-engine). Apple Speech: no choice
  (it's whatever the system ships). WhisperKit: `tiny`, `base`, `small`,
  `large-v3`. whisper.cpp: `tiny.en`, `base.en`, `small.en`, etc.
- Cleanup engine model picker. Foundation Models: `System 3B` (default),
  `System 3B + custom prompt` (v1.1). Ollama: `qwen2.5:3b`, `gemma3:4b`,
  `phi4-mini`, custom.
- **Download progress** for first-run model downloads (WhisperKit,
  Ollama). Per-model size and ETA.

#### 2.4.9 (v2) Section: Modes

A new "Modes" section. Each mode is a named preset: name, optional
icon, optional hotkey, custom cleanup prompt, optional per-app binding.
Inline list with an "Add…" button.

#### 2.4.10 (v2) Section: Snippets

A list of voice commands. Each snippet: trigger phrase → expansion
text. e.g., "new line" → "\n", "my email" → "tamil@example.com", "lgtm"
→ "Looks good to me. 👍". Add / edit / delete.

#### 2.4.11 (v2) Section: Vocabulary

Custom word list for STT. Add / remove words. The STT engine is given
the list as a custom vocabulary hint (where supported — Apple
SpeechAnalyzer: yes; WhisperKit: yes).

#### 2.4.12 (v1) Settings window chrome

- A small "speak — Settings" title (the `.` is the designer's vanity;
  ignore).
- A "?" button in the window chrome that opens the Help / About
  panel.
- Settings *remembers its size and position* (`@SceneStorage` on the
  window). Mac idiom.

---

### 2.5 History window

**Goal:** Searchable, exportable, clearable list of past dictations.
The user should be able to (a) find a past dictation by substring,
(b) copy its text, (c) re-paste it at the cursor, (d) export the
whole history as JSON.

**Status:** **Built** (P9, loop #16). Search, Clear, Export, empty
state, list with cleaned/raw + timestamp + engine. **Defer:** live
refresh, per-row copy, re-paste, multi-select.

**Reference patterns:**
- **VoiceInk history:** modal sheet, search bar, list with row actions
  (Copy, Delete, "Send to editor"). Power-user density.
- **MacWhisper history:** split view — list left, detail right. The
  detail shows the full transcript with timestamps per word.
- **Superwhisper history:** simple list, "Copy" on click, "Delete" on
  right-click.
- **FluidVoice history:** none (transcript is ephemeral — strong moat
  stance: "we don't keep your data"). `speak` keeps it (default ON,
  opt-out to disable).

#### 2.5.1 Layout (current)

```
┌────────────────────────────────────────────────────────┐
│ speak — Dictation History                       ⊕ ⊗    │
├────────────────────────────────────────────────────────┤
│ 🔍 Search dictations                          ⏳       │
├────────────────────────────────────────────────────────┤
│ ┌──────────────────────────────────────────────────┐   │
│ │ Hello world, this is a test.                     │   │  lineLimit 3
│ │ Jun 21, 2026 at 10:32 AM · apple-speech+fm      │   │  caption secondary
│ ├──────────────────────────────────────────────────┤   │
│ │ This is a longer dictation that wraps to multi…  │   │
│ │ Jun 21, 2026 at 10:30 AM · apple-speech+fm      │   │
│ ├──────────────────────────────────────────────────┤   │
│ │ (no cleanup) Raw transcript only.                │   │
│ │ Jun 21, 2026 at 10:28 AM · apple-speech         │   │
│ └──────────────────────────────────────────────────┘   │
├────────────────────────────────────────────────────────┤
│ [Export…]                              [Clear History] │
└────────────────────────────────────────────────────────┘
                                                  520 × 460
```

#### 2.5.2 v0.1 — Per-row actions

Hovering a row reveals 3 trailing buttons: Copy, Paste, Delete.
The Copy button writes the text to the pasteboard. The Paste button
*simulates Cmd+V* (same as the live paste path) so the user can
re-paste a past dictation. The Delete button removes the row (with
undo via a 5-second toast).

**Open question:** should "Paste" *also* be the implicit double-click
action? Power users say yes; new users say no (double-click should
select). **v0.1:** double-click selects + opens a detail modal; Paste
is a button.

#### 2.5.3 v0.1 — Live refresh

When the History window is open and a new dictation completes, the
list refreshes in-place (animated row insertion at the top). This
requires the `HistoryStore` to publish changes — `actor` doesn't do
this; the engine will need to post a `NotificationCenter` event
(`speak.history.didAppend`) that the History view model subscribes to.

#### 2.5.4 v1 — Multi-select

`Cmd+A` selects all rows; `Cmd+Click` adds to selection. A floating
toolbar appears: `Copy N`, `Delete N`, `Export N`. This is the
**MacWhisper killer feature** for power users triaging large
histories.

#### 2.5.5 v1 — Detail view (right pane)

A 2-pane layout: list left, detail right. Detail shows:
- Full cleaned text (and raw text, collapsed by default)
- Per-word timestamps (from `SpeechAnalyzer` word timings)
- Duration
- Engine used
- "Copy" / "Re-paste" / "Delete" actions

#### 2.5.6 v1 — Tags / folders

User can tag dictations (e.g., "work", "personal") or move them into
folders. Folders appear as a sidebar. **Why this matters:** at 10,000
entries, search alone is not enough; users will want to scope by
project.

---

### 2.6 Permission recovery surface

**Goal:** When a permission is revoked while the app is running
(extremely common — users toggle off in System Settings all the time),
surface a clear, persistent, dismissable affordance so the user
knows *why* dictation is broken.

**Status:** **Partially built.** The menubar shows a "Grant
Accessibility Permission" row when `controller.permissionsNeeded` is
true (`SpeakApp.swift`). The onboarding re-shows on relaunch if
permissions are denied. **Defer:** in-app banner, deep-link from any
denied state.

**Reference patterns:**
- **Wispr Flow:** small red dot on the menubar icon when a permission
  is missing, with a tooltip "Click to grant permissions".
- **MacWhisper:** modal popover on app launch if permissions missing.
- **VoiceInk:** a single permanent "Permissions" row in the menubar
  dropdown.

**The `speak` shape:**

```
┌────────────────────────────────────────────────────────┐
│ ⚠  speak — Microphone permission required             │  ← banner, top of screen
│     [Open System Settings]   [Dismiss]                  │
└────────────────────────────────────────────────────────┘
```

A 40-pt-tall transient banner that lives at the top of the screen for
8 s (auto-hide) or until the user clicks a button. Triggered when
`PermissionManager.status()` returns `.denied` for any required
permission. The banner is *non-focus-stealing* (an NSPanel like the
HUD) so it doesn't interrupt the user's app.

**Open question:** does the banner get in the way? It might. A
*less-intrusive* alternative is a small badge on the menubar icon that
opens a popover with the same content. Reference: Apple's own "App is
using your microphone" indicator (the green dot in the menubar).
**v0.1:** try the popover, fall back to the banner if it's not
noticeable.

---

### 2.7 About / Help panel

**Goal:** Brand statement, version, link to README/repo, link to
issues, list of attributions, list of open-source licenses.

**Status:** `NSApplication.shared.orderFrontStandardAboutPanel(nil)` is
wired in the menubar. The default macOS about panel is *boring* but
functional. **Defer:** custom about panel with brand + privacy story.

**Reference patterns:** every Mac app's about panel.

**The `speak` shape (v1):**

```
┌────────────────────────────────────────────────────┐
│                                          ⊗         │
│                                                    │
│         ⏺  (large SF Symbol, .tint, 80pt)           │
│                                                    │
│              speak  v0.1.0                         │  22pt bold
│         Built locally. Used privately.              │  13pt secondary
│                                                    │
│  ─────────────────────────────────────────────     │
│  Made by [Your Name] · MIT License ·               │  hyperlink
│  [github.com/speak/speak]                          │
│                                                    │
│  Audio engine:  Apple SpeechAnalyzer               │
│  AI cleanup:    Apple Foundation Models             │  (v0.1)
│  Storage:       ~/Library/Application Support/speak/│  hyperlink
│                                                    │
│  ─────────────────────────────────────────────     │
│  [View on GitHub]  [Report an issue]  [Quit speak] │
└────────────────────────────────────────────────────┘
                                                  440 × 400
```

A custom `NSWindow` with a SwiftUI view. Reachable from the menubar's
"About speak…" row. The default macOS about panel stays as a fallback
(via `orderFrontStandardAboutPanel`).

---

### 2.8 (v1) Snippet editor

**Goal:** Define voice commands. Each snippet is a trigger phrase +
expansion text. e.g., "new line" → "\n", "period" → ".", "my email" →
"tamil@example.com", "code block" → "```\n\n```".

**Status:** **Future.** Not built; `LLMCleaning` is the v0 cleanup
mechanism. Snippets are a parallel, deterministic expansion path that
runs *before* the LLM cleanup (so a snippet like "period" becomes
"." and the LLM doesn't re-process it).

**Reference patterns:**
- **Wispr Flow snippets:** 50+ built-in snippets, user-defined, scope
  (global / per-app), order.
- **Superwhisper snippets:** same shape, fewer built-ins.
- **VoiceInk snippets:** inline editor, simple list.
- **MacWhisper:** "Word Replacements" — list of find → replace pairs.
  Simpler than snippets but covers 80% of use cases.

**The `speak` shape (v1):**

```
┌─────────────────────────────────────────────────────────┐
│ speak — Snippets                                ⊕ ⊗    │
├─────────────────────────────────────────────────────────┤
│  🔍 Search snippets                                     │
│  ─────────────────────────────────────────────────      │
│  ┌───────────────────────────────────────────────────┐  │
│  │ "new line"        →  \n                            │  │
│  │ "new paragraph"   →  \n\n                          │  │
│  │ "period"          →  .                             │  │
│  │ "comma"           →  ,                             │  │
│  │ "question mark"   →  ?                             │  │
│  │ "exclamation"     →  !                             │  │
│  │ "open paren"      →  (                             │  │
│  │ "close paren"     →  )                             │  │
│  │ ─── my custom ───                                   │  │
│  │ "my email"        →  tamil@example.com              │  │
│  │ "lgtm"            →  Looks good to me.              │  │
│  └───────────────────────────────────────────────────┘  │
│  ─────────────────────────────────────────────────      │
│  [+ Add Snippet]  [Import…]  [Export…]                 │
└─────────────────────────────────────────────────────────┘
                                                  520 × 480
```

**Built-in snippets (v1):** the top 10 voice punctuation commands
(period, comma, question mark, exclamation, new line, new paragraph,
colon, semicolon, open/close paren). These cover the most-common use
case — Wispr's most-loved feature.

**Storage:** JSON in `~/Library/Application Support/speak/snippets.json`.
Importable / exportable so users can share snippet packs.

**Open question:** should snippets run *before* the LLM cleanup, or
*as part of it*? Trade-off:
- *Before:* deterministic, fast, the LLM doesn't touch the output.
  Punctuation commands become punctuation characters. But the LLM might
  *re-clean* the output and re-add the punctuation the snippet already
  inserted.
- *As part of:* more flexible (snippets can trigger transforms), but
  less predictable, and breaks the "I said 'period' and a period
  appeared" guarantee.

**v1 decision (proposed):** snippets run **before** cleanup. Cleanup
is configured to *not* add punctuation when a snippet already added it
(via a "skip punctuation" mode in the cleanup prompt).

---

### 2.9 (v1) Custom vocabulary editor

**Goal:** Add words the STT engine should listen for. Useful for
names, technical terms, jargon.

**Status:** **Future.** Apple `SpeechAnalyzer` supports a custom
vocabulary via `SFSpeechLanguageModel`. The store is just a JSON list
of strings; the wiring is straightforward.

**The `speak` shape (v1):**

```
┌─────────────────────────────────────────────────────────┐
│ speak — Vocabulary                              ⊕ ⊗    │
├─────────────────────────────────────────────────────────┤
│  Words the speech engine should listen for.             │
│  ─────────────────────────────────────────────────      │
│  ┌───────────────────────────────────────────────────┐  │
│  │  Tamil                                           │  │
│  │  Wispr Flow                                      │  │
│  │  Cgeventtap                                      │  │
│  │  SpeechAnalyzer                                  │  │
│  │  Apple Foundation Models                         │  │
│  │  MacWhisper                                      │  │
│  │  ...                                             │  │
│  └───────────────────────────────────────────────────┘  │
│  ─────────────────────────────────────────────────      │
│  [+ Add Word]  [Import from contacts]  [Clear]          │
└─────────────────────────────────────────────────────────┘
```

**v1.1:** "Import from contacts" — reads the user's Contacts (with
permission) and adds first / last / company names to the vocabulary.

**Open question:** should vocabulary be per-engine? Apple Speech's
custom vocab format is different from WhisperKit's. **v1:** one
vocabulary, transformed per-engine at use time.

---

### 2.10 (v1) Modes editor

**Goal:** Named presets that bundle (language, cleanup mode, cleanup
prompt, snippets, vocabulary, hotkey). The user switches modes via a
submenu in the menubar or via a hotkey.

**Status:** **Future.** This is the **single most-requested feature**
in competitor reviews (Wispr, Superwhisper, VoiceInk all have it).
The data model is the only blocker; the UI follows.

**The `speak` shape (v1):**

```
┌─────────────────────────────────────────────────────────┐
│ speak — Modes                                  ⊕ ⊗    │
├─────────────────────────────────────────────────────────┤
│  Switch between presets. Each mode bundles language,     │
│  cleanup, and formatting.                                │
│  ─────────────────────────────────────────────────      │
│  ┌───────────────────────────────────────────────────┐  │
│  │  Default       [●  on]                             │  │
│  │  ─ en-US, Foundation Models cleanup, casual        │  │
│  │                                                    │  │
│  │  Code          [○  on]                             │  │
│  │  ─ en-US, code-aware cleanup, monospace aware      │  │
│  │                                                    │  │
│  │  Email         [○  on]                             │  │
│  │  ─ en-US, formal cleanup, greeting/sign-off aware  │  │
│  │                                                    │  │
│  │  Casual        [○  on]                             │  │
│  │  ─ en-US, no filler removal, just punctuation      │  │
│  └───────────────────────────────────────────────────┘  │
│  ─────────────────────────────────────────────────      │
│  [+ New Mode]   [Duplicate]   [Delete]                  │
└─────────────────────────────────────────────────────────┘
```

**v1.1:** per-app modes (auto-switch when the frontmost app changes).

---

### 2.11 (v2) Voice commands / AI transforms

**Goal:** Select text in any app, invoke a voice command ("make this
shorter", "fix that", "translate to Spanish"), and the local LLM
applies the transform.

**Status:** **Future.** Apple Intelligence already has Writing Tools
for this on macOS 15+; the v2 feature wraps it (or a local LLM
alternative) in a `speak`-branded UX.

**Reference:** Wispr Flow's "AI Commands" — invoked via a global
hotkey while text is selected, applied via a popover with multiple
transform options.

**The `speak` shape (v2):**

```
┌─────────────────────────────────────────────────────────┐
│ speak — AI Commands                              ⊕ ⊗    │
├─────────────────────────────────────────────────────────┤
│  Select text in any app, then:                          │
│   • ⌥⌘R  Rephrase                                       │
│   • ⌥⌘S  Make shorter                                  │
│   • ⌥⌘L  Make longer                                   │
│   • ⌥⌘F  Fix grammar                                    │
│   • ⌥⌘T  Translate to…  (menu of languages)            │
│   • ⌥⌘B  Bullet list                                    │
│   • ⌥⌘N  Numbered list                                  │
│   • ⌥⌘E  Explain (for code)                            │
│  ─────────────────────────────────────────────────      │
│  Custom commands:                                       │
│   • "make it sound friendlier"  →  (Foundation Models)  │
│   • "write like Shakespeare"    →  (Foundation Models)  │
└─────────────────────────────────────────────────────────┘
```

**Open question:** does this overlap with macOS Writing Tools? Yes,
and that's fine — `speak` is voice-first, Writing Tools is
selection-first. We can offer both, with `speak` as the
voice-activation path.

---

### 2.12 (v1) CLI shim

**Goal:** `speak --start`, `speak --stop`, `speak --status`,
`speak --config <key>=<value>`, `speak --export > history.json`.

**Status:** **Future.** Listed in `product.md` §9 v1. Not built.

**Reference:** every Mac dictation app ships a CLI. Wispr's is well-
documented (`wispr flow --help`).

**The `speak` shape (v1):**

```
$ speak --help
speak — local-first voice dictation
Usage:
  speak --start                  Start dictation
  speak --stop                   Stop dictation and paste
  speak --cancel                 Cancel in-flight dictation
  speak --status                 Print current state (idle|listening|...)
  speak --toggle                 Toggle (start if idle, stop if listening)
  speak --config <key>=<value>   Set a config value (e.g. language=en-GB)
  speak --export <file>          Export history to <file> (JSON)
  speak --mute                   Mute microphone
  speak --unmute                 Unmute microphone
  speak --version                Print version
```

**Edge case:** CLI cannot grant permissions; the user must run the GUI
once. The CLI is for power users (and the `speak` dogfood team) only.

---

### 2.13 (v1) Status popover (menubar click)

**Goal:** A richer alternative to the current dropdown menu. A
**popover** that shows live status, recent dictations, and quick
actions, in a single 360×400 card.

**Reference:** Apple's "Now Playing" menubar popover. The shape is
familiar to Mac users.

**Why we'd switch from dropdown to popover:** a popover is **much**
more discoverable for the v1 feature set (modes, snippets, language,
engine status). A dropdown menu with 20+ items is overwhelming; a
popover with sections is scannable.

**The `speak` shape (v1):**

```
┌──────────────────────────────────────────────┐
│  speak  ⏺                                    │  ← header, status icon
│  ──────────────────────────────────          │
│  Status: Listening  (0:04)                    │  ← live status row
│  Mode: Default  |  Language: en-US            │  ← quick info
│  Engine: Apple Speech  +  Foundation Models   │  ← quick info
│  ──────────────────────────────────          │
│  [▶  Start Dictation]      ⌥⌘Space           │  ← primary action
│  [🔇 Mute Microphone]                        │  ← toggle
│  ──────────────────────────────────          │
│  Recent dictations:                          │
│  • Hello world, this is a test.    10:32 AM  │  ← top 3, click to re-paste
│  • This is a longer dictation…     10:30 AM  │
│  • Raw transcript only.            10:28 AM  │
│  [See all history →]                         │
│  ──────────────────────────────────          │
│  [Settings…]  [About speak…]                 │
└──────────────────────────────────────────────┘
                                       360 × 400
```

**Open question:** dropdown vs popover is a 1-time migration. The
trade-off is real: dropdown is simpler to ship, popover is richer for
v1+ features. **v0:** dropdown (already built). **v1:** evaluate the
migration; if modes + snippets are 6+ items, popover wins.

---

## 3. Component catalog

> Every component has a **name**, **API** (the SwiftUI view name), and
> **usage rule**. This is the v0.1 refactor plan: extract these into
> `App/UIComponents/` (or `SpeakCore/UI/`) so they're testable + reusable.

### 3.1 Buttons

- **`PrimaryButton`** = `Button(.borderedProminent)`, large control
  size. Used for: "Get Started", "Grant Microphone Access", "Finish
  Setup".
- **`SecondaryButton`** = `Button(.bordered)`, regular control size.
  Used for: "Open System Settings", "Export…".
- **`DestructiveButton`** = `Button(role: .destructive)`, plain.
  Used for: "Clear History", "Delete" per-row.
- **`GhostButton`** = `Button(.plain)` with secondary foreground.
  Used for: "Skip for now", "Cancel", "See all history →".

**Rule:** never use the default `Button()` style — it inherits the
context style and looks inconsistent across the app.

### 3.2 Status icon

- **`MenubarStatusIcon(state: MenubarIcon)`** — wraps the
  `systemImage(for:)` mapping in the App layer. Already exists
  (`SpeakApp.swift`).
- **States:** see §2.2.1.

### 3.3 Level meter

- **`LevelMeterView(level: Double, isActive: Bool)`** — already exists
  in `Overlay/`. 5 vertical bars, cosine envelope, breathing when
  inactive.
- **Variants:**
  - **Compact** (24×16) — for in-menubar
  - **Standard** (27×20) — for the HUD
  - **Large** (60×40) — for a "live audio" detail view (v1)

### 3.4 Empty state

- **`EmptyStateView(icon: String, title: String, subtitle: String?)`**
  — used in: History, Snippets, Vocabulary, Modes, Custom
  Dictionary.
- **Layout:** centered icon (40–60 pt), title (15 pt semibold),
  subtitle (13 pt secondary), optional CTA button.

### 3.5 Loading

- **`LoadingDots()`** — three animated dots for "listening…"
  placeholder.
- **`ProgressDots(currentStep: Int, totalSteps: Int)`** — onboarding
  footer dots. Already exists in `OnboardingView.swift`.
- **`SpinningIndicator()`** — 16-pt ProgressView, scale 0.7. Used in
  HUD processing state.

### 3.6 Form rows

- **`SettingRow<Content: View>(title: String, description: String?,
  content: Content)`** — wraps a `LabeledContent` for consistent
  label-spacing.
- **`SettingToggle(title: String, description: String?, isOn: Binding<Bool>)`**
  — title + description + native toggle.
- **`SettingPicker<T>(title: String, selection: Binding<T>, options: [(String, T)])`**
  — title + native menu picker.

### 3.7 Cards / Pills

- **`Card<Content: View>(content: Content)`** — rounded rect, 14 pt
  radius, `.regularMaterial` background, 16 pt padding.
- **`Pill(label: String, systemImage: String?, color: Color)`** —
  used for status chips (e.g., mode indicator in HUD).

### 3.8 Toast / banner

- **`Toast(message: String, systemImage: String?, duration: TimeInterval)`**
  — top-of-screen transient banner, used for permission recovery,
  errors, "Copied to clipboard" confirmations.

### 3.9 Transcript view

- **`TranscriptTextView(text: String, confidence: [Double]?)`** —
  renders partial or final transcript with optional per-word
  confidence coloring.

### 3.10 Permission row

- **`PermissionRow(kind: PermissionKind, status: PermissionStatus,
  isLoading: Bool, onAction: () -> Void)`** — the core of the
  onboarding permission steps. Already exists in
  `OnboardingView.swift` (private).

### 3.11 Hotkey recorder

- **`HotkeyRecorderSheet()`** — the deferred Settings → Record…
  modal. **v0.1 build target.** Includes the live-preview record card
  (§2.4.2).

### 3.12 Search field

- **`SearchField(text: Binding<String>, placeholder: String)`** —
  magnifier icon + plain `TextField` + clear button. Used in
  History, Snippets, Vocabulary, Modes. Pattern is consistent
  across surfaces.

---

## 4. UX flows

### 4.1 First launch → working dictation (target: ≤90 s)

```
[Install]  →  [Launch]
                  │
                  ▼
            Onboarding: Welcome (5 s read)
                  │ tap "Get Started"
                  ▼
            Onboarding: Microphone (10 s; tap "Grant" + system dialog)
                  │ auto-advance
                  ▼
            Onboarding: Accessibility (15 s; tap "Open Settings" + manual toggle)
                  │  poll detects grant → auto-advance
                  ▼
            Onboarding: Input Monitoring (15 s; same)
                  │
                  ▼
            Onboarding: Hotkey (5 s read)
                  │ tap "Finish Setup"
                  ▼
            Onboarding: Done (1.5 s)
                  │ auto-close
                  ▼
            Menubar appears, idle
                  │ user double-taps Fn in any app
                  ▼
            HUD appears, "Listening…"
                  │ user speaks 5 s
                  │ user single-taps Fn
                  ▼
            HUD shows "Cleaning up…" (200–800 ms)
                  │ paste
                  ▼
            HUD shows "Done" (600 ms)
                  │ hide
                  ▼
            Menubar returns to idle, history updated
```

**Total time target:** 90 s from launch to first paste. **Breakdown:**
- Onboarding read time: 25 s (5+10+15+15+5 reads, very fast skim)
- Permission grant + system dialog: 25 s (mic is one tap; ax + im
  are manual toggles)
- First dictation: 40 s (fumbling for the right hotkey + speaking)

**Friction points to address:**
- The two manual-grant permissions (ax, im) are the slowest. **v0.1:**
  add a 3-second "skip for now" that defers them, with a banner when
  the user comes back.
- The hotkey test: **v0.1:** add the "Try it now" mini-test on the
  hotkey step (§2.1.5).

### 4.2 Revoked permission → recovery

```
[User revokes Mic in System Settings]
                  │
                  ▼
            Next dictation fails (.microphoneDenied)
                  │
                  ▼
            HUD shows "⚠  Mic permission denied — open System Settings"
            (4 s, then hides)
                  │
                  ▼
            Menubar gets a red dot (or a "Permissions Required" row)
                  │
                  ▼
            [User clicks "Open System Settings" from menubar or banner]
                  │
                  ▼
            System Settings opens to Privacy_Microphone
            [User re-grants]
                  │
                  ▼
            Next double-tap Fn works normally
```

**Edge case:** if the user denies *and* dismisses the banner, the
menubar still shows the red dot. The dot is **persistent** until the
permission is granted.

### 4.3 Mute → unmuted

```
[User clicks "Mute Microphone" in menubar]
                  │
                  ▼
            Menubar label: "🔇 Mute Microphone" → "🎙  Unmute Microphone"
            Subtitle appears: "Muted — dictation disabled"
                  │
                  ▼
            [User double-taps Fn]
                  │
                  ▼
            Nothing happens (no HUD, no error)
            [Log: "beginDictation refused: muted"]
                  │
                  ▼
            [User unmutes]
                  │
                  ▼
            Subtitle disappears, double-tap Fn works again
```

**v1 addition:** a **global mute chord** (e.g., Cmd+Shift+M) so the
user can mute without opening the dropdown. **v0 ships the menu
toggle only** (per `human-verification.md` §4.6).

### 4.4 Engine swap (Apple Speech → WhisperKit)

```
[User opens Settings → Transcription]
                  │
                  ▼
            [Selects "WhisperKit" from Speech Engine menu]
                  │
                  ▼
            First-time: download banner appears
            "Downloading whisper-large-v3-turbo (1.5 GB) — 5 min remaining"
                  │
                  ▼
            On download complete: "WhisperKit ready" badge
                  │
                  ▼
            Next dictation uses WhisperKit
            HUD shows: "Engine: WhisperKit" (v1)
```

**v0.1:** the engine badge in the HUD is a small chip in the top-left.
When a dictation is in progress, the chip flips to the active engine.

### 4.5 Engine unavailable → graceful fallback

```
[Apple Intelligence is OFF, cleanup is enabled]
                  │
                  ▼
            [User starts dictation]
                  │
                  ▼
            FoundationModelsCleaner.isAvailable returns false
                  │ (logged)
                  ▼
            Cleanup is **skipped** (not failed)
            Raw transcript is pasted
            HUD shows "Done" normally
                  │
                  ▼
            (No error surfaced — the user gets a result, even if
             less polished)
```

**The fallback is invisible to the user** — that's the design
posture. The `human-verification.md` §1 row confirms: "With Apple
Intelligence OFF, the session still reaches `done` and pastes the raw
transcript."

**v0.1 surface:** the Settings → AI Cleanup section shows a live
status row ("Apple Intelligence: OFF — cleanup disabled, raw
transcript will be pasted"). This is **only visible to users who go
looking for it**, so the fallback is invisible by default.

---

## 5. Aspirational surfaces (v2+)

### 5.1 Conversation view (alias for History, rename only)

The History surface is called "History" because it's a list. Power
users who dictate 50+ times a day think of it as a **conversation
log** — entries relate to the app they were dictating into, the
project, the day. **v2:** rename "History" to "Conversations" and add:
- Per-app grouping (collapsible)
- Per-day grouping
- A "today" quick-filter pill

### 5.2 Live confidence overlay (Wispr-style)

The HUD shows partial text. Each word has a confidence score (0–1).
Low-confidence words (0.0–0.6) are rendered in `.secondary`; mid
(0.6–0.85) in `.primary`; high (0.85+) in primary with a subtle
underline. This is **the single biggest UX tell** Wispr users
love — it tells you which words to glance at and which to trust.

**v1:** ship it. The data is already in `TranscriptionResult`.

### 5.3 Code mode (v2)

When the frontmost app is a code editor (Xcode, VS Code, Cursor, JetBrains),
`speak` enters "Code mode": no filler removal, no capitalization fix,
snippets like "open paren" → "(", "new line" → "\n", "tab" → "  "
(2 or 4 spaces, configurable).

**Implementation:** per-app mode in v1; code-mode prompt in v2.

### 5.4 Multi-dictation (batch)

Dictate 5 separate thoughts; press Fn to separate; press Fn (long)
once to paste all 5. **Wispr's "edit before paste" + multi-segment
is the killer combination.** v2.

### 5.5 Live translation

Speak in English; the LLM translates to French/Spanish/etc. before
paste. **Tricky** because the LLM has to run *before* the paste, not
*as cleanup*. **v2 or v3.**

### 5.6 Audio-reactive desktop wallpaper / menubar glow

Subtle background animation on the menubar icon (a 1-pixel glow that
pulses with the mic level). **Anti-feature: don't ship.** Mac dictation
apps that do this are toys. **Stay subtle.** The HUD is the
attention surface; the menubar should be calm.

---

## 6. Open design questions (require human input)

These are the items I (the agent) cannot decide without you:

1. **Brand color.** The current code uses `.tint` (system accent).
   `speak`'s product page on the eventual site should have a brand
   color (e.g., a custom purple). Ship a default `.tint` in v0; add
   a `Brand.accent` token in v1.
2. **Hotkey default.** `.doubleTap Fn` is the current default. Wispr's
   default is `Opt+Space`. MacWhisper's is `Fn (hold)`. **Trade-off:**
   double-tap is unique to `speak` and is the signature UX, but
   Wispr migrants will hunt for Opt+Space. **Proposal:** default to
   double-tap Fn (signature UX); surface Opt+Space as a 1-click
   alternative in the hotkey step of onboarding.
3. **Edit-before-paste toggle default.** Wispr's signature feature.
   **Proposal:** OFF by default (the magic is the cursor types it);
   ON for Wispr migrants, behind a 1-line toggle in Settings.
4. **First-run tooltip.** After onboarding, should we show a
   1-time toast over the menubar icon explaining "Double-tap Fn to
   start"? **Proposal:** yes, with a "Don't show again" link. 6-second
   auto-dismiss.
5. **History window: list vs. popover.** Should "History…" open a
   window (current) or a popover from the menubar (more discoverable,
   less screen real estate)? **Proposal:** window in v0, evaluate
   popover in v1.
6. **Brand name + icon.** `speak` is the codename. Final product
   name and icon need a designer. **No agent call.**

---

## 7. What this doc does NOT decide

This is **ideation**, not a contract. The active contracts remain:
- `docs/product.md` — the destination
- `docs/architecture.md` — the types and seams
- `docs/roadmap.md` — the build order
- `docs/quality.md` — the test plan
- `docs/benchmark.md` — the definition of done

When a v0.1 screen is built, this doc's section for that screen
should be **moved** to a build brief (or kept here as the design
reference, with a `Built: <date> · Tests: <file>` footer). The
ideation remains the *why*, the test files are the *what*.

---

## 8. Acknowledgments (the reference apps)

This ideation draws on the visible UX of:

- **Wispr Flow** — the frontier. Top-center pill, edit-before-paste,
  AI commands, snippets, modes. The cautionary tale (top pill) AND
  the gold standard (everything else).
- **MacWhisper** — beautiful list + detail, power-user density,
  model picker. The reference for "what power users want."
- **Superwhisper** — the cleanest HUD motion in the category. The
  reference for "do less, better."
- **VoiceInk** — the open-source-friendly, free competitor. The
  reference for "what does a power-user dictation app look like when
  the price is zero."
- **FluidVoice** — the open-source baseline. The reference for
  "what is the minimum viable dictation app."
- **Aiko** — Apple's-on-Apple approach. The reference for "use
  SpeechAnalyzer + Writing Tools + a thin layer."
- **Talon** — the power-user outlier. The reference for "what does
  voice control look like at the extreme." (Not a direct competitor;
  informs voice-command design.)

`speak`'s UI is the *intersection* of these: Superwhisper's HUD +
Wispr's snippets (v1) + VoiceInk's history + FluidVoice's openness +
Aiko's Apple-only stack. The moat (local + free + open + MIT) is what
none of them can offer together.

---

*End of frontend ideation. The next step is implementation per
`docs/roadmap.md` — this doc is the design reference the builder
agents will pull from.*

---

## 1.6 ↻ Reorientation note (2026-06-21 — added after Wispr Flow Home dashboard deep-dive)

**This section was added after studying the Wispr Flow Home dashboard
screenshot (`wisperflow.png`). It reorients three load-bearing assumptions
in the original §0–§5.**

### The three assumptions that changed

1. **`speak` should have a full-window Home dashboard, not just menubar.**
   The current `speak` design treats the menubar as the only always-present
   surface; everything else (Settings, History) is a modal window. Wispr
   Flow's Home dashboard is the **opposite model**: the full-window Home
   dashboard is the always-primary surface, and the menubar/HUD is
   supplementary. The conversation log is the landing page — it's where
   the user lands when they open the app, and it's what makes the app
   feel like a *product* rather than a *tool*. **This is a big
   architectural shift.** See §2.14 for the new Dashboard surface and
   §6 for the open question.

2. **The sidebar is the navigation.** Wispr uses a 2-pane layout (sidebar
   + content) with 7 feature areas in the sidebar. My original ideation
   had Settings-as-a-window. The sidebar model is more discoverable,
   scales to v1+ features (Snippets, Dictionary, Style, Transforms,
   Scratchpad), and is the standard Mac idiom (System Settings, Mail,
   Music, Finder).

3. **The feature names changed.** My original "Modes / Custom Vocabulary
   / AI Commands" terminology was engineering-flavored. Wispr's
   user-facing names — **Style / Dictionary / Transforms** — are
   friendlier, more discoverable, and match what users actually search
   for in reviews. Updated throughout the appendix (§9).

### The full Wispr Flow Home dashboard — annotated

```
┌─ macOS chrome ───────────────────────────────────────────────────────────────────┐
│  ⬛ 🟡 🟢  ▭  (split-window tile)                  [bell]  [👤]                  │
├──────────────────────────────────────────────────────────────────────────────────┤
│ SIDEBAR (200pt)        │ MAIN CONTENT                                            │
│                        │                                                          │
│ ⏶ Flow  [Basic]       │  Hey Tamilarasan, get back into the flow with [fn]    │ ← hero
│                        │                       ↑                                    │   (28pt bold + key cap)
│ ▦ Home       (active)  │                                                          │
│ 📊 Insights            │  TODAY                                                  │ ← 11pt uppercase
│ 📖 Dictionary          │  ┌────────────────────────────────────────────────┐    │
│ ✂  Snippets            │  │ 02:52 am   Amen.                                │    │
│ Tt Style               │  │ 02:52 am   ─                                   │    │   row
│ ✨ Transforms          │  │ 02:52 am   ─                                   │    │   (timestamp | text)
│ 📄 Scratchpad          │  │ 02:51 am   Can you hear me?                     │    │
│                        │  └────────────────────────────────────────────────┘    │
│ ╭─promo card─╮         │                                                          │
│ │1,995 words │         │  YESTERDAY                                              │
│ │ remaining  │         │  ┌────────────────────────────────────────────────┐    │
│ │ You get    │         │  │ 04:36 am   The .env file has real API keys and │    │
│ │ 2,000/week │         │  │            credentials. We need to test and     │    │
│ │ [Upgrade]  │         │  │            validate everything, so can you…     │    │
│ ╰────────────╯         │  │ 03:18 am   Understand the project, explore…     │    │
│                        │  │ 03:17 am   Thank                                │    │
│ 👥 Invite your team    │  │ 03:10 am   Explore the project and understand…  │    │
│ 🎁 Get a free month    │  │ 03:03 am   can you explain to me how you can…   │    │
│ ⚙  Settings            │  └────────────────────────────────────────────────┘    │
│ ?  Help                │                                                          │
└──────────────────────────────────────────────────────────────────────────────────┘
                                                       ↑ floats over the right side
                                                       ┌──────────────────────────┐
                                                       │ 1,565  total words        │  ← serif numbers
                                                       │   94   wpm               │     (32pt serif)
                                                       │    2   day streak 🖐      │
                                                       │ ─────────────────────    │
                                                       │ Voice Profile Unlocked!  │
                                                       │ Discover your unique…    │
                                                       │ ┌──────────────────────┐ │
                                                       │ │   Create report      │ │  ← orange CTA
                                                       │ └──────────────────────┘ │
                                                       └──────────────────────────┘
```

### 30 design observations (each with a `speak` recommendation)

| # | Wispr observation | `speak` recommendation |
|---|---|---|
| 1 | **Two-pane layout** (sidebar + content), ~200pt sidebar, rest content. | **Adopt v0.1.** Standard Mac idiom. New `DashboardWindowController` (mirror of `OnboardingWindowController`). |
| 2 | **7 sidebar items + 4 footer items.** Feature areas scale horizontally in the sidebar. | **Adopt v0.1.** v0 sidebar = Home, Settings, Help. v1 adds Dictionary, Snippets, Style, Transforms, Scratchpad. |
| 3 | **Brand "Flow" + plan pill "Basic"** in the top of the sidebar. | **Adopt v0.1.** "speak" + no plan (we're free forever). v0.1: replace pill with "v0.1" build tag for transparency. |
| 4 | **"Home" is the conversation log** (not a separate "History" page). It's the landing surface. | **Adopt v0.1.** Rename `HistoryWindowController` → `DashboardWindowController`; default landing surface. |
| 5 | **Grouped by day** with uppercase letter-spaced labels (TODAY / YESTERDAY). | **Adopt v0.1.** Add day-grouping to `HistoryViewModel`. New `HistoryEntryGroup { day: Date, entries: [HistoryEntry] }`. |
| 6 | **Full text shown inline** — no truncation, no "lineLimit 3." | **Adopt v0.1.** Current `lineLimit(3)` is a workaround for the small window; in the dashboard, the list is the conversation. |
| 7 | **Empty rows preserved** with timestamps. The paper trail. | **Adopt v0.1.** Store empty entries (transcripts with `text == ""`) so users can see "I pressed the hotkey at 02:52 but said nothing." Useful for debugging. |
| 8 | **Sidebar selection is a soft warm-gray rounded rect**, not a colored bar. | **Adopt v0.1.** Token `Tokens.Color.Sidebar.selected` ≈ `Color(white: 0.92)`. |
| 9 | **All sidebar icons are line-style SF Symbols** with consistent stroke weight. | **Adopt v0.1.** Use only `.fill` and `.circle` variants — no filled icons except when active. |
| 10 | **Hero CTA at the top of content** — "Hey {name}, get back into the flow with [fn]" — the hotkey is a **visual key cap**. | **Adopt v0.1.** Add a new `KeyCapView` component. v0.1 hero: "Welcome back. Press [fn] to start." (no name — no account). |
| 11 | **The "fn" key cap is orange/rust, rounded, looks like a physical key.** | **Adopt v0.1.** `KeyCapView(label: "fn", color: .brandAccent)`. Used in onboarding + dashboard hero + Settings. |
| 12 | **The "Hey {name}" personalization** is account-driven. | **Skip v0.1** (no account). v1: ask name in onboarding (opt-in), surface here. |
| 13 | **Timestamps are 13pt secondary, monospaced-looking.** | **Adopt v0.1.** Use SF Mono for timestamps (`font: .system(size: 13, design: .monospaced)`). Gives the "log file" feel. |
| 14 | **Day labels are uppercase letter-spaced** — `letterSpacing: 1.5`, `text-transform: uppercase`. | **Adopt v0.1.** `.textCase(.uppercase).tracking(1.5)`. |
| 15 | **Right-floating contextual card** (Voice Profile Unlocked, with orange CTA). | **Adopt v1+** (not v0.1). "Milestone" cards for free — "First 100 words", "1-week streak", etc. |
| 16 | **Large SERIF numbers for hero stats** (1,565 / 94 / 2). Editorial / premium feel. | **Adopt v1+** (with the Insights surface). v0: stay sans-serif to match the Mac minimalism. |
| 17 | **Stats labels are small sans-serif secondary** next to the serif number ("total words" / "wpm" / "day streak"). | **Adopt v1+** (with Insights). |
| 18 | **The "Basic" plan pill is a neutral outline** (not a colored badge). | **Adopt v0.1** (with the build-tag use case). No aggressive "PRO" red badges — the moat is free, not premium. |
| 19 | **The "1,995 words remaining" promo card** has its own lavender background, lives in the sidebar bottom. | **Replace v0.1** with a "What's new in v0.1" card (or a tip card). speak has no usage limit. |
| 20 | **"Invite your team" + "Get a free month"** are freemium growth levers. | **Skip entirely.** speak is per-user, free, open. |
| 21 | **"Settings" + "Help" are SEPARATE sidebar items** (not nested). | **Adopt v0.1.** Settings = the existing form. Help = a new lightweight Markdown viewer (or a webview to the GitHub README). |
| 22 | **Top-right: notification bell + profile icon.** | **Replace v0.1** with: `?` (help) + maybe an update-check icon. speak has no notifications and no profile. |
| 23 | **The window has the macOS split-tile icon** in the chrome (left of traffic lights). | **Adopt v0.1** (this is just the macOS standard — `window.styleMask` includes `.titled` and the OS adds it). |
| 24 | **The window is full-height** by default; content area scrolls. | **Adopt v0.1.** Dashboard window: 880×640 minimum, max content height = dynamic, content scrolls. |
| 25 | **Sidebar items have a left-edge invisible padding** (icon and text are inset ~12pt). | **Adopt v0.1.** `Tokens.Spacing.m` for sidebar item left padding. |
| 26 | **Day-label rows ("TODAY", "YESTERDAY") have no card** — they are direct headings, then the card follows. | **Adopt v0.1.** Day-label is a standalone text element, then a `Card` with the entries. |
| 27 | **Empty rows are rendered as a thin dashed line** (the divider is the only visible element). | **Adopt v0.1.** When `entry.cleanedText == nil && entry.rawText.isEmpty`, show just the timestamp + a hairline. |
| 28 | **No "Clear" or "Export" buttons visible** in this view. They're hidden in Settings or via a header context menu. | **Adopt v0.1.** Keep destructive actions in Settings; dashboard is read-only. (One-click Copy on a row, though.) |
| 29 | **The orange "Create report" button is full-width inside the floating card** — high-contrast, impossible to miss. | **Adopt v1+** (with Insights / Reports). |
| 30 | **The right-floating card overlaps the main content** but is small enough not to obscure the primary content (which is on the left). | **Adopt v1+.** v0.1 dashboard has no floating card; keep it minimal. |

### The critical reorientation question (§6 also calls this out)

**Should `speak` ship as menubar-only (current) or with a full-window Home dashboard (Wispr-style)?**

| | Menubar-only (current) | Full-window Dashboard (proposed) |
|---|---|---|
| **Vibe** | Tool, daemon, "I just want to dictate" | Product, app, "this is my voice journal" |
| **Discoverability** | Low — users find Settings by accident | High — the sidebar IS the IA |
| **v1 feature scale** | Modal windows stack up (Snippets window, Dictionary window, etc.) | Sidebar grows; no modal stacking |
| **Mac idiom** | Pushover-style (Bartender, etc.) | Mail / Music / System Settings-style |
| **Engineering cost** | Lower (current path) | Higher (new DashboardWindow, sidebar nav) |
| **LSUIElement** | Yes (no Dock icon) | Adds "Show in Dock" toggle in Settings, OR keeps LSUIElement and surfaces Dashboard from the menubar |
| **Risk** | The "real Wispr alternative" is being a tool, not a product | Drift from "minimal" identity, build more before users want it |

**The `speak` v0 case for menubar-only:** the project's brand is "small, opinionated, native, Mac app." A 200pt sidebar with 7 items is a lot of chrome for a tool that's used 99% of the time without being seen. `speak` users are power users who don't need a dashboard.

**The `speak` v1 case for the dashboard:** modes + snippets + dictionary + transforms = 4+ surfaces that don't fit in a menubar dropdown. The popover (§2.13) is one option; a full window is the other. Wispr's evidence: the Home dashboard is the #1 reason their users open the app daily.

**Proposed decision (v0.1):** ship menubar-only for v0, **add the dashboard in v0.1 alongside the popover option.** The dashboard is the "rich" mode; the popover is the "fast" mode. Both surface from the menubar. The user picks their default in Settings.

**This is a [decision] for the human.** It changes the build order — `DashboardWindowController` becomes a v0.1 deliverable, not a v2+ aspirational surface. See §9 for the updated surface list.

---

## 9. Appendix A — Wispr-driven reorientation (v0.1 surface list)

This appendix updates the original §0–§5 in light of §1.6.

### A.1 New surface: Home dashboard (§2.14)

A full-window Dashboard that combines what was originally "Settings" +
"History" + new v1 surfaces into a single 2-pane app surface, accessible
from the menubar. The current `SpeakApp` `WindowGroup` model is
replaced with a `DashboardWindowController` (mirror of
`OnboardingWindowController`).

**Layout:**

```
┌────────────────────────────────────────────────────────────────────────┐
│ ⬛ 🟡 🟢  [tile]                                            [help] [⌘W]│
├──────────────┬─────────────────────────────────────────────────────────┤
│              │                                                          │
│  ⏶ speak     │  Welcome back. Press [fn] to start.                    │ ← hero (no name)
│              │                                                          │
│  ▦ Home      │  ─────────────────────────────────                      │
│  📖 History  │                                                          │
│  ⚙  Settings │  TODAY                                                  │
│  ?  Help     │  ┌──────────────────────────────────────────────────┐  │
│              │  │ 02:52 am   Amen.                                  │  │
│  ───v1+ ───  │  │ 02:51 am   Can you hear me?                       │  │
│  📖 Dictionary│  └──────────────────────────────────────────────────┘  │
│  ✂ Snippets   │                                                          │
│  Tt Style     │  YESTERDAY                                              │
│  ✨ Transforms│  ┌──────────────────────────────────────────────────┐  │
│  📄 Scratchpad│  │ 10:32 am  Hello world, this is a test.            │  │
│              │  │ 10:30 am  This is a longer dictation that wraps…  │  │
│              │  └──────────────────────────────────────────────────┘  │
│              │                                                          │
│              │  [Show older →]                                          │
│              │                                                          │
└──────────────┴─────────────────────────────────────────────────────────┘
                                                  880 × 640 (min)
```

**Components used:** `KeyCapView` (new — see §3.13), `Card`, day-grouped
list, sidebar nav (new — see §3.14).

**Sidebar IA (v0.1):**
- **Home** (the conversation log)
- **Settings** (the existing 4-section form, embedded as a tab in the dashboard)
- **Help** (a new lightweight Markdown viewer pointed at the GitHub README)

**v1 sidebar additions** (shown disabled / with a "coming in v1" badge):
- Dictionary
- Snippets
- Style
- Transforms
- Scratchpad

**Settings-as-tab (not window):** clicking Settings replaces the
content area with the existing form. No separate window. **This removes
the `SettingsWindowController` modal-window pattern.**

**Menubar + Dashboard coexistence:** the dashboard is opened via
"Open Dashboard…" in the menubar dropdown. It's a normal
`NSWindow` + `NSHostingView` (mirror of `OnboardingWindowController`).
The menubar icon stays the always-present surface; the dashboard is
user-invoked.

### A.2 Renamed v1 surfaces (terminology update)

| Original name (v0 ideation) | Wispr-aligned name (v0.1) | Why |
|---|---|---|
| Custom Vocabulary (v1) | **Dictionary** | Matches Wispr + MacWhisper; friendlier than "Vocabulary" |
| Modes (v1) | **Style** | Matches Wispr; clearer that these are formatting presets |
| AI Commands (v2) | **Transforms** | Matches Wispr; "transform" is the user-facing verb |
| (new) | **Scratchpad** | Wispr's quick-notes surface; strong power-user feature |
| (new) | **Insights** | Wispr's gamification (WPM, streak, total words, charts) |

### A.3 New v1 surface: Scratchpad (§2.15)

A quick-notes surface INSIDE `speak`. The user can dictate into the
scratchpad without pasting to an external app. The scratchpad is
persistent (stored locally), searchable, and exportable. It's the
"voice-only" mode for users who want a private journal / brain-dump
target.

**Layout (v1):**

```
┌──────────────────────────────────────────────────────────────────┐
│ speak — Scratchpad                                         ⊕ ⊗   │
├──────────────────────────────────────────────────────────────────┤
│  🔍 Search scratchpad                                             │
│  ─────────────────────────────────────────────────                │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │ Today, 10:32 AM                                            │  │
│  │                                                            │  │
│  │ The .env file has real API keys and credentials. We need   │  │
│  │ to test and validate everything, so can you create a new   │  │
│  │ branch and start working…                                  │  │
│  │                                                            │  │
│  │ ──────────────────────────────────────────                 │  │
│  │ Yesterday, 4:36 AM                                         │  │
│  │ …                                                          │  │
│  └────────────────────────────────────────────────────────────┘  │
│  ─────────────────────────────────────────────────                │
│  [+ New Entry]  [Export…]                                         │
└──────────────────────────────────────────────────────────────────┘
                                                  640 × 600 (min)
```

**Why this matters:** a major use case for voice dictation is "I need
to brain-dump right now and I don't have a text editor open." The
scratchpad IS the text editor. The user double-taps Fn, the HUD
appears, the user speaks, and the text lands in the scratchpad (not
at a cursor). The flow is: open app → press Fn → speak → press Fn
→ done. No need to switch to another app.

**Implementation:** new `ScratchpadStore` (similar to `HistoryStore`).
A toggle in Settings: "When no cursor is detected, paste into
Scratchpad instead of doing nothing." Default OFF in v0.1 (defer the
auto-detect); ON in v1 (detect via `AXUIElement.focusedUIElement`).

### A.4 New v2 surface: Insights (§2.16)

A gamification / analytics surface. Tracks:
- **Total words** dictated (cumulative + per week)
- **WPM** (words per minute) — the personal speed stat
- **Day streak** — consecutive days with at least one dictation
- **Active hours** — heatmap of when the user dictates
- **Top snippets** — most-used voice commands
- **Engine usage** — breakdown of STT/cleanup engines used

**Layout (v2 — Wispr-style hero stats):**

```
┌──────────────────────────────────────────────────────────────────┐
│ speak — Insights                                           ⊕ ⊗   │
├──────────────────────────────────────────────────────────────────┤
│  This week                                                       │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │  1,565   total words                                        │  │   ← LARGE SERIF
│  │     94   wpm                                               │  │     (32pt serif)
│  │      2   day streak                                        │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                                  │
│  Activity                                                        │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │  ▁▂▅█▇▃▁▂▄  (12-week bar chart, weekly word count)          │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                                  │
│  Top snippets                                                     │
│  • period (×147)                                                 │
│  • new line (×83)                                                │
│  • my email (×21)                                                │
│                                                                  │
│  Engines used                                                     │
│  • Apple Speech      98%                                         │
│  • Foundation Models 92%                                         │
└──────────────────────────────────────────────────────────────────┘
```

**The big design question for Insights:** the LARGE SERIF numbers
(Wispr's signature) are an opinionated move. Two valid options:
- **Adopt serif** (mirror Wispr — premium / editorial feel; clashes
  slightly with Mac minimalism; can be a "Wispr import" tell).
- **Stay sans-serif** (the rest of `speak` is SF Pro; serif numbers
  feel inconsistent; cleaner Mac idiom).

**Proposal: stay sans-serif in v2 but bump the size to 40pt.** This
gives the same "hero stat" feel without the serif. If the human wants
serif, easy switch via `Tokens.Typography.StatNumber.font`.

### A.5 Updated component catalog (additions)

#### 3.13 `KeyCapView(label: String, color: Color)` (new)

A styled keyboard-key visual. Used in:
- Onboarding (the "fn" key in the hotkey step)
- Dashboard hero ("Press [fn] to start")
- Settings (current hotkey display, next to the rebind button)
- Onboarding done step

**Layout:**

```
┌──────┐
│  fn  │   ← ~36 × 32 pt, rounded rect (6 pt), orange/rust background,
└──────┘     black "fn" text, 14 pt SF Pro Rounded medium, center-aligned
```

**Variants:** `KeyCapView(.fn)`, `KeyCapView(.globe)`, `KeyCapView(.cmd)`,
`KeyCapView(.cmdShift("Space"))` — the modifier+key combined glyph.

**Why a component:** the same visual is used in 4+ places. Without a
component, each one will diverge (different rounding, different
shadows, different padding).

#### 3.14 `Sidebar<Content: View>(items: [SidebarItem], selection: Binding<SidebarItem.ID>, content: Content)` (new)

A two-pane container with the standard Mac sidebar:
- 200pt fixed width
- Item rows: icon + label, ~32 pt tall
- Selection: soft warm-gray rounded rect background
- Vertical scroll if items > available height
- Divider above the footer items

**API sketch:**

```swift
struct SidebarItem: Identifiable, Hashable {
    let id: String
    let icon: String  // SF Symbol name
    let label: String
    let badge: String?  // optional "v1" pill
    let isEnabled: Bool  // false → show but disabled
}

struct Sidebar<Content: View>: View {
    let items: [SidebarItem]
    @Binding var selection: String
    let content: Content
    // …
}
```

#### 3.15 `DayGroupedList(entries: [HistoryEntry])` (new)

A list view that groups entries by day and renders each group as a
card with an uppercase letter-spaced day label above.

**Layout:**

```
TODAY                                          ← 11pt uppercase, letter-spaced 1.5
┌──────────────────────────────────────────┐
│ 02:52 am  Amen.                          │
│ 02:51 am  Can you hear me?               │
└──────────────────────────────────────────┘

YESTERDAY
┌──────────────────────────────────────────┐
│ 04:36 am  The .env file has real…        │
│ 03:18 am  Understand the project…        │
└──────────────────────────────────────────┘
```

**Why a component:** this is the Home dashboard's primary content.
Without a component, the dashboard view grows and the grouping logic
leaks.

#### 3.16 `StatTile(value: String, label: String, font: Font)` (new, v2)

A large-number + small-label tile for the Insights hero. Used 3-up
in a row.

**Layout:**

```
┌─────────────┐
│  1,565      │   ← 40pt sans (or 32pt serif), bold
│  total words│   ← 13pt secondary, regular
└─────────────┘
```

---

## 10. What this reorientation means for the build order

The original `docs/roadmap.md` (P0–P14) is unchanged — `speak` is still
v0-complete on the engine, the HUD, the paste, the history, the
settings, the menubar. The new surfaces (Dashboard, Scratchpad,
Insights, Dictionary, Style, Transforms) are **v0.1+ additions** and
do not change the v0 ship gate.

**v0.1 build sequence (proposed, after the reorientation):**

1. **`SpeakCore/UI/Tokens.swift`** — the design-token seam (no magic
   numbers in views). Unblocks everything else.
2. **`App/UIComponents/KeyCapView.swift`** — used in 4+ places.
3. **`App/UIComponents/Sidebar.swift`** + `SidebarItem` — unblocks the
   dashboard.
4. **`App/Dashboard/DashboardWindowController.swift`** — the full
   window, mirror of `OnboardingWindowController`.
5. **`App/Dashboard/DashboardView.swift`** — the 2-pane layout, Home
   tab first.
6. **`App/Dashboard/HistoryViewModel`** rewrite — add day-grouping, full
   text (no lineLimit), empty-row handling.
7. **Settings-as-tab** — refactor `SettingsView` from a window scene to
   a tab in the dashboard. Deprecate `SettingsWindowController`.
8. **Menubar "Open Dashboard…" item** — wire to `DashboardWindowController.show()`.
9. **Help tab** — a simple Markdown viewer pointed at the GitHub README.
10. **v1 surface scaffolding** — Dictionary / Snippets / Style /
    Transforms / Scratchpad tabs (initially empty placeholders with
    "coming in v1" badges).
11. **Insights tab** (v2) — the gamification surface.

This sequence is **backwards-compatible with the v0 ship**: each
deliverable is additive, no existing code is changed (except the
Settings-as-window → Settings-as-tab refactor in step 7, which is a
targeted move, not a rewrite).

---

*End of reorientation. The original doc (§0–§8) is preserved verbatim
above; the v0.1 surface list is in §9. Both are ideation, not
contract — promote to `roadmap.md` / `product.md` when the human
approves the dashboard + the IA changes.*

---

## 11. Wispr Flow surface deep-dive (recall-based — awaiting screenshot verification)

> **Honesty boundary:** this section is built from **memory of Wispr Flow's
> UI** as of 2025–2026. I have only **one verified screenshot** (the Home
> dashboard in §1.6). Every claim below is tagged:
> - `[verified]` — corroborated by the Home dashboard screenshot
> - `[recall:high]` — well-documented public UX, multiple sources
> - `[recall:med]` — known feature, but specific UI details uncertain
> - `[recall:low]` — educated guess; needs screenshot verification
>
> **What I need from you to upgrade this section to `[verified]`:**
> 1. Screenshot of the **recording HUD / voice capture** (the floating pill
>    in active recording state)
> 2. Screenshot of the **edit-before-paste expansion** (the post-stop
>    review state)
> 3. Screenshot of the **device / microphone picker**
> 4. Screenshot of the **Settings** main page (or any Settings tab)
> 5. Screenshot of the **voice profile setup** during onboarding
> 6. Screenshot of the **Dictionary** editor
> 7. Screenshot of the **Snippets** editor
> 8. Screenshot of the **Style / Modes** editor
> 9. Screenshot of the **Transforms** editor
> 10. Screenshot of the **Insights** page (analytics / gamification)
> 11. Screenshot of the **Scratchpad** view
> 12. Screenshot of the **menubar dropdown** (the click-menu)
>
> Each surface below has the screenshot it needs called out in the
> "Verification" subsection. Send them in any order; I'll iterate.

### 11.1 Device input / microphone picker `[recall:med]`

**Goal:** Let the user pick which microphone `speak` listens on, see
the live level for each device, and detect when devices are added /
removed (e.g., AirPods connect).

**Where it lives in Wispr:** Settings → Audio & Devices, OR a tab in
the main settings pane. `[recall:med]`

**The `speak` shape (proposed):**

```
┌────────────────────────────────────────────────────────────────┐
│ speak — Audio & Devices                                  ⊕ ⊗   │
├────────────────────────────────────────────────────────────────┤
│  Microphone                                                    │
│  ─────────────────────────────────────────────────              │
│  ○ MacBook Pro Microphone          [▌▌▌▌▌▌]  −12 dB             │  ← live level
│  ● AirPods Pro                     [▌▌▌]      −24 dB  ✓         │  ← selected
│  ○ USB Microphone (Apogee)         [▌▌▌▌▌▌▌] −8  dB             │
│  ○ Plantronics Headset             [▌]        −48 dB             │
│  ─────────────────────────────────────────────────              │
│  [+ Refresh]  [System Sound Settings…]                         │
│                                                                │
│  When dictation starts                                          │
│  ○ Auto-select last used                                          │
│  ● Always prompt (v1)                                            │
│                                                                │
│  Noise suppression (v0.1)                                       │
│  ☐ Use macOS noise suppression when available                  │
│                                                                │
│  Test microphone                                                │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  [▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌]  −6 dB                  │  │
│  │  Say "testing, testing, one two three"                   │  │
│  │  [Stop test]                                             │  │
│  └──────────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────────┘
```

**Components used:** `List` with radio-style selection, `LevelMeterView`
(§3.3, large variant for the test), `Toggle` for noise suppression,
`Button` for the test.

**Per-row live level:** every device in the list shows a real-time
level meter when it's selected (or when the user hovers). This is the
"is my mic actually picking up sound" affordance — invaluable when
diagnosing "Wispr / speak isn't hearing me." The level source is
`AVAudioEngine` input-node RMS for each device.

**Verification needed:** screenshot of Wispr's audio device picker. The
device list, the level meter placement, the noise suppression toggle,
and the test affordance are all `[recall:med]` — Wispr has had varying
UIs here over the last 2 years.

**Edge cases:**
- Bluetooth device disconnects mid-dictation → fall back to system
  default with a toast: "AirPods disconnected — using MacBook mic."
- Multiple input devices with the same name (e.g., two AirPods) →
  show "AirPods Pro — A" / "AirPods Pro — B" using BT address
  disambiguation. `[recall:low]`
- No input device available → block the start, show a recovery banner
  (matches the existing permission recovery surface §2.6).

### 11.2 Voice capture / recording HUD (the pill) `[recall:high]`

**Goal:** Show the user that dictation is in progress, stream the
partial transcript live, and provide post-stop edit + paste affordances.

**Where it lives:** a **top-center floating NSPanel**, always on top,
non-focus-stealing. Wispr's signature surface.

**The `speak` shape (we built this in §2.3; recalling Wispr's variant
here for the comparison):**

```
   ┌──────────────────────────────────────────────────────────┐
   │                                                          │
   │             ┌──────────────────────────────────┐         │
   │             │  ▌▌▌▌▌▌▌  "the quick brown fox"  │         │   ← top-center floating pill
   │             │                                  │         │     ~480 × 80 pt
   │             │  [paste in 1.4s]                 │         │     frosted glass
   │             └──────────────────────────────────┘         │
   │                                                          │
   └──────────────────────────────────────────────────────────┘
```

**Three Wispr states `[recall:high]`:**

#### 11.2.1 Recording (the active pill)

- **Position:** top-center of the focused screen, ~80pt from the
  top edge (clear of the menubar/notch).
- **Shape:** rounded pill, ~480 × 80 pt, frosted glass.
- **Content (left → right):**
  - **Sound wave** (5–7 vertical bars) — the live mic level
  - **Live partial transcript** — streaming text, single line
  - **Duration counter** — "0:04" in 11pt secondary, right-aligned
  - **Cancel button** — small `x` in the top-right
- **Animation:** the wave bars react to the mic level in real time
  (not a breathing animation — actual mic data). `[recall:high]`
- **Color:** white text on translucent dark background OR dark text
  on translucent light, depending on the system appearance. Adaptive.
- **Reference:** this is the cautionary tale referenced in
  `dictation-flow.md` §4. The "top-center" position is what we
  *reject* in favor of bottom-center. We adopt every other detail.

#### 11.2.2 Edit-before-paste (the expansion) `[recall:high]`

This is Wispr's **killer feature**. After the user stops, the pill
**expands** vertically to ~480 × 220 pt, showing:

```
   ┌──────────────────────────────────────────────────────────┐
   │  ┌──────────────────────────────────────────────────┐   │
   │  │ "the quick brown fox jumps over the lazy dog"    │   │   ← editable text
   │  │                                                    │   │     (TextEditor)
   │  │ "send it."                                          │   │
   │  └──────────────────────────────────────────────────┘   │
   │                                                            │
   │  [Cancel]                  Editing · paste in 1.2s         │
   │                                                            │
   │  [Paste]   ⌘↩                                              │   ← default action
   └──────────────────────────────────────────────────────────┘
```

**Key details `[recall:high]`:**
- **Auto-paste countdown** — visible in the footer ("paste in 1.2s").
  The user can tap anywhere in the text to **pause** the countdown
  (so the user has time to edit). This is a genius UX move: the
  default is "paste immediately" but the user can intervene by
  tapping. No explicit "Edit" toggle needed.
- **Edit affordance:** the text is a real `TextEditor` — the user
  can click in, fix a word, delete a word, add a word. The partial
  transcript becomes a *real* document for 2 seconds.
- **Default action:** `⌘↩` to paste, `Esc` to cancel. Power-user
  shortcuts.
- **Sub-second per-word delays** are visible — the pill flickers
  open and then auto-pastes. The animation is so smooth that the
  user *thinks* they pasted directly, but they actually had a 2s
  review window.
- **Tap-to-pause** the countdown is the killer pattern. We adopt
  it.

**The `speak` v1 plan:** this is the "edit-before-paste toggle" from
the original §2.3.5 ideation. We deferred it to v1 because (a) it
breaks the "feels like the cursor typed it" magic, and (b) it's a
v1 surface that needs its own design pass. The Wispr version gives
us the template: countdown + tap-to-pause.

#### 11.2.3 Done (auto-fade)

- After paste (or after the countdown elapses), the pill collapses
  back to ~80 pt and shows a green ✓ for 400 ms.
- Then it fades out over 200 ms.
- The auto-fade is **fast** — the user shouldn't be left staring
  at a "done" indicator for more than half a second.

**Verification needed:** screenshots of (1) the active recording pill,
(2) the edit-before-paste expansion. The exact dimensions, the
countdown visibility, and the auto-paste timing are `[recall:med]`.

### 11.3 Settings (the main settings page) `[recall:high]`

**Goal:** Surface every user-tunable in a discoverable, organized way.

**Where it lives:** in the sidebar — `Settings` is one of the 4 footer
items (matches §1.6 observation #21). The Settings "tab" replaces the
content area of the dashboard.

**The `speak` shape (Wispr-style):**

```
┌──────────────┬─────────────────────────────────────────────────────┐
│              │                                                     │
│  ⏶ speak     │  Settings                                           │  ← content title
│              │  ───────────────────────────────────────            │
│  ▦ Home      │                                                     │
│  📖 History  │  General                                            │  ← section
│  ⚙  Settings │  ───────────────────────────────                   │
│  ?  Help     │  Display name          [Tamilarasan           ]    │  ← text field
│              │  Language              [English (US)        ▾]    │
│  ───v1+ ───  │  Hotkey                [fn (double-tap)      ▾]    │
│              │  Theme                 [● System  ○ Light  ○ Dark]  │
│  📖 Dict.    │                                                     │
│  ✂ Snippets   │  Audio                                                 │
│  Tt Style    │  ───────────────────────────────                   │
│  ✨ Transform│  Microphone           [AirPods Pro          ▾]    │
│  📄 Scratchp │  Noise suppression    [☐ Use macOS]                │
│  📊 Insights │  Audio feedback       [● On  ○ Off]                │
│              │                                                     │
│              │  Cleanup                                                 │
│              │  ───────────────────────────────                   │
│              │  AI cleanup           [● On  ○ Off]                │
│              │  Cleanup model        [Foundation Models   ▾]    │
│              │  Cleanup level        [Balanced             ▾]    │
│              │                                                     │
│              │  Privacy                                                │
│              │  ───────────────────────────────                   │
│              │  ✓ Audio never leaves this Mac                     │
│              │  History retention     [30 days  ▾]                │
│              │  [Export history]  [Delete all history]            │
│              │                                                     │
└──────────────┴─────────────────────────────────────────────────────┘
```

**Sections (Wispr-style, 5 sections vs my 4):**
1. **General** — display name, language, hotkey, theme
2. **Audio** — microphone picker, noise suppression, audio feedback
3. **Cleanup** — AI cleanup toggle, model, level (Basic / Balanced / Thorough)
4. **Privacy** — the moat claim, history retention, export/delete
5. **Account** — Wispr has this; speak skips (no account)

**What I missed in my original §2.4:**
- **Display name** (the user sets their name in onboarding → used in
  dashboard hero and reports)
- **Theme override** (System / Light / Dark — a Mac idiom that
  native SwiftUI handles for free)
- **Cleanup level** (a single picker for "how much should the AI
  rewrite" — Basic / Balanced / Thorough. Maps to different
  `LLMCleaning` prompts)
- **Audio feedback** (a sound when dictation starts/stops — like
  VoiceInk's "ka-chunk" sound. Optional, off by default)
- **History retention** (30 days / 90 days / forever — currently
  speak has a `maxEntries` cap; retention is a different axis)

**Privacy section:** this is the **most important section** for `speak`.
Wispr's privacy section is buried; we put it **second from the
bottom**, prominent, with the moat claim as a read-only green
check. The export/delete affordances live here too.

**Verification needed:** a screenshot of Wispr's Settings to confirm
the section breakdown and the order. The exact names of the sections
(`General / Audio / Cleanup / Privacy` vs. my `Activation /
Transcription / AI Cleanup / Text Insertion`) are `[recall:med]`.

### 11.4 Voice profile setup (onboarding-specific) `[recall:med]`

**Goal:** Record 2–3 sample sentences from the user to "personalize"
the voice model. Wispr uses this for the "Voice Profile" feature
that unlocks after enough data; `speak` can skip this (Apple
SpeechAnalyzer personalizes automatically based on usage).

**Where it lives:** after the accessibility permission step, before
the hotkey step in onboarding. Optional, with a "Skip" link.

**The shape (Wispr):**

```
┌────────────────────────────────────────────────┐
│  ● ● ● ● ●                                     │
│                                                │
│           ┌────────────────────┐               │
│           │ 🎙  (microphone)   │               │
│           └────────────────────┘               │
│                                                │
│      Personalize your voice profile            │  ← title
│                                                │
│   Read these 3 sentences aloud so we can       │  ← body
│   learn how you speak. Takes 30 seconds.       │
│                                                │
│   ┌────────────────────────────────────────┐   │
│   │ Sentence 1 of 3                         │   │  ← sample text
│   │ "The quick brown fox jumps over the     │   │     in a card
│   │  lazy dog while the rain patters        │   │
│   │  softly on the window."                 │   │
│   └────────────────────────────────────────┘   │
│                                                │
│            ┌──────────────┐                    │
│            │  I'm Ready   │                    │
│            └──────────────┘                    │
│                                                │
│   ☐ Skip — I don't want a profile              │
│                                                │
└────────────────────────────────────────────────┘
```

**On click "I'm Ready":**
- The card becomes a recording indicator
- The user reads the sentence
- A progress bar fills
- "Great! Next sentence →"
- Repeat 3 times
- "All done! Your voice profile is ready."
- Auto-advance

**For `speak`:** this is **explicitly skipped**. Apple `SpeechAnalyzer`
adapts to the user's voice over time without explicit enrollment. We
do NOT need this step. The onboarding stays at 5 steps (welcome →
mic → ax → im → hotkey → done).

**However:** the "Voice Profile Unlocked" milestone from the Home
dashboard *could* be repurposed. After ~50 dictations, show a
celebration: "speak has learned your voice — your transcripts are now
~X% more accurate on average." (We'd need to measure this; speculative.)

**Verification needed:** screenshot of Wispr's voice profile setup
flow. The exact copy, the number of sentences (I've assumed 3), and
the skip flow are all `[recall:med]`.

### 11.5 Dictionary (custom vocabulary) `[recall:med]`

**Goal:** Manage the user's list of custom words the STT engine
should listen for. Useful for names, jargon, technical terms.

**Where it lives:** a sidebar item (renamed from "Custom Vocabulary"
in §9.2). A new dashboard tab.

**The `speak` shape (Wispr-style):**

```
┌──────────────┬─────────────────────────────────────────────────────┐
│              │                                                     │
│   ...        │  Dictionary                                         │
│              │  ───────────────────────────────────────            │
│  📖 Dict. ←  │                                                     │
│              │  🔍 Search words                                     │
│              │  ───────────────────────────────────────            │
│              │  ┌─────────────────────────────────────────────┐  │
│              │  │ Word         Pronunciation?   Source          │  │
│              │  │ ────────────────────────────────────────    │  │
│              │  │ Tamil        (auto)            Manual         │  │
│              │  │ Speakanalyzer(speak-AN-al-yzer)Manual         │  │
│              │  │ WisprFlow    (wisper-flow)      Manual         │  │
│              │  │ AppIntents   (app-IN-tents)     Manual         │  │
│              │  │ Cgeventtap   (cg-EVENT-tap)     Manual         │  │
│              │  │ ...                                           │  │
│              │  └─────────────────────────────────────────────┘  │
│              │                                                     │
│              │  [+ Add Word]  [Import from contacts]  [Export]     │
└──────────────┴─────────────────────────────────────────────────────┘
```

**Components:**
- Search bar at the top (matches History's pattern, §3.12)
- Table view with columns: word, pronunciation hint, source
- Source column: "Manual" (user-added) / "Contacts" (imported) /
  "Auto-learned" (speak detected a repeated word and added it)

**The pronunciation hint column** is interesting — Wispr lets you
specify how a word is pronounced, which the STT engine uses as a
bias. For `speak`, Apple `SpeechAnalyzer` supports a
`SFSpeechLanguageModel` with `addToVocabulary(phrase:pronunciation:)`
method `[recall:med]`.

**"+ Add Word" affordance:**
- Inline form with two fields: Word, Pronunciation (optional)
- `Return` to save
- Validation: no duplicates (case-insensitive), max 100 chars,
  no whitespace inside a single word

**"Import from contacts"** (v1.1):
- Opens the macOS Contacts picker
- User picks which contacts to import
- We add first name, last name, organization from each
- Permission: `NSContactsUsageDescription` in Info.plist
- `[recall:med]` — Wispr has this feature; we add it in v1.1

**Verification needed:** screenshot of Wispr's Dictionary editor.
The exact columns, the pronunciation field, the contacts import
flow, and the "auto-learned" source are all `[recall:med]`.

### 11.6 Snippets (voice commands) `[recall:high]`

**Goal:** Manage voice commands — trigger phrases that expand to
text. Wispr ships with ~50 built-in snippets; users can add their own.

**Where it lives:** a sidebar item. A new dashboard tab.

**The `speak` shape (Wispr-style):**

```
┌──────────────┬─────────────────────────────────────────────────────┐
│              │                                                     │
│   ...        │  Snippets                                           │
│              │  ───────────────────────────────────────            │
│  ✂ Snippets ←│                                                     │
│              │  🔍 Search snippets                                  │
│              │  [Built-in ▾]  [Personal]  [All]                    │  ← tabs
│              │  ───────────────────────────────────────            │
│              │  ┌─────────────────────────────────────────────┐  │
│              │  │ Trigger           → Expansion              │  │
│              │  │ ────────────────────────────────────────    │  │
│              │  │ "period"          → .                      │  │
│              │  │ "comma"           → ,                      │  │
│              │  │ "question mark"   → ?                      │  │
│              │  │ "exclamation"     → !                      │  │
│              │  │ "new line"        → \n                     │  │
│              │  │ "new paragraph"   → \n\n                   │  │
│              │  │ "open paren"      → (                      │  │
│              │  │ "close paren"     → )                      │  │
│              │  │ "colon"           → :                      │  │
│              │  │ "semicolon"       → ;                      │  │
│              │  │ ─── Personal ───                            │  │
│              │  │ "my email"        → tamil@example.com      │  │
│              │  │ "lgtm"            → Looks good to me.      │  │
│              │  │ "ship it"         → 🚀                     │  │
│              │  └─────────────────────────────────────────────┘  │
│              │                                                     │
│              │  [+ Add Snippet]  [Import…]  [Export…]             │
└──────────────┴─────────────────────────────────────────────────────┘
```

**Components:**
- Search bar
- Tabbed filter: Built-in / Personal / All
- Table view with two columns: Trigger, Expansion
- A subtle separator between "Built-in" and "Personal" snippets
  (this is a design detail Wispr does well — it visually
  distinguishes "shipped" from "yours")

**Built-in snippets (v1 ships):**
- The 10 voice punctuation commands from §2.8
- Plus a few common developer shortcuts: "code block" → "```\n\n```",
  "bullet" → "  - ", "tab" → "  " (configurable 2 or 4)

**"+ Add Snippet" affordance:**
- Inline form: Trigger, Expansion, optional Description
- Validation: trigger must be unique (case-insensitive),
  trigger must contain only lowercase + spaces (enforced pattern)
- Trigger phrases should be 1–3 words (UX guideline)

**Per-app snippets (v1.1):** `[recall:med]`
- Wispr lets you scope a snippet to a specific app (e.g., "send it"
  in Slack → 🚀, in email → "Best, Tamil")
- `speak` v1.1: optional per-app scope. The picker shows
  "Global / This app only" radio.

**The interaction order is important `[recall:high]`:**
- Snippets run **before** the LLM cleanup (so a snippet like
  "period" becomes "." and the LLM doesn't re-process it)
- A snippet that inserts punctuation *tells* the cleanup engine
  to skip punctuation (via a special token in the transcript)
- This is the open question from §2.8. Wispr's behavior is the
  reference.

**Verification needed:** screenshot of Wispr's Snippets editor.
The exact built-in snippet list, the per-app scope UI, the
trigger-phrase validation, and the import/export format are all
`[recall:med]`.

### 11.7 Style (modes / formatting presets) `[recall:high]`

**Goal:** Define named formatting presets that bundle a cleanup
prompt + optional formatting rules. The user picks a mode before
dictating (or it auto-switches per-app).

**Where it lives:** a sidebar item. A new dashboard tab.

**The `speak` shape (Wispr-style):**

```
┌──────────────┬─────────────────────────────────────────────────────┐
│              │                                                     │
│   ...        │  Style                                              │
│              │  ───────────────────────────────────────            │
│  Tt Style  ← │                                                     │
│              │  ┌─────────────────────────────────────────────┐  │
│              │  │  ●  Default                                  │  │  ← active mode
│              │  │     Casual, friendly, with filler removal   │  │     (radio button)
│              │  │                                                │  │
│              │  │  ○  Professional                               │  │
│              │  │     Formal, no contractions, terse           │  │
│              │  │                                                │  │
│              │  │  ○  Casual                                     │  │
│              │  │     Relaxed, keeps "yeah" and "gonna"        │  │
│              │  │                                                │  │
│              │  │  ○  Code                                       │  │
│              │  │     Code-aware, preserves variable names     │  │
│              │  │                                                │  │
│              │  │  ○  Email                                      │  │
│              │  │     Greeting/sign-off aware, formal           │  │
│              │  └─────────────────────────────────────────────┘  │
│              │                                                     │
│              │  Active mode: Default                               │
│              │  [Edit cleanup prompt…]   [Reset to default]         │
│              │                                                     │
│              │  [Apply to all apps]  [Per-app overrides →]         │
└──────────────┴─────────────────────────────────────────────────────┘
```

**5 built-in modes (Wispr-style):**
1. **Default** — casual, friendly, with filler removal
2. **Professional** — formal, no contractions, terse
3. **Casual** — relaxed, keeps "yeah" and "gonna"
4. **Code** — code-aware, preserves variable names, no filler
5. **Email** — greeting/sign-off aware, formal

**`[recall:med]`** — Wispr's mode list is more dynamic (users can
create custom modes). The 5 above are the most common shipped modes
across the category.

**Per-app overrides (v1.1) `[recall:med]`:**
- "Per-app overrides →" opens a sub-view
- Lists frontmost apps seen (from `NSWorkspace.runningApplications`)
- User picks a default mode per app
- The mode auto-switches when the frontmost app changes (with a
  brief menubar icon update)

**"Edit cleanup prompt…" affordance:**
- Opens a sheet with a multi-line text editor
- Shows the current prompt (the `LLMCleaning` system prompt for
  this mode)
- User can edit; `Save` writes back to the per-mode setting
- `Reset to default` restores the shipped prompt

**Implementation in `speak`:** `[decision]`
- v0.1: ship the 5 built-in modes + 1 active mode selection
- v1: custom mode editor (name + prompt + optional icon)
- v1.1: per-app overrides

**Verification needed:** screenshot of Wispr's Style editor.
The exact built-in mode names, the per-app override UI, the
custom-mode editor, and the active-mode indicator are all
`[recall:med]`.

### 11.8 Transforms (AI commands) `[recall:high]`

**Goal:** Define text-rewrite commands. User selects text in any
app, invokes a transform via hotkey, and the local LLM applies it.

**Where it lives:** a sidebar item. A new dashboard tab.

**The `speak` shape (Wispr-style):**

```
┌──────────────┬─────────────────────────────────────────────────────┐
│              │                                                     │
│   ...        │  Transforms                                         │
│              │  ───────────────────────────────────────            │
│  ✨ Transf. ←│                                                     │
│              │  Select text in any app, then:                      │
│              │                                                     │
│              │  ┌─────────────────────────────────────────────┐  │
│              │  │  Hotkey    Name              Description      │  │
│              │  │ ────────────────────────────────────────    │  │
│              │  │  ⌥⌘R      Rephrase           Rewrite clearly │  │
│              │  │  ⌥⌘S      Make shorter       Condense        │  │
│              │  │  ⌥⌘L      Make longer        Expand          │  │
│              │  │  ⌥⌘F      Fix grammar        Correct         │  │
│              │  │  ⌥⌘T      Translate          Pick language…  │  │
│              │  │  ⌥⌘B      Bullet list        • item 1        │  │
│              │  │  ⌥⌘N      Numbered list      1. item 1       │  │
│              │  │  ⌥⌘E      Explain (for code) Add comments     │  │
│              │  │  ⌥⌘P      Proofread          Tighten copy    │  │
│              │  │  ⌥⌘H      Humanize           Less robotic    │  │
│              │  │ ─── Custom ───                              │  │
│              │  │  ⌥⌘1      Friendlier         …               │  │
│              │  │  ⌥⌘2      Shakespearean      …               │  │
│              │  └─────────────────────────────────────────────┘  │
│              │                                                     │
│              │  [+ Add Transform]  [Reset all to defaults]         │
└──────────────┴─────────────────────────────────────────────────────┘
```

**Built-in transforms (Wispr ships ~10–12):**
1. **Rephrase** ⌥⌘R
2. **Make shorter** ⌥⌘S
3. **Make longer** ⌥⌘L
4. **Fix grammar** ⌥⌘F
5. **Translate** ⌥⌘T (opens language picker)
6. **Bullet list** ⌥⌘B
7. **Numbered list** ⌥⌘N
8. **Explain (for code)** ⌥⌘E
9. **Proofread** ⌥⌘P
10. **Humanize** ⌥⌘H

**The interaction flow `[recall:high]`:**
- User selects text in any app (Slack, email, code editor)
- Presses the transform hotkey (e.g., ⌥⌘S)
- A small **popover** appears near the selection with:
  - Loading spinner + "Rewriting…"
  - After ~1–2s, the rewritten text
  - **Undo** button (restores the original)
  - **Apply** button (replaces the selection, default action)
  - `Esc` to cancel

**Why this is a v2 surface (not v0.1) `[recall:high]`:**
- Requires text-selection detection (`AXUIElement` focused range)
- Requires per-app integration (text replacement varies — rich text
  fields, code editors, terminal, all behave differently)
- The LLM cost is non-trivial (rewriting 100 words = ~300 tokens
  in/out, ~1.5s on Apple Foundation Models)
- The user-facing risk is high: "my text got rewritten and I lost
  what I wrote" is a bad outcome

**`speak` v2 plan:**
- Ship the 10 built-in transforms with hardcoded `⌥⌘` + letter
  hotkeys
- Use a single "Transform" popover for all transforms (with the
  result + Apply/Undo)
- Per-app selection extraction (rich text vs plain text vs
  markdown) is the engineering risk

**Verification needed:** screenshot of Wispr's Transforms editor
AND the live popover. The exact hotkey letters, the popover layout,
and the per-app behavior are all `[recall:med]`.

### 11.9 Insights (analytics / gamification) `[recall:med]`

**Goal:** Show the user how much they've dictated, their speed
(WPM), their consistency (streak), and a few other vanity metrics.

**Where it lives:** a sidebar item. A new dashboard tab.

**The `speak` shape (Wispr-style):**

```
┌──────────────┬─────────────────────────────────────────────────────┐
│              │                                                     │
│   ...        │  Insights                                           │
│              │  ───────────────────────────────────────            │
│  📊 Insights←│                                                     │
│              │  This week                                           │
│              │  ┌─────────────────────────────────────────────┐  │
│              │  │  1,565  total words                           │  │   ← hero stats
│              │  │     94  wpm                                  │  │     (serif)
│              │  │      2  day streak                           │  │
│              │  └─────────────────────────────────────────────┘  │
│              │                                                     │
│              │  Activity (last 12 weeks)                          │
│              │  ┌─────────────────────────────────────────────┐  │
│              │  │     ▁▂▅█▇▃▁▂▄▁                             │  │   ← bar chart
│              │  │  W1 W2 W3 W4 W5 W6 W7 W8 W9 W10 W11 W12    │  │
│              │  └─────────────────────────────────────────────┘  │
│              │                                                     │
│              │  Top snippets                                       │
│              │  • period (×147)                                    │
│              │  • new line (×83)                                   │
│              │  • my email (×21)                                   │
│              │                                                     │
│              │  Top apps                                           │
│              │  • TextEdit (×234)                                  │
│              │  • Slack (×189)                                     │
│              │  • Cursor (×87)                                     │
│              │                                                     │
│              │  Active hours (heatmap)                            │
│              │  ┌─────────────────────────────────────────────┐  │
│              │  │  12a ┌──┐                                   │  │
│              │  │  6a  │  │                                   │  │
│              │  │  12p ┌──┐  ┌──┐                            │  │
│              │  │  6p  │  │  │  │                            │  │
│              │  └─────────────────────────────────────────────┘  │
└──────────────┴─────────────────────────────────────────────────────┘
```

**Sections (Wispr's pattern):**
1. **Hero stats** — 3 large numbers (total words, WPM, streak)
2. **Activity chart** — bar chart of weekly word count (12 weeks)
3. **Top snippets** — most-used voice commands
4. **Top apps** — most-dictated-into apps (from the focused app
   at the time of dictation)
5. **Active hours** — a heatmap of when the user dictates
6. **Achievements** — milestone unlocks ("First 100 words",
   "1-week streak", "1,000 total words", etc.)

**`[recall:med]`** on the exact layout. Wispr's Insights has had
several redesigns in 2025; the above is the most common shape.

**For `speak`:**
- v2 ships 4 of the 6 sections (skip Top apps and Achievements —
  Top apps has privacy implications, Achievements is freemium
  growth lever we don't need)
- v3 ships Achievements as a freemium-style "milestone" surface
  (for free, no paywall — just delightful)
- Top apps is **privacy-sensitive** — it requires logging which
  app was frontmost at dictation time. v2: opt-in (default OFF).
  v3: removed (the data isn't needed).

**Data sources:**
- total words: `HistoryEntry.cleanedText.wordCount` (or
  `rawText.wordCount` if cleaned is nil)
- WPM: `HistoryEntry.wordCount / duration.minutes`
- streak: consecutive days with at least one entry
- weekly chart: grouped by week
- top snippets: requires the snippet usage to be logged (v2 only)

**Verification needed:** screenshot of Wispr's Insights page. The
exact chart types, the metrics, the achievements, and the
heatmap are all `[recall:med]`.

### 11.10 Scratchpad (quick notes) `[recall:med]`

**Goal:** A persistent note-taking surface inside `speak`. The user
can dictate into the scratchpad without focusing an external app.

**Where it lives:** a sidebar item. A new dashboard tab.

**The `speak` shape (Wispr-style):**

```
┌──────────────┬─────────────────────────────────────────────────────┐
│              │                                                     │
│   ...        │  Scratchpad                                         │
│              │  ───────────────────────────────────────            │
│  📄 Scratch.←│                                                     │
│              │  ┌─────────────────────────────────────────────┐  │
│              │  │ Today                                         │  │
│              │  │ ────────────────────────────────────────    │  │
│              │  │  10:32 am                                     │  │
│              │  │  "The .env file has real API keys and        │  │
│              │  │   credentials. We need to test and            │  │
│              │  │   validate everything…"                       │  │
│              │  │                                                │  │
│              │  │ Yesterday                                     │  │
│              │  │ ────────────────────────────────────────    │  │
│              │  │  4:36 am                                      │  │
│              │  │  "Understand the project, explore deeply,    │  │
│              │  │   ideate the current state."                  │  │
│              │  └─────────────────────────────────────────────┘  │
│              │                                                     │
│              │  [New Entry]  [Search…]  [Export…]                  │
└──────────────┴─────────────────────────────────────────────────────┘
```

**Differences from Home (conversation log):**
- Home = the *destination of every dictation* (whatever app was
  focused). Each entry is a dictation that ended with a paste.
- Scratchpad = the *destination when no app is focused* (or when
  the user explicitly chose "dictate to scratchpad"). Each entry
  is a dictation that ended with text written to the scratchpad.

**The flow `[recall:high]`:**
- User opens the scratchpad (or it's already open)
- User double-taps Fn
- HUD appears bottom-center (NOT top-center — we rejected that)
- User speaks
- User single-taps Fn
- **HUD shows "Saving to Scratchpad"** instead of "Cleaning up…"
- The text lands in the scratchpad
- HUD shows "Done" + fade
- The scratchpad view auto-scrolls to the new entry

**`[decision]`:**
- v0.1: scratchpad is the manual destination (user clicks "New
  Entry" then dictates). Auto-route is v1.
- v1: detect "no focused text field" via `AXUIElement` → auto-route
  to scratchpad. The "no focused field" affordance: the HUD shows
  a small "↳ Scratchpad" label so the user knows where it's going.

**`[recall:med]`** on the exact UI. The Home-vs-Scratchpad
distinction is well-known; the implementation details vary.

**Verification needed:** screenshot of Wispr's Scratchpad view.
The exact layout, the auto-route behavior, and the HUD label
("Saving to Scratchpad" vs "Pasting at cursor") are all
`[recall:med]`.

### 11.11 Menubar dropdown menu `[recall:high]`

**Goal:** One-tap access to the most common actions from the
menubar — start/stop, mute, history, settings, account, quit.

**The `speak` shape (Wispr-style):**

```
speak — ready (double-tap Fn to start)        ← status line
─────────────────────────────────────
▶ Start Dictation                  ⌥⌘Space
🔇 Mute Microphone
─────────────────────────────────────
  Mode ▸                            ← submenu: Default / Professional / Casual / Code / Email
  Language ▸                        ← submenu: English (US) / English (GB) / Spanish / …
  Style ▾  Default                  ← quick mode indicator
─────────────────────────────────────
  Open Dashboard…                    ⇧⌘D
  History…                            ⌘H
  Settings…                           ⌘,
  Help                                 ⌘?
─────────────────────────────────────
  About speak…                        ⌘A
─────────────────────────────────────
  Quit speak                          ⌘Q
```

**Submenus (Wispr's pattern):**
- **Mode ▸** — Default / Professional / Casual / Code / Email /
  More… (opens the Style tab)
- **Language ▸** — en-US / en-GB / fr-FR / de-DE / es-ES / More…
  (opens the dictionary tab)
- **Engine ▸** (Wispr has this) — Auto / Apple Speech / WhisperKit
  / Cloud (for Pro users)

**`[recall:high]`** on the submenu structure. Wispr's menubar is
the most-iterated surface in the app; the pattern is well-known.

**`speak` v0.1 plan:**
- Add the "Mode ▸" submenu (5 modes)
- Add the "Language ▸" submenu (starts at 2, grows with v1)
- Add the "Open Dashboard…" item (the new dashboard surface)
- Keep the current "Start Dictation / Mute / History / Settings /
  About / Quit" items

**Status line `[recall:med]`:**
- Wispr shows the dictation count for the day: "12 dictations
  today · 1,247 words"
- We adopt this in v0.1 (a single line: "12 dictations today")

**Verification needed:** screenshot of Wispr's menubar dropdown
(in idle, listening, and muted states). The submenu structure, the
status line, and the engine submenu are all `[recall:med]`.

### 11.12 UI components catalog (additions to §3)

These components are inferred from the recall-based surface analysis
above. They augment the component catalog from §3.

#### 11.12.1 `KeyCapView` (already in §3.13)

#### 11.12.2 `Sidebar` (already in §3.14)

#### 11.12.3 `DayGroupedList` (already in §3.15)

#### 11.12.4 `StatTile` (already in §3.16)

#### 11.12.5 `DevicePickerRow` (new) `[recall:med]`

A row in the device picker: device name + live level meter + selection
radio. Used in §11.1.

```
┌────────────────────────────────────────────────────────────┐
│ ● AirPods Pro    [▌▌▌▌▌▌▌▌]  −12 dB                          │
│ ○ MacBook Mic    [▌▌▌▌]      −24 dB                          │
└────────────────────────────────────────────────────────────┘
```

**Components:** `LevelMeterView` (large variant), `Color.primary`
text, `Toggle` (or radio-style button), 13pt secondary for dB.

#### 11.12.6 `PlanBadge(plan: String)` (new) `[verified:from Home]`

A small outline pill that says "Basic" / "Pro" / "v0.1". Verified
from the Home dashboard. For `speak`, we'd render the version
(`v0.1`) instead of a plan tier.

#### 11.12.7 `UpgradeCard(title: String, body: String, cta: String)` (new) `[verified:from Home]`

The light-purple card in the sidebar bottom of Wispr's Home.
Verified from the Home dashboard. For `speak`, we'd repurpose as
a "What's new" card (showing the latest feature, with a
"Learn more →" link).

#### 11.12.8 `HotkeyRow(hotkey: HotkeyBinding, onRecord: () -> Void)` (new)

The hotkey row in Settings — current binding + Record button.
Used in §2.4.2.

#### 11.12.9 `EditBeforePastePill` (new) `[recall:med]`

The expanded post-stop pill with the editable text + countdown +
Apply/Cancel buttons. Used in §11.2.2.

#### 11.12.10 `TransformPopover` (new) `[recall:med]`

The popover that appears near a text selection when a transform
hotkey is pressed. Shows "Rewriting…" spinner → result + Apply/Undo.

#### 11.12.11 `SnippetRow(trigger: String, expansion: String, isBuiltIn: Bool)` (new)

A row in the Snippets list. Two columns: trigger + expansion. The
"Built-in / Personal" separator is a section header, not a row
property.

#### 11.12.12 `ModeCard(name: String, description: String, isActive: Bool, onSelect: () -> Void)` (new)

A radio-style card for the Style tab. The active mode has a filled
radio + a thin border accent.

#### 11.12.13 `HeatmapView(data: [Date: Int], bucket: Calendar.Component)` (new, v2) `[recall:med]`

The 7x24 (or 7x12) heatmap for "Active hours" in Insights.

#### 11.12.14 `BarChart(data: [Int], labels: [String])` (new, v2) `[recall:med]`

The 12-week bar chart for "Activity" in Insights.

#### 11.12.15 `MilestoneCard(milestone: String, unlockedAt: Date?)` (new, v3) `[recall:med]`

A celebration card shown in the dashboard when a milestone is
reached ("First 100 words", "1-week streak", etc.).

### 11.13 Summary: the screenshot wishlist

To upgrade this section from `[recall]` to `[verified]`, share
screenshots of the following Wispr Flow surfaces. I'll redo each
sub-section as a verified deep-dive (same template, much higher
fidelity):

| # | Surface | Why it matters | `[recall]` tier |
|---|---|---|---|
| 1 | Recording HUD — active state | The cautionary tale top-center pill | `[recall:high]` |
| 2 | Recording HUD — edit-before-paste expansion | The killer feature (countdown + tap-to-pause) | `[recall:high]` |
| 3 | Audio / device picker | The device list + live level + noise suppression | `[recall:med]` |
| 4 | Settings main page | Section breakdown, theme, display name | `[recall:med]` |
| 5 | Voice profile setup (onboarding) | The 3-sentence recording flow | `[recall:med]` |
| 6 | Dictionary editor | The custom-words UI with pronunciation | `[recall:med]` |
| 7 | Snippets editor | The built-in + personal list | `[recall:high]` |
| 8 | Style / Modes editor | The 5 built-in modes | `[recall:high]` |
| 9 | Transforms editor | The 10 built-in AI commands | `[recall:high]` |
| 10 | Insights page | The 6 sections of analytics | `[recall:med]` |
| 11 | Scratchpad view | The dictation-without-cursor surface | `[recall:med]` |
| 12 | Menubar dropdown | The click-menu with submenus | `[recall:high]` |
| 13 | Onboarding full flow | The 5–7 step flow (welcome → permissions → voice profile → done) | `[recall:high]` |

**Even 3–4 of the most important (1, 2, 6, 7, 8, 12) would let me
upgrade ~80% of this section to `[verified]`.** Send them when you
have a chance and I'll iterate.

---

*End of recall-based deep-dive. The original §0–§10 are preserved
verbatim. §11 is the recall-based analysis of the other Wispr
surfaces, awaiting screenshot verification per §11.13.*
