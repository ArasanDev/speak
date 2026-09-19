# Cleanup Architecture Gap Analysis

> Field comparison of `speak`'s AI neat-writing seam (`LLMCleaning` →
> `CaptureSession.runCleanup` → `PromptBuilder` → `FoundationModelsCleaner`)
> against the reference open-source implementation in VoiceInk
> (`AIEnhancementService` → `AIService`/LLMkit → `CustomPrompt` + `ModeConfig`).
> Local reference clone: `ai_tmp/` (gitignored). Analysis is binding input to
> the capability track; it does not import code — `speak` stays Apple-only in v0.
>
> Status: analysis, 2026-09-20. Feeds `docs/roadmap.md` v0.1 capability items.

## 1. Architecture comparison

| Concern | VoiceInk (`AIEnhancementService`) | `speak` (`LLMCleaning` seam) | Assessment |
|---|---|---|---|
| Result object | `AIEnhancementResult` — text, `duration`, `promptName`, `systemMessage`, `userMessage` | `CleanupPassResult` — `cleanedText`, `engineId`, `cleanupSeconds`, `status` | **Gap G4** — speak tracks latency honestly but never captures the rendered prompt or raw model output for debugging/eval. |
| Context injection | `RecordingContextSnapshot` captures selectedText + clipboard + OCR screen text at record start; injected as XML blocks in the system prompt | `ContextInput` enum (`.selection`, `.clipboard`, `.currentFile`, `.appName`) + `context:` param on `PromptBuilder.build` exist; **no caller ever supplies values** | **Gap G1** — the seam is fully designed and dead. `.selection` and `.appName` are feasible under the two existing permissions. `.clipboard` and screen OCR are deliberately out (§2.6 never-read-pasteboard; two-permission rule). |
| Failure handling | Typed `EnhancementError` (timeout / rateLimit / serverError / notConfigured…) → retry with exponential backoff (max 3 attempts) → then throw to UI | All errors → `llmCleanupFailed(String)` → `runCleanup` falls back to raw transcript, `.done`, honest `.fallbackRaw(reason)` status | Divergence is **deliberate** — cleanup failure is never a user-facing error in speak (logged decision in `CaptureSession+Cleanup`). But **Gap G2**: error taxonomy is collapsed to a string, so transient-vs-permanent can't be distinguished — matters once pluggable (cloud) engines ship. |
| Retry / resilience | `makeRequestWithRetry` — exponential backoff on network/server/429; configurable `retryOnTimeout`; `waitForRateLimit()` floor between requests | None — single `clean()` attempt inside the 10 s `T_cleanup` race | **Gap G3** — for on-device FM retry is mostly meaningless, but `OpenAICompatibleCleaner` (opt-in cloud) has no transient-failure recovery within the budget. |
| Output sanitization | `AIEnhancementOutputFilter` strips `<thinking>`/`<think>`/`<reasoning>` blocks before delivery | `extractTargetTranscript` parses the FM response shape; no thinking-tag stripping | **Gap G5** — Apple FM emits no reasoning traces, but reasoning models served via OpenAI-compatible endpoints (qwen3, deepseek-r1, ollama) leak `<think>` blocks into pasted text. Must be fixed before the pluggable path ships. |
| Prompt structure | Single `enhancementSystemTemplate` — rules + context-rules + task-instructions + few-shot examples; user prompt text is interpolated as `TASK_INSTRUCTIONS`; `useSystemInstructions` toggle lets a custom prompt run raw | `PromptBuilder` — profile systemPrompt + structured knob clauses (format/tone/length/intensity) + vocabulary + context + category fragment + per-profile few-shot `examples` | **speak is stronger here.** Structured knobs compile to clauses only when non-default; per-profile few-shot `examples` are the strongest lever for a ~3B model. VoiceInk's example block is fixed globally; speak's is per-profile. |
| Per-app routing | `ModeConfig.appConfigs` + `urlConfigs` — mode triggers on app or URL; bundles STT model, enhancement provider, prompt, output mode, `autoSendKey` | `Profile.targetApps` + `ProfileResolver` — bundle-ID routing to a profile carrying prompt/knobs/model/`autoSubmit` | Parity on app routing. **Gap G6a**: `Profile.autoSubmit` is stored and editable in AI Studio but **never read** at paste time — dead field. **Gap G6b**: URL triggers not needed (speak targets agent contexts, not browsers). |
| Output routing | `ModeOutputMode` — paste / respond / customCommand per mode | Paste-always at cursor; Agent destination handles the "respond to agent" case via AgentBridge | Partial parity — different model, same outcome. `respond` maps to speak's agent-call flow rather than an output mode. |
| Warm-up | `ModelPrewarmService` at app lifecycle | `LLMCleaning.warmUp()` per-dictation at capture start | **speak is better** — warm-up rides the capture window, so first `clean()` after stop is already hot. |
| Streaming/felt speed | Enhance once, post-stop | `StreamingChunkCoordinator` + filmstrip — progressive per-block polish during capture | **speak is ahead** — VoiceInk has no during-capture enhancement. |
| Custom vocabulary | `CustomVocabularyService` injected into system prompt | `customVocabulary` on `.styled`/`.profile` modes → vocabulary clause | Parity. |
| Rate limiting | 1 s floor between enhancement requests | None needed — one `clean()` per dictation; streaming coordinator serializes its own calls | Parity for current shape; revisit if fan-out cleanup ever lands. |

