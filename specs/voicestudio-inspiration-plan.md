# VoiceStudio Inspiration Plan — v0.1 Adaptation Track

> **Purpose**: The curated borrow-list from the VoiceStudio (formerly OmniVoice-Studio)
> reference project (`ai_docs/VoiceStudio`), mapped onto `speak`'s identity, hard
> rules, and roadmap. Each slice has a `[decision]`, a done-when, and a home.
> **Status**: living — orchestrator-owned, implementer-executed · **Last reviewed**: 2026-09-08

---

## 0. Why this exists

The v0 dictation core is frozen and validated (P14 ship gate passed). The next phase
(v0.1) builds toward the Profile Engine + Agent Interface. VoiceStudio is the
reference for **local-first voice product patterns**: 16 TTS / 11 ASR engines behind a
Model Catalogue, a dictation widget with honest delivery states and session-bound
insertion safety, a local speech platform, MCP + per-agent voice bindings, and a
"two defensible bets + obsessive polish" strategy.

Constraint fence — anything violating these is rejected (non-takes, §3):
- AGENTS.md §2 hard rules (local-only, 2 permissions, Apple-frameworks-only in v0,
  single Swift codebase, **never read the pasteboard**, no print, no force-unwrap/goto).
- Product identity (§0/§2 of `docs/product.md`): *speak* is the local human-agent
  interface, not a media/voice studio; dictation is the foundation, agents the destination.
- v0 core is frozen: slices must be additive, opt-in-by-default where they touch live UX.

---

## 1. The borrow list (Tier 1 — steal now)

| # | Idea (VoiceStudio) | Adapted for speak | Home / roadmap | Verified-offline? |
|---|---|---|---|---|
| W01 | Warm recognizers / preload / measured cold-start | **Warm cleanup model**: prewarm the Foundation Models engine so stop→clean latency drops; measure before/after | `SpeakCore/Cleanup` (this track) | Wiring yes; live latency `[deferred — needs Apple Intelligence Mac]` |
| W02 | Model Catalogue (install/remove/select/route, availability reasons, guided downloads) | First-class *Models* surface behind the existing engine selectors; availability + install hints | v0.1 (V01-1/V01-2), v1 (V1-1/V1-2) | Partial (needs real download flows) |
| W03 | Staged review "Review / Rapid-fire" | Raw→clean review before paste by default; rapid-fire auto-paste opt-in | Profile Engine commit step (task #29+) | Yes (state machine) |
| W04 | Deterministic fallback parsers | Steering phrases ("make it a bullet list", "no wait") get LLM-parse + keyword fallback | V1-3 Transforms, V1-7 course correction | Yes (pure Swift) |
| W05 | Honest delivery "Inserted"/"Copied" | Overlay done-state reports *Inserted at cursor / Copied / Blocked by secure field* | P6 overlay done-state | State yes; live `[deferred — needs human]` |
| W06 | Session-bound insertion ownership | Paste path enforces session-scoped target ownership (stale result ≠ newer target) | P6 + AVB | Mostly exists — audit + tests |
| W07 | Diagnostics surface (self-check, logs, scrubbed bundle) | In-app Diagnostics screen (permissions, engine availability, log tail, export bundle) | App layer (small) | Yes |
| W08 | Per-agent voice bindings | AVB-6 registered session → TTS persona for VoiceOut ("who is speaking") | AVB-8/9 + Voices surface | Partial |
| W09 | STT empty-decode failover + engine demotion | Empty-final + real audio ⇒ retry once via installed fallback engine; per-engine reliability | v0.1 (V01-1) | Partial (needs 2nd engine) |
| W10 | Agent skills ecosystem | Official `speak` skill for Claude Code / Codex / OpenCode dogfood | Docs + distribution | Yes |

## 2. The borrow list (Tier 2 — later-but-real)

- **VAD + endpointing** (their research basis) → V1-6 auto-segmentation; Apple VAD, not custom DSP.
- **Incremental re-clean** (their incremental re-dub) → V1-7 course correction + V3-3 multi-turn:
  re-clean only the changed tail, stitch with prior cleaned text (history already stores raw+cleaned).
- **CI op-count budgets** (hardware-independent) → one `clean()` call per dictation, zero when disabled.
- **i18n + locale-parity tests from day one** (21 locales) → adopt when the first non-English surface lands.

## 3. Non-takes (deliberate rejections)

| VoiceStudio feature | Why rejected |
|---|---|
| Clipboard snapshot/restore lease | **Reads the pasteboard → AGENTS.md §2.6 violation.** Keep write-only + Cmd+V. Adopt only the session-ownership half (W06). |
| Voice cloning / dubbing / audiobooks / vocal isolation / batch queues / watch folders | *speak* is an input interface for agents, not a media studio. Diarization only matters as V2-3 history speaker labels (WhisperKit SpeakerKit, not pyannote). |
| Remote workers / HF token stores / cloud API-key panels | Cloud is v1+ opt-in, Keychain-based, already planned. Their Phase-5 demand-driven deferral discipline is a model for ours. |
| AGPL licensing | Speak is MIT. |

## 4. Strategy (the "two bets" lens)

VoiceStudio's north star is *two defensible innovations + obsessive polish*. Speak's two
bets already exist in its docs and the frozen v0 is the validated foundation under them:

1. **The Profile Engine novel loop** — stream → live AI preview → steer → commit (§6d moat).
2. **The local human-agent voice interface** — agent turns in/out with sessions, receipts, attention.

This track concentrates next slices on closing those two loops (with live dogfood) wrapped in
the Tier-1 "trust plumbing" (warm model, catalogue UX, delivery honesty, diagnostics).

## 5. Slice ordering (dependency-aware)

1. **W01 — Warm cleanup model** (this branch: `feat/v01-warm-cleanup`) — fixes the single
   documented v0 finding (cleanup latency on long dictations); Core-only, additive.
2. W07 — Diagnostics surface (trust plumbing, independent).
3. W05 + W06 — Delivery honesty + session-bound paste audit (one loop).
4. W08 — Per-session voice persona (needs AVB-8/9 context).
5. W02 — Models Catalogue surface (needs v0.1 engines to be real first).
6. W04 — Steering phrase fallbacks (needs Transforms/Profile-Engine wiring).

---