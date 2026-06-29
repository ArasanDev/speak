# `speak` — The Profile Engine (design spec)

> **Status**: Locked product thesis (2026-06-29, human decision). This is the
> spine the product is becoming: a **local-first, voice-driven, fully
> customizable AI text engine**. Everything downstream — Agent Mode (V01-0),
> per-app context (V01-3), Transforms (V1-3), code-aware mode (V1-4) — is an
> **instance of this one engine**, not a separate feature.
>
> Depends on `product.md` (WHY) + `architecture.md` (the `LLMCleaning` seam).
> System prompts live in `specs/profile-system-prompts.md`. Small-model rules
> are §6 here and the roadmap's small-models track.

---

## 1. The layering — what is core and what is extension

The product has three layers. **The lower a layer, the more immutable it is.**

```
┌─────────────────────────────────────────────────────────────┐
│  EXTENSION   Profile engine: customizable, profile-driven    │  ← the push
│              AI text. System-prompt control. AI Studio.       │     (this spec)
│              Overlay = real-time control surface.             │
├─────────────────────────────────────────────────────────────┤
│  DEFAULT     AI voice processing: on-device neat-writing      │  ← default on
│              (the "Clean" profile). Filler/grammar/format.    │
├─────────────────────────────────────────────────────────────┤
│  BASE CORE   Double-press = activate · single-press = stop.   │  ← NEVER changes
│  (immutable) Raw voice → text, ALWAYS available, no AI.       │
└─────────────────────────────────────────────────────────────┘
```

**Base core (the irreducible floor — never trade away):**
- **Double-press to activate, single-press to deactivate.** This gesture is the
  product's identity. It does not change.
- **Raw voice capture → raw transcript is always available**, with zero AI in
  the path. If every model is unavailable, offline, or disabled, `speak` still
  captures speech and delivers raw text. This is the guarantee the whole tower
  stands on.

**Default layer:** the `Clean` profile runs on the raw transcript by default —
on-device neat-writing (Apple Foundation Models). Turning AI off falls straight
through to base-core raw text. No dead ends.

**Extension layer (this spec):** profiles. The same engine, steered by a system
prompt, producing exactly the right text for wherever it lands — especially
coding agents.

---

## 2. The one idea: a Profile

A **profile** is the unit of customization. It is, at heart, **a name + a system
prompt + a few rules**. We ship excellent defaults; every part is customizable.
This is the "default + customization version for everything" principle,
generalized into a single data model.

Every overlay chip is a profile. Every customization a user makes is editing a
profile. Agent Mode is a profile. Code-aware mode is a profile. There is one
engine; profiles are its configuration.

### 2.1 Schema

```swift
public struct Profile: Codable, Identifiable, Sendable {
    public let id: UUID
    public var name: String              // "Clean", "Chat", "Code", "Commit"
    public var icon: String              // SF Symbol name (overlay chip glyph)
    public var isBuiltIn: Bool           // shipped default: resettable, not deletable

    // ── The heart: the customization point ──────────────────────────────
    public var systemPrompt: String      // default shipped; fully user-editable
    public var examples: [Example]       // few-shot pairs — the strongest small-model lever

    // ── Structured knobs (compile into prompt clauses; power users may ignore) ──
    public var format: OutputFormat      // asIs | paragraph | bullets | numbered | codeBlock | verbatim
    public var tone: Tone                // neutral | terse | formal | casual
    public var length: LengthBias        // preserve | condense | expand
    public var contextInputs: Set<ContextInput>  // selection | clipboard | currentFile | appName

    // ── Routing & delivery ──────────────────────────────────────────────
    public var targetApps: [String]      // bundle IDs that auto-activate this profile
    public var autoSubmit: Bool          // simulate Return after paste (agent terminals)
    public var model: ModelChoice        // .foundationModels (default) | pluggable
}

public struct Example: Codable, Sendable {
    public var spoken: String            // raw dictation
    public var written: String           // desired output
}

public enum OutputFormat: String, Codable, Sendable {
    case asIs, paragraph, bullets, numbered, codeBlock, verbatim
}
public enum Tone: String, Codable, Sendable { case neutral, terse, formal, casual }
public enum LengthBias: String, Codable, Sendable { case preserve, condense, expand }
public enum ContextInput: String, Codable, Sendable {
    case selection, clipboard, currentFile, appName
}
public enum ModelChoice: Codable, Sendable {
    case raw                              // base-core passthrough, no model
    case foundationModels                 // default, on-device
    case pluggable(engineID: String)      // MLX / OpenAI-compatible (v0.1+)
}
```

