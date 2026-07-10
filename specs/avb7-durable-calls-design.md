# AVB-7 — Durable Agent Calls + Local Inbox — Implementation Design

Spec: `specs/agent-voice-bridge.md` §7.2, domain objects §3, safety §8, success test 2 (§9).
Builds on AVB-6's in-memory `AgentSessionRegistry` actor (SpeakCore/AgentBridge) for session
identity/ownership. Reuses AVB-5's `HumanResponseOutcome`, `RequestInputMode`,
`RequestInputExtractor`, and the CFMessagePort CLI transport — no new transport.

## Decisions

1. **`AgentCall` is a new domain type, not a reuse of `HumanResponseOutcome`.** The outcome
   type stays the terminal-answer vocabulary; `AgentCall` wraps it with durable request state
   (pending/presented), timestamps, and ownership. Why: `HumanResponseOutcome` has no room for
   "not yet resolved" and must not grow one — collapsing "no answer yet" into an outcome enum
   invites exactly the "ambiguity as false success" bug AVB-5 explicitly avoided.
2. **Separate SQLite store (`AgentCallStore`), separate file, same raw-C-API pattern as
   `HistoryStore`.** Why: access pattern differs fundamentally — history is append/read-only
   and export/clear are its whole surface; agent calls are mutated in place (pending →
   presented → terminal), queried by state for the inbox badge, and have their own retention
   (expiry) unrelated to dictation history retention. Coupling them would leak agent-call
   churn into the user-facing History pane's semantics.
3. **Submit and poll are both fire-and-return DB operations — no run-loop pump.** Why:
   `CLIPortServer`'s pump (`pumpUntilResult`, CLIPortServer.swift:457) already carries a
   documented orphaned-`Task` risk when its ceiling elapses before the awaited work finishes;
   the port is a single synchronous callback on the main run loop, so holding a pump open for
   a long-poll would block every other CLI command (including another agent's `--status` or
   `speak_get_call`) for the duration. Submit and get are synchronous actor reads/writes with
   no waiting, so neither needs a pump at all.
4. **`speak_request_input` keeps its existing synchronous dictation round-trip** (pump
   included) but now durably records the call as a side effect, satisfying "thin adapter over
   the durable path" without touching its latency or tested behavior. New durable calls
   (`speak_submit_call`) do **not** open the mic at submit time — presentation and capture are
   decoupled and driven by the human from the inbox.
5. **Default attention policy for this slice: `visible` only — badge + inbox row, never
   auto-spoken.** Why: spec §9 test 2 requires the inbox to reduce time-to-response *without
   creating interruption noise*; auto-speaking every pending call would just move the existing
   `speak_ask`-style interruption into a queue instead of removing it. `urgency` is persisted
   and threaded through so a future policy can use it — it is never allowed to escalate
   presentation in this slice (spec §3: "urgency is input, never authority").

## Domain types

