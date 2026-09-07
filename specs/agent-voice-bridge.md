# Human-Agent Interface Runtime — Product Contract `[decision 2026-07-11]`

**Status:** active/binding — north star · **Binds:** the product boundary (§1), domain
objects (§3), safety invariants (§8) for the agent-bridge layer; `docs/roadmap.md` "North
star" cites this as the canonical contract · **Owner:** orchestrator · **Depends on:**
`docs/product.md` · **Superseded by:** none · **Last substantive change:** 2026-07-11

> **Canonical post-dictation direction.** `docs/product.md` defines why the
> product exists; this specification defines the interaction model. The v0
> dictation ship gate remains unchanged.

## 1. Product boundary

`speak` is the local input, output, routing, and attention layer between a
human and software agents. It is not an agent, reasoning engine, orchestration
framework, or general automation server.

Connected agents own planning, tools, execution, and verification. `speak`
owns voice capture, local transformations, session addressing, delivery state,
human calls, response routing, and presentation. MCP is the first adapter; it
is not the domain model. `[decision]`

## 2. Closed loop

```text
human expression
  → preserve raw speech
  → shape intent locally
  → deliver to an identified agent session
  → receive a receipt
  → present semantic agent events
  → request attention only when needed
  → capture a bounded human response
  → return it to the originating session
```

Dictation-to-focused-field remains the universal fallback. An unavailable or
incapable adapter must never make basic dictation unusable.

## 3. Domain objects

These objects belong in `SpeakCore` and must not depend on MCP types.

### `VoiceTurn`

One human expression: immutable raw transcript, optional corrected transcript,
optional locally derived intent envelope, creation time, and provenance for
every transformation. A later amendment refers to the original turn rather
than pretending to be unrelated input.

### `AgentSession`

A routable destination: stable identifier, provider/client, repository or
working directory, human label, state, capabilities, and last-seen time.
Registration does not grant access to files, screen contents, history, or the
microphone.

### `DeliveryReceipt`

The result of attempting to deliver a turn or response: delivery identifier,
destination, state (`accepted`, `rejected`, `timedOut`, `cancelled`), and time.
“Sent” means an adapter acknowledged it; `speak` never infers delivery from a
successful paste or process write.

### `AgentEvent`

A semantic state update such as `working`, `progress`, `blocked`, `failed`, or
`completed`. It is not a token stream, chain of thought, log transport, or
arbitrary UI instruction.

### `AgentCall`

A durable request requiring the human: free-form question, constrained choice,
approval, or acknowledgement. It records origin, prompt, choices, consequence,
urgency recommendation, state, creation time, and expiration.

### `HumanResponse`

A typed outcome: `answered`, `declined`, `cancelled`, `timedOut`, or `busy`,
with text or choice only when appropriate. Cancellation and ambiguity must
never silently become `false`.

### `AttentionPolicy`

Local user-owned rules deciding whether an event is silent, visible, queued,
or spoken. Agent urgency is input to the policy, never authority over it.

## 4. Tools are semantic workflows

An MCP tool describes the human job to complete, not the UI/audio primitives
used to complete it. Agents must not compose `show_overlay`, `play_audio`,
`open_microphone`, and `create_button`. They invoke workflows such as:

- `speak_register_session`
- `speak_report_progress`
- `speak_notify`
- `speak_request_input`
- `speak_request_approval`
- `speak_complete`

`speak` composes persistence, inbox state, notification, TTS, visible capture,
timeout, response parsing, and routing consistently. Common metadata includes
`sessionId`, `idempotencyKey`, summary, semantic kind, response contract,
expiration, and privacy hints.

## 5. Current implementation `[verified from source 2026-07-30]`

The installed `speak-mcp` process is the **only** MCP server: it serves MCP over
local stdio and talks to the running app through the existing local CFMessagePort
CLI transport. JSON-RPC / tool dispatch live in `SpeakCore/AgentBridge/
AgentBridgeServer`; the App target owns mic, TTS, overlay, and permissions. There
is no second MCP dispatcher inside the App. `[decision 2026-07-30]`

