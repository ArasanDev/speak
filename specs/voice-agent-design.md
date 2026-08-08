# The Voice Agent — STT · TTS · Text-to-Text, Combined

**Status:** proposal — awaiting human ratification of §8 · **Binds:** nothing yet ·
**Owner:** orchestrator · **Depends on:** `specs/agent-voice-bridge.md`,
`specs/frontend-identity.md`, `docs/product.md` · **Last substantive change:** 2026-08-08

> Every capability claim below is tagged. Apple-API claims are `[verified]` only where a
> `swiftc -typecheck` against the local **macOS 26.5** SDK exited 0 during this session.

---

## 0. The headline

Four findings decide this whole design. **D is the one to read first** — it is the only one
backed by measurement rather than by reading code, and it sets the build order.

**A. Roughly 60% of the voice agent is already built — and orphaned.**
`VoiceActivityDetector` (286 LOC, RMS energy, barge-in event) and `SpeechSynthesizerStream`
(373 LOC, word-boundary progress, `speakStream(AsyncStream<String>)`, `stopImmediately()`)
are fully implemented and unit-tested with **zero live construction sites**. `[verified —
grep, working tree 2026-08-08]`

```
SpeechSynthesizerStream(   →  0 sites outside /Tests/
VoiceActivityDetector(     →  0 sites outside /Tests/  (7 hits are attach* plumbing only)
ConversationLoopManager(   →  1 site: ConversationInputPresenter.swift:68
```

The uncommitted working tree deletes `Speak/App/MCP/AskUserToolHandler.swift`,
`AgentBridgeServer+Layer4.swift`, and `CLIPortServer+Layer4.swift` — the exact files that
`specs/output-conversation-reconnect.md` §1.5.2 cites as having wired these two primitives
up. **That spec's live-VAD log describes code that no longer exists in this tree.** Anyone
reading it next will conclude full-duplex is one small fix away. It isn't; it's unwired
again.

So today's "conversation" is a **UI skin over single-shot dictation**: the only
`ConversationLoopManager` runs in `.gatedTurn` and its VAD events are *fabricated by hand* —
`handleVADSpeechStarted()` is called exactly once from `markListening()`
(`ConversationInputPresenter.swift:97`), never from acoustic energy.

**B. Apple's on-device model already does tool calling, streaming, and persona.**
`[verified — swiftc -typecheck, macOS 26.5 SDK, exit 0]`

```swift
struct WeatherTool: Tool {                     // ✅ Tool protocol
    @Generable struct Arguments {              // ✅ @Generable + @Guide
        @Guide(description: "City name") var city: String
    }
    func call(arguments: Arguments) async throws -> String { … }
}
let session = LanguageModelSession(tools: [WeatherTool()],
                                   instructions: Instructions("You are terse."))  // ✅ persona
for try await partial in session.streamResponse(to: "hello") { … }                // ✅ streaming
let typed = try await session.respond(to: "hi", generating: AgentReply.self)      // ✅ guided
session.prewarm(); _ = session.transcript; _ = session.isResponding               // ✅ reuse
```

The v0 hard rule ("Apple frameworks only") is **not** a constraint on this design. The
agent can be built entirely on-device with zero third-party dependencies and zero egress —
the moat holds by construction. `FoundationModelsCleaner.swift:99` uses none of this: it
builds a fresh `LanguageModelSession` per `clean()` call, no tools, no streaming, no memory.

**C. Full-duplex barge-in is achievable — the OS provides acoustic echo cancellation.**
`[verified — swiftc -typecheck, exit 0]`

```swift
try engine.inputNode.setVoiceProcessingEnabled(true)   // ✅ AEC
try engine.outputNode.setVoiceProcessingEnabled(true)  // ✅ reference signal
engine.inputNode.voiceProcessingOtherAudioDuckingConfiguration =
    AVAudioVoiceProcessingOtherAudioDuckingConfiguration(
        enableAdvancedDucking: true, duckingLevel: .max)   // ✅ OS ducking
```

`AudioCapture` uses none of it — grep for `voiceProcessing` / `duck` / `echoCancel` across
`Speak/` returns zero hits. Without AEC the mic hears the agent's own TTS and barges in on
itself; that is the failure mode that kills every naive full-duplex demo.

**This is three lines to compile and a gated mode to ship — not a flag flip.** Two reasons,
both grounded in the existing capture code:

1. **It renegotiates the input format.** `AudioCapture.swift:119` reads
   `input.outputFormat(forBus: bus)` and builds the `AVAudioConverter` from it at `:129`.
   `setVoiceProcessingEnabled(true)` changes that negotiated format, so it must be called
   *before* the format is read, and it `throws`. The code is more resilient here than it
   looks — `:191-193` re-checks each buffer's format against the live converter and rebuilds
   at `:193` — but the documented `AudioCapture` crash mode is precisely `installTap` /
   `engine.start()` with a stale format raising an uncatchable `NSException`. This path
   needs deliberate ordering, not an insertion.
