# speak — Frontend Identity & the Pet `[decision 2026-07-11]`

> Authored by the orchestrator as the product's design direction. Implementers:
> build exactly this; escalate taste questions rather than improvising.
> Supersedes the Wispr-Flow-derived look as the *default*; `HUDStyle.classic`
> remains available but is no longer the identity.

## 0. The thesis

speak is not a dictation utility with a settings window. It is the **human's
side of the desk** in a world of working agents — the input, output, routing,
and attention layer (`specs/agent-voice-bridge.md` §1). The UI must say that
at a glance. The identity therefore has one organizing idea:

**Presence.** The product has a body on the desktop — a small, living,
instrument-like creature (the Pet) — and every other surface is a quiet,
disciplined studio around it.

The reference world is **broadcast and studio hardware**: VU meters, ON AIR
lamps, patch bays, tally lights. Instruments that are alive but never cute,
honest but never noisy. NOT: mascots, Clippy, chat-app gradients, glassy
crypto-dashboard glow.

## 1. The one aesthetic risk (spend boldness here only)

**The Pet — working name "Voice Desktop Pet."** A creature whose body is a *live waveform*:
five vertical bars in a soft capsule, behaving like an organism. Codex's pet
and Claude Code's spinner are the inspiration for *presence*, not for form —
Voice Desktop Pet's form is ours: bars-as-body means every animation is a true signal
readout, never decoration. A VU meter that became a pet.

Everything else in the app stays quiet so Voice Desktop Pet can be the memorable thing.

## 2. Two-temperature palette (structure IS information)

The single system rule everything obeys: **warm = human, cool = agent.**
Every surface, badge, waveform, and state color answers "who is acting?"

| Token | Hex | Role |
|---|---|---|
| `ink` | `#16181D` | primary surface (dark; not pure black) |
| `ink2` | `#1F232B` | raised surface / cards |
| `bone` | `#E9E6E0` | primary text on ink |
| `mica` | `#8A8F98` | secondary text, hairlines |
| `humanAmber` | `#FFB25A` | the human channel: live mic, dictation levels, hotkey affordances |
| `onAir` | `#FF5C49` | recording tally: mic is OPEN (honest, unmissable, never reused for anything else) |
| `agentViolet` | `#9D8CFF` | the agent channel: agent speech, agent activity, session chips |
| `delivered` | `#5FBF8F` | terminal success: pasted, answered, completed |

Light mode derives from the same semantics (bone surfaces, ink text, identical
channel hues at adjusted luminance). Respect system appearance; never force
dark. NSVisualEffectView materials stay for panels — tint them, don't paint
over vibrancy.

Hard rule: `onAir` appears **iff the microphone is capturing.** It is the
tally light. No marketing use, no hover states, nothing.

## 3. Typography (all Apple-native, zero deps)

| Role | Face | Why |
|---|---|---|
| Display / dashboard pane titles | **New York** (serif), semibold, tight | speech is language; the editorial voice is the distinctive move a dev-tool never makes. Used with restraint — titles only. |
| UI / controls / body | **SF Pro** | native rhythm, correct on macOS |
| Transcripts, live words, timers, session IDs | **SF Mono** | the transcript is *material* — monospace says "verbatim record," and tabular numerals keep timers steady |

Scale: 11 / 13 (base) / 15 / 20 / 28. Weights: regular + semibold only.
No thin weights, no ALL-CAPS labels except two-letter status tags.

## 4. Motion charter

- Every animation maps to a real signal (audio level, state transition,
  attention request). If it doesn't read from a signal, cut it.
- Durations: 120ms (micro), 320ms (state), springs `response 0.35 /
  damping 0.8`. Nothing slower except Voice Desktop Pet's idle breath (~4s cycle).
- Reduce Motion: crossfades replace movement; Voice Desktop Pet's breath becomes a slow
  opacity pulse; word-materialize becomes plain fade-in.
- One orchestrated moment: capture-start — Voice Desktop Pet (or HUD) ignites `onAir`,
  bars jump to live levels within 100ms. This is the product's handshake;
  it must feel instant.

## 5. Voice Desktop Pet — the Pet (component spec)

### Form
- 56×36pt capsule (hit target ≥44pt), `ink2` fill at 92% opacity over a
  vibrancy material, hairline `mica` stroke, 18pt radius.
- Body: five vertical bars, 3pt wide, 3pt gaps, vertically centered,
  min height 4pt, max 22pt. Bars are THE face — no eyes, no smile.
- A 5pt tally dot sits top-right of the capsule: `onAir` when mic open,
  `agentViolet` when an agent is speaking/waiting, hidden otherwise.

### States (a real state machine, `PetState`)
| State | Bars behavior | Color |
|---|---|---|
| `dormant` | flat line, 40% opacity | `mica` |
| `idle` | slow breath ripple, center-out (~4s) | `bone` @ 70% |
| `listening` | live audio levels (same signal as HUD) | `humanAmber`, tally `onAir` |
| `processing` | left→right metronome sweep | `humanAmber` → `bone` |
| `agentWorking` | gentle alternating tick (outer bars) | `agentViolet` |
| `attention` | double-knock pulse every 6s + count badge | `agentViolet`, badge `bone`/`ink` |
| `speaking` | levels mirror TTS output envelope | `agentViolet` |

