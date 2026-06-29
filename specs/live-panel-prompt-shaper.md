# `speak` — Live Panel: the Prompt Shaper (PE-3)

> The overlay HUD shown during dictation becomes a **shaper you glance at**, not a
> menu you operate. Realizes `profile-taxonomy.md` in the live moment. Apple
> low-friction: auto-resolved + voice carry the common case; the panel is the
> exception path.

## Layout — adaptive top strip (one row, two only for Agent)

```
Agent destination (e.g. CC inside Cursor):
┌──────────────────────────────────────────────────────────┐
│  ⟨Agent⟩   Write   Note                            ⌄more  │ ← Row 1: destination (auto-selected)
│  Task   Fix   Ask   Commit   Shell                        │ ← Row 2: Agent categories (ONLY for Agent)
│  ● listening → "make it refactor the parser…"   ⌘⏎ send   │
│  ∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿ waveform ∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿∿            │
└──────────────────────────────────────────────────────────┘

Write destination (e.g. Mail) — no second row:
┌──────────────────────────────────────────────────────────┐
│  Agent   ⟨Write⟩   Note                                   │
│  ● listening → "let them know the build is fixed"         │
└──────────────────────────────────────────────────────────┘
```

- **Row 1 = destination** chips (`Agent · Write · Note`), pre-selected by `ProfileResolver`.
- **Row 2 = Agent categories**, rendered **only when the active destination is Agent**. Write/Note show no second row. Complexity scales with destination.
- Active chip uses the calming accent (Monaco theme); state stays glanceable.

## Interaction (per-dictation, reversible)

1. **Glance** — the target+destination line (`→ Cursor · Agent`) does the "know" job with zero clicks.
2. **Switch** — click a chip → applies to **this dictation only**; the saved default never changes. Category defaults to `task`.
3. **Voice (later milestone)** — "as a commit message…", "switch to Write", "ask: …" → the strip confirms. Voice is itself a shape control.
4. **Pin (later)** — after correcting a context twice, offer one-click "always Agent here" → friction gone permanently.

## State plumbing (the real work)

- `DictationController` (@Observable) exposes the **active destination** (resolved) + **active AgentCategory** (default `.task`) for the current/next dictation, and a setter for a **per-dictation override** that does NOT mutate `ProfileStore` defaults.
- `SpeakEngine.newSession(...)` already builds `CleanupMode.profile(profile, level:, customVocabulary:)`; thread the chosen `AgentCategory` through to `PromptBuilder` (PT-1 already gates the fragment to Agent).
- The panel is **non-activating** (never steals focus from the coding agent) and self-dismissing — same window behavior as today's overlay.

## Scope

- **In (PE-3):** the adaptive strip, click-to-switch destination + category per-dictation, controller state + engine threading, the glance line.
- **Out (later):** voice override (PE-3.1), Pin-to-context (PE-3.2), knobs/length/tone (PE-4), AI Studio deep category editing.
- Every default/fragment stays validated by the **SM-0 eval harness**.

## Done-when (binary)

- During dictation the strip shows the resolved destination; for Agent it shows the category row, for Write/Note it does not.
- Clicking a destination/category chip reshapes THIS dictation's output (verified via log: the resolved profile + category change) without changing the saved default.
- 4 gates green.