2. **It imposes AGC + noise suppression on every capture.** Voice processing is not additive
   — it changes the signal the transcriber sees. Dictation is the shipped product and is
   gated by `benchmark.md` MATCH. Enabling AEC globally could regress that gate.

So AEC must be **scoped to conversation sessions**, which means `AudioCapture` gains a
capture *mode* (`.dictation` / `.conversation`), not a boolean. VA-0's acceptance criteria
must include: log `inputFormat(forBus: 0)` and `outputFormat(forBus: 0)` before and after
enabling, confirm the converter path and the route-change handler survive the change, then
**re-run the MATCH gate**. If the format shifts, VA-0 grows a gate and a benchmark re-run.

The *availability* of the API is `[verified]`. The cost of adopting it is `[unverified]`
until that measurement runs.

**D. The loop is fast enough, and the dominant cost is a policy we choose — not compute.**
`[verified — make measure-latency, n as noted, M-series / macOS 26]` Full table and method in §5.

```
endpoint 600 (policy)  +  model TTFT 250  +  TTS to audible 267   =  1117 ms   today
endpoint 200 (semantic)+  model TTFT 250  +  TTS to audible 267   =   717 ms   achievable
```

The design survives contact with measurement: nothing here needs a faster model or a faster
synthesizer. **54% of the budget is the VAD silence window** — dead air we impose on
ourselves. Semantic endpointing is worth ~400 ms, more than any other optimisation available,
which is why it moves to the front of the build order.

Two corrections this measurement forced, both of which would otherwise have shipped as bugs:

- **`didStart` is enqueue, not audibility** (1–2 ms warm — below the physical floor). The real
  figure is 267 ms, from a mixer tap. `ttsFirstAudio` must be marked from the render path.
- **Prewarming at launch collapses the first-turn tail**: created ahead and prewarmed, p50
  ~316 ms and the >850 ms tail eliminated (0/9 runs vs 2/9 without). It barely moves the
  median — killing the worst turn is the whole value. The app holds one long-lived prewarmed
  session. `[decision]` (A session built at request time was once observed at 2125 ms, but
  that is n=1 under audio load — see §5 finding 3.)

And one product blocker: **all 41 installed English voices are `.default` quality — zero
enhanced, zero premium.** Tone (§4.4) is undermined before it starts; this is an onboarding
task, not a tuning knob.

---

## 1. Speech-to-Text — key areas for improvement

### 1.1 The seam throws away everything a conversation needs

`Transcriber.swift:15-25` — `TranscriptChunk` is `{ text, isFinal, timestamp }`. That is
all a consumer gets. But the Apple result underneath is far richer. Source of truth:
`SpeechTranscriber` is a `final public class` at line 335 of
`$(xcrun --sdk macosx --show-sdk-path)/System/Library/Frameworks/Speech.framework/Modules/
Speech.swiftmodule/arm64e-apple-macos.swiftinterface`; its nested `Result` is at line 418
`[verified — dump anchored to the enclosing class, macOS 26.5 SDK]`:

```swift
public struct Result : SpeechModuleResult {
    public let range: CMTimeRange                  // audio-relative timing
    public let resultsFinalizationTime: CMTime
    public var text: AttributedString              // runs carry .audioTimeRange + .transcriptionConfidence
    public let alternatives: [AttributedString]    // n-best hypotheses
}
```

Each member was independently typechecked against `SpeechTranscriber.Result` specifically
(`result.range`, `result.alternatives`, `run.audioTimeRange`, `run.transcriptionConfidence`
→ exit 0; `result.resolvedRange` → does not exist). Anchoring matters here: the file also
declares `DictationTranscriber.Result` (line 147) with a near-identical shape, and the SDK
ships a macabi variant — an unanchored grep picks the wrong one.

`AppleSpeechTranscriber.swift:512` collapses all of it to one line:

```swift
let text = String(result.text.characters)   // range, alternatives, confidence, timing → discarded
```

**This is the single highest-leverage STT change in the codebase.** But the four fields are
not equally safe to build on:

| Field | Tag | Note |
|---|---|---|
| `range`, `alternatives` | `[verified]` | Non-optional `let` on the struct. Always present. Build on these first. |
| `run.audioTimeRange` | `[verified]` — attribute key exists | Populated-ness `[unverified]`. |
| `run.transcriptionConfidence` | **`[unverified — needs live audio]`** | The attribute *key* typechecks. That is not evidence it carries a value at runtime, and Apple's on-device recognizers have historically returned nil/0.0 confidence for anything but final results. |

Measurement that would settle it: run a dictation through `AppleSpeechTranscriber` with a
temporary log of `run.transcriptionConfidence` per run, on both partial and final results,
over a live audio corpus. Until that runs, §1.4's confidence-shading and tap-to-correct UI
are **contingent features**, not planned ones. This follows the convention already set at
`AppleSpeechTranscriber.swift:140-144`, which tags contextual-biasing effect `[inferred]`
for exactly this reason.