> **`Raw` is special.** It is the base-core bypass, modeled as a built-in
> profile with `model == .raw` and an empty system prompt → the raw transcript
> passes through untouched. It is always present and cannot be deleted.

### 2.2 The PromptBuilder

The system prompt is the engine; the structured knobs are conveniences. A pure
`PromptBuilder` assembles the final prompt sent to the model:

```
finalPrompt = systemPrompt
            + clause(for: format)        // e.g. "Format the result as a numbered list."
            + clause(for: tone)          // e.g. "Use a terse style."
            + clause(for: length)        // e.g. "Be more concise than the input."
            + injected(contextInputs)    // selection / clipboard / file name / app name
            + fewShot(examples)          // spoken→written pairs
            + "\n\nDictated speech:\n" + rawTranscript
```

Power users who edit `systemPrompt` directly can leave the knobs at defaults —
the knobs only *add* clauses; they never override an explicit prompt. This keeps
"sensible defaults, infinite ceiling" true at the data-model level.

---

## 3. Profile resolution (which profile applies to a dictation)

Resolved at `newSession()` time, highest priority first:

1. **Live overlay override** — the user tapped a Tier-1 chip for *this*
   dictation. Wins over everything. Ephemeral (does not change the default).
2. **Auto-select by frontmost app** — `NSWorkspace.frontmostApplication.bundleIdentifier`
   matches a profile's `targetApps` (Cursor → Code, Terminal → CLI, claude.ai →
   Chat). This is the agent-aware behavior, now user-editable per profile.
3. **Global default profile** — user's chosen default (ships as `Clean`).
4. **Fallback** — if AI is off/unavailable → `Raw` (base core). Never an error.

---

## 4. The two surfaces (where profiles are authored vs. used)

This resolves the earlier "where do settings live" confusion. There are **two
distinct settings surfaces with two different jobs** — they are not duplicates.

| | **Dashboard → AI Studio** | **Overlay control surface** |
|---|---|---|
| Job | *Author / customize* profiles | *Pick / steer* the active profile |
| Cadence | Occasional, deliberate | Every dictation, in-flow |
| Entry point | Gear bottom-left of the main window (the natural place) | An icon **on the live overlay** (NOT a settings gear) |
| Edits | System prompts, examples, defaults, app-binding | This-utterance-only overrides |
| Persistence | Saved to the profile | Ephemeral (one dictation) |

> The icon we kept trying to place belongs on the **overlay** — but as *live
> customization* ("steering"), not as a duplicate of app settings. App-wide
> settings stay in the dashboard. See `product.md` §6d.

### 4.1 AI Studio (dashboard pane)

- List of profiles (built-ins + user-created). Built-ins show **Reset to
  default**; customize freely, always recoverable.
- Per-profile editor: name, icon, **system prompt** (the main field), few-shot
  examples, the structured knobs, target-app bindings, auto-submit, model.
- **Live test box**: type or speak a sample → see the transformed output. This
  is the same engine the overlay live-preview uses (§5), reused.
- A global **default profile** picker and a master AI on/off (off ⇒ base-core Raw).

### 4.2 Overlay control surface (tiers)

Calm by default; power on demand. The overlay is a **non-activating** panel, so
controls are click / hover / **voice** — never keyboard-focus (that is also what
keeps paste working). Every control has a spoken equivalent (hands stay on the
keyboard).

- **Tier 1 (always visible — the 80%)**: profile chips (`Raw · Clean · Chat ·
  Code · Prompt · Commit`), the target indicator (`→ Cursor`), and a
  live-preview toggle. *This is the primary direction.*
- **Tier 2 (behind the customization icon)**: format, tone/length, transform
  (expand/condense), context-attach (selection / file / clipboard). *Inspiration
  to mine — these are just the profile's knobs exposed live.*