```swift
// SpeakCore/AgentBridge/AgentCall.swift

/// Caller-supplied hint only — never authority over presentation (spec §3).
public enum AgentCallUrgency: String, Codable, Sendable, Equatable {
    case low, normal, high
}

/// spec §3 `AgentCall` state machine:
///   pending --present()--> presented --resolve()--> {answered, declined, cancelled, timedOut}
///   pending/presented --expire()--> expired   (deadline elapsed, human never engaged)
/// `expired` is distinct from `timedOut`: `timedOut` means a live capture round-trip's own
/// deadline elapsed (AVB-5 semantics, still used by the adapter path); `expired` means the
/// call sat in the inbox past `expiresAt` with no human action at all.
public enum AgentCallState: String, Codable, Sendable, Equatable {
    case pending, presented, answered, declined, cancelled, timedOut, expired

    public var isTerminal: Bool {
        switch self {
        case .pending, .presented: return false
        case .answered, .declined, .cancelled, .timedOut, .expired: return true
        }
    }
}

/// Durable request record (spec §3 `AgentCall`). `response` is populated only once `state`
/// reaches a terminal value — it is exactly a `HumanResponseOutcome`, never a re-encoding of
/// one, so `speak_get_call`'s reply and `speak_request_input`'s reply share one shape.
public struct AgentCall: Sendable, Equatable, Identifiable {
    public let id: UUID
    /// AVB-6 `AgentSession.sessionId` that submitted this call. Required for
    /// `speak_submit_call`/`speak_get_call`; `nil` only for the `speak_request_input`
    /// legacy adapter path, which never leaves the requesting call stack (§ Isolation below).
    public let sessionId: String?
    public let requestId: String
    public let idempotencyKey: String?
    public let prompt: String
    public let mode: RequestInputMode
    public let choices: [String]
    public let consequence: String?
    public let spokenSummary: String?
    public let urgency: AgentCallUrgency
    public var state: AgentCallState
    public let createdAt: Date
    public let expiresAt: Date?
    public var presentedAt: Date?
    public var resolvedAt: Date?
    public var response: HumanResponseOutcome?
}

public enum AgentCallSubmitResult: Sendable, Equatable {
    case created(AgentCall)
    /// Same (sessionId, idempotencyKey) already has a live (non-terminal) call.
    /// Distinct from `.busy` (AVB-5: "a synchronous capture is in flight") — this is
    /// "you already asked this", a different cause, never collapsed into the same signal.
    case duplicateSubmission(existingCallId: UUID)
}

public protocol AgentCallStoring: Sendable {
    func submit(
        sessionId: String?, requestId: String, idempotencyKey: String?, prompt: String,
        mode: RequestInputMode, choices: [String], consequence: String?, spokenSummary: String?,
        urgency: AgentCallUrgency, expiresAt: Date?
    ) async throws -> AgentCallSubmitResult

    func get(id: UUID, requestingSessionId: String?) async throws -> AgentCall?
    /// Non-terminal calls, newest first — backs the inbox list + badge count.
    func pendingAndPresented() async throws -> [AgentCall]
    func markPresented(id: UUID) async throws
    /// CAS: only transitions if current state is non-terminal. Returns `false` if the
    /// call already resolved (race lost) — caller logs and discards, never overwrites.
    @discardableResult
    func resolve(id: UUID, outcome: HumanResponseOutcome) async throws -> Bool
    /// Sweep: transitions any non-terminal call past `expiresAt` to `.expired`. Called on
    /// store open (recovery) and periodically (e.g. inbox refresh).
    func expireOverdue(now: Date) async throws
}

public actor AgentCallStore: AgentCallStoring { /* raw SQLite3, HistoryStore's pattern */ }
```

## Schema DDL

New file `~/Library/Application Support/speak/agent-calls.sqlite` (own connection, own actor).

```sql
CREATE TABLE IF NOT EXISTS agent_calls (
    id             TEXT PRIMARY KEY NOT NULL,
    sessionId      TEXT,
    requestId      TEXT NOT NULL,
    idempotencyKey TEXT,
    prompt         TEXT NOT NULL,
    mode           TEXT NOT NULL,
    choicesJSON    TEXT,
    consequence    TEXT,
    spokenSummary  TEXT,
    urgency        TEXT NOT NULL DEFAULT 'normal',
    state          TEXT NOT NULL,
    createdAt      REAL NOT NULL,
    expiresAt      REAL,
    presentedAt    REAL,
    resolvedAt     REAL,
    responseJSON   TEXT
);
CREATE INDEX IF NOT EXISTS idx_agent_calls_state ON agent_calls (state, createdAt DESC);
CREATE INDEX IF NOT EXISTS idx_agent_calls_session ON agent_calls (sessionId, createdAt DESC);
-- Partial unique index: only live (non-null-key) submissions collide; NULL keys never conflict.
CREATE UNIQUE INDEX IF NOT EXISTS idx_agent_calls_idempotency
    ON agent_calls (sessionId, idempotencyKey) WHERE idempotencyKey IS NOT NULL;
```

Migration approach mirrors `HistoryStore.setupSchema`: `CREATE TABLE IF NOT EXISTS` +
idempotent `ALTER TABLE ... ADD COLUMN` lines for any future additive column, ignoring the
"duplicate column" error on already-migrated DBs. No `PRAGMA user_version` machinery — matches
the existing single-additive-column precedent (`[decision]` at HistoryStore.swift:285).

`resolve()`'s CAS is a single statement, not read-then-write:

```sql
UPDATE agent_calls
SET state = ?, resolvedAt = ?, responseJSON = ?
WHERE id = ? AND state IN ('pending','presented');
-- caller checks sqlite3_changes() == 1; 0 means already-resolved, discard silently (logged).
```

## Tool surface