The safe framing: `alternatives` alone gives cheap disambiguation, and `range` alone gives
real latency instrumentation and word-level Pet lipsync. Neither needs confidence.

### 1.2 No endpointing — turns can only end by hotkey

There is no acoustic "the human stopped talking" signal in the live pipeline. Finalization
happens only when an external caller invokes `Transcribing.stop()`. A conversation cannot
work this way — you'd hold a key down for every turn.

`VoiceActivityDetector` already implements exactly this (600 ms silence → `.speechEnded`,
50 ms debounce → `.speechStarted`, `.bargeIn` gated on `isTTSPlaying`). It just needs to be
constructed and attached. The attach seams already exist at three layers:
`AudioCapture.swift:385`, `CaptureSession.swift:266`, `SpeakEngine.swift:760`.

### 1.3 The rest, ranked

| # | Gap | Evidence | Fix cost |
|---|---|---|---|
| 1 | Confidence / n-best / timing discarded | `AppleSpeechTranscriber.swift:512` | Low — extend `TranscriptChunk` |
| 2 | No live VAD endpointing | 0 construction sites | Low — wire the built class |
| 3 | No AEC → no true barge-in | 0 `voiceProcessing` hits | **Medium** — API `[verified]`, but renegotiates input format (`:119`/`:129`) and imposes AGC+NS on dictation → needs a capture *mode* + MATCH re-run |
| 4 | Mute is logical only; mic tap never stops | `ConversationLoopManager.setMuted` | Medium — must gate the tap |
| 5 | Two uncoordinated watchdogs (10 s STT, 5 s session) | `AppleSpeechTranscriber.swift:304`, `CaptureSession.swift:749` | Medium — one latency budget |
| 6 | Blocking model download inside `startStream` | `AppleSpeechTranscriber.swift:348-405` | Medium — hoist + progress |
| 7 | `isFinal` windows concatenated with hardcoded `" "` | `CaptureSession.swift:114` `[unverified]` double-space | Low |
| 8 | Contextual biasing effect unmeasured | `AppleSpeechTranscriber.swift:140-144` `[inferred]` | Needs a corpus |
| 9 | Single hardcoded id `"apple-speech-en-US"` regardless of locale | `:122` | Trivial |

### 1.4 UI features for STT

- **Live confidence shading** in the overlay — low-confidence words rendered in `mica`
  rather than `bone`. Turns §1.1 into something the user can *see*, and makes the
  agent's "did you mean…?" legible instead of mysterious.
- **Tap-to-correct from n-best** — click a shaky word, pick from `alternatives`. Near-free
  once the data stops being discarded, and each correction is training data for the
  auto-dictionary (`V01-4`).
- **Endpoint sensitivity control** — one slider, "Ends turn after: 0.4 s ⟷ 1.2 s", mapping
  to `VoiceActivityDetector.Configuration.silenceThresholdDuration`. This is the single
  knob that makes a voice agent feel patient or twitchy; it must not be a hardcoded 0.6.
- **A real live waveform + VAD threshold line** — the AI Studio "STT Waveform" tab exists;
  overlay the energy threshold on it so the user can *see* why it did or didn't trigger.
- **Language auto-detect indicator** — currently a manual picker with a download badge.
- **Per-turn latency readout** (dev/Insights): endpoint → final → first token → first audio.

---

## 2. Text-to-Speech — key areas for improvement

### 2.1 The seam is blocking and indivisible

`SpeechSynthesizing.speak(_ text: String, …) async` suspends until the **entire** utterance
finishes. One call = one indivisible utterance. There is no way to start speaking sentence 1
while the model is still generating sentence 2.

This single fact sets the floor on perceived latency: the user hears nothing until the whole
response has been generated. For a 40-word reply on a model documented at 5–10 s for long
cleanup inputs, that is a multi-second silence where a conversation should be.

`SpeechSynthesizerStream` already solves it — `speakStream(_ stream: AsyncStream<String>)`
consumes text chunks and feeds AVSpeechSynthesizer's internal queue. It has zero callers.

### 2.2 The rest, ranked

| # | Gap | Evidence | Why it matters |
|---|---|---|---|
| 1 | No sentence-level streaming from token stream | `SpeechSynthesizing.swift:26-61` | Sets the latency floor |
| 2 | No word-boundary callbacks in the live synthesizer | `AppleSpeechSynthesizer` omits `willSpeakRangeOfSpeechString` | No lipsync, no karaoke, no progress |
| 3 | Interrupt is manual only (Escape), not acoustic | `handleInterrupt()` → `cancelAll()` **is** wired; `stopImmediately()` has 0 callers and `isTTSPlaying` is never set | You can stop it with a key, not by talking |
| 4 | No ducking | 0 hits | Agent talks over your music |
| 5 | One global voice for every purpose | `SettingsStore.ttsVoiceIdentifier` | Readback, agent, and notification are indistinguishable |
| 6 | No Personal Voice | `requestPersonalVoiceAuthorization` never referenced | Named in `horizon-voice-os.md`, never built |
| 7 | No SSML/prosody | plain `AVSpeechUtterance(string:)` | No emphasis, no pauses |
| 8 | Pet `isSpeaking` is `queuedCount > 0` polled at 5 Hz | `PetPanelController.swift:406` | Pip mimes speech it isn't tracking |
| 9 | Three separate synthesizer instances | `DictationController`, `AIStudioPaneView:288`, `SpeechSynthesizerStream` | Nothing can coordinate stop/duck |
| 10 | No time-to-first-audio instrumentation | logs char count, not latency | The number that defines the product is unmeasured |