## 2. The gaps, ranked

Ordered by user-visible impact, not implementation order.

### G1 — Context injection is a dead seam  *(capability: context-aware cleanup)*
`PromptBuilder.build(context:)` accepts `[ContextInput: String]`, the `.profile`
mode carries the profile, and `ContextInput` defines `.selection`/`.appName` —
but every call site passes the default `[:]`. Nothing captures or injects
context, so profiles that would benefit ("reply to the selected text", "use the
app's terminology") get a dumber prompt than designed.

- **Buildable under current permissions**: `.appName` (frontmost bundle → display
  name — already resolved for routing) and `.selection` (AX `kAXSelectedTextAttribute`
  on the focused element — Accessibility permission we already hold).
- **Deliberately excluded**: `.clipboard` (violates §2.6 never-read-pasteboard —
  this is a moat, not a gap) and screen OCR (requires a third permission —
  Screen Recording — violating the two-permission rule). Keep both out; the
  reference implementation's clipboard/screen context is not a pattern to copy.
- Wire: a `ContextSnapshotService` at `beginDictation` (main actor, beside the
  `frontmostApp` capture already there) → pass through `SpeakEngine` →
  `.profile` mode → `PromptBuilder`. Snapshots at dictation start, never read
  again — same discipline as the frontmost-App capture.

### G5 — Reasoning-tag leakage in pluggable engines  *(blocks V01-2 consumers)*
`AIEnhancementOutputFilter` exists upstream precisely because OpenAI-compatible
reasoning models emit `<think>…</think>` blocks into output. speak's
`OpenAICompatibleCleaner` will paste those blocks verbatim. A shared
`CleanupOutputFilter` (strip thinking/reasoning tags, trim) should run at the
`LLMCleaning` boundary for pluggable engines — cheap, pure, unit-testable.

### G6a — `Profile.autoSubmit` is a dead field
Stored, editable in AI Studio, documented as "simulate Return after paste" —
and never read in the paste path. Either wire it (`PasteboardWriter` → Return
key event after Cmd+V for profiles where `autoSubmit == true`, gated to
terminal-like contexts) or delete it from the model until built. A dead knob in
a user-facing editor is a broken promise.

### G4 — Prompt observability for eval and debugging
`runCleanup` knows `cleanupSeconds` and `status` but discards the rendered
prompt and raw model response. VoiceInk's result carries `systemMessage`/
`userMessage` for exactly this reason. speak's eval harness (`CleaningQualityScorer`,
`make eval`) currently can't diff "what did we send" against "what came back"
without reconstructing prompts out-of-band. Add the rendered instructions +
raw response to the cleanup result (or log at `.debug`) so eval runs and
failure forensics are first-class.

### G3/G2 — Transient-failure recovery + error taxonomy (pluggable path)
Two coupled items for the opt-in cloud cleaner: (a) typed error cases
(timeout / rate-limited / server / auth) instead of `llmCleanupFailed(String)`,
(b) bounded retry-with-backoff **inside** the existing `T_cleanup` race for
transient cases only. On-device FM needs neither — this is scoped to
`SpeakLLM`/pluggable engines. Do not add retries to `runCleanup` itself; the
10 s budget is the outer bound regardless.

## 3. What not to copy

Explicit rejections — divergence is deliberate, matching `v01-capability-track.md`
§rejected-scope precedent:

- **Clipboard context** — §2.6 hard rule. The reference app reads the pasteboard
  at record start; speak never will. `ContextInput.clipboard` should be removed
  from the enum or documented as permanently unimplemented so agents don't wire it.
- **Screen-capture context** — needs a third OS permission (Screen Recording).
  The two-permission rule is load-bearing for the product's trust story.
- **Per-mode STT model** — VoiceInk lets each mode pick a different transcriber.
  speak's single `Transcribing` seam is a deliberate simplicity constraint;
  per-profile STT choice can wait until a second STT engine actually ships.
- **Prompt-only configuration** — the reference's free-text `CustomPrompt` is
  weaker than speak's Profile (structured knobs + few-shot examples). Do not
  regress to prompt-only editing.

## 4. Recommended wiring order

1. **G6a** — wire or remove `autoSubmit` (smallest, closes a user-visible lie).
2. **G5** — `CleanupOutputFilter` at the pluggable boundary (unblocks V01-2
   correctness for reasoning models).
3. **G1** — `ContextSnapshotService` for `.selection` + `.appName` (the biggest
   capability gain; uses permissions already held).
4. **G4** — prompt/response capture into `CleanupPassResult` (feeds eval + the
   transparency moat).
5. **G3+G2** — typed errors + bounded retry for `OpenAICompatibleCleaner`
   (v0.1 cloud-path hardening; after V01-2 lands).
