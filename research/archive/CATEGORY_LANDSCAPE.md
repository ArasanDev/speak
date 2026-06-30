# Voice-First Coding Tools — 2026 Category Landscape

> **Status**: Exploration. Anchor: Wispr Flow. Sweep: every adjacent app in the dictation, voice-coding, IDE-voice-mode, and voice-agent-platform buckets.
> **Date**: 2026-06-18
> **Working dir**: `/Users/tamil/Developers/deepvoice`
> **Use case**: validates the IDEATION.md market-gap claim and reveals which directions of `deepvoice` are crowded vs unclaimed.

---

## 0. TL;DR

The 2026 voice-coding category resolves into **5 buckets**. `deepvoice`
Direction A (ambient pair-programmer) sits in the **unclaimed
quadrant**. Direction B (voice-first CLI) has **two direct shipping
competitors** as of 2026-03: **Claude Code `/voice`** and **Codex
`Ctrl+M`**, plus a third-party **VoiceMode** wrapper. This is *new
since the IDEATION.md* and changes the recommendation ordering.

| Bucket | Examples | What they do | Competes with `deepvoice` Direction |
|---|---|---|---|
| 1. Voice dictation | Wispr Flow, Willow, Superwhisper, Aiko, MacWhisper, VoiceInk | Speech -> text, type for you | None directly |
| 2. Voice-first coding | Serenade, Talon, VoiceMode | Speech -> structured code commands | B (lightly) |
| 3. IDE-integrated voice input | Claude Code `/voice`, Codex `Ctrl+M`, Cursor voice-mode, GitHub Copilot Voice | Push-to-talk into existing chat | **B (directly)** |
| 4. Voice agent platforms | LiveKit Agents, Vapi, Retell, Bland, Deepgram | Infrastructure for building voice agents | None (we build *on* these) |
| 5. Ambient AI (scribes, meeting notes) | Granola, Otter, Fireflies, DeepCura, VoiceboxMD | Always-on transcription, structured notes | A (adjacent) |

**Updated recommendation** (refines IDEATION.md §0):

- **A is still the v0 wedge** — it is the only direction with no
  shipping competitor. Buckets 1, 2, 3 all converge on "speak a
  prompt, get a chat reply." A is the unclaimed ambient/agentic
  quadrant.
- **B is now table-stakes**, not a differentiator. Both Claude Code
  and Codex shipped voice dictation in 2026-Q1. `deepvoice` should
  ship voice-input parity as a feature of A, not as a separate
  product direction.
- **C and D are modes of A**, as before.
- **Build on bucket 4**, don't reinvent it. LiveKit Agents is the
  default for production voice agents in 2026; deepvoice should
  use it for transport, not roll its own WebRTC stack.

---

## 1. Bucket 1 — Voice dictation (Wispr Flow and clones)

These products convert speech to text and type it into whichever app
has focus. **None of them have a tool loop, a plan, or a verify
step.** They are sophisticated typewriters. `deepvoice` does not
compete with them — but they are the *baseline* the user is already
paying for, so the bar for "voice is good enough" is set here.

### 1.1 Wispr Flow (anchor)