### 2.3 UI features for TTS

- **Voice identity picker, promoted out of the AI Studio sub-tab.** Three *roles*, not one
  global setting: **Agent voice** (the persona), **Readback voice** (your own text played
  back), **Notification voice** (short, terse). Distinct voices are how the user knows
  without looking whether they're hearing themselves or the agent — the audio equivalent of
  the frozen two-temperature palette in `frontend-identity.md`.
- **Speaking transcript with karaoke highlight** — word-by-word, driven by
  `SpeechSynthesizerStream.progressStream`, which already emits exactly this and has no
  consumer. Also lets you *click ahead* or *click to stop*.
- **Barge-in affordance** — visible "listening while speaking" state. The Pet already has
  `speaking` (violet) and `listening` (amber) states; full-duplex means both at once, which
  the two-temperature palette expresses naturally.
- **Per-persona voice preview** in the persona editor: hear the tone before committing.
- **Interrupt button + Escape**, always visible while the agent speaks.
- **Speaking-rate quick control** in the menubar — the one TTS setting people change mid-use.

---

## 3. Text-to-Text — the honest assessment

`LLMCleaning` is a **transaction**, not a conversation:

```swift
func clean(_ text: String, mode: CleanupMode) async throws -> String
```

Single string in, single string out. No message history, no streaming, no tools, no
structured output, and — per `FoundationModelsCleaner.swift:20` — **a fresh
`LanguageModelSession` per call**, so no memory between turns and no `prewarm()` benefit.

