---
name: voice-actions-h1-skeleton
description: H-1 Voice Actions intent-router (specs/horizon-voice-os.md Pillar 1). As of loop #45 it IS wired into the live pipeline (CaptureSession.stop → SpeakEngine.newSession → DictationController); this note documents the skeleton design + how the live wiring was done.
metadata:
  type: project
---

Built 2026-07-06 in worktree `agent-a7d238ba9579f6761` (uncommitted, pending
orchestrator merge): `Speak/SpeakCore/VoiceActions/` — `ActionRouting.swift`
(`PrefixActionRouter`, pure deterministic prefix gate, no LLM), `ActionExecuting.swift`
+ `ShortcutsCLIExecutor.swift` (`Process`-backed `/usr/bin/shortcuts`), and
`VoiceActionsCoordinator.swift` (ties router + executor + existing
`CommandModeService` together). `SettingsStore.voiceActionsEnabled` (default
false) + `voiceActionsPrefix` (default "hey speak") gate the whole feature.

**Why:** specs/horizon-voice-os.md Sequencing #1 — "H-1 Intent router skeleton +
deterministic gate (no new perms) — after V01-3 lands." The full design (spec
line 22-25) is "deterministic prefix gate + 3B classification"; the 3B pass is
explicitly out of scope for H-1. [decision H-1] command-vs-action split without
a classifier: exact case-insensitive match against a caller-supplied action
catalog → `.action` (canonical catalog casing preserved, not spoken casing —
`shortcuts run` may be case-sensitive); anything else under the prefix →
`.command`. This is a stand-in for the eventual 3B pass, not real understanding.

**Live wiring (loop #45, uncommitted in a worktree, pending orchestrator commit):**
the paste happens *inside* `CaptureSession.stop()` → `runPaste()`, so the App
layer sees the transcript only AFTER paste and cannot suppress it for an executed
action. Therefore the wiring lives in the engine/session, NOT `DictationController`
(the task brief's guess was wrong — surfaced, not papered over):
- `CaptureSession` gained an optional `voiceActionsHandler: (@Sendable (String)
  async -> VoiceActionOutcome)?` (default nil), injected exactly like
  `voiceCommandPreprocessor`. `stop()` calls `routeVoiceActions(...)` at the
  `rawText`-ready seam (after the empty-transcript guard, before cleanup+paste);
  it returns a terminal `TranscriptionResult?` — non-nil ⇒ action/command executed,
  paste SUPPRESSED, settle `.done` via `settleVoiceActionExecuted` (no latency, no
  paste); nil ⇒ proceed with normal cleanup+paste. `.dictation` and
  `.degradedToDictation` both return nil ⇒ ORIGINAL transcript is pasted.
- `SpeakEngine.init` gained `voiceActionsExecutor` + `voiceActionsCommandService`
  (both nil-default, all-SpeakCore ⇒ engine stays AppKit-free). `newSession()`
  builds the handler ONLY when `settings.voiceActionsEnabled`; disabled ⇒ nil
  handler ⇒ byte-identical pre-H-1 path. **The catalog fetch is prefix-gated**:
  the handler runs `PrefixActionRouter.route(rawText, [])` first and only calls
  `executor.listActionNames()` (spawns `shortcuts list`) when the prefix matched —
  keeps the subprocess off the stop→paste critical path for plain dictation.
- `DictationController` passes `voiceActionsExecutor: ShortcutsCLIExecutor()`.
  **`CommandModeService` is left nil in production** (needs the App-layer AX
  `SelectionAccessing` conformer, still `[deferred — human verification]`), so the
  `.command` route degrades to dictation; the `.action` (Shortcuts) route is the
  real live path.
- History: an executed action DOES write a history entry (rawText = utterance,
  cleanedText nil, latency 0) — falls out of `settleVoiceActionExecuted` returning
  non-empty rawText; consistent with the `latency==0 ≡ no-measurement` sentinel.
- Tests: `VoiceActionsPipelineTests.swift` (colocated) drives a real
  `CaptureSession` with the same handler closure `newSession` builds.

`[unverified — dogfood H-4]`: headless `shortcuts run` behavior for
input-requesting shortcuts — the executor has a timeout watchdog as mitigation
but it has never been tested against a real such shortcut. `[deferred]` still:
live `.command` route (needs the AX selection conformer), and the 3B classifier
(spec line 22-25) that replaces the deterministic exact-catalog-match stand-in.

See also [[project-speechanalyzer-segment-semantics]] for the sibling
CaptureSession accumulation pattern this module deliberately does NOT touch.
