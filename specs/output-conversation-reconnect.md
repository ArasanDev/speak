# Spec: Output — Reconnecting the Conversation

Status: **active** · Owner: output slice · Depends on: `specs/agent-voice-bridge.md` §5

## 1. What actually happened (the diagnosis)

> **Correction (2026-07-30):** an earlier draft of this spec claimed Loop #78 removed
> `speak_ask_user` / `speak_stream_speech` and the `.askUser` / `.streamSpeech` CLI
> verbs. **That was wrong.** Both verbs are present at `CLIContract.swift:124,126`,
> both tools are advertised by `AgentBridgeTools.swift`, and the whole Layer-4 path is
> wired end to end. The real causes are below. [verified by grep on `b72bd7c`]

The bidirectional voice loop was **built successfully** on 2026-07-26 in commit
`e4ae017` — "bidirectional-voice: full-duplex voice loop + VAD + barge-in + MCP
bridge (Layers 1-4)". Current state of the four layers:

| Layer | Artifact | State on `b72bd7c` |
|---|---|---|
| 1 | `VoiceActivityDetector` (286 LOC, RMS energy, 600ms silence, barge-in callback) | **zero non-test callers — never instantiated** |
| 1 | `SpeechSynthesizerStream` (373 LOC, sub-10ms `stopImmediately()`) | **zero non-test callers — never instantiated** |
| 2 | `ConversationLoopManager` (495 LOC, `.fullDuplex` transitions, VAD handlers, interrupt) | **intact and reachable** |
| 3 | `ConversationOverlayView` (Mute / Interrupt / mode switcher) | present, wired |
| 4 | `SpeakMCPServer` + `AskUserToolHandler` + both tools | **present and wired** |

Two independent failures, neither an engineering-capability failure:

1. **The tools were invisible, because the installed bridge was 19 days stale.** The
   installed `~/Library/Application Support/speak/mcp/bin/speak-mcp` was dated Jul 11;
   its embedded `SpeakCore.framework` Jul 10. The source advertises **eleven** tools;
   that stale bridge exposed **nine** — missing exactly `speak_ask_user` and
   `speak_stream_speech`. An agent connected to it could not see the bidirectional
   surface at all. `make install-mcp-user` is not in `make gates` and nothing warned.
   [verified: the orchestrator's own live MCP session listed precisely those nine]

2. **Even when reached, `.fullDuplex` cannot commit a turn.** `AskUserToolHandler`
   defaults to `.fullDuplex`, opens the mic via `beginDictation()`, and sets
   `onUserTurnCommitted`. But that callback fires only from `commitUserTurn` or
   `handleVADSilenceDetected` — and **nothing ever constructs a
   `VoiceActivityDetector`**, so `handleVADSilenceDetected` is never called. The user
   speaks, and the call hangs until the 120-second timeout. Likewise no barge-in,
   because `SpeechSynthesizerStream` is never constructed either.

Symptom, precisely: *the mic opens, the overlay appears, you talk, nothing happens,
it times out.* That is what "I tried bidirectional and it wasn't successful" was.

Cause 1 is already fixed (bridge reinstalled). This spec fixes cause 2 and makes
cause 1 structurally impossible to recur.

## 2. Objective

An agent can hold a spoken conversation with the human — speak, be interrupted
mid-sentence, hear the reply, continue — through the **existing** tool surface. No
new MCP tool, no amendment to `specs/agent-voice-bridge.md` §5.

## 3. Design — instantiate the two orphans

**Do not add a `conversation` mode to `RequestInputMode`, and do not add a tool.**
An earlier draft proposed that; it was based on the incorrect belief that
`speak_ask_user` had been withdrawn. It has not been. The front door exists and
works — what is missing is that two of the four Layer-1 primitives are never
constructed. [decision]

The fix is narrow: `AskUserToolHandler` must own a `VoiceActivityDetector` and a
`SpeechSynthesizerStream`, and feed them into the `ConversationLoopManager` handlers
that already exist and are already tested.

### 3.1 What must be wired

- `AudioCapture` buffers → `VoiceActivityDetector` → the three existing
  `handleVADSpeechStarted` / `handleVADTranscriptUpdated` / `handleVADSilenceDetected`
  entry points. The handlers exist and are tested; only the feed is missing.
- Agent speech → `SpeechSynthesizerStream`, with `VoiceActivityDetector`'s barge-in
  callback calling `stopImmediately()`. This is the whole point: interruption is
  what makes it a conversation instead of an intercom.
- `AskUserToolHandler` constructs both primitives (today it constructs neither) and
  tears them down on every exit path. `onUserTurnCommitted` already resolves the
  continuation — that half works; it is simply never reached.
- The existing 120s timeout must remain the backstop, not the primary path. After
  this change a normal turn commits on VAD silence in well under a second.

### 3.2 Hard constraints

- **The mic must close.** Full-duplex holds the microphone open — the most invasive
  thing this app does. `onAir` **iff** capturing (`specs/frontend-identity.md`,
  frozen, 32-case test). Hardware mute refuses or cancels capture:
  `SpeakEngineMuteTests` pins that `startStream` is never called while muted, and
  that must hold in `.fullDuplex` too.
- No ambient listening. A conversation is only ever open because an agent asked and
  it ends deterministically.
- No networking, auth, or `print` in `SpeakCore` / App / CLI — `verify-moat` will
  break the build.

## 4. Making bridge staleness loud

The 19-day drift cost more than the missing code did. Fix it structurally:

- Embed a **contract version** constant in `CLIContract`, bumped whenever the wire
  protocol changes.
- `speak_status` reports both the bridge's compiled-in version and the running app's.
  On mismatch it returns a **loud, actionable error** — naming
  `make install-mcp-user` — instead of a plausible-looking reply.
- A stale bridge must fail visibly. Silent degradation is what produced 19 days of
  "I don't know why it doesn't work."

## 5. Non-goals

- `speak_report_progress` / `speak_request_approval` / `speak_complete`
  (`agent-voice-bridge.md` §5 lines 89–94) stay unbuilt. That is AVB-8, a separate
  slice. Do not start it here.
- No changes to the input/dictation pipeline.

## 6. Verification

- Unit: a full-duplex turn commits on VAD silence, not on the 120s timeout.
- Unit: `AskUserToolHandler` releases VAD, synthesizer, and mic on every exit path.
- Unit: barge-in stops synthesis in <10ms of the VAD callback.
- Unit: the mic is released on every conversation-end path — normal, timeout, cancel,
  error, hardware mute.
- Unit: version mismatch surfaces as an error, never as a normal reply.
- Integration: a live agent completes a two-turn spoken exchange with one
  interruption, through the reinstalled bridge.
- `make gates` clean. Quote exit codes; a gate that passes without running
  manufactures confidence.