This is the correct design for dictation cleanup and must not change. `docs/roadmap.md`
declares the layering immutable ("base core → Clean profile → Profile Engine, never
invert"). **The voice agent must not modify these three seams.** It adds a fourth, parallel
one. That distinction is the difference between an additive feature and a rewrite.

**What already exists and is worth harvesting:**

- `AgentPlaygroundView` + `PlaygroundPersonaEditor` — a working multi-turn chat surface with
  a `messages: [ChatWireMessage]` array and a system-prompt editor. **A persona editor and
  the only conversation memory in the app already ship** — in a developer dashboard,
  disconnected from the voice path.
- `LocalInferenceServer` (`SpeakLLM/InferenceServer/`) serves Apple's on-device model over
  OpenAI- *and* Anthropic-compatible HTTP on loopback (`acceptLocalOnly = true`), with a
  `ModelRegistry` covering Apple FM / Ollama / MLX. **Caveat: its streaming is fake** —
  `InferenceRouter.stream` calls batch `complete()` then `chunkTextIntoWords()`. The
  transport is real and reusable; the incrementality is not. Do not build the voice loop on
  it — use `LanguageModelSession.streamResponse(to:)` directly, which is genuinely
  incremental `[verified]`.
- Profiles / Transforms / CommandMode — a library of task-shaped prompts. `CommandModeService`
  is a live LLM-backed in-place text edit over Accessibility selection.
- `ShortcutsCLIExecutor` — the **only** tool-execution primitive in the codebase today:
  shells out to `/usr/bin/shortcuts run <name>` via `Process`, reached by exact prefix match
  (no LLM selection), default-off behind `voiceActionsEnabled`. Precedent worth noting, and
  worth revisiting against the "no OS-automation" invariant before it meets a model that can
  *choose* to call it.

**One more real gap:** `PromptBuilder` supports context injection (`.selection`,
`.clipboard`, `.currentFile`, `.appName`) but the sole production caller
(`FoundationModelsCleaner.swift:346-349`) never passes a `context:` dict, and
`CleanupMode.profile(...)` has no field to carry one. The plumbing exists and is tested;
nothing populates it. A voice agent that doesn't know what app you're in is much less useful,
so this becomes load-bearing in VA-3.

---

## 4. The voice agent — the design

### 4.1 Thesis: the local model is front-of-house, not the brain

The user's instinct that "a very small model is sufficient" is not a compromise — it is the
correct architecture, and it's what makes this legal under the existing product contract.

`specs/agent-voice-bridge.md` §1 binds: *"`speak` is the local input, output, routing, and
attention layer between a human and software agents. It is not an agent, reasoning engine,
orchestration framework."*

A small on-device model doing **turn-taking, intent classification, tool selection, short
spoken replies, and deciding when to escalate** is not a reasoning engine. It is *precisely*
"input, output, routing, and attention," now with a voice. The heavy reasoning still belongs
to the agents already connected over `speak-mcp` — Claude Code, Codex, and whatever else is
registered in `AgentSessionRegistry`.

That reframe is the whole product:

> **`speak` becomes the voice front-end to your agent fleet.** Apple's on-device model is
> the host who greets you, understands what you want, handles the small stuff itself, and
> hands the hard stuff to the right agent — then reads you the answer.

The small model never has to be smart. It has to be *fast* and *well-routed*. And the fleet
it routes to is already registered, already addressable, already durable
(`AgentCallStore`).

**Which small model, concretely.** The user noted "there are multiple models available
today," so to answer directly: **Apple's on-device Foundation Model *is* the small local
model for VA-1.** It ships with macOS 26, costs 0 MB of download, adds no third-party
dependency, and — per §0-B, `[verified]` exit 0 — already does tool calling, token
streaming, persona instructions, and guided structured output. It satisfies the v0
"Apple frameworks only" rule by construction, so `verify-moat` keeps passing with no
carve-out.

The other models stay reachable rather than excluded: MLX-hosted small models (Qwen3-0.6B /
1.7B, already contemplated as `V1-1`) plug in behind the same `ConversingAgent` seam as an
alternate implementation. That is the entire point of putting the seam there. Start on
Apple FM because it is free and already installed; swap or add later on measured evidence,
not on preference.

### 4.2 The fourth seam

```swift
public protocol ConversingAgent: Sendable {
    var id: String { get }
    var isAvailable: Bool { get async }

    /// One conversational turn. Emits deltas as they generate — never buffers to completion.
    func respond(
        to turn: UserTurn,
        persona: Persona,
        tools: [AgentTool]
    ) -> AsyncThrowingStream<AgentDelta, Error>

    func interrupt() async          // barge-in: abandon generation now
    func reset() async              // new conversation, drop transcript
}

public enum AgentDelta: Sendable {
    case textDelta(String)                        // → sentence buffer → TTS
    case toolCallStarted(name: String, summary: String)   // → Pet .agentWorking + HUD
    case toolCallFinished(name: String, ok: Bool)
    case turnFinished(TurnSummary)
}
```

`AppleConversingAgent` conforms via one long-lived `LanguageModelSession(tools:instructions:)`
with `streamResponse(to:)` — all `[verified]` available. `Persona.instructions` becomes
`Instructions`. Session reuse gives free conversational memory via `session.transcript`.

**Nothing above touches `Transcribing`, `LLMCleaning`, or `SpeechSynthesizing`.** Dictation
is untouched.

### 4.3 The loop

```
  ┌── AEC-enabled AVAudioEngine (setVoiceProcessingEnabled) ──────────────┐
  │                                                                      │
  mic ──┬──► AppleSpeechTranscriber ──► TranscriptChunk{text, isFinal,   │
        │                                 confidence, range, alternatives}│
        └──► VoiceActivityDetector ──► .speechStarted / .speechEnded(600ms)
                                       └─► .bargeIn  ─────────┐          │
                                                              │          │
        endpoint ──► ConversationLoopManager.commitUserTurn ───┤          │
                                                              ▼          │
                        ConversingAgent.respond() ──► AsyncThrowingStream │
                                                              │          │
                     ┌── .toolCallStarted ──► Pet .agentWorking + HUD chip│
                     ├── .textDelta ──► SentenceBuffer ──► speakStream()  │
                     └── .turnFinished ──► ConversationLoopManager        │
                                                              │          │
        SpeechSynthesizerStream.progressStream ──► Pet lipsync + karaoke  │
        .bargeIn ──► stopImmediately() (<10ms) + interrupt() ─────────────┘
```

Every box is either **already built** (VAD, `SpeechSynthesizerStream`,
`ConversationLoopManager`, `ConversationOverlayView`, `AgentSpeechQueue`, Pet states) or
**verified available** (AEC, `Tool`, `streamResponse`). The genuinely new code is:
`ConversingAgent` + `AppleConversingAgent`, a `SentenceBuffer`, the tool set, and the
persona model.

### 4.4 Tone — persona as a first-class object

```swift
public struct Persona: Sendable, Codable, Identifiable {
    public let id: String
    public var name: String               // "Pip"
    public var instructions: String       // → FoundationModels `Instructions`
    public var voiceIdentifier: String?   // its own voice, not the global one
    public var rate: Float
    public var pitch: Float
    public var verbosity: Verbosity       // .terse | .normal | .explanatory
    public var toolScope: Set<String>     // which tools this persona may call
    public var accent: PersonaAccent      // violet | amber-tinted | custom (Pet + HUD)
}
```

Tone today is `Profile.tone` — four fixed cases (`.neutral/.terse/.formal/.casual`) that
`PromptBuilder.toneClause` renders as one appended sentence. That is a text-cleanup knob, not
a character. `Persona` replaces it for the agent path only; `Profile.tone` stays as-is for
dictation cleanup.

Tone is not just a system prompt. It's the 5-tuple **(instructions, voice, rate, verbosity,
tool scope)** — how it thinks, how it sounds, how much it says, and what it's allowed to do.
`verbosity` matters more in voice than in text: a paragraph you skim in 2 s takes 25 s to
hear. `.terse` should be the default, and `frontend-identity.md` §7's copy voice ("plain
verbs, sentence case, instrument not person, never exclamation points") should be baked into
the shipped default `instructions` so the agent *sounds* like the product looks.

