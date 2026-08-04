# `specs/` — Index

24 spec files (plus this index). Every spec now carries a standardized status header directly under its H1:
**Status · Binds · Owner · Depends on · Superseded by · Last substantive change**. This
index groups them by status, most-binding first. If you only read one thing: the
**frozen/binding** and **active/binding** tiers below are what you cannot violate without
either breaking a test or contradicting the product's current direction. Everything else
is history, research, or a rejected branch kept for provenance.

Status derived from `git log`, test references, and `docs/roadmap.md`/`docs/progress.md`
cross-checks — not vibes. See each file's header for its own evidence.

## Frozen/binding (test-enforced contracts)

- **`frontend-identity.md`** — the `onAir` #FF5C49-iff-capturing rule and the two-temperature
  palette. Pinned by a 32-case test suite (`PetViewMathTests`, `PetStateTests`,
  `OverlayControllerTests`). Do not edit the body.
- **`verification-ledger.md`** — the record of primary-source-verified fact for every
  `[verified]`/`[corrected]`/`[refuted]`/`[unverified]` tag. Referenced by `CLAUDE.md`,
  `AGENTS.md`, and three test suites. Do not edit the body.

## Active/binding (current product direction)

- **`agent-voice-bridge.md`** — the north star. Product boundary, domain objects, safety
  invariants for the human-agent interface runtime. `docs/roadmap.md` cites this as the
  canonical contract.
- **`profile-engine.md`** — the three-layer immutable architecture (base core → default
  Clean → Profile Engine extension). Substrate already shipped.
- **`profile-system-prompts.md`** — shipped default system-prompt text per profile,
  user-editable. See contradiction note below re: the `Chat` profile.
- **`profile-taxonomy.md`** — the destination-first model (Agent/Write/Note/Raw) and
  Agent-only categories. See contradiction note below.
- **`input-felt-speed.md`** — active input-slice spec: masking cleanup latency behind
  streamed partials, <1.2s felt-speed done condition.
- **`output-conversation-reconnect.md`** — active output-slice spec: re-wiring the
  full-duplex voice loop that was built but never activated.

## Reference (still depended on, not itself a contract)

- **`wispr-input-layer-taste.md`** — Wispr Flow choreography research, actively cited by
  `input-felt-speed.md`.

## Closed findings / historical (implemented or resolved, kept as provenance)

- **`dictation-flow.md`** — P0-era hotkey/paste build contract; phases A–E have their logic
  implemented and unit-verified (roadmap P5/P6 are `[~IN PROGRESS]`, live-verification items
  still open), superseded by subsequent hardening loops in `docs/progress.md`.
- **`avb7-durable-calls-design.md`** — implementation design for AVB-7 (durable Agent
  Calls), which is `[x]` done in `docs/roadmap.md`. Accurate record of shipped code.
- **`live-panel-prompt-shaper.md`** — PE-3c-1 destination card/pill/Escape-close and
  PE-3.2 pin-to-context are both implemented (`AgentCategory`, `PinnedContextStore`,
  `DictationController+LivePanel.swift`). Not in `docs/roadmap.md` under a PE-3 label, but
  the shipped code matches the design 1:1.
- **`constraint-split-cs1-finding.md`** — CS-1 rejected, CS-2 validated-but-parked pending
  a stronger on-device model (WWDC26 provider API).
- **`wispr-parity-and-spec.md`** — its stated deliverables (`docs/benchmark.md`, `SPEC.md`)
  already exist and are canonical; this document is provenance for how they were produced.
- **`validation-findings.md`** — dated (2026-06-22/26) audit report; no inbound references
  found, whether individual findings were each closed is undetermined (see below).

## Superseded

- **`horizon-voice-os.md`** — self-declared superseded 2026-07-11 by
  `agent-voice-bridge.md`/`docs/product.md`. Confirmed by `docs/roadmap.md`.
- **`speak-ui-design-final-2026-06-28.md`** — its five-surface information architecture
  (menubar/overlay/dashboard/settings/privacy) still stands, but its *visual identity/look*
  is explicitly superseded by `frontend-identity.md` (2026-07-11).

## Research/snapshot (point-in-time, not a contract)

- **`landscape-analysis-2026-06-28.md`** — competitive analysis, fed
  `speak-ui-design-final-2026-06-28.md`.
- **`ui-ux-strategic-research-2026-06-28.md`** — strategic UI/UX research, same lineage.
- **`voice-ai-tts-research.md`** — TTS model evaluation; superseded in part, since shipped
  VoiceOut uses Apple's built-in `AVSpeechSynthesizer` rather than the third-party models
  evaluated here.

---

