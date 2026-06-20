# `deepvoice` — Voice-First Agentic Coding (Ideation Memo)

> **Status**: Ideation. Not a PRD. Pick a direction → turn this into a PRD.
> **Date**: 2026-06-18
> **Author**: ideation pass, grounded in 2026 primary sources (linked inline).
> **Working dir**: `/Users/tamil/Developers/deepvoice` (greenfield).

---

## 0. Decision card

| | Direction | One-line | Build effort | Market gap |
|---|---|---|---|---|
| **A** | **Ambient pair-programmer** (recommended v0) | Always-on, only speaks when it has something. | 2 wks | **Large** — nobody owns it |
| B | Voice-first CLI over Piclaw harness | Speak the task, agent runs the loop. | 1 wk | Medium — competes with IDE voice modes |
| C | Spec-to-diff voice narrator | Speak a spec, get a patch + narration. | 1 wk | Small — competing with PR bots |
| D | Voice test/explainer loop | Run tests, narrate failures, ask "fix this one?" | 1 wk | Niche |

**Pick A as v0.** A composes with B, C, D later (same harness, different
UX). The market gap is the largest and the build is no bigger than the
sum of the others.

**Why not B first?** B is what people expect voice-coding to be, and
that's why it's crowded. Cursor, Copilot, and the new IDE voice modes
all converge on "speak a prompt, get a chat reply." A is genuinely
different.

---

## 1. The 2026 market gap

The voice-coding landscape in mid-2026 is two completely separate
products pretending to be one:

1. **Dictation tools** — *Willow Voice*, *Wispr Flow*, *Superwhisper*
   (and a dozen clones). They convert speech to text and type it for
   you. They are **not agentic** — they have no tool loop, no plan, no
   verify step. The 2026 buyer guide [ranks them on accuracy, latency,
   and price](https://utter.to/blog/best-voice-dictation-software-2026/);
   the leader is Willow at "95%+" accuracy, Wispr at ~90%. They are
   sophisticated typewriters, not coding agents.

2. **IDE voice modes** — Cursor, GitHub Copilot, Antigravity. They add
   a microphone button to an existing chat sidebar. The voice input is
   transcribed to a prompt, then run through the *same* chat
   pipeline. There is no real-time interruption, no audio feedback
   during tool calls, no spoken permission gates, no
   voice-as-transport design. The 2026 AI coding tools comparison
   [lists voice as a checkbox feature](https://www.sitepoint.com/ai-coding-tools-comparison-2026/),
   not a first-class surface.

**What nobody is building**: a voice-native harness where speech is
the *primary* I/O channel for an agentic loop. Not a dictation
preprocessor for a chat box. Not a fancy TTS that reads a finished diff.
A product where the engineer speaks, the agent runs the plan →
tool → verify loop, and the agent speaks back at the right moments —
interrupting when the engineer speaks, narrating only when there is
something to say, asking spoken permission before destructive
actions.

**Independent validation from the demand side.** Anthropic's
[*2026 Agentic Coding Trends Report*](https://resources.anthropic.com/hubfs/2026%20Agentic%20Coding%20Trends%20Report.pdf)
(Jan 2026) names two trends that point straight at this product:

- **Orchestration shift** — "the primary human role in building
  software is orchestrating AI agents that write code, evaluating
  their output, providing strategic direction." The engineer is no
  longer the implementer; the engineer is the conductor.
- **Delegation gap** — the same report (per
  [Pathmode's summary](https://pathmode.io/blog/orchestration-era-needs-intent))
  says ~60% of engineers feel under-trained for the new role. The
  barrier to delegation is mostly cognitive: writing good prompts,
  supervising long runs, catching silent failures.

Voice is the natural interface for an orchestrator. It is hands-free,
eye-free, interruptible, and conversational. It removes the biggest
friction in the delegation gap — *saying* what you want is faster than
*typing* it, especially while watching a run, a test suite, or a
debugger.

**Independent validation from the supply side.** OpenAI's Realtime
API hit **GA on 2025-08-28** with the `gpt-realtime` model
([announcement](https://openai.com/index/introducing-gpt-realtime/),
[InfoQ write-up](https://www.infoq.com/news/2025/09/openai-gpt-realtime/),
[Latent.Space "missing manual"](https://www.latent.space/p/realtime-api)).
The transport supports full-duplex audio, server-side VAD, semantic
turn detection, and function calling (i.e. real tool use) — exactly
the surface `deepvoice` needs. The 2026 production guide
([Fora Soft](https://www.forasoft.com/blog/article/openai-realtime-api-voice-agent-production-guide-2026))
documents WebRTC + SIP + MCP wiring as standard. The transport is a
solved problem; the *harness* is the open question.

**One contrarian risk to take seriously.** A 2026 Medium essay, "The
ambient AI trap: why doctors are returning to active dictation in
2026" ([link](https://medium.com/@ryanshrott/the-ambient-ai-trap-why-doctors-are-returning-to-active-dictation-in-2026-4a87895f7c84)),
argues that always-listening products get switched off in clinical
practice because they misfire on background speech and erode trust.
The lesson for `deepvoice`: **ambient must be opt-in per session, the
wake word must be reliable, and the agent must be silent by default.**
This is a design constraint, not a deal-breaker.

---

## 2. The 4 directions

### A. Ambient pair-programmer (recommended v0)

**Hook.** The agent is *always listening* but *only speaks when it has
something*. You say "hey deepvoice" → it wakes. You say nothing → it
runs the agentic loop silently, then *interrupts you* with a
sentence: "tests failed on `parseUser` — want me to fix it?" or
"build is green, ready to commit." You speak back, it acts.

**Target user.** Senior engineers doing long-running work (refactor,
test suite, migration) who are already in a headphones-and-walk-away
workflow. People who already use Claude Code in `--dangerously-skip-permissions`
mode and want to supervise from the couch.

**Why this wins.** It is the *only* direction in this list that no one
else is shipping in 2026. Cursor/Copilot voice modes are push-to-talk
chat. Willow/Wispr are dictation. An ambient, voice-native harness is
the unclaimed quadrant.

**Hard parts unique to A.**
- Always-on mic with **hardware-level privacy** (macOS push-to-talk
  pattern, indicator light, no cloud audio when muted).
- **Initiation policy** — when does the agent speak without being
  asked? (See §6.)
- **Push channel** — voice as output, not just input. The TTS path
  must sound like a colleague, not a screen reader.

### B. Voice-first CLI over the Piclaw harness

**Hook.** `deepvoice "rename parseUser to parseUserRecord, add JSDoc"`
runs the same loop as the Piclaw CLI, but every prompt is spoken.
`file_edit`, `shell_run`, `test`, `git_commit` are all voice-driven.

**Target user.** Engineers who already use Claude Code/Piclaw and
want a hands-free mode for repetitive tasks ("commit and push",
"rebase onto main", "run the test suite and report").

**Why this is the *obvious* one — and why it shouldn't be v0.** It is
the natural first guess, and that is exactly why every IDE voice mode
is converging on it. Competing here is competing on accuracy and
latency against Cursor and Copilot, with no differentiation. **Build
B inside A** — once the ambient harness exists, the CLI flag is a
trivial extra.

### C. Spec-to-diff voice narrator

**Hook.** You speak a 30-second spec. The agent plans, edits, runs
tests, and *narrates the result* out loud: "I renamed it, added JSDoc
on lines 12-19, and your tests still pass. Here is the diff…"
Audio summary, not real-time.

**Target user.** Engineering managers reviewing junior work, code
reviewers on the go, accessibility-first engineers.

**Why not first.** Smallest market of the four. Adjacent to A
(ambient) — once the harness exists, this is just an async wrapper
around it.

### D. Voice test/explainer loop

**Hook.** The agent runs the test suite. When something fails, it
speaks the error and asks: "want me to fix this one?" You say yes or
skip. It learns your preferences.

**Target user.** Engineers debugging a flaky test suite or a CI
failure overnight.

**Why not first.** A is a strict superset: the ambient harness can
run a test loop, narrate failures, and ask the same questions. D is a
*mode* of A, not a separate product.

### Layered product (if user prefers all four)

A is the v0 *and* the runtime. B/C/D are UX modes of A.

```
deepvoice start --mode ambient   # A
deepvoice run "..."              # B
deepvoice spec ...               # C
deepvoice watch --tests          # D
```

All four share the same harness, tools, providers, and voice transport.

---

## 3. v0 architecture (Direction A)

Port the Piclaw package layout directly. Voice is one new package;
the rest is harness.

```
packages/
  voice/          # NEW: Realtime API client, mic capture, audio out
    src/
      client.ts        # WebRTC + Realtime API session
      vad.ts           # server VAD config + custom wake-word
      barge-in.ts      # interruption policy (< 200ms cutoff)
      permissions.ts   # spoken permission gates, default-deny
      tts-cues.ts      # "I'm going to run tests", "tests failed"
    test/
  harness/        # ported from /Users/tamil/Developers/mini/packages/{agent,ai,contracts}
    src/
      plan.ts          # goal -> steps
      tool.ts          # step -> tool call
      verify.ts        # tool result -> next step or finish
      compact.ts       # context shaping
  tools/          # ported from packages/tools
    file_edit.ts
    shell_run.ts
    git_*.ts
    test_*.ts
  providers/      # model picker, orthogonal to voice
    openai.ts
    anthropic.ts
    ollama.ts
  cli/            # ported from packages/cli + new voice subcommands
    src/
      commands/
        start.ts       # deepvoice start --mode ambient
        run.ts         # deepvoice run "..."
        stop.ts
        status.ts
  rules/          # NEW: spoken permission gates, default-deny destructive
    destructive.ts     # rm -rf, git push --force, DROP TABLE
    spoken-consent.ts  # TTS the action, await spoken "yes"
  prompts/        # ported from packages/prompts
  skills/         # ported from packages/skills
```

**Transport.** WebRTC for browser/mic capture, Realtime API over
WebSocket as fallback. Use the documented Realtime API
[VAD and turn detection](https://developers.openai.com/api/docs/guides/realtime-vad)
features; semantic VAD is preferred over server VAD for noisy home
offices. Barge-in via `response.cancel` on the server side; cutoff
target is **< 200ms** between user speech and agent stop.

**Model picker is orthogonal.** `deepvoice --model claude-sonnet-4`
swaps the planning model. The voice transport is just audio I/O; the
planner and verifier are the same as the text CLI. The 2026
*Building Claude Code with Harness Engineering* write-up
([link](https://levelup.gitconnected.com/building-claude-code-with-harness-engineering-d2e8c0da85f0))
and *98% of Claude Code Is Not AI*
([link](https://cobusgreyling.medium.com/98-of-claude-code-is-not-ai-bab2f37dee0e))
both confirm: the *harness* is most of the product. Voice is a
transport, not a redesign.

**Tools are first-class.** `file_edit` runs identically with or
without voice. The same tool registry, the same JSON schema, the same
permission model. Voice is added at the I/O layer only. This is the
biggest design decision in the architecture and the one that keeps
`deepvoice` from becoming a chat wrapper.

**Permission gates are spoken.** Default-deny for any tool marked
`destructive: true` in its manifest (rm -rf, force-push, DROP TABLE).
When the agent wants to run one, it speaks the action: *"I'm about to
run `git push --force-with-lease origin main`. Say 'yes' to confirm."*
The user says "yes", the tool runs. Spoken consent is *more* secure
than a click in some ways — it can't be misclicked, it leaves an
audio record.

**Transcript is canonical.** Every session writes a transcript
(transcribed speech + tool calls + tool results) to
`~/.deepvoice/sessions/<id>.jsonl`. Audio is optional repro — the
transcript is what you grep, what you commit, what you review.

---

## 4. The 4 hard parts

### 4.1 Latency -> trust

- First-token audio latency: target **< 300ms p50**, **< 600ms p95**.
  The OpenAI Realtime API is documented at sub-300ms on WebRTC; the
  [Fora Soft 2026 production guide](https://www.forasoft.com/blog/article/openai-realtime-api-voice-agent-production-guide-2026)
  reports this is achievable in production.
- Barge-in cutoff: target **< 200ms**. Anything slower and the
  agent talks over you, killing trust.
- Failure mode: if p95 latency exceeds 1s for 3 consecutive turns,
  surface a spoken warning ("I'm running slow — want me to switch
  models?") and fall back to a faster transport.

### 4.2 Hallucinated destructive tool calls

Voice in -> voice out is a closed loop with no visual checkpoint.
A hallucinated `rm -rf` spoken into your terminal is worse than a
typed one. Mitigations, in order:

1. **Default-deny** on any tool with `destructive: true`. The
   permission model is opt-in per session, not opt-out.
2. **Spoken consent** for destructive tools, as above.
3. **Tool-driven determinism**: rename and format operations must go
   through a tool (`file_edit`), not be LLM-emitted in prose. A spoken
   "I renamed parseUser to parseUserRecord" is a *report* of the
   tool call, not the tool call itself.
4. **Dry-run mode** for first-time destructive tools: the agent
   speaks the planned command but does not execute. The user has to
   explicitly say "do it" before the second invocation.

### 4.3 Always-on mic privacy

The ambient direction requires a mic that is *always on* in some
sense. The 2026 *ambient AI trap* essay
([link](https://medium.com/@ryanshrott/the-ambient-ai-trap-why-doctors-are-returning-to-active-dictation-in-2026-4a87895f7c84))
warns that always-on products get disabled when they misfire.
Mitigations:

1. **Hardware mute** is a hard requirement. The macOS push-to-talk
   pattern: a keyboard chord (e.g. ^⌥Space) toggles mic capture.
   When muted, no audio leaves the device, period.
2. **Indicator light** — system-level (macOS shows a mic-in-use dot)
   *and* in-app (a persistent dock badge when listening).
3. **Wake word, not raw audio** — by default, the mic only sends
   audio to the cloud after a local wake-word detector fires
   (Picovoice Porcupine or openWakeWord). No audio in the
   pre-wake state.
4. **No audio logging by default** — transcripts are written, audio
   is not. If the user opts in to audio repro for debugging, it's
   encrypted at rest and rotated every 7 days.

### 4.4 Determinism for voice -> code

Voice is lossy. "rename parseUser to parseUser record" (with the
spurious space) and "parse user" (two words) sound similar to a
noisy VAD. The harness must be robust to this:

1. **Tool names are explicit** — the agent doesn't say "I ran the
   rename tool", it says "I ran `file_edit --op rename --from
   parseUser --to parseUserRecord`." Spoken tool reports include
   the tool name and arguments verbatim.
2. **Confirm before commit** — for any `git commit`, `git push`,
   file write, or destructive op, the agent speaks the action and
   waits for "yes" (or a typed equivalent in the CLI).
3. **Spoken tool error reports include the failing command and
   stderr** — the user can hear the *exact* failure, not a
   paraphrase.
4. **No LLM-emitted diffs in prose** — if the agent wants to show
   a 50-line diff, it writes it to a file and tells the user the
   path. Voice is for narrative, not for code.

---

## 5. 2-week build plan

| Day | Goal | Done when |
|---|---|---|
| 1 | Realtime API wire-up, hello-world agent speaks | `node -e "..."` triggers Realtime API, audio plays |
| 2 | Piclaw harness port — `plan -> tool -> verify` works with a text model | One Piclaw tool (e.g. `file_edit`) runs end-to-end with audio I/O |
| 3 | Mic capture (WebRTC) + speaker out | Speak -> agent transcribes -> tool runs -> agent speaks result |
| 4 | Wake word + hardware mute | ^⌥Space toggles mic; no audio in pre-wake state |
| 5 | Spoken permission gates + default-deny on destructive | "rm -rf foo" is blocked; "yes" spoken unblocks; "yes" typed also unblocks |
| 6 | Tool routing — file_edit, shell_run, git_*, test_* all reachable from voice | Each tool callable by spoken intent |
| 7 | Latency tuning — first-token < 300ms p50, barge-in < 200ms | Measured, logged, surfaced in status command |
| 8 | Initiation policy — when does the agent *speak unprompted*? | Spoken "tests failed" fires after a real failure; nothing else fires |
| 9 | Dogfood on a real project — Piclaw itself, or `/Users/tamil/Developers/mini` | 4 hours of real use; notes on every misfire |
| 10 | Dogfood continued, fix the top 3 misfires | Misfire rate drops below 1/30min |
| 11 | `deepvoice start\|run\|stop\|status\|spec\|watch` CLI surface | All six commands work, `--help` is honest |
| 12 | Transcript format + `~/.deepvoice/sessions/*.jsonl` reader | `deepvoice log <id>` plays back the session |
| 13 | README, `IDEATION.md` -> `PRD.md` once direction is picked | `PRD.md` exists if A is confirmed |
| 14 | Demo: 5-minute screen recording, end-to-end ambient flow | `docs/demo-2026-06.mov` exists |

---

## 6. Open questions for the user (in priority order)

1. **A as v0, or layered?** Confirm or override the recommendation.
2. **Initiation policy.** When does the agent speak without being
   asked? Options:
   - (a) Strictly reactive — agent only speaks when you speak first.
   - (b) Failure-only — agent speaks unprompted only when something
     goes wrong (test failure, build break, lint error).
   - (c) State-change — agent speaks on any meaningful state
     transition (task done, plan revised, new file created).
   - (d) Always — agent narrates its thinking continuously.
   My recommendation: **(b)**. Reactive enough to feel ambient, quiet
   enough to not become noise. Maps to the *ambient AI trap* warning.
3. **Wake word**. Custom trained (more private, slower to ship) or
   existing engine like Picovoice (faster, more reliable, costs
   money). My recommendation: Picovoice for v0, custom later.
4. **Multi-modal later.** Should v0 leave a seam for screen share
   / visual diff narration? (Direction C is essentially this.) My
   recommendation: yes, leave a seam, do not build it.
5. **Provider diversity.** OpenAI Realtime API for audio, but the
   planner/verifier can be Claude, GPT, Gemini, or local Ollama.
   My recommendation: planner on Claude Sonnet 4 by default,
   swappable per session.
6. **Distribution.** CLI only, TUI only, or both? My recommendation:
   CLI first (fits the Piclaw lineage), TUI later if there's a
   secondary voice surface (a small Electron app or a menubar app
   for the ambient mode).

---

## 7. Sources (primary, 2025-2026)

- OpenAI — [Introducing gpt-realtime and Realtime API updates for production voice agents (2025-08-28)](https://openai.com/index/introducing-gpt-realtime/)
- InfoQ — [OpenAI's gpt-realtime Enables Production-Ready Voice Agents (2025-09-11)](https://www.infoq.com/news/2025/09/openai-gpt-realtime/)
- Latent.Space — [OpenAI Realtime API: The Missing Manual](https://www.latent.space/p/realtime-api)
- Fora Soft — [OpenAI Realtime API: Production Voice Agents (2026)](https://www.forasoft.com/blog/article/openai-realtime-api-voice-agent-production-guide-2026)
- OpenAI docs — [Voice activity detection (VAD)](https://developers.openai.com/api/docs/guides/realtime-vad)
- Anthropic — [*2026 Agentic Coding Trends Report* (PDF)](https://resources.anthropic.com/hubfs/2026%20Agentic%20Coding%20Trends%20Report.pdf)
- Anthropic — [*2026 Agentic Coding Trends Report* (HTML)](https://resources.anthropic.com/2026-agentic-coding-trends-report)
- Pathmode — [Anthropic's 2026 Agentic Coding Trends Report: Orchestration Era Needs Intent](https://pathmode.io/blog/orchestration-era-needs-intent)
- Tessl — [8 agentic coding trends shaping software engineering in 2026](https://tessl.io/blog/8-trends-shaping-software-engineering-in-2026-according-to-anthropics-agentic-coding-report/)
- Utter — [The Best Voice Dictation Software in 2026](https://utter.to/blog/best-voice-dictation-software-2026/)
- Willow Voice — [Wispr Flow Review: AI Voice Dictation Tool January 2026](https://willowvoice.com/blog/wispr-flow-review-voice-dictation)
- SitePoint — [AI Coding Tools 2026 | Comparison Guide](https://www.sitepoint.com/ai-coding-tools-comparison-2026/)
- Picovoice — [Complete Guide to Wake Word Detection (2026)](https://picovoice.ai/blog/complete-guide-to-wake-word/)
- arXiv — [Dive into Claude Code: The Design Space of Today's and Future AI Agent Systems](https://arxiv.org/html/2604.14228v1)
- Cobus Greyling — [98% of Claude Code Is Not AI](https://cobusgreyling.medium.com/98-of-claude-code-is-not-ai-bab2f37dee0e)
- Building Claude Code with Harness Engineering — [LevelUp write-up](https://levelup.gitconnected.com/building-claude-code-with-harness-engineering-d2e8c0da85f0)
- Ryan Shrott — [The ambient AI trap: why doctors are returning to active dictation in 2026](https://medium.com/@ryanshrott/the-ambient-ai-trap-why-doctors-are-returning-to-active-dictation-in-2026-4a87895f7c84)
- WebRTC vs WebSocket for OpenAI Realtime — [Reddit r/WebRTC discussion](https://www.reddit.com/r/WebRTC/comments/1g7hqmr/webrtc_vs_websocket_for_openai_realtime_voice_api/)

---

## 8. Codebase seams already in scope

- **Piclaw** (`/Users/tamil/Developers/mini/`) — package layout
  `agent / ai / cli / contracts / plugins / prompts / skills / tools / tui`
  is the harness to port. `packages/cli` synthesizes most TUI state.
  `packages/shared` (contracts) is the type seam.
- **pi-harness-lab** (`/Users/tamil/Developers/pi-harness-lab/app/`) —
  runtime-control proof path; useful for testing voice-driven tool
  permissions.
- **prompts-prd** (`/Users/tamil/projects/prompts-prd/`) — PRD/prompt
  pack templates. Use `template/PRD_TEMPLATE.md` once direction is
  picked.
