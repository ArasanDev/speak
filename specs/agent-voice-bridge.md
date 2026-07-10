# Human-Agent Interface Runtime — Product Contract `[decision 2026-07-11]`

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

## 5. Current implementation `[verified from source 2026-07-11]`

The installed `speak-mcp` process serves MCP over local stdio and talks to the
running app through the existing local CFMessagePort CLI transport. Five tools
exist:

- `speak_notify`
- `speak_say`
- `speak_ask`
- `speak_confirm`
- `speak_status`

`speak_notify` validates a semantic kind but currently behaves as queued TTS;
its detail is not displayed or persisted. `speak_ask` and `speak_confirm` use a
visible request-owned capture, suppress focused-field paste, and wait
synchronously. Non-interrupting speech is serialized; interrupting speech
replaces active and pending agent speech; human dictation cancels agent speech.

These five tools prove transport and the single-process voice loop. They are
compatibility primitives, not the finished workflow surface.

## 6. Next implementation slice: structured input

Implement `speak_request_input` before expanding to multi-agent UI. It accepts:

- request identifier and idempotency key;
- prompt;
- mode: `freeform`, `choice`, or `approval`;
- choices when required;
- timeout;
- optional consequence and spoken summary.

It returns structured content containing exactly one outcome:
`answered`, `declined`, `cancelled`, `timedOut`, or `busy`. It reuses the visible
HUD and local STT, preserves paste suppression and request ownership, and
rejects concurrent capture as `busy`. Existing `speak_ask` and `speak_confirm`
become compatibility adapters over this workflow.

Done when every outcome, simultaneous requests, cancellation, timeout,
stale-answer isolation, and schema compatibility are tested, followed by one
live Codex or Claude Code question-response round trip. `[decision]`

## 7. Subsequent slices

1. Session registration and capability negotiation.
2. Durable Agent Calls with local inbox and response retrieval.
3. Semantic progress/completion events and compact activity presentation.
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
