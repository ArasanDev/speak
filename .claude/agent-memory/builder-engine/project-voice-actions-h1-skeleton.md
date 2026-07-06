---
name: voice-actions-h1-skeleton
description: H-1 Voice Actions intent-router (specs/horizon-voice-os.md Pillar 1) built as a standalone SpeakCore/VoiceActions/ module — NOT wired into CaptureSession/SpeakEngine/DictationController yet.
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

**How to apply:** the module is deliberately NOT wired into the live dictation
pipeline — `CaptureSession`/`SpeakEngine`/`DictationController` are untouched,
so existing dictation behavior is byte-identical even with the feature merged.
Whoever picks up H-2/H-3/H-4 (or wires H-1 live) needs to: (1) call
`VoiceActionsCoordinator.handle(transcript:knownActionNames:)` somewhere after
a final transcript (likely `SpeakEngine.newSession()` or `DictationController`,
following the same "read settings once per session" pattern as
`activeVoiceCommandPreprocessor` in `SpeakEngine.swift`), (2) supply a live
`CommandModeService` (needs the App-layer `AccessibilitySelection` AX
conformer, already `[deferred — human verification]` for
`CommandModeController`), (3) decide where `ShortcutsCLIExecutor.listActionNames()`
gets called from (it's async/Process-backed — probably cached per-session, not
per-transcript, to avoid a `shortcuts list` subprocess on every dictation).
`[unverified — dogfood H-4]`: headless `shortcuts run` behavior for
input-requesting shortcuts — the executor has a timeout watchdog as mitigation
but it has never been tested against a real such shortcut.

See also [[project-speechanalyzer-segment-semantics]] for the sibling
CaptureSession accumulation pattern this module deliberately does NOT touch.