### Published tool catalog

| Tool | Role |
|---|---|
| `speak_register_session` | Session registration + capability negotiation |
| `speak_status` | App/mic/engine availability |
| `speak_notify` | Attention-worthy spoken outcome (semantic kind) |
| `speak_request_input` | Structured human input (`freeform` / `choice` / `approval`) |
| `speak_submit_call` / `speak_get_call` | Durable inbox (async; requires session) |
| `speak_say` | Compatibility TTS primitive |
| `speak_ask` / `speak_confirm` | Compatibility wrappers over `speak_request_input` |

`speak_notify` validates a semantic kind but currently behaves as queued TTS;
its detail is not displayed or persisted. `speak_request_input` owns the
visible capture, paste suppression, busy-on-concurrent, and typed outcomes.
`speak_ask` / `speak_confirm` are thin adapters over that workflow. Non-
interrupting speech is serialized; interrupting speech replaces active and
pending agent speech; human dictation cancels agent speech.

### Presentation (not MCP surface)

Conversation overlay (`ConversationLoopManager`, Magenta HUD, VAD helpers) is an
optional **presentation backend** for `speak_request_input` and the agent speech
queue. Conversation mode (`fullDuplex` / `pushToTalk` / `gatedTurn`) is a local
Speak setting — never an MCP tool argument. Agents must not compose overlay,
mic, or TTS primitives. `[decision 2026-07-30]`

### Withdrawn tools

`speak_ask_user` and `speak_stream_speech` (Layer-4 experiment) are **withdrawn**
from the MCP catalog. They duplicated `speak_request_input` / `speak_say` and
leaked UI/audio primitives into the adapter surface. `[decision 2026-07-30]`

## 6. Structured input `[done — AVB-5]`

`speak_request_input` accepts:

- request identifier and idempotency key;
- prompt;
- mode: `freeform`, `choice`, or `approval`;
- choices when required;
- timeout;
- optional consequence and spoken summary.

It returns structured content containing exactly one outcome:
`answered`, `declined`, `cancelled`, `timedOut`, or `busy`. It reuses the visible
HUD (classic or conversation presentation) and local STT, preserves paste
suppression and request ownership, and rejects concurrent capture as `busy`.

## 7. Subsequent slices

1. ~~Session registration and capability negotiation.~~ **Done (AVB-6).**
2. ~~Durable Agent Calls with local inbox and response retrieval.~~ **Done (AVB-7).**
3. Semantic progress/completion events and compact activity presentation (AVB-8).
4. Human voice-turn delivery to a selected session with receipts.
5. Amendment and cancellation of recent deliveries.
6. Per-client enablement, cooldown, deduplication, quiet policy, and privacy.
7. Additional provider adapters only after the first closed loop is dogfooded.

## 8. Safety invariants

- Audio, transformations, interaction state, and attention policy remain local
  by default.
- Hotkey input always outranks and interrupts agent TTS.
- No agent receives ambient microphone access.
- Every agent-initiated capture is visible, bounded, and cancellable.
- Only the originating call/session receives its response.
- No tool reads pasteboard contents, dictation history, files, or screen text.
- No generic shell, Git, browser, Shortcuts, or OS-automation tools belong in
  the agent bridge.
- Explicit adapter-contributed vocabulary/context is scoped and inspectable.
- Raw speech is retained alongside, never overwritten by, transformed intent.

## 9. Success tests

The product direction remains falsifiable:

1. Structured voice turns reduce clarification/rework against raw STT.
2. The inbox reduces time-to-human-response without creating interruption noise.
3. Direct session delivery is preferred to focused-field paste and has a
   measured misrouting rate below the product threshold.

Until those tests pass, describe direct multi-agent interaction as an active
product hypothesis, not a proven moat.
