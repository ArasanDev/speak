# Horizon: `speak` → the Voice Layer for the Mac `[decision 2026-07-06, Fable loop #42]`

> Status: DIRECTION SPEC. Builds strictly on top of the immutable layering
> (base core → Clean profile → Profile Engine). Nothing here inverts it.
> Each pillar ships as an opt-in extension; the dictation core stays untouched.

## Thesis
Dictation is the wedge, not the product. Every competitor stops at
"speech → text in a box." The structural opening: the Mac now has an
on-device LLM, an on-device streaming STT, App Intents, and an exploding
population of terminal AI agents — and **no one owns the voice channel that
connects a human to all of it, locally**. `speak` already holds the four
hard primitives: global hotkey, streaming STT, on-device LLM, and
paste/selection I/O. The horizon is composing them into three pillars.

## Pillar 1 — Voice Actions (Command Mode → OS layer)
From "clean my words" to "do the thing I said."
- **Intent router**: first stage after final transcript classifies the
  utterance on-device: `dictation` (default, unchanged) vs `command`
  ("make this more formal", exists today via CommandModeService) vs
  `action` ("open my downloads", "reply to this saying yes").
  Router = deterministic prefix gate ("hey speak…" / explicit hotkey
  chord) + 3B classification. Mis-route ALWAYS degrades to dictation —
  never lose the user's words. (CS-2 two-pass finding applies: gate
  deterministically first, extract second.)
- **Action surface v1**: Shortcuts invocation via the system `shortcuts`
  CLI (`shortcuts list` / `shortcuts run`) — user-created shortcuts wrap
  other apps' App Intents, so the user curates an explicit, revocable
  action catalog. Direct cross-app App Intents invocation has **no public
  API** (expose-only framework) `[verified 2026-07-06, validator]`.
  No AppleScript soup, no accessibility scraping for v1.
  `[unverified — dogfood H-4]`: headless `shortcuts run` behavior for
  input-requesting shortcuts.
- Ships as: `VoiceActions/` in SpeakCore behind `ActionRouting` protocol.

## Pillar 2 — The conversational loop (speak ↔ Mac)
Voice out closes the loop: hands-free, eyes-free.
- On-device TTS readback (`AVSpeechSynthesizer`, Personal Voice where
  granted): read back the cleaned text on request ("read that back"),
  speak short answers from the on-device model ("what's a synonym for…").
- Interruptible: mic stays primary; any hotkey press cuts TTS instantly.
- Ships as: `VoiceOut/` behind `SpeechSynthesizing` protocol; zero
  network, consistent with the privacy contract.

## Pillar 3 — Agent Bridge (the era bet)
Terminal agents (Claude Code etc.) are becoming the developer's main
interface — and they are voiceless. `speak` becomes their voice channel:
- **speak-as-MCP-server** (stdio, local-only). Tool contract `[decision 2026-07-06]`:
  - `speak_say(text, interrupt?)` — Mac speaks the agent's message aloud
    (VoiceOut/Pillar 2). Fire-and-forget status channel.
  - `speak_ask(question, timeout?)` — speaks the question, opens the mic,
    runs the normal STT→cleanup pipeline, returns the human's spoken
    answer as the tool result. The agent blocks on the human's *voice*.
  - `speak_confirm(question)` — constrained yes/no variant; deterministic
    yes/no/cancel extraction on-device, returns a boolean.
  - `speak_status()` — mic/permission/engine availability so agents can
    degrade gracefully.
  Architecture: the MCP process is a thin stdio shim (`speak-mcp`,
  second CLI target) that talks to the running menubar app over a local
  XPC/UNIX-socket seam (`AgentBridgeService` in SpeakCore) — the app owns
  mic, permissions, TTS; the shim owns JSON-RPC. Every agent-initiated
  mic open is visually surfaced in the HUD (never silent listening).
  Distribution: `brew install speak` + one `.mcp.json` line gives any
  MCP-capable agent ears and a voice, 100% local.
  The human talks to their agent fleet through `speak`.
- Builds directly on V01-0 Agent Mode (frontmost-terminal detection) and
  V01-3 per-app context — those become the *passive* tier; MCP is the
  *active* tier.
- 100% local: stdio transport, no sockets exposed, no cloud.

## Sequencing (value order, additive)
1. H-1 Intent router skeleton + deterministic gate (no new perms) — after V01-3 lands.
2. H-2 VoiceOut readback ("read that back") — independent, small, huge demo value.
3. H-3 MCP server vertical slice: `confirm()` end-to-end with Claude Code.
4. H-4 App Intents action surface.

## Hard constraints carried forward
100% local by default · Apple frameworks first (MCP server is plain
stdio + JSON, no dep needed) · mis-detection degrades to plain dictation ·
every pillar has an off switch · pasteboard is still write-only.

## Validation results (2026-07-06, validator agent — all three closed)
- [x] Cross-app App Intents: no public API; v1 = `shortcuts` CLI wrapping
  (spec corrected above) `[verified]`
- [x] AVSpeechSynthesizer: feasible as specced. Personal Voice authorized
  via `requestPersonalVoiceAuthorization` (macos 14+, handle `.unsupported`);
  voice fallback chain personal → premium → enhanced → default (premium
  voices are user-downloaded); `stopSpeaking(at: .immediate)` for
  interruption. Typecheck-confirmed against local macOS 26 SDK. Start
  latency `[inferred]` <~300ms — measure in H-2 benchmark.
- [x] MCP stdio server in pure Foundation: `[verified]` — working ~70-line
  prototype ran full handshake (initialize → initialized → tools/list →
  tools/call). Current protocol 2025-11-25; serving an older version the
  client accepts (e.g. 2025-06-18 for Claude Code) is spec-legal.
  Implement `ping`; -32601 only for unknown requests, never notifications.
  Transport: newline-delimited JSON; shutdown on stdin close.
