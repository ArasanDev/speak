# v0.1 Capability Track

> **Purpose**: The ordered capability slices that take `speak` from the frozen
> v0 dictation core toward the Profile Engine + Agent Interface destination.
> Each slice has a `[decision]`, a done-when, and a home.
> **Status**: living — orchestrator-owned, implementer-executed · **Last reviewed**: 2026-09-17

---

## 0. Why this exists

The v0 dictation core is frozen and validated (P14 ship gate passed). The next
phase (v0.1) builds toward the Profile Engine + Agent Interface. The slices
below close the two product loops — the Profile Engine commit loop and the
local human-agent voice interface — wrapped in the trust plumbing a local
voice product needs: warm engines, honest delivery states, diagnostics, and
session-scoped insertion safety.

Constraint fence — anything violating these is rejected (see §3):
- AGENTS.md §2 hard rules (local-only, 2 permissions, Apple-frameworks-only in v0,
  single Swift codebase, **never read the pasteboard**, no print, no force-unwrap/goto).
- Product identity (§0/§2 of `docs/product.md`): *speak* is the local human-agent
  interface, not a media/voice studio; dictation is the foundation, agents the destination.
- v0 core is frozen: slices must be additive, opt-in-by-default where they touch live UX.

---

## 1. The capability list (Tier 1 — build now)

| # | Capability | What it means for speak | Home / roadmap | Verified-offline? |
|---|---|---|---|---|
| C01 | Warm cleanup model | Prewarm the Foundation Models engine so stop→clean latency on long dictations drops; measure before/after | `SpeakCore/Cleanup` — **landed `e4303f4`** | Wiring yes; live latency `[deferred — needs Apple Intelligence Mac]` |
| C02 | Models Catalogue surface | First-class *Models* surface behind the existing engine selectors; install/remove/select/route, availability reasons, guided downloads | v0.1 (V01-1/V01-2), v1 (V1-1/V1-2) | Partial (needs real download flows) |
| C03 | Staged review | Raw→clean review before paste by default; rapid-fire auto-paste opt-in | Profile Engine commit step (task #29+) | Yes (state machine) |
| C04 | Steering phrase fallbacks | Steering phrases ("make it a bullet list", "no wait") get LLM-parse + deterministic keyword fallback | V1-3 Transforms, V1-7 course correction | Yes (pure Swift) |
| C05 | Honest delivery states | Overlay done-state reports *Inserted at cursor / Copied / Blocked by secure field* — never a generic "done" | P6 overlay done-state | State yes; live `[deferred — needs human]` |
| C06 | Session-bound insertion ownership | Paste path enforces session-scoped target ownership (a stale result never targets a newer field) | P6 + AVB | Mostly exists — audit + tests |
| C07 | Diagnostics surface | In-app Diagnostics screen: permissions, engine availability, log tail, scrubbed export bundle | App layer (small) | Yes |
| C08 | Per-session voice persona | AVB-6 registered session → TTS persona for VoiceOut ("who is speaking") | AVB-8/9 + Voices surface | Partial |
| C09 | STT empty-decode failover | Empty-final + real audio ⇒ retry once via an installed fallback engine; per-engine reliability | v0.1 (V01-1) | Partial (needs 2nd engine) |
| C10 | Agent skill distribution | Official `speak` skill for coding-agent harnesses | Docs + distribution | Yes |

## 2. The capability list (Tier 2 — later-but-real)

- **VAD + endpointing** → V1-6 auto-segmentation; Apple VAD, not custom DSP.
- **Incremental re-clean** → V1-7 course correction + V3-3 multi-turn:
  re-clean only the changed tail, stitch with prior cleaned text (history already stores raw+cleaned).
- **CI op-count budgets** (hardware-independent) → one `clean()` call per dictation, zero when disabled.
- **i18n + locale-parity tests from day one** → adopt when the first non-English surface lands.

## 3. Rejected scope (deliberate decisions)

| Rejected | Why |
|---|---|
| Clipboard snapshot/restore lease | **Reads the pasteboard → AGENTS.md §2.6 violation.** Keep write-only + Cmd+V. Only the session-ownership half is adopted (C06). |
| Voice cloning / dubbing / audiobooks / vocal isolation / batch queues / watch folders | *speak* is an input interface for agents, not a media studio. Diarization only matters as V2-3 history speaker labels. |
| Remote workers / token stores / cloud API-key panels | Cloud is v1+ opt-in, Keychain-based, already planned. Demand-driven deferral: build cloud surfaces only when the engines behind them are real. |

## 4. Strategy (the "two bets" lens)

Speak's north star is *two defensible innovations + obsessive polish*. The frozen
v0 is the validated foundation under them:

1. **The Profile Engine novel loop** — stream → live AI preview → steer → commit (§6d moat).
2. **The local human-agent voice interface** — agent turns in/out with sessions, receipts, attention.

This track concentrates next slices on closing those two loops (with live dogfood),
wrapped in the Tier-1 trust plumbing (warm model, catalogue UX, delivery honesty, diagnostics).

## 5. Slice ordering (dependency-aware)

1. **C01 — Warm cleanup model** (landed `e4303f4`) — fixes the single
   documented v0 finding (cleanup latency on long dictations); Core-only, additive.
2. C07 — Diagnostics surface (trust plumbing, independent).
3. C05 + C06 — Delivery honesty + session-bound paste audit (one loop).
4. C08 — Per-session voice persona (needs AVB-8/9 context).
5. C02 — Models Catalogue surface (needs v0.1 engines to be real first).
6. C04 — Steering phrase fallbacks (needs Transforms/Profile-Engine wiring).