`attention` is driven by the AVB-7 inbox count (`pendingAndPresented`) —
Voice Desktop Pet IS the inbox badge. Until AVB-7 lands, the state exists with a stub
provider returning 0.

### Behavior
- Non-activating, always-on-top `NSPanel` (follow `TranscriptOverlayPanel`
  precedents: `.nonactivatingPanel`, no focus steal, `FirstMouseHostingView`
  so the first click lands). Joins all Spaces
  (`.canJoinAllSpaces`, `.fullScreenAuxiliary`).
- Draggable anywhere; on release, snaps to the nearest screen edge with an
  8pt inset; position persisted per display UUID in `SettingsStore`.
- Click: toggle dictation — the exact hotkey path (`DictationController`),
  no parallel path. While listening, click stops (same as single-press).
- Right-click menu: Start/Stop Dictation · Open speak · Hide Voice Desktop Pet
  (session) · Disable Voice Desktop Pet (setting). Menu is the escape hatch; keep it short.
- Hover: capsule widens ~1.15× and shows a one-line status in SF Mono
  ("listening…", "2 agents active", "1 waiting on you"). Collapses on exit.
- `petEnabled` in `SettingsStore`, **default false** this slice (opt-in until
  dogfooded; zero regression for existing users). Toggle in Settings and in
  the menubar menu.

### Animation soul (research-informed amendment, 2026-07-11)

Findings from the Codex Pets record, Clippy post-mortems, and desktop-pet /
ambient-display research (three-agent sweep; sources in the research reports):

1. **Never interrupt — presence only.** Clippy died of interruption and false
   agency (Reeves, Cooper), not of having a face. Voice Desktop Pet therefore never
   overlays, never pops, never speaks uninvited; the `attention` knock is
   peripheral and rate-limited (≥6s), and everything else is glanceable state.
2. **Bars behave like a face; anatomy stays abstract.** Research: people
   build "rich imaginative narratives from minimal stimuli" when they
   perceive agency, and "unrealistic, cute avatars work better than
   human-like ones" (Lawhead). So Voice Desktop Pet earns character through *behavior*:
   - **blink**: all five bars dip in unison for ~120ms at irregular
     30–90s intervals while `idle` (life, not information — the ONE licensed
     exception to the signal-only rule, because liveliness IS the signal
     that speak is running);
   - **sleep**: `dormant` bars settle into the flat line with a barely
     visible 6s breath — closed eyes, functionally honest;
   - **perk-up**: on capture-start, a 100ms anticipation dip *then* the jump
     to live levels (Disney "anticipation" — the principle that survives at
     this scale, per the tiny-canvas findings).
3. **Readability at 56×36pt beats richness.** At pet scale the principles
   that matter are Appeal, Anticipation, Timing, Secondary Action;
   squash/stretch is imperceptible. The tally dot is the secondary action —
   it corroborates the bars, never contradicts them. Silhouette (capsule +
   bar heights) must read every state at a glance from peripheral vision.
4. **Codex Pets' state triad maps to our bridge lifecycle** (running /
   waiting-for-input / complete ↔ `agentWorking` / `attention` /
   `delivered` flash) — validation that pet-as-agent-status is a proven
   pattern. Their "click opens chat with the agent" is Voice Desktop Pet's destiny once
   voice-turn delivery (bridge spec §7.4) lands; for now click = dictate.
5. **Off by default is the shipped norm** (Codex Pets ship opt-in too) and
   the calm-technology metric applies: Voice Desktop Pet succeeds if it *reduces*
   app-polling and interruptions, never by engagement time.

### What Voice Desktop Pet must never do
- Open the mic by itself (only the human's click/hotkey does — spec §8).
- Animate for marketing reasons (see motion charter).
- Block, steal, or hold keyboard focus. Ever.

## 6. Surface transformation plan (phased)

- **FE-1 (now): tokens + Voice Desktop Pet.** `Speak/App/DesignSystem/` (Color/Font/Motion
  tokens as SwiftUI extensions) + `Speak/App/Pet/` (panel, view, state
  machine, settings). No existing surface restyled yet.
- **FE-2: the HUD converges.** Aurora becomes the default and adopts the
  two-temperature rule (listening = amber family, cleanup = bone sweep,
  agent = violet). Classic remains selectable. Overlay chrome moves to
  tokens. The capture card drops Wispr-Flow-era styling.
- **FE-3 (after AVB-7): the dashboard becomes the console.** New York pane
  titles, ink surfaces, Agent Inbox pane in the new language, session chips
  (violet) with per-session activity. Menubar icon gains the tally-dot logic.
- **Horizon (design-noted, NOT built):** conversation threads per agent
  session; @-mention routing of turns to agents from a thread ("channel"
  model — speak as the local Slack for your agents). Voice Desktop Pet's hover lozenge is
  the seed of that thread list. No implementation until the AVB slices
  make sessions/turns real.

## 7. Copy voice

Plain verbs, sentence case, the interface speaks as an instrument, not a
person: "Listening", "Pasted", "1 agent waiting", "Mic is off". Errors say
what happened + the next action ("Mic permission is off — open System
Settings"). Never "Oops", never apologies, never exclamation points.