- **URL**: [wisprflow.ai](https://wisprflow.ai/)
- **Docs**: [docs.wisprflow.ai](https://docs.wisprflow.ai/articles/9559327591-flow-plans-and-what-s-included)
- **Pricing** (verified 2026-06, [voicescriber](https://voicescriber.com/wispr-flow-pricing-review),
  [weesperneonflow](https://weesperneonflow.ai/en/blog/2026-03-17-voice-dictation-pricing-comparison-lifetime-deals-2026/)):
  - **Free Basic** — limited
  - **Pro** — $15/user/month, or $12/user/month annual
  - **Enterprise** — custom, "startup-grade speed, enterprise-grade
    security", "20% faster GTM execution" (their marketing)
- **Architecture** ([spokenly review](https://spokenly.app/blog/wispr-flow-review),
  [Wispr engineering post](https://wisprflow.ai/post/technical-challenges)):
  - **Cloud only**. No on-device processing. Audio leaves the device.
  - Subprocessors: **Baseten, OpenAI, Anthropic, Cerebras, AWS**.
  - Has a "privacy mode" claiming zero data retention, but
    base architecture is cloud.
  - ASR + LLM post-processing pipeline.
- **Target user**: knowledge workers, PMs, sales, support. Not
  developers specifically.
- **Strengths**: cross-app, fast, polished UX, strong dictation
  accuracy, growing enterprise tier.
- **Weaknesses for our purposes**: no tool loop, no agentic
  behavior, cloud-only (privacy-sensitive users avoid it), no
  voice-as-output.

### 1.2 Willow Voice

- **URL**: [willowvoice.com](https://willowvoice.com/)
- **Reviews**: [G2](https://www.g2.com/products/willow-voice/reviews),
  [YouTube "Dictation Tool Apple Should've Built"](https://www.youtube.com/watch?v=KZj55HMkTQ4),
  [getvoibe](https://www.getvoibe.com/resources/willow-voice-review/)
- **Accuracy**: claims 95%+ on English; runs against Wispr in most
  head-to-heads.
- **Differentiator**: cross-platform (Mac, iOS, Windows), strong
  on Apple silicon.
- **Tone**: "the dictation tool Apple should've built" — they
  position as privacy-first and Apple-native.
- **For `deepvoice`**: Willow is a strong "type for me" baseline
  that developers already use. We don't compete; we could even
  *use* Willow/Wispr as our speech-to-text backend in v0 to skip
  building our own ASR pipeline.

### 1.3 Superwhisper

- **URL**: [superwhisper.com](https://superwhisper.com/),
  [App Store](https://apps.apple.com/us/app/superwhisper-ai-dictation/id6471464415)
- **Pricing**: $9.99/mo (cheaper than Wispr).
- **Platforms**: macOS, Windows, iOS.
- **Position**: budget Wispr alternative. No standout differentiator.
- **Review**: [Spokenly comparison](https://spokenly.app/blog/wispr-flow-vs-superwhisper-vs-macwhisper),
  [YouTube 2026 review](https://www.youtube.com/watch?v=ZIeMg6fpdVc).

### 1.4 Aiko (Sindre Sorhus)

- **URL**: [sindresorhus.com/aiko](https://sindresorhus.com/aiko)
- **Source**: [GitHub openai/whisper discussion #1300](https://github.com/openai/whisper/discussions/1300),
  [Lifehacker coverage](https://lifehacker.com/tech/aiko-free-ai-transcription-app),
  [App Store](https://apps.apple.com/au/app/aiko/id1672085276)
- **Author**: Sindre Sorhus — prolific open-source Mac developer.
  High signal: he ships and maintains.
- **Pricing**: **free**.
- **Model**: Whisper-based, on-device. Privacy-first.
- **Platforms**: macOS, iOS.
- **For `deepvoice`**: Aiko is the existence proof that a
  privacy-respecting, on-device, free, open-source dictation app
  can ship. It is the right *baseline* for an "ambient" voice
  product — no audio ever leaves the device, period. `deepvoice`
  v0 should consider a similar STT path for the pre-wake state.

### 1.5 MacWhisper

- **URL**: macwhisper.com (linked from Spokenly comparison)
- **Position**: best for local file transcription with some
  system-wide dictation support.
- **Use case**: long-form audio transcription (meetings,
  interviews) more than real-time dictation.
- **For `deepvoice`**: not directly relevant; included for
  completeness in the Mac-native dictation space.

### 1.6 VoiceInk

- **URL**: [tryvoiceink.com](https://tryvoiceink.com/)
- **Position**: best lightweight offline option for Mac.
- **For `deepvoice`**: another privacy-first Mac-native option.
  Bundle of VoiceInk + Piclaw-style tools could be a v0
  quickstart.

### 1.7 Buyer-guide aggregators

- [Utter "Best Dictation Software 2026"](https://utter.to/blog/best-dictation-software-2026/)
  — 10 apps compared, Mac-focused.
- [Spokenly Wispr Flow review](https://spokenly.app/blog/wispr-flow-review)
  — competitor analysis.
- [Zack Proser "Best Dictation App for Mac in 2026"](https://zackproser.com/blog/best-mac-dictation-app-2026)
- [Codebridge "Best Voice-to-Text Apps for Mac in 2026"](https://www.codebridge.tech/articles/best-voice-to-text-apps-for-mac)

---

## 2. Bucket 2 — Voice-first coding tools

These are the products that *do* have a coding-specific layer, but
they are still "speak a command, run a command" — not a full
agentic loop with planning and verification. Closer to `deepvoice`
Direction B than A.

### 2.1 Serenade

- **URL**: [serenade.ai](https://serenade.ai/)
- **Position**: open-source voice-to-code engine. Supports VS Code,
  JetBrains, Chrome ([claude-code-alternatives.com](https://claude-code-alternatives.com/ide-extensions/serenade/)).
- **Status**: still alive as of 2026, but the YouTube results
  cluster around 2020-2021 ([dev.to Heroku](https://dev.to/heroku/using-serenade-to-code-by-voice-5007),
  [Better Programming](https://betterprogramming.pub/code-by-voice-using-serenade-5f51f4153854))
  and the [Salma Alam-Naylor piece](https://whitep4nth3r.com/blog/how-i-learned-to-code-with-my-voice/)
  — search results are dated. Update cadence is low.
- **Pitch**: "write code using natural speech, speech-to-code engine
  designed for developers from the ground up, fully open-source."
- **For `deepvoice`**: Serenade is the *idea* `deepvoice` Direction B
  was based on. Their low update velocity suggests the market
  hasn't pulled voice-coding forward — most developers are still
  dictating into Claude Code/Cursor chat, not into a custom
  voice-to-code engine.

### 2.2 Talon

- **URL**: [talonvoice.com](https://talonvoice.com/)
- **Position**: hands-free coding, accessibility-first.
- **Reviews**: [handsfreecoding.org](https://handsfreecoding.org/2021/12/12/talon-in-depth-review/),
  [Josh Comeau "Coding with voice dictation using Talon Voice"](https://www.joshwcomeau.com/blog/hands-free-coding/),
  [YouTube hands-free computer use](https://www.youtube.com/watch?v=e3xaH1pJKsI).
- **Community**: small but loyal; long-running project; the
  default for accessibility-driven voice coding.
- **For `deepvoice`**: Talon is the wrong *layer* for us to compete
  with — they own accessibility. But their *conventions* (sleep
  mode, voice commands for editor actions, noise vocabularies) are
  worth studying.

### 2.3 VoiceMode (`voicemode.dev`)

- **URL**: [voicemode.dev](https://voicemode.dev/)
- **Pitch**: "VoiceMode brings natural voice conversations to
  Claude Code and other AI coding assistants. Open-source,
  local-first, and OpenAI-compatible."
- **This is a major finding for `deepvoice`**. VoiceMode is a
  *wrapper* around Claude Code (and other harnesses) that adds
  full-duplex voice. It is open source. It claims local-first and
  OpenAI Realtime API compatibility.
- **For `deepvoice`**: **candidate dependency**. If VoiceMode
  already wires Realtime API -> Claude Code's harness, `deepvoice`
  could ship a thin "ambient wrapper" layer over VoiceMode + the
  Piclaw loop instead of building voice transport from scratch.
  This is worth a serious technical evaluation in §3 of this doc.

### 2.4 Voice Cursor (`voicecursor.ai`)

- **URL**: [voicecursor.ai](https://voicecursor.ai/)
- **Pitch**: a third-party dictation tool positioned for Cursor
  specifically. ("Best voice dictation app for ...")
- **For `deepvoice`**: niche, not a threat.

---

## 3. Bucket 3 — IDE-integrated voice input (THE NEW COMPETITORS)

**This bucket did not exist as recently as 2025-Q4.** In 2026-Q1
both Claude Code and Codex shipped push-to-talk voice dictation
into their CLI/TUI harnesses. This is the biggest change to the
competitive landscape since the IDEATION.md was written.

### 3.1 Claude Code `/voice` (Anthropic, official)

- **Docs**: [code.claude.com/docs/en/voice-dictation](https://code.claude.com/docs/en/voice-dictation)
- **Command**: `/voice` slash command.
- **Interaction**: hold-to-talk push-to-talk, **spacebar hardcoded**
  ([GitHub issue #35411](https://github.com/anthropics/claude-code/issues/35411),
  "Remappable voice push-to-talk key + system-wide Claude dictation").
- **STT language**: defaults to English, no language config
  ([issue #33170](https://github.com/anthropics/claude-code/issues/33170)).
- **Documentation gap**: voice mode and `voiceEnabled` setting are
  undocumented ([issue #31355](https://github.com/anthropics/claude-code/issues/31355)).
- **Rollout status** (Reddit
  [r/ClaudeAI thread](https://www.reddit.com/r/ClaudeAI/comments/1rjkwqk/new_voice_mode_is_rolling_out_now_in_claude_code/)):
  "live for ~5%" of users as of 2026-03.
- **Coverage**: [Developers Digest guide](https://www.developersdigest.tech/guides/voice-dictation),
  [Reza Rezvani "Claude Code Just Got a /voice Command"](https://alirezarezvani.medium.com/claude-code-just-got-a-voice-command-and-it-changes-how-you-talk-to-your-terminal-3e77bd16e972),
  [BuildMVPFast hands-free guide 2026](https://www.buildmvpfast.com/blog/claude-voice-mode-hands-free-programming),
  [YouTube walkthrough](https://www.youtube.com/watch?v=6egegQBQcks).
- **What it actually is**: speech-to-text push-to-talk that fills
  the prompt buffer. It is **not** real-time voice, **not** voice
  output, **not** ambient. It is a voice-to-textbox replacement.
- **For `deepvoice`**: this is Direction B as a *feature* of
  Claude Code, not a separate product. It validates the demand
  for voice input into coding harnesses. It does *not* address
  Direction A (ambient, voice-as-output, push-to-talk failures).

### 3.2 Codex voice transcription (OpenAI, official)

- **Hotkey**: `Ctrl + M` in both Codex App and Codex CLI
  ([LinkedIn, Mar 3 2026](https://www.linkedin.com/posts/vaibhavs10_icymi-you-can-use-voice-transcription-in-activity-7434657205737459714-ifCa)).
- **Codex macOS global dictation**: in beta, [issues open](https://community.openai.com/t/global-dictation-in-codex-macos-not-working/1383381)
  ("used to work well previously with the same shortcuts").
- **Multi-language STT**: Chinese + English + German works
  ([issue #7215](https://github.com/openai/codex/issues/7215)).
- **Native voice-to-text support**:
  [issue #12689](https://github.com/openai/codex/issues/12689).
- **Third-party wrappers**: [WhisperTyping for Windows](https://whispertyping.com/tech/voice-typing-for-codex-cli/),
  [Spokenly Codex voice mode guide](https://spokenly.app/blog/voice-dictation-for-developers/codex).
- **For `deepvoice`**: same as Claude Code — Direction B is now
  partly shipped. But also a *huge opportunity*: `deepvoice`
  Direction A could ship as a thin layer *over* Codex's existing
  voice input + harness, not as a replacement. **The Codex
  harness is the most natural surface to extend.**

### 3.3 Cursor voice mode (third-party + native)

- **Native**: Cursor 3.7 shipped a "Design Mode" in 2026-06 with
  voice + multi-select ([digitalapplied](https://www.digitalapplied.com/blog/cursor-3-7-design-mode-voice-multi-select-june-2026)).
- **Third-party**: a `voice-mode` Python package exists with
  Cursor integration ([voice-mode.readthedocs.io](https://voice-mode.readthedocs.io/en/stable/integrations/cursor/)).
- **For `deepvoice`**: Cursor is a closed platform. We can't ship
  a Cursor-integrated Direction A without their cooperation. Skip.

### 3.4 GitHub Copilot Voice (GitHub Next, official)

- **URL**: [githubnext.com/projects/copilot-voice/](https://githubnext.com/projects/copilot-voice/)
- **Source**: [githubnext/copilot-voice/README.md](https://github.com/githubnext/githubnext/blob/main/copilot-voice/README.md?plain=1)
- **Microsoft Learn video**: [Voice-Powered Coding with GitHub Copilot](https://learn.microsoft.com/en-us/shows/visual-studio-code/voice-powered-coding-with-github-copilot)
- **Also**: VS Code Speech — built into VS Code itself, paired
  with Copilot.
- **For `deepvoice`**: Copilot Voice is real, but it's still
  push-to-talk transcription into chat. Same Direction B as
  Claude Code/Codex.

### 3.5 Aggregator voice setups

- Reddit
  [r/ClaudeAI "go-to voice-to-text setup for Cursor or Claude Code"](https://www.reddit.com/r/ClaudeAI/comments/1l9mzwi/whats_your_goto_voicetotext_setup_for_cursor_or/)
  documents the *ad-hoc* reality: most users combine OS dictation
  (Win+H / Fn+F5) or Wispr Flow with their coding tool. They
  glue the pieces themselves because no tool owns the integration.
- **Implication for `deepvoice`**: there is demand for a
  *cohesive* product, not a third voice-input option.

---

## 4. Bucket 4 — Voice agent platforms (infrastructure)

`deepvoice` should **build on these**, not compete with them. The
hard real-time audio work is solved at this layer.

### 4.1 LiveKit Agents

- **URL**: [livekit.com](https://livekit.com/),
  [github.com/livekit/agents](https://github.com/livekit/agents)
- **Position**: open-source framework for building real-time,
  multi-modal voice agents. Handles audio/video pipelines, agent
  orchestration, tool calling.
- **Ecosystem**: integrates with OpenAI Realtime, Anthropic,
  custom STT/TTS pipelines. Production-grade WebRTC.
- **Reddit consensus**
  ([r/AI_Agents](https://www.reddit.com/r/AI_Agents/comments/1oj9gos/so_many_agent_frameworks_to_use_or_try_what/)):
  "LiveKit handles the real-time infra (audio/video pipelines),
  while frameworks like CrewAI/Mastra are for agent orchestration.
  They're complementary."
- **For `deepvoice`**: **primary transport candidate**. Use
  LiveKit Agents for the WebRTC + Realtime API wiring; build the
  Piclaw harness on top.

### 4.2 Vapi

- **URL**: vapi.ai
- **Position**: managed voice agent platform. Phone-call-grade
  latency, no infra to manage.
- **For `deepvoice`**: skip — too opinionated, too phone-call
  focused, no local-first option.

### 4.3 Retell AI

- **URL**: retell.ai
- **Position**: similar to Vapi, voice-agent-as-a-service.
- **For `deepvoice`**: skip — same reason.

### 4.4 Bland AI

- **URL**: bland.ai
- **Position**: outbound voice agents, sales / support focused.
- **For `deepvoice`**: skip — wrong market.

### 4.5 Deepgram Voice Agent API

- **URL**: [deepgram.com](https://deepgram.com/learn/best-speech-to-text-apis-2026)
- **Position**: low-latency STT + voice agent stack. Pairs well
  with their own STT.
- **For `deepvoice`**: STT engine candidate, not the full
  transport. Pair with LiveKit for orchestration.

### 4.6 Comparison

- [open.cx "AI Voice Agent Platforms Compared (2026)"](https://www.open.cx/blog/ai-voice-agent-platform-comparison-2026)
- [Lumay "Top 10 AI Voice Agent Platforms"](https://www.lumay.ai/blogs/top-10-ai-voice-agent-platforms)
- [Ainora "Retell AI vs Bland AI vs Vapi: Voice Agent Platform Comparison (2026)"](https://ainora.lt/blog/retell-ai-vs-bland-ai-vs-vapi-comparison-2026)

---

## 5. Bucket 5 — Ambient AI (scribes, meeting notes)

This is the *only* bucket where "ambient always-listening" has
proven product-market fit. It is a useful reference for the
ambient direction, even though the use case (clinical notes,
meeting notes) is different.

### 5.1 Consumer / prosumer

- **Granola** — AI meeting notes, ambient, no bot joins the call.
- **Otter** — meeting transcription, established player.
- **Fireflies** — meeting notes + search.
- **Fathom** — free tier, growing fast.
- **Tana** — meeting notes with structured outputs.
- **Reviews**: [Tana "Best AI meeting assistants in 2026 for real actions"](https://tana.inc/blog/best-ai-meeting-assistants-2026),
  [alfred_ "Best AI Meeting Notetakers 2026"](https://get-alfred.ai/blog/best-ai-meeting-notetakers).

### 5.2 Clinical (regulated, high-stakes)

- **DeepCura** — ambient dictation for doctor-patient
  conversations ([deepcura.com](https://www.deepcura.com/resources/ambient-dictation)).
- **VoiceboxMD** — combined ambient + active dictation, $79/mo
  ([voiceboxmd.com](https://voiceboxmd.com/ai-scribe-for-nurse-practitioners/)).
- **Twofold** — comparison of ambient vs dictation vs smart
  scribe ([trytwofold.com](https://www.trytwofold.com/blog/compare-ai-scribe-workflows)).
- **The ambient AI trap** ([Medium](https://medium.com/@ryanshrott/the-ambient-ai-trap-why-doctors-are-returning-to-active-dictation-in-2026-4a87895f7c84))
  — doctors returning to *active* dictation because ambient
  misfires. This is the warning we keep in §4.3 of the IDEATION.

### 5.3 For `deepvoice`

The clinical scribe market is the only 2026 evidence that
ambient always-listening works at scale. It works because the
failure mode is *visible* (note gets written, doctor reviews),
not destructive. That maps perfectly to `deepvoice` Direction A
where the *transcript* is the canonical artifact.

---

## 6. What `deepvoice` would be different

Synthesizing buckets 1-5 against the IDEATION.md's 4 directions:

| Direction | Closest competitor in 2026 | How `deepvoice` differentiates |
|---|---|---|
| A — ambient pair-programmer | Clinical AI scribes (different domain); partial overlap with Granola's "no bot" ambient pattern | **No competitor in coding**. Voice-as-output push channel, agent-initiated failure narration, full Piclaw tool loop underneath. |
| B — voice-first CLI | Claude Code `/voice`, Codex `Ctrl+M`, Cursor 3.7, Copilot Voice, Serenade, Voice Cursor | **Shipped by everyone**. Not a differentiator. Build B as a feature of A, not a separate product. |
| C — spec-to-diff narrator | None (closest is PR-summary bots) | Voice output for *long-form* async work. Adjacent to A. |
| D — voice test loop | None in coding (Granola-style for meetings) | Push channel + harness = unique. Adjacent to A. |

**The wedge is A.** It is the only direction with no direct
competitor, and it is the only direction where voice is
load-bearing (not just an input convenience).

---

## 7. Implications for `deepvoice` strategy

1. **Stop thinking about Direction B as a separate product.** It
   is table-stakes. Ship voice-input parity in v0 only because
   Direction A needs it; don't market it.

2. **Evaluate `voicemode.dev` early.** It may already be the
   transport layer. If it works with Piclaw-style harnesses
   cleanly, `deepvoice` becomes a thin ambient wrapper, not a
   full voice stack. (Saves 2-3 days of build time.)

3. **Use LiveKit Agents for transport, not a hand-rolled WebRTC
   stack.** This is the 2026 consensus choice for production
   voice agents.

4. **Ship a Wispr/Aiko/Willow integration path** so users can use
   their existing dictation tool as the STT backend. Don't
   force them to switch.

5. **The Codex harness is the most natural `deepvoice` surface.**
   Codex already has voice input (`Ctrl+M`), a documented
   tool-call architecture, and a `/voice` equivalent coming.
   `deepvoice` Direction A could ship as a Codex extension /
   wrapper, not a from-scratch harness.

6. **The clinical AI scribe market validates the ambient
   pattern.** It works because transcripts are visible artifacts,
   not destructive actions. Frame `deepvoice` A as "ambient
   supervision with visible transcripts" to borrow trust cues.

7. **The "ambient AI trap" warning still applies.** Default to
   failure-only initiation (option (b) in IDEATION.md §6), not
   continuous narration. Test the wake word against background
   speech. Ship a hardware mute that is impossible to bypass.

---

## 8. Sources (primary, 2025-2026)

### Bucket 1 — Voice dictation
- Wispr Flow — [wisprflow.ai](https://wisprflow.ai/), [docs.wisprflow.ai](https://docs.wisprflow.ai/articles/9559327591-flow-plans-and-what-s-included)
- Wispr Flow engineering — [Technical challenges and breakthroughs behind Flow](https://wisprflow.ai/post/technical-challenges)
- Wispr Flow reviews — [voicescriber 2026 pricing](https://voicescriber.com/wispr-flow-pricing-review), [Spokenly 2026 review](https://spokenly.app/blog/wispr-flow-review), [Weesper Neon Flow 2026 comparison](https://weesperneonflow.ai/en/blog/2026-03-17-voice-dictation-pricing-comparison-lifetime-deals-2026/)
- Willow Voice — [willowvoice.com](https://willowvoice.com/), [G2 reviews](https://www.g2.com/products/willow-voice/reviews), [Wispr Flow review on willowvoice.com](https://willowvoice.com/blog/wispr-flow-review-voice-dictation), [YouTube "Dictation Tool Apple Should've Built"](https://www.youtube.com/watch?v=KZj55HMkTQ4)
- Superwhisper — [superwhisper.com](https://superwhisper.com/), [App Store](https://apps.apple.com/us/app/superwhisper-ai-dictation/id6471464415), [Spokenly comparison](https://spokenly.app/blog/wispr-flow-vs-superwhisper-vs-macwhisper)
- Aiko — [sindresorhus.com/aiko](https://sindresorhus.com/aiko), [GitHub openai/whisper discussion #1300](https://github.com/openai/whisper/discussions/1300), [Lifehacker](https://lifehacker.com/tech/aiko-free-ai-transcription-app)
- MacWhisper, VoiceInk — [Utter 2026 buyer guide](https://utter.to/blog/best-dictation-software-2026/), [tryvoiceink.com](https://tryvoiceink.com/), [Zack Proser 2026](https://zackproser.com/blog/best-mac-dictation-app-2026)

### Bucket 2 — Voice-first coding
- Serenade — [serenade.ai](https://serenade.ai/), [claude-code-alternatives.com](https://claude-code-alternatives.com/ide-extensions/serenade/), [Salma Alam-Naylor "How I learned to code with my voice"](https://whitep4nth3r.com/blog/how-i-learned-to-code-with-my-voice/)
- Talon — [talonvoice.com](https://talonvoice.com/), [handsfreecoding.org review](https://handsfreecoding.org/2021/12/12/talon-in-depth-review/), [Josh Comeau](https://www.joshwcomeau.com/blog/hands-free-coding/)
- VoiceMode — [voicemode.dev](https://voicemode.dev/)
- Voice Cursor — [voicecursor.ai](https://voicecursor.ai/)

### Bucket 3 — IDE voice modes
- Claude Code voice — [code.claude.com/docs/en/voice-dictation](https://code.claude.com/docs/en/voice-dictation), [issue #35411](https://github.com/anthropics/claude-code/issues/35411), [issue #33170](https://github.com/anthropics/claude-code/issues/33170), [issue #31355](https://github.com/anthropics/claude-code/issues/31355), [r/ClaudeAI rollout thread](https://www.reddit.com/r/ClaudeAI/comments/1rjkwqk/new_voice_mode_is_rolling_out_now_in_claude_code/), [Rezvani /voice article](https://alirezarezvani.medium.com/claude-code-just-got-a-voice-command-and-it-changes-how-you-talk-to-your-terminal-3e77bd16e972), [BuildMVPFast](https://www.buildmvpfast.com/blog/claude-voice-mode-hands-free-programming), [Developers Digest](https://www.developersdigest.tech/guides/voice-dictation)
- Codex voice — [issue #12689](https://github.com/openai/codex/issues/12689), [issue #7215](https://github.com/openai/codex/issues/7215), [LinkedIn announcement](https://www.linkedin.com/posts/vaibhavs10_icymi-you-can-use-voice-transcription-in-activity-7434657205737459714-ifCa), [OpenAI community thread](https://community.openai.com/t/new-space-toggle-for-voice/1375202), [Spokenly Codex guide](https://spokenly.app/blog/voice-dictation-for-developers/codex)
- Cursor voice — [voice-mode.readthedocs.io](https://voice-mode.readthedocs.io/en/stable/integrations/cursor/), [Cursor 3.7 Design Mode](https://www.digitalapplied.com/blog/cursor-3-7-design-mode-voice-multi-select-june-2026)
- Copilot Voice — [githubnext.com/projects/copilot-voice/](https://githubnext.com/projects/copilot-voice/), [GitHub Next README](https://github.com/githubnext/githubnext/blob/main/copilot-voice/README.md?plain=1), [Microsoft Learn video](https://learn.microsoft.com/en-us/shows/visual-studio-code/voice-powered-coding-with-github-copilot)
- Aggregator — [r/ClaudeAI "go-to voice-to-text setup"](https://www.reddit.com/r/ClaudeAI/comments/1l9mzwi/whats_your_goto_voicetotext_setup_for_cursor_or/)

### Bucket 4 — Voice agent platforms
- LiveKit — [livekit.com](https://livekit.com/), [github.com/livekit/agents](https://github.com/livekit/agents), [Fora Soft build guide](https://forasoft.medium.com/build-and-deploy-livekit-ai-voice-agents-a-step-by-step-business-guide-6291a7ddc57e)
- Vapi / Retell / Bland — [open.cx 2026 comparison](https://www.open.cx/blog/ai-voice-agent-platform-comparison-2026), [Lumay top 10](https://www.lumay.ai/blogs/top-10-ai-voice-agent-platforms), [Ainora head-to-head](https://ainora.lt/blog/retell-ai-vs-bland-ai-vs-vapi-comparison-2026)
- STT engines — [Deepgram best STT APIs 2026](https://deepgram.com/learn/best-speech-to-text-apis-2026), [Deepgram vs ElevenLabs Scribe](https://deepgram.com/learn/elevenlabs-speech-to-text), [NextLevel real-time STT](https://nextlevel.ai/best-speech-to-text-models/)
- Wake word — [Picovoice Porcupine](https://picovoice.ai/blog/complete-guide-to-wake-word/), [github.com/picovoice/porcupine](https://github.com/picovoice/porcupine), [github.com/dscripka/openWakeWord](https://github.com/dscripka/openWakeWord)

### Bucket 5 — Ambient AI
- Granola, Otter, Fireflies — [Tana 2026 review](https://tana.inc/blog/best-ai-meeting-assistants-2026), [alfred_ 2026 review](https://get-alfred.ai/blog/best-ai-meeting-notetakers), [meetingnotes.com](https://meetingnotes.com/blog/best-ai-note-takers)
- Clinical scribes — [DeepCura ambient dictation](https://www.deepcura.com/resources/ambient-dictation), [VoiceboxMD](https://voiceboxmd.com/ai-scribe-for-nurse-practitioners/), [Twofold comparison](https://www.trytwofold.com/blog/compare-ai-scribe-workflows)
- Warning — [The ambient AI trap](https://medium.com/@ryanshrott/the-ambient-ai-trap-why-doctors-are-returning-to-active-dictation-in-2026-4a87895f7c84)