```jsonc
// speak_submit_call — fast, no mic, no pump. Returns immediately.
{
  "name": "speak_submit_call",
  "inputSchema": { "type": "object", "properties": {
    "requestId": {"type": "string"},
    "idempotencyKey": {"type": "string"},
    "prompt": {"type": "string"},
    "mode": {"type": "string", "enum": ["freeform", "choice", "approval"]},
    "choices": {"type": "array", "items": {"type": "string"}},
    "consequence": {"type": "string"},
    "spokenSummary": {"type": "string"},
    "urgency": {"type": "string", "enum": ["low", "normal", "high"], "description":
      "A hint only — never overrides the human's local attention policy."},
    "expiresInSeconds": {"type": "number"}
  }, "required": ["requestId", "prompt", "mode"] }
}
// returns: {"callId": "<uuid>", "state": "pending"}  OR
//          {"callId": "<uuid-of-existing>", "state": "<its current state>", "duplicate": true}

// speak_get_call — fast, no mic, no pump. Poll on a caller-chosen interval (no server-side wait).
{
  "name": "speak_get_call",
  "inputSchema": { "type": "object", "properties": {
    "callId": {"type": "string"}
  }, "required": ["callId"] }
}
// returns: {"state": "pending" | "presented"}  OR
//          {"state": "answered", "text": "...", "choice": "..."} | declined | cancelled |
//          timedOut | expired
// Isolation failure (wrong session): tool error, not a state value — "call not found" (never
// reveals that the id exists for another session — spec §8 "only the originating
// call/session receives its response").
```

`speak_request_input` (existing) is unchanged at the MCP schema level. Internally,
`AgentBridgeServer.runRequestInputTool` now also calls `AgentCallStore.submit(...)` (sessionId:
nil) immediately followed by `markPresented` before driving the existing dictation round-trip
via `CLIBridgeBackend.requestInput`, then `resolve(id:outcome:)` with the result — same
latency, now durably visible in the inbox while in flight and briefly after. `speak_ask` /
`speak_confirm` are unaffected (they don't route through `AgentCall` — no spec requirement to).

## Wire changes (CLIContract.swift / CLIPortServer.swift)

Two new `CLICommand` cases, additive only (old/new cross-decode preserved per existing
convention):

- `.submitCall` — request carries the same fields as `speak_submit_call`'s arguments plus
  `sessionId` (threaded from the AVB-6-registered MCP connection, see Isolation below). Handled
  **outside** `MainActor.assumeIsolated`'s closure like `ask`/`confirm`/`requestInput` are, but
  with **no `Task`+pump** — it's a direct `await` on the `AgentCallStore` actor, replied inline.
  Reply: `.callSubmitted(callId:, state:, duplicate:)`.
- `.getCall` — request carries `callId` + `sessionId`. Direct actor read, replied inline. Reply:
  `.callStatus(state:, response: HumanResponseOutcome?)`.

`CLICommandHandler` protocol gains two new methods mirroring `cliRequestInput`'s doc style, but
returning immediately (`async` only because the store is an actor, not because they wait on
anything): `cliSubmitCall(...) async -> AgentCallSubmitResult`, `cliGetCall(id:sessionId:) async
-> AgentCall?`. No new `CLIAskOutcome`-style wrapper needed — the store's own types are the
wire payload.

## State machine (text diagram)

```
                 submit()                 markPresented()
        ┌──────────┐  ──────────────►  ┌───────────┐
        │  (none)  │                   │  pending  │ ───────────────► presented
        └──────────┘                   └───────────┘                      │
                                              │  expireOverdue()           │ resolve()/expireOverdue()
                                              ▼                            ▼
                                          expired ◄──────────────────────  {answered, declined,
                                                                             cancelled, timedOut}
```
All terminal states are absorbing. `resolve()` is the only transition out of `presented`
besides expiry; both `resolve()` and `expireOverdue()` use the same `state IN
('pending','presented')` CAS guard, so whichever commits first wins and the other is a no-op.

## Inbox presentation (this slice's cut line)

Reuse existing scaffolding, no new chrome pattern:
- **Include:** one new Dashboard pane (`AgentInboxPaneView`, `Dashboard/Panes/`, following
  `HistoryPaneView`'s shape) listing non-terminal `AgentCall`s (prompt, urgency tag, elapsed
  time, mode). Per row: **Answer by voice** (drives the same `CaptureSession` +
  `RequestInputExtractor` pipeline `speak_request_input` already uses, then calls
  `resolve(id:outcome:)`), **Decline**, **Dismiss** (→ `cancelled`, no mic). A menubar badge
  (small count overlay on the existing `MenubarIcon`, `App/Overlay` or `SpeakApp.swift`) shows
  `pendingAndPresented().count`; tapping opens the Dashboard to this pane.
- **Defer:** spoken/proactive announcement of new calls (belongs to a future `AttentionPolicy`
  slice), swipe/multi-select, per-session filtering UI, historical/resolved-call browsing,
  push-style live badge updates (poll on pane appear + a coarse timer is enough for v-slice).

## Attention integration

A newly-submitted call is inserted as `pending`; the app (not the agent) decides when to call
`markPresented` — for this slice, **immediately on submit**, since the fixed policy is
`visible` (badge + inbox row) with no queuing tier yet. It never enters `AgentSpeechQueue` —
that queue stays scoped to `speak_say`/`speak_notify`'s spoken channel. `urgency` is persisted
and returned in `speak_get_call` payloads (so a future policy consumer has it) but this slice's
`AgentCallStore`/inbox code path never branches on it — enforcing spec §3's "urgency is input,
never authority" by construction, not by convention.

## Isolation invariants

- **Only the originating session retrieves its response:** `speak_submit_call`/`speak_get_call`
  require a `sessionId` resolved from the calling MCP process's registered `AgentSession` (AVB-6
  registry — `BridgeBackend` gains a `boundSessionId: String?` set at `speak_register_session`
  time and threaded into every durable-call call). `AgentCallStore.get(id:requestingSessionId:)`
  returns `nil` (not an error revealing existence) when `call.sessionId != requestingSessionId`.
  An unregistered caller (no AVB-6 session) cannot use `speak_submit_call`/`speak_get_call` at
  all — tool error "register a session first" — closing the hole a `nil` sessionId would open.
