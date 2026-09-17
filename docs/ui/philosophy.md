# speak — UI Philosophy

> **Purpose**: the design philosophy — why each surface exists, what idea it embodies, what it must never do. Read this before `foundations.md` (tokens) or `surfaces-v0.md` (catalog). · **Audience**: contributor, AI agent, maintainer · **Status**: canonical — describes shipped code; reconciles `specs/frontend-identity.md` (frozen direction) with `App/DesignSystem/` (the implementation) · **Last reviewed**: 2026-09-17

---

## 0. The one-sentence philosophy

**speak is an instrument, not an app.**

The reference world is broadcast and studio hardware — VU meters, ON AIR
lamps, tally lights, patch bays. Instruments are alive but never cute, honest
but never noisy. Every pixel either reads a real signal or gets cut.

(`specs/frontend-identity.md` §0 is the frozen source of this direction. This
file is the living layer that keeps it honest against shipped code.)

## 1. The three load-bearing rules

Everything else follows from these. When a design decision is ambiguous,
answer these first.

### Rule 1 — "Who is acting?" is the only color question

The palette is two-temperature: **warm = human, cool = agent.** Every surface,
badge, waveform, and state color answers who is acting — `speakHumanAmber`
for the human channel, `speakAgentViolet` for the agent channel. A theme may
change hue; it may never change meaning. Role semantics are load-bearing.

Implemented: `App/DesignSystem/SpeakColors.swift` (the SEMANTICS block is the
contract).

### Rule 2 — `onAir` is a tally light, not a brand color

`speakOnAir` appears **iff the microphone is capturing**. No marketing use, no
hover states, no decoration. It is the honesty contract made visible: the user
can always verify capture by looking. If a color appears while the mic is
closed, it is not `onAir`.

Hard rule, pinned by `OverlayControllerTests` / `specs/frontend-identity.md` §2.

### Rule 3 — Motion reads a signal or doesn't exist

Every animation maps to a real signal: audio level, state transition,
attention request. If it doesn't read from a signal, cut it. Durations are
120 ms (micro) / 320 ms (state) / spring 0.35·0.8 — nothing slower except an
explicitly licensed idle breath.

Implemented: `App/DesignSystem/SpeakMotion.swift` (`micro`, `state`,
`idleBreath`, all Reduce-Motion-aware).

---

## 2. Per-surface philosophy — what each thing IS

Each surface has one idea. If a change adds a second idea to a surface, it
belongs on a different surface.

### The HUD — *the instrument*

**Files:** `App/Overlay/TranscriptOverlayPanel.swift` (NSPanel shell),
`TranscriptOverlayView.swift` (frame), `HUDLaneViews.swift` +
`HUDLaneContent.swift` (zones), `OverlayViewModel.swift` (state).

**Its idea:** *prove capture is happening without stealing attention.* The
user is mid-thought, mid-sentence — the HUD exists so they never wonder "is it
hearing me?" It is a readout, not a dialog.

Consequences:

- **Never steals focus.** `NSNonActivatingPanelMask`, always-on-top, joins all
  Spaces. Hard constraint — the HUD is peripheral by construction.
- **One silhouette, four states.** `HUDLane.panelShape` — a near-rectangle
  with micro-curved corners (`RoundedRectangle(14, .continuous)`) — is the
  single shape constant shared by clip, tint wash, hairline, and the opt-in
  animated borders. States are expressed *inside* the frame (leading slot
  morphs, phase-colored wash, header text), never by reshaping the frame.
- **No furniture.** No dividers, no icon tiles, no separate timer compartment.
  The timer rides inline in the header (`LISTENING · 0:12`). If an element
  doesn't change what the user does next, it doesn't ship.
- **The border is quiet by default.** A static 1 pt `speakCardBorder`
  hairline. Animated borders (full glow, edge flow) are opt-in Settings only —
  they must still follow `panelShape` and honor the signal rule (`onAir`
  spectrum only while capturing).

### The menubar icon — *the presence dot*

**Files:** `SpeakApp.swift` (`MenubarIcon` mapping), `StatusBarController`.

**Its idea:** *the always-present proof that speak is alive.* The only
surface that exists in every state including idle. State → SF Symbol mapping
(`waveform` / `waveform.circle.fill` / `hourglass` / `checkmark.circle.fill` /
`exclamationmark.triangle.fill`) with phase color. It answers "is speak
running and what is it doing" in a glance, nothing more.

### The Dashboard — *the console*

**Files:** `App/Dashboard/` (`DashboardView`, `PaneScaffold`, `Panes/`).

**Its idea:** *the studio around the instrument.* Where the HUD is
peripheral, the dashboard is the focused surface: history, insights,
dictionary, style, transforms, agent inbox. It is the place complexity is
allowed to live — because the user chose to open it.

Consequences: sidebar navigation (Mac idiom), panes built from the shared
card primitives (§3), New-York serif for pane titles only (`speakDisplay`).
Nothing in the dashboard may leak into the HUD — glanceable stays glanceable.