- **Tier 3 (capture controls, always reachable)**: pause/resume mic, undo last
  sentence, re-clean with another profile, cancel. *Aspirational; some land
  early (cancel/pause), some later.*

> Tiers 2 and 3 are **not new engines** — they are wrappers exposing the same
> `Profile` knobs and capture controls. Once Tier 1 + the profile engine exist,
> they are UI-surfacing decisions, not new architecture. This is what de-risks
> the roadmap.

---

## 5. The novel core loop: stream → preview → steer → commit

The unexplored space competitors miss: the capture moment is **interactive**,
not a dumb recording window.

```
double-press ─► raw streams (app UI + at-cursor preview, NEVER inserted)
            ─► live AI preview forms below the raw (the "what will land")
            ─► user steers (tap a chip OR say "make it a bullet list")
            ─► single-press ─► commit: dismiss previews, paste ONLY final AI text
```

- **Raw is never inserted** into the document — it is ephemeral indication, in
  two places at once (our UI + the caret-anchored overlay, best-effort per
  `roadmap` P2.x).
- **Only the final, profile-shaped AI text is pasted**, once, at the cursor.
- Steering works mid-utterance because the mic is already live.

---

## 6. Small-model design rules (NON-NEGOTIABLE)

The default engine is **Apple Foundation Models — a very small (~3B), on-device
model** with a limited context window and weaker instruction-following than
frontier models. Every profile, prompt, and feature is designed for *this*
reality first. (Larger pluggable models, v0.1+, only relax these — never the
other way.)

Rules every system prompt and profile must obey:

1. **Short, imperative system prompts.** No essays. The model has limited
   attention; every extra sentence dilutes it.
2. **Few-shot examples are the strongest lever.** 1–2 `spoken → written` pairs
   steer a small model better than paragraphs of instructions. Profiles carry
   `examples` for exactly this.
3. **One job per profile.** Do not ask a small model to detect intent *and*
   reformat *and* translate in one pass. Compose profiles instead.
4. **Explicit output contract.** End every prompt with "Output ONLY the result —
   no preamble, no explanation, no quotes." Small models love to chatter.
5. **Deterministic formatting beats reasoning.** Prefer structured, rule-based
   output (lists, fixed shapes) over open-ended reasoning the model may botch.
6. **Bounded latency + length.** Cap input tokens; chunk long dictations. Target
   on-device cleanup within `benchmark.md §7` latency budgets.
7. **Always degrade to Raw.** Any model failure, timeout, or unavailability →
   raw transcript pastes. Never an error, never a dead end (base-core guarantee).

These rules are enforced by an **eval harness** (roadmap small-models track): a
golden set of `spoken → expected` fixtures per profile, scored for correctness,
format adherence, and latency on-device, so prompt edits are measured, not
guessed.

---

## 7. Why this is the moat

Cloud tools won't give you raw system-prompt control over your text privately.
Local tools don't have this UX. `speak` sits in the gap: **a fully programmable,
100%-on-device AI text engine** — defaults for everyone, system-prompt control
for power users — that turns speech into exactly the right text for wherever it
goes, especially coding agents. No account, no API key, no egress, free forever.

---

## 8. Build order (see `roadmap.md` for the gated tasks)

1. **v0** — base core + default `Clean` profile, paste reliable everywhere
   (the current fix phase: single paste path, no keystroke injection).
2. **Profile engine MVP** — `Profile` type + `PromptBuilder` + the 6 default
   profiles + resolution order. (Generalizes the existing `LLMCleaning`/
   `CleanupMode` seam.)
3. **Small-models eval harness** — golden fixtures + scoring, on-device.
4. **AI Studio** (dashboard) — author/customize profiles + live test.
5. **Overlay Tier 1** — profile chips + target indicator + live preview.
6. **Caret-anchored raw streaming** (roadmap P2.x).
7. **Overlay Tier 2/3** — knobs + capture controls (wrappers over the above).

The scattered roadmap items (V01-0 Agent Mode, V01-3 per-app context, V1-3
Transforms, V1-4 code-aware) are **re-framed as profiles / profile features**
once the engine exists — they stop being separate code paths.