- **`speak_request_input`'s adapter path** stores `sessionId: nil` and is exempt from this check
  by construction: its `resolve()` happens synchronously inside the same call stack that
  submitted it (CLIPortServer's existing pump), so no other caller can ever reach it via
  `speak_get_call` before it's already terminal and gone from the inbox's non-terminal set.
- **Recovery on app restart:** rows persist in SQLite as-is; nothing auto-resumes a mic capture.
  On `AgentCallStore` open, run `expireOverdue(now:)` once so any call whose `expiresAt` passed
  while the app was closed shows as `.expired`, not stuck `.pending` forever. Calls still inside
  their expiry window reappear in the inbox exactly as before restart — durability is the point.

## Concurrency hazards (ship-blockers if unguarded)

1. **Resolve/expire race** (human answers as the expiry sweep fires) — CAS `UPDATE ... WHERE
   state IN (...)`; loser's write affects 0 rows, discarded and logged, never an error.
2. **Concurrent duplicate submissions** (same sessionId+idempotencyKey) — partial unique index;
   loser's `INSERT` throws `SQLITE_CONSTRAINT`, caught → `.duplicateSubmission(existingCallId:)`
   — **never** the AVB-5 `.busy` signal, which means a causally different thing (a live
   synchronous capture in progress). Distinct causes must not share one signal.
3. **TOCTOU on isolation check** — `get`/`resolve` do the ownership check and the mutation in
   one non-suspending actor method body; no `await` between check and act.
4. **Two code paths must never resolve the same call.** `speak_submit_call` calls only resolve
   via the inbox UI; `speak_request_input` calls only resolve via their own synchronous pump —
   no shared resolution path, so no future change can wire one onto the other's id space.
5. **Orphaned-Task risk avoided structurally, not mitigated** — Decision 3 means neither new
   tool spawns a `Task` awaited via `pumpUntilResult`. A future genuine long-poll must not reuse
   that pump; it needs its own bounded, cancellable mechanism off the single-threaded callback.

## Test plan (invariants a test must lock)

- State machine: every legal transition succeeds; illegal ones (`resolve`/`markPresented` on a
  terminal call) are documented no-ops, never crashes.
- CAS race: two concurrent `resolve()` calls on one id — exactly one wins; loser gets `false`.
- Idempotency race: two concurrent `submit()` calls, same (sessionId, key) — one `.created`,
  one `.duplicateSubmission(existingCallId:)` pointing at the same id.
- Isolation: `get(id:requestingSessionId:)` is `nil` for a mismatched session; succeeds for a
  matching session; a `nil`-session call is only visible to a `nil`-session requester.
- Recovery: a `pending` row with a past `expiresAt`, after reopen + `expireOverdue(now:)`,
  becomes `.expired`; a row with a future `expiresAt` is untouched.
- `speak_request_input` adapter parity: all existing AVB-5 outcome/timeout/cancel/schema tests
  pass unmodified — the durable side effect must not change observable tool behavior.
- Schema: opening a fresh DB creates the table; opening an already-migrated DB twice is a no-op.

## Explicit deferrals

- Any non-`visible` `AttentionPolicy` tier (silent/queued/spoken) — needs user-facing settings
  UI and a policy object, out of scope for this slice per Decision 5.
- Proactive spoken announcement of new calls.
- Cross-session inbox view / filtering by agent (single flat list this slice; `sessionId` is
  stored and available for a later filter, not exposed in UI yet).
- Amendment/cancellation of an already-submitted call by the *agent* (only the human can
  decline/dismiss in this slice — spec §7.2 item 5 is a separate future slice).
- Multi-call batching, structured-content MCP blocks (still text-JSON, matching AVB-5's
  `renderRequestInput` precedent — no schema-generation library).

## Open questions

None that block implementation — every design question above resolved to a decision.