Ships with three: **Pip** (terse host, default), **Scribe** (dictation-focused, read-back
and correction only, no routing), **Router** (thin — classify and dispatch, barely speaks).
`PlaygroundPersonaEditor` already exists as the editing surface.

### 4.5 Tools — scoped to what `speak` legitimately owns

`agent-voice-bridge.md` §8 forbids shell/Git/browser/OS-automation *in the agent bridge*.
That invariant should hold here too, and it's not a limitation — the interesting tools are
the ones only `speak` can offer:

| Tool | Does | Why it's safe |
|---|---|---|
| `route_to_agent(sessionId, text)` | Deliver a voice turn to a registered MCP agent | **The headline tool.** Reuses `AgentSessionRegistry` + `AgentCallStore`. Turns speak into the fleet's voice front-end. |
| `list_agents()` | "Who's working right now?" | Read-only, own registry |
| `check_inbox()` | "Anything waiting on me?" | Reads `AgentCallStore`, already durable |
| `answer_call(callId, response)` | Answer a pending agent question by voice | Path already exists (`answerAgentCallByVoice`) |
| `recall(query)` | Search **own** dictation history | Own SQLite. Never the pasteboard, files, or screen |
| `apply_transform(name, text)` | Run an existing Transform/Profile | Reuses `LLMCleaning` |
| `add_vocabulary(term)` | "Remember that name" | Feeds `contextualStrings` — closes the STT loop by voice |
| `set_preference(key, value)` | "Talk slower", "switch to Aurora" | Own `SettingsStore` |
| `insert_snippet(name)` | Paste a stored snippet | Write-only pasteboard, unchanged |

Note what's absent: no shell, no filesystem, no browser, no screen reading, no pasteboard
*reads*. Every hard rule survives intact. `verify-moat` keeps passing because nothing here
adds a networking or auth symbol to `SpeakCore`/`App`/`CLI`.

**Tool-call consent UI is required and currently missing entirely.** Voice makes accidental
invocation easy — there is no visual "are you sure." Each `toolCallStarted` must render a
HUD chip naming the tool in plain language, and any tool marked consequential must speak its
confirmation and wait. That's a new surface; nothing in the app does it today.

### 4.6 Interactions this unlocks

Grouped by how much new machinery each needs.

**Free once the loop closes:**
- "What's Claude working on?" → `list_agents` → spoken status. Ambient awareness of a fleet
  you currently have to go look at.
- "Tell Claude to use the other approach." → `route_to_agent`. Voice as the fleet's control
  plane — this is the interaction that doesn't exist anywhere else.
- "Anything waiting on me?" → `check_inbox` → answer by voice, hands-free.
- Barge-in: interrupt a long answer mid-sentence just by speaking.
- "Wait, no — scratch that" mid-dictation (`V1-7`) becomes natural once turns are a loop.

**Small additions:**
- **Voice correction loop:** low-confidence word → agent asks → you confirm → it writes to
  `contextualStrings`. The system gets measurably better at *your* vocabulary by talking.
  *Contingent on runtime confidence being populated (§1.1) — if it isn't, the same loop can
  be driven off `alternatives.count > 1`, which is `[verified]` non-optional.*
- **Readback-and-edit:** "read that back… change the second sentence to…" — the
  multi-turn voice editing on the roadmap as `V3-3`, reachable much earlier.
- **Push-to-talk-to-agent**, a distinct chord from dictation. Today there is no
  human-initiated way to address the agent at all; it only speaks when an MCP agent
  provokes it.

**The ambitious one:**
- **Handoff.** You dictate; the agent notices it's a task, not prose, and asks "want me to
  send that to Claude in `deepvoice`?" — one word and it's routed. That's the moment `speak`
  stops being a dictation tool and becomes the interface to everything else.

---

## 5. Latency budget — the number that decides if this feels alive

Below ~800 ms end-to-end feels conversational; above ~1.5 s people start talking over it.

**This has now been measured.** `make measure-latency` (`scripts/measure-latency.swift`, E1)
runs on a clean clone with no Xcode project, app bundle, or permissions, and is re-runnable so
a regression is visible. Figures below are from an M-series Mac on macOS 26. `[verified]`