### Settings — *the workbench*

**Files:** `App/Settings/`.

**Its idea:** *every knob the engine exposes, honestly labeled.* Native form
controls (`Form`, `Toggle`, `Picker`), grouped cards, live previews that
mirror the real surface (`OverlayPreviewPanel` renders the actual
`panelShape`, animation, and border — the preview can never drift from the
panel because it shares the constants).

### Onboarding — *the handshake*

**Files:** `App/Onboarding/`.

**Its idea:** *earn the two permissions, then get out of the way.* The only
surface allowed to take focus uninvited — justified because without it the
product does nothing. Five steps, ≤90 s to first dictation.

### History — *the record*

**Files:** `App/History/`, `App/Dashboard/Panes/HistoryPaneView`.

**Its idea:** *the log file.* Transcripts and timestamps are *material* —
they render in the monospace content voice (`Font.speakMono*` in
`App/Theme/SpeakTheme.swift`) because monospace says "verbatim record" and
tabular numerals keep times steady.

### Cards, wells, and chips — *the furniture*

**Files:** `App/DesignSystem/SpeakCard.swift`.

Two primitives only:

- `speakCard()` — the raised grouped card (r16, `speakSurface` + hairline).
- `speakInset()` — the recessed well (r8, `speakWindowCanvas` + hairline) for
  code/commands/JSON inside a card.

Capsules exist for exactly one job: small interior chips and badges
(conversation-mode chips, status pills). A capsule is a *label*, never a
*panel* — the panel silhouette is the near-rectangle.

### The Pet — *the presence layer (spec'd, not shipped)*

`specs/frontend-identity.md` §5 specifies a Voice Desktop Pet: a 56×36 pt
creature whose body is a live waveform — the one licensed place for character.
It is the *only* aesthetic risk the identity takes; everything else stays
quiet so the Pet can be memorable. **Status: not implemented** — no `Pet/`
directory exists in `App/`. The spec stands; build it exactly as written or
escalate, don't improvise.

---

## 3. The shape language

| Shape | Radius | Meaning |
|---|---|---|
| Near-rectangle | 14 pt continuous (`HUDLane.panelShape`) | A *surface* — HUD, panels, the instrument face |
| Card | 16 pt continuous (`speakCard`) | A *group* — settings sections, dashboard cards |
| Well | 8 pt continuous (`speakInset`) | A *recess* — code, commands, verbatim material |
| Capsule | full | A *label* — chips, badges, status pills. Never a panel |

Rule: silhouettes are semantic. When two surfaces share a shape, they claim
kinship — don't reuse a radius casually.

## 4. The never list

Design anti-goals — things that are always wrong regardless of taste:

- **Never steal focus** from the app the user is dictating into (HUD, Pet,
  toasts — all non-activating).
- **Never animate without a signal.** No parallax, no bounce, no rotation, no
  ambient shimmer that isn't the (licensed) idle breath.
- **Never use `onAir` decoratively.** It means "mic open," full stop.
- **Never put a second idea on the HUD.** If it needs explanation or a button
  row, it belongs in the dashboard.
- **Never read as Electron.** No bespoke icon fonts, no heavy shadows, no
  custom controls where a native one exists (`AGENTS.md` — Apple frameworks
  only).
- **Never let a preview lie.** Settings previews share the live constants
  (`HUDLane.panelShape`, real animation views) — a preview that drifts is a
  bug, not a polish item.
- **Never apologize in copy.** "Mic permission is off — open System Settings."
  Instrument voice: state + next action. No "Oops," no exclamation points
  (copy voice, `frontend-identity` §7).

## 5. Where the design system lives (the real files)

| Layer | File | Owns |
|---|---|---|
| Color roles | `App/DesignSystem/SpeakColors.swift` | two-temperature palette, `onAir`/`delivered` semantics, flow-border spectra |
| Typography | `App/DesignSystem/SpeakTypography.swift` + `App/Theme/SpeakTheme.swift` | New York display / SF Pro UI / SF Mono + Monaco content voice |
| Motion | `App/DesignSystem/SpeakMotion.swift` | durations, the one spring, Reduce-Motion helpers |
| Surfaces | `App/DesignSystem/SpeakCard.swift` | `speakCard` / `speakInset` primitives |
| HUD shape | `App/Overlay/HUDLaneViews.swift` | `panelShape`, `panelCornerRadius`, lane anatomy |
| Flow borders | `App/DesignSystem/AnimatedFlowBorderModifier.swift` + `App/Overlay/EdgeFlowBorder.swift`, `AnimatedGradientBorder.swift` | opt-in animated borders |

`docs/ui/foundations.md` holds the token *values* and a11y/i18n rules;
`surfaces-v0.md` holds the per-surface pixel catalog. This file holds the
*why* — when they disagree with the code, the code and this file win, and the
catalog gets updated.
