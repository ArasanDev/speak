# Agent Voice Bridge — Product Contract `[decision 2026-07-10]`

## Product promise

`speak` lets a local coding agent reach the developer when the agent deserves
attention, and lets the developer answer without returning to the terminal.
Speech recognition and speech synthesis stay on the Mac by default.

`speak` is the human I/O layer. It is not an agent, an orchestration framework,
or a general-purpose automation MCP server. The connected coding agent owns
reasoning and actions; `speak` owns attention, voice input, and voice output.

## Core jobs

1. **Rich prompt input** — the existing global dictation path remains the
   primary wedge and must not regress.
2. **Attention-worthy notification** — an agent reports a completion, blocker,
   warning, or explicitly requested readback using a short spoken summary.
3. **Bounded response** — an agent asks one visible question and receives the
   answer from an explicit local capture session.
4. **Explicit approval** — a future specialization presents action, scope, and
   consequence and preserves yes/no/cancel/timeout as distinct outcomes.

## MCP surface

### Product tool: `speak_notify`

Inputs:

- `summary` — short, self-contained spoken outcome.
- `kind` — `completion`, `blocked`, `warning`, or `requested`.
- `interrupt` — whether this notification may replace current speech.
- `detail` — reserved for the future visual inbox; currently ignored and never spoken.

Agents should call it only for final outcomes, blockers, high-severity warnings,
or readback explicitly requested by the user. Routine progress, logs, diffs,
stack traces, and token streams stay visual.

The existing `speak_say`, `speak_ask`, `speak_confirm`, and `speak_status` tools
remain compatibility primitives during migration. `speak_notify` is the
preferred application-level entry point.

### Next product tool: `speak_request_input`

This will unify free-form questions and choices and return a structured outcome:
`answered`, `declined`, `cancelled`, `timedOut`, or `busy`. It must not ship as a
promoted workflow until capture is paste-free, the result is owned by the
request that started it, and the microphone interaction is visibly surfaced.

### Later resources

- `speak://status` — running/listening/speaking/busy and permission state.
- `speak://capabilities` — supported response modes and local engines.

Resources are additive. Core interoperability must continue to work with MCP
clients that support tools only.

## Attention and safety policy

- User policy outranks agent-supplied urgency.
- Default speech is concise: outcome first; details remain on screen.
- Hotkey input always interrupts TTS.
- An agent never gets ambient microphone access.
- Every agent-initiated capture is visible and cancellable.
- Only the requesting client receives its answer.
- No MCP tool reads pasteboard contents, dictation history, files, or screen text.
- No generic shell, Git, browser, or OS-automation tools belong in this server.
- Voice Actions remain a separate, human-invoked, user-curated Shortcuts path.

## MVP sequence

1. Productize and dogfood completion/blocker notification.
2. Add speech cancellation, queue policy, cooldown, and per-client enablement.
3. Replace the current question primitives with paste-free, request-owned input.
4. Add approval-specific presentation and structured outcomes.
5. Add status/capability resources and a native setup/diagnostics screen.
6. Add a local multi-agent inbox only after the single-agent loop proves useful.

## Success signal

The flagship loop is: start a long coding task by voice, leave the terminal,
hear one concise completion or blocker, answer one bounded question, and let the
agent continue. The product succeeds when this closes agent loops faster without
creating notification noise or requiring cloud audio.