| Component | Measured (p50) | Basis |
|---|---|---|
| Endpoint delay — silence VAD | **600** | Policy, not compute: `silenceThresholdDuration`. Pure dead air. |
| Model TTFT, warm | **250** | `FoundationModels` `streamResponse` → first non-empty snapshot, n=5 |
| TTS → first **audible** sample | **267** | Mixer tap detecting real signal, n=5 |
| **Composite, today's policy** | **1117** | 600 + 250 + 267 |
| **Composite, 200 ms semantic endpointing** | **717** | 200 + 250 + 267 |

Supporting figures: `write()` first buffer 145 ms (synthesis compute alone; the remaining
~120 ms to audible is player scheduling and output latency). Utterance duration for a
five-word reply ~1640 ms — replies are far longer than the latency to start them, so
**verbosity is the bigger felt-time lever than TTFT.**

**Three findings that changed the design.**

1. **Endpoint policy is 54% of the budget, and it is the only component that is a choice
   rather than physics.** Semantic endpointing is worth ~400 ms — larger than any model or
   TTS optimisation available. This independently confirms on this machine what LiveKit
   converged on. It is therefore the *first* thing built, not a later refinement.

2. **`didStart` is not audibility — do not use it as `ttsFirstAudio`.** It measures 1–2 ms
   warm, below the floor for CoreAudio output start, because it fires on enqueue. The honest
   figure is 267 ms, from a tap on the mixer. An earlier revision of this table quoted the
   enqueue number and understated every total by ~265 ms. `TurnMetrics.ttsFirstAudio` must be
   marked from the render path, never from the synthesizer delegate.

3. **Create the model session ahead of the request; `prewarm()` it at launch.** A session
   created and immediately queried while the process was busy cost 2125 ms to first token —
   but that is **n=1, taken in-process right after the TTS block had been hammering the audio
   stack, and the fresh-process runs below do not corroborate it. Treat it as an upper bound,
   not a typical value.** The decision does not rest on it: the tail data does. The same first
   turn in a fresh process, with the session created ~2 s before the request, cost ~350 ms.
   Measured over n=9 fresh processes each:

   | First-turn TTFT | p50 | max | runs > 850 ms |
   |---|---|---|---|
   | session created, no `prewarm()` | 363 | 927 | 2 / 9 |
   | session created + `prewarm()` | 316 | **392** | **0 / 9** |

   `prewarm()` barely moves the median — **it collapses the tail.** For a product judged on
   its worst turn rather than its average, that is the whole value. `[decision]` The app holds
   one long-lived `LanguageModelSession`, created and prewarmed at launch.

4. **The transcriber segments sentences itself, and STT finalization is nearly free.**
   `[verified — make probe-partials, E6]` Feeding synthesized multi-sentence audio through
   `SpeechAnalyzer` at real-time pace produced this, and it reshapes the endpoint design:

   - **Volatile results DO carry punctuation.** `"The meeting is at 3."` arrived as a
     *volatile* at 2267 ms with its terminal `.` — 174 ms before the matching final. So the
     decider may read punctuation from the partial stream. (Conclusive: observed. The
     converse would not have been — synthetic speech is prosodically flat.)
   - **`isFinal` is a sentence boundary, not an utterance boundary.** A single continuous
     utterance produced **two** finals, one per spoken sentence. The transcriber is doing
     segmentation for us; a final arriving mid-stream is the strongest available "a complete
     thought just closed" signal, and it is free.
   - **Last audio in → final result: 53 ms and 80 ms.** STT finalization is not a latency
     contributor and can be struck from the budget. The 600 ms endpoint policy is even more
     dominant than §5's table implies.
   - **Terminal punctuation on a *final* proves nothing.** The deliberately incomplete
     `"…quarterly numbers and"` came back as `"…quarterly numbers, Anne."` — the model both
     hallucinated a word and appended a period. **Finalization punctuates unconditionally.**
     Only punctuation observed on a *volatile*, while audio is still arriving, carries
     information, because there the model chose to close a sentence it could still extend.

   `[decision]` The decider keys on volatile punctuation and lexical tail, and treats a final
   as a boundary hint — never as proof the human is done talking.

Still `[unverified]`, and deliberately not in the table above: first-token → first-clause
flush (needs `SentenceBuffer`). The barge-in path keeps its own budget —
`stopImmediately()` self-reports elapsed time and targets <100 ms.

**Non-latency finding from the same harness, and a shipping blocker for tone (§4.4): all 41
installed English voices are `.default` quality — zero `.enhanced`, zero `.premium`.** The
agent sounds robotic out of the box no matter how good the persona is. Enhanced/Premium are a
user download (System Settings → Accessibility → Spoken Content), so this is an **onboarding**
item, not a tuning one. The harness prints a warning when it detects this.

---

## 6. Phasing