## Contradictions found (surfaced, not resolved)

Ranked by how likely each is to mislead a reader, highest first.

1. **`profile-taxonomy.md` vs. shipped code** — `profile-taxonomy.md:17` states: *"3
   destinations + Raw. No `Clean`/`Chat`/`Code`/`CLI`/`Prompt`/`Commit` as siblings —
   those were never separate destinations."* But
   `Speak/SpeakCore/Profiles/DefaultProfiles.swift:15-22` documents a later, deliberate
   decision: *"V01-3 (per-app context awareness)... `Chat` (below) closes that gap: same
   bundle-ID → profile mapping mechanism..., just a fifth built-in with `tone: .casual`."*
   The code's own comment frames this as an intentional amendment, not drift, but the two
   documents now flatly disagree on how many destinations exist. A reader of
   `profile-taxonomy.md` alone would not know `Chat` exists.
2. **`speak-ui-design-final-2026-06-28.md` vs. `frontend-identity.md`** —
   `speak-ui-design-final-2026-06-28.md:5` (original) declared *"Status: Locked design —
   implementation can now proceed"* with no scope limit. `frontend-identity.md:5-6` later
   states it *"Supersedes the Wispr-Flow-derived look as the default; `HUDStyle.classic`
   remains available but is no longer the identity."* The two only partially overlap — IA
   (sidebar, panes) vs. visual identity (palette, Pet) — but nothing in either file marks
   that boundary explicitly; a reader has to infer it.
Not a contradiction, but a note: `horizon-voice-os.md` self-declares "Superseded
2026-07-11" in its own body — unusual, since most superseded specs don't know it.
Confirmed consistent with `docs/roadmap.md:31`; flagged only because a self-aware
supersession note can read as "half-current" if skimmed.

## Proposed reorganization (data only — not executed)

No files were moved, renamed, or deleted. `CLAUDE.md`, `AGENTS.md`, `README.md`, and
`.claude/skills/*/SKILL.md` were grepped for every path below; inbound references are
listed so a central pass can repair them if a move is approved.

| current path | proposed path | why | inbound references that would break |
|---|---|---|---|
| `specs/horizon-voice-os.md` | `specs/archive/horizon-voice-os.md` | superseded, kept only as provenance | `CLAUDE.md:79` (agent-bridge design list), `docs/roadmap.md:31` |
| `specs/validation-findings.md` | `specs/archive/validation-findings.md` | closed dated audit, no inbound refs | none found |
| `specs/wispr-parity-and-spec.md` | `specs/archive/wispr-parity-and-spec.md` | its outputs are the live artifacts now, this is provenance | none found |
| `specs/dictation-flow.md` | `specs/archive/dictation-flow.md` | build contract fulfilled | none found |
| `specs/live-panel-prompt-shaper.md` | `specs/archive/live-panel-prompt-shaper.md` | design shipped, accurate historical record | none found |
| `specs/avb7-durable-calls-design.md` | `specs/archive/avb7-durable-calls-design.md` | shipped design record | `CLAUDE.md:79`, `docs/progress.md:249` |
| `specs/constraint-split-cs1-finding.md` | `specs/archive/constraint-split-cs1-finding.md` | closed finding, but still has a live revisit trigger (WWDC26 provider API) — **consider leaving in place** instead of archiving | `docs/progress.md:422` |
| `specs/landscape-analysis-2026-06-28.md` | `specs/research/landscape-analysis-2026-06-28.md` | dated competitive snapshot | none found |
| `specs/ui-ux-strategic-research-2026-06-28.md` | `specs/research/ui-ux-strategic-research-2026-06-28.md` | dated strategic snapshot | none found |
| `specs/voice-ai-tts-research.md` | `specs/research/voice-ai-tts-research.md` | dated tech-evaluation snapshot, partially superseded | none found |
| `specs/wispr-input-layer-taste.md` | *(leave in place)* | still actively depended on by `input-felt-speed.md` — don't archive a live dependency | `specs/input-felt-speed.md:3` |

Everything not listed above (`frontend-identity.md`, `verification-ledger.md`,
`agent-voice-bridge.md`, `profile-engine.md`, `profile-system-prompts.md`,
`profile-taxonomy.md`, `input-felt-speed.md`, `output-conversation-reconnect.md`,
`speak-ui-design-final-2026-06-28.md`) stays in `specs/` at the top level — actively
binding or actively referenced.

## Could not determine

- Whether `validation-findings.md`'s individual P0/P1 findings were each closed
  one-by-one — no per-finding tracking found in `docs/progress.md`; only the file's own
  "no inbound references" absence is evidence it isn't live-tracked elsewhere.
