# Spec: Output — Reconnecting the Conversation

Status: **active** · Owner: output slice · Depends on: `specs/agent-voice-bridge.md` §5

## 1. What actually happened (the diagnosis)

The bidirectional voice loop was **built successfully** on 2026-07-26 in commit
`e4ae017` — "bidirectional-voice: full-duplex voice loop + VAD + barge-in + MCP
bridge (Layers 1-4)". Four layers landed:

| Layer | Artifact | State today |
|---|---|---|
| 1 | `VoiceActivityDetector` (286 LOC, RMS energy, 600ms silence, barge-in callback) | **zero non-test callers** |
| 1 | `SpeechSynthesizerStream` (373 LOC, sub-10ms `stopImmediately()`) | **zero non-test callers** |
| 2 | `ConversationLoopManager` (495 LOC, `.fullDuplex` transitions, VAD handlers, interrupt) | **intact**, reached only from the overlay, pinned to `.gatedTurn` |
| 3 | `ConversationOverlayView` (Mute / Interrupt / mode switcher) | present |
| 4 | `SpeakMCPServer` + `speak_ask_user` / `speak_stream_speech` | **removed** |

Two independent failures, neither of them an engineering-capability failure:

1. **The front door was deleted.** Loop #78 (2026-07-30) withdrew `speak_ask_user`
   and `speak_stream_speech` and removed `.askUser` / `.streamSpeech` from
   `CLIContract`, for spec purity — §5 did not list them. Correct call on process,
   but it left the engine with no path an agent could reach. The VAD and the
   interruptible TTS became dead code.
2. **The bridge under test was 19 days stale.** The installed
   `~/Library/Application Support/speak/mcp/bin/speak-mcp` was dated Jul 11; its
   embedded `SpeakCore.framework` Jul 10. `CLIContract` — the wire protocol, which
   lives *in* `SpeakCore` — changed across five commits after that date. Every test
   was conducted against a bridge that could not speak the protocol it was speaking
   to. `make install-mcp-user` is not part of `make gates` and nothing warned.

So the capability exists. This spec **reconnects** it and makes failure mode 2
structurally impossible.

## 2. Objective

An agent can hold a spoken conversation with the human — speak, be interrupted
mid-sentence, hear the reply, continue — through the **existing** nine-tool surface,
with no new tool and no amendment to `specs/agent-voice-bridge.md` §5.

## 3. Design — `conversation` as a mode, not a tool

`RequestInputMode` (`SpeakCore/AgentBridge/HumanResponse.swift:14`) is a
`String`-backed enum: `freeform`, `choice`, `approval`. Add a fourth:

```swift
case conversation
```

`speak_request_input` with `mode: "conversation"` drives
`ConversationLoopManager` in `.fullDuplex` instead of presenting a single-shot
prompt. This is deliberately **not** a new tool.

**Why this and not re-adding `speak_ask_user`:** §5 withdrew `speak_ask_user`
specifically because it *duplicated* `speak_request_input`. A mode on the existing
tool duplicates nothing, so §5's own reasoning endorses it. The tool list stays at
nine and Loop #78's decision is honoured rather than reverted. [decision]

### 3.1 What must be wired

- `AudioCapture` buffers → `VoiceActivityDetector` → the three existing
  `handleVADSpeechStarted` / `handleVADTranscriptUpdated` / `handleVADSilenceDetected`
  entry points. The handlers exist and are tested; only the feed is missing.
- Agent speech → `SpeechSynthesizerStream`, with `VoiceActivityDetector`'s barge-in
  callback calling `stopImmediately()`. This is the whole point: interruption is
  what makes it a conversation instead of an intercom.
- `ConversationLoopManager.onUserTurnCommitted` → a `HumanResponseOutcome` returned
  through the existing durable `AgentCallStore` path. All five outcomes must remain
  reachable — `answered`, `declined`, `cancelled`, `timedOut`, `busy`. Ambiguity
  must never silently become an empty string.
- Multi-turn: a `conversation` call stays open across turns and closes on explicit
  end, timeout, or user cancel. It must not leak a session or an open mic.

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

- Unit: `.conversation` mode round-trips every one of the five
  `HumanResponseOutcome` cases.
- Unit: barge-in stops synthesis in <10ms of the VAD callback.
- Unit: the mic is released on every conversation-end path — normal, timeout, cancel,
  error, hardware mute.
- Unit: version mismatch surfaces as an error, never as a normal reply.
- Integration: a live agent completes a two-turn spoken exchange with one
  interruption, through the reinstalled bridge.
- `make gates` clean. Quote exit codes; a gate that passes without running
  manufactures confidence.