**VA-0 — Instrument and un-orphan.** *Partially done.* ✅ `TurnMetrics` (stage vocabulary +
`OSSignposter`, 7 tests) and ✅ `make measure-latency` (E1, the standalone harness behind §5)
have landed. Remaining: mark the stages from the live loop rather than from tests, and mark
`ttsFirstAudio` **from the render path — not the synthesizer delegate** (§5, finding 2).
Construct a real `VoiceActivityDetector`, attach it via the existing three-layer seam.
Give `AudioCapture` a capture **mode** (`.dictation` / `.conversation`) and enable AEC +
ducking only in `.conversation` — see §0-C for why this is not a flag flip. **Exit criteria
for that change: input/output formats logged before and after, converter and route-change
paths confirmed intact, and the `benchmark.md` MATCH gate re-run green.** Stop discarding
`AppleSpeechTranscriber.swift:512` — extend `TranscriptChunk` with `range` and
`alternatives` (both `[verified]` non-optional), and add `confidence` as optional, logging
its runtime populated-ness over a live corpus before any UI depends on it (§1.1).
*Outcome: the loop can close, and we can measure it.* No new UI.

**VA-1 — The loop.** `ConversingAgent` + `AppleConversingAgent` over a **single long-lived,
launch-prewarmed** `LanguageModelSession(tools:instructions:)` (§5, finding 3 — prewarming is
what kills the first-turn tail). **Semantic endpointing is built here, not deferred to VA-4**: §5 sizes
it at ~400 ms, the largest single win on the board. `SentenceBuffer`. Wire
`SpeechSynthesizerStream` for real. Barge-in end-to-end: `.bargeIn` → `stopImmediately()` +
`interrupt()`. Mute must gate the actual tap, not just the state machine. *Outcome: you can
talk to it and interrupt it.* Three tools only: `list_agents`, `check_inbox`, `recall`.

**VA-2 — Tone.** `Persona` model, three shipped personas, per-role voices (agent / readback
/ notification), `PlaygroundPersonaEditor` repointed at `Persona`. Pet lipsync from
`progressStream`. Karaoke transcript. *Outcome: it has a character.*

**VA-3 — Routing.** `route_to_agent`, `answer_call`, tool-call consent UI, push-to-talk-to-
agent chord, durable conversation transcript surface. *Outcome: it's the fleet's front
door.* This is where the product thesis is actually tested.

**VA-4 — Polish.** Endpoint-sensitivity slider, confidence shading, tap-to-correct from
n-best, voice-driven vocabulary learning, `set_preference`.

Neural TTS (Kokoro/Piper/SuperTonic, `voice-ai-tts-research.md`) stays out of scope: it would
be the first third-party dependency, and §5 measured Apple's synthesizer at 267 ms to audible
against a 600 ms endpoint window — real, but not the bottleneck, and a neural model would very
likely be slower rather than faster. The case for it is **voice quality**, not latency, and the
cheaper fix there is prompting the user to install Enhanced/Premium voices (§5).

---

## 7. What this costs

- **`specs/output-conversation-reconnect.md` is stale** and should be marked so. Its §1.5.2
  evidence describes deleted files.
- **`specs/horizon-voice-os.md` should be un-superseded** — it's the closest prior art.
- **`AgentInboxPaneView.swift:29,147,177` uses `speakOnAir` for urgency**, violating the
  frozen "onAir iff the microphone is capturing" rule in `frontend-identity.md`. Full-duplex
  makes the tally light load-bearing; this must be fixed first or the rule is already dead.
- The 32-case `PetState` test and the `SpeakEngineMuteTests` invariant both hold under this
  design — but VA-1's mute change touches the second one directly and must extend, not
  weaken, it.

---

## 8. The decision required

This design assumes one thing not yet ratified.

**Recommendation: the in-app voice agent is *session-scoped*, never ambient.** It is
explicitly invoked (hotkey or chord), has a deterministic end, and `onAir` stays honest —
lit iff the mic is capturing. Under that constraint every §8 invariant of
`agent-voice-bridge.md` survives, the frozen palette rule survives, `verify-moat` keeps
passing, and the §1 product boundary is *fulfilled* rather than broken: the local model
routes and presents; the connected agents reason.

**The alternative** — an always-listening ambient assistant — would be a different product.
It breaks "no ambient microphone access," makes the tally light meaningless, and forfeits
the structural-privacy claim that is currently the moat. I do not recommend it.

Either way, `agent-voice-bridge.md` §1 needs an explicit amendment saying a local
conversational router is in scope, because a reasonable reader of the current text would
say this design violates it. **That amendment is the user's call, not mine.**

Checked against the working tree, not just the committed file: `agent-voice-bridge.md` has
uncommitted modifications, so it was worth confirming they don't already resolve this. They
don't. `git diff` touches only §5 (rewriting "Current implementation" to the 2026-07-30 tool
catalog, adding the "Presentation (not MCP surface)" block, and withdrawing `speak_ask_user`
/ `speak_stream_speech`). **The §1 boundary sentence — "It is not an agent, reasoning engine,
orchestration framework, or general automation server" — is untouched.** If anything the
uncommitted edit tightens the surrounding posture: it newly states that agents "must not
compose overlay, mic, or TTS primitives." The decision below is still open and still yours.
