> Living state file. Agents: rewrite the "current" section at end of each loop. Do not delete history — append.
> Archive location: `docs/progress-archive.md`.

# `speak` — Progress (NOW)

---

## Current phase

**Loop #42 (2026-07-06) — Horizon "Voice Layer" direction opened + 5 features landed in one orchestrated fan-out (6 parallel worktree agents). Gates on master `41d92c9`: build ✅ / test 652 XCTest + 127 Swift Testing, 0-fail, 9-skip ✅ / lint 0-serious ✅ / verify-moat 7/7 ✅.**

### What changed this loop (read before doing anything)
-16. **H-1 — Voice Actions intent-router skeleton (`specs/horizon-voice-os.md` Pillar 1). UNCOMMITTED, in worktree `.claude/worktrees/agent-a7d238ba9579f6761` — pending orchestrator review/merge.**
   - New `Speak/SpeakCore/VoiceActions/` module: `ActionRouting.swift` (`VoiceRoute` enum + `ActionRouting` protocol + `PrefixActionRouter` — pure, deterministic prefix-gate classifier, no LLM in this slice per the CS-2 "gate first" finding), `ActionExecuting.swift` (protocol + `ActionExecutionResult`), `ShortcutsCLIExecutor.swift` (`Process`-backed `/usr/bin/shortcuts list`/`run` conformer, concurrent pipe-drain to avoid the classic `Process` deadlock, timeout watchdog for input-requesting shortcuts), `VoiceActionsCoordinator.swift` (ties router+executor+existing `CommandModeService` together — every non-success path degrades to `.degradedToDictation` carrying the ORIGINAL transcript, never silently drops words, including `CommandModeOutcome.noSelection`/`.modelUnavailable`).
   - `SettingsStore`: `voiceActionsEnabled` (default **false**) + `voiceActionsPrefix` (default `"hey speak"`) — master toggle gates the whole feature; existing users see zero behavior change.
   - **[decision H-1]** command-vs-action split (no 3B classifier in this slice): exact case-insensitive match against the caller-supplied action catalog → `.action` (canonical catalog casing, not spoken casing — `shortcuts run` may be case-sensitive); anything else under the prefix → `.command`. This is a deterministic stand-in for the eventual 3B pass (spec line 22-25), not semantic understanding — `[deferred]` until CS-2's revisit trigger (stronger on-device model) makes real classification worthwhile.
   - **Scope deliberately NOT done**: wiring into the live pipeline (`CaptureSession`/`SpeakEngine`/`DictationController`) — this is the H-1 *skeleton* per spec Sequencing #1 ("no new perms"); dictation stays byte-identical. Live command execution needs the App-layer AX `SelectionAccessing` conformer, already `[deferred — human verification]` for `CommandModeController`. `[unverified — dogfood H-4]`: headless `shortcuts run` behavior for input-requesting shortcuts (the executor's timeout watchdog is the mitigation, untested against a real such shortcut).
   - New tests: `VoiceActionsRoutingTests` (14 tests incl. a full decision-table test), `VoiceActionsCoordinatorTests` (10 tests, focused on the never-lose-words contract), `ShortcutsCLIExecutorTests` (7 tests against a deterministic fixture shell script — no dependency on real Shortcuts app state), `SettingsStoreTests` (+4). All net-new; zero existing tests modified beyond additive tail insertions.
   - Gates (this worktree): build ✅ / `make test` 804 passed, 0 failed, 9 skipped (pre-existing) ✅ / `make lint` 0 serious, 0 new warnings in touched files ✅ / `make verify-moat` 7/7 ✅. Caught and fixed one real force-unwrap (`errText!`) via the moat's `testNoForceUnwrapInProductionCode` heuristic scanner before this was reported done.
-15. **Loop #42 (2026-07-06) — Fable-orchestrated parallel build: horizon spec + V01-2/V01-3/V01-5 + Aurora HUD + H-3 MCP bridge.**
   - **`d8b28d3`/`23231c2`/`ecd0a54` [horizon] `specs/horizon-voice-os.md`** — the direction spec: dictation is the wedge, the product is the Mac's voice layer. Three pillars: (1) Voice Actions (intent router → `shortcuts` CLI action surface — direct cross-app App Intents invocation has NO public API `[verified]`), (2) VoiceOut conversational loop (AVSpeechSynthesizer, Personal Voice — feasible-as-specced `[verified]`), (3) MCP Agent Bridge (`speak_say`/`speak_ask`/`speak_confirm`/`speak_status` — any MCP agent gets ears + a voice, 100% local). All three validated by a docs/SDK-typecheck validator agent before building.
   - **`1a030d0` [V01-3] per-app context, profile-native** — new `Chat` profile (Slack/Discord/Messages/WhatsApp/Telegram → casual), `Write` trimmed to Mail+browsers; `perAppContextEnabled` toggle gates the frontmost-bundle read in `SpeakEngine.newSession` (off ⇒ exact no-context baseline). Agent correctly escalated that the literal brief (standalone AppContext detector) would duplicate the Profile Engine; direction call: profile-native.
   - **`ad8e760` [V01-5] multiple hotkey bindings** — `ExtraBinding`/`ExtraBindingSet` (max 4/action, mouse buttons 4–10, duplicate-source validation), `HotkeyMonitor.updateExtraBindings` rebuilds tap mask only when mouse-binding presence flips, live-apply via `withObservationTracking`, Settings editor (`ExtraBindingsSection`). `[deferred — human]`: live otherMouseDown delivery with AX-only.
   - **`6fe5dec` [H-UI] Aurora HUD** — opt-in `HUDStyle.aurora` (default `.classic`, zero regression): ambient orb (Canvas+TimelineView, 60fps, breathes with level), materializing word ticker, state color language, Reduce Motion honored. Integration decision: kept `FirstMouseHostingView` (agent's `NSHostingView` would have regressed PE-3 chip first-click). `[deferred — visual]`: live style swap, capsule proportions, processing hue-drift taste check.
   - **`cd08c96` [V01-2] OpenAI-compatible cleanup engine** — new **`SpeakLLM` framework target** holds `OpenAICompatibleClient` (URLSession) + `LLMKeychainStore` (Keychain) so the moat greps over SpeakCore/App/CLI stay symbol-clean — structural guarantee preserved, not exempted. Presets: Ollama (loopback-only, no key), Sarvam/OpenAI/Groq/OpenRouter (opt-in, Keychain key required). `OllamaCleaner` stub deleted. Follow-up open: `CleanupEngineSheet` key-entry UI (no way to enter API key in-app yet).
   - **`ba791c1`/`41d92c9` [H-3] MCP agent bridge vertical slice** — `SpeakCore/AgentBridge/` (JSONValue, JSON-RPC 2.0 codec, MCP types w/ version negotiation, 4-tool catalog, dispatcher actor, `BridgeBackend` seam) + `speak-mcp` stdio shim (`Speak/MCP/`, `SpeakMCP` target). Protocol 2025-11-25, negotiates down to 2025-06-18 (Claude Code). **Live e2e verified**: initialize → initialized → tools/list → tools/call speak_status (real CFMessagePort IPC) → EOF exit. `speak_say`/`speak_ask`/`speak_confirm` declared but tool-error until VoiceOut + app transport land.
   - **Integration notes (orchestrator)**: 3 of 6 worktrees forked pre-`Speak/` reorg — ported via path-rewritten `git apply -3`; conflicts resolved in SettingsStore (3×), OverlayController, TranscriptOverlayPanel, project.yml, .swiftlint.yml. Split `HUDStyleSection.swift` + `AboutSettingsTab.swift` out of SettingsView and moved two DictationController funcs to extensions to hold lint caps.
   - **In flight**: H-2 VoiceOut readback (`SpeechSynthesizing` + overlay read-back button) — agent finishing; wire `speak_say` to it when landed.
-14. **Loop #41 (2026-07-06) — Constraint-split exploration: CS-1 rejected, CS-2 architecture validated + parked (`82bb24c`).** Fable-driven (diverge→converge, 3 passes) next-iteration design for the coding-agent input path: surface spoken hedges ("don't touch the tests") as a trailing `Constraints:` block. Measured **live** against the on-device 3B (Apple Intelligence is enabled now — the "gated off" note was stale):
   - **CS-1** (single-prompt `PromptBuilder` fragment on `.task`/`.fix`): over-triggers, 97.39%→85.71%. **Reverted.**
   - **CS-2** (two-pass inside `FoundationModelsCleaner`: deterministic prohibition pre-gate → one-job extraction session → Swift-formatted block): over-trigger **solved**, Pareto-safe on recall (cleanup body untouched → original 17 fixtures non-regress), latency unchanged. Blocked only by **3B extraction fidelity** (~50% recall, unstable, one fabrication). **Parked** (user decision) — wiring reverted; validated design + eval acceptance gate preserved in `specs/constraint-split-cs1-finding.md`. Revisit via WWDC26 provider API (V1-13).
   - Baseline protected: `make test` 603,9-skip,0-fail ✅ / `make verify-moat` 7/7 ✅. Live eval Agent baseline re-confirmed at 97.39% (one pre-existing `ask` fixture fails — separate, unrelated).

-13. **Loop #40 (2026-07-04) — 9 commits, no open branches besides `eval/rubric-scorer` (stale, unmerged content already superseded on master).**
   - **`8142bde` [repo] Reorganize source under `Speak/`**: `App/`, `SpeakCore/`, `CLI/`, `Tests/` moved under a single `Speak/` root (pure rename, no logic changes); `project.yml`/Makefile/`.swiftlint.yml` updated to match. Any doc or script referencing old top-level `App/`, `SpeakCore/`, `CLI/`, `Tests/` paths is now stale — update to `Speak/App/…` etc.
   - **`7d84fd1` [fix] PrivacyPaneView**: replaced fake hardcoded "Verify Moat" results in the UI with a real, honest audit (wired to `MoatAuditor`).
   - **`205fc9f`–`22c1364` [UI/UX/fix] Coding-customization panel**: split out of the base overlay into its own non-activating panel (`CodingCustomizationPanel` + `CodingCustomizationView`); fixed `canBecomeKey` so its prompt `TextEditor` accepts input; text box is now primary with presets/prompt deferred behind a disclosure; Escape degrades gracefully (closes coding panel first, then stops dictation); fixed an orphaned `AppShell` Window scene that caused a blank window on launch; Settings pinned to the bottom of the sidebar, separate from the scrollable nav list.
   - **`c61f114`/`5444fdc` [merge] PE-2 — AI Studio settings tab**: few-shot examples editor landed on master (was "in flight" as of loop #39).
   - **`7168ac8`/`210b713` [merge] P11-a — install targets**: `make install` (copies `Speak.app` to `/Applications/`) + `make github-release` landed on master (was "in flight" as of loop #39).
   - **`56aacc7`/`157b63f` [merge] P12 — README + privacy section + onboarding lifecycle tests** landed.
   - **`e4eef32` [SM-2]** — cherry-picked imperative fix-fragment prompt tweak + live A/B eval harness (`FixABTests.swift`, `research/fix-fragment-ab-result.md`) from the abandoned `pe/sm-2-metric` branch.
   - **Roadmap correction**: `docs/roadmap.md` P2/P3 were still marked `[TODO]` despite `AudioCapture.swift`, `AppleSpeechTranscriber.swift`, `PermissionManager.swift` already existing and tested — checklist items reconciled this loop (see roadmap diff); code was ahead of the checklist, not the other way around.
   - Gates re-verified this loop: build ✅ / `make test` 597 tests, 6 skipped, 0 failures ✅ / `make verify-moat` 7/7 ✅.

-12. **PE-4 + P2.3 + re-clean button — ALL MERGED TO MASTER (`b1907d9`).**
   Three changes landed together after parallel agent dispatch + orchestrator conflict resolution:
   - **PE-4 — Overlay Tier 2/3 knobs + capture controls**: `perDictationFormat/Tone/Length` pickers in the selector card, cancel (xmark.circle) abandons dictation, re-clean (arrow.clockwise) re-runs cleanup on last raw transcript. `DictationController+Knobs.swift` + `KnobsTests.swift` (9 tests). Re-clean button wired in `.done` state overlay — nils itself on first tap to prevent double-fire.
   - **P2.3 — Dual raw stream (processing preview)**: `CaretOverlayController.showProcessing(rawText:)` keeps the caret overlay visible during the 0.3–1.5s cleanup window, showing raw transcript + ⟳ suffix. `lastRawTranscript` set on every partial update, cleared on `resolveActiveDestination`.
   - Gates: build ✅ / test 572,5-skip,0-fail ✅ / eval Agent 98.51% Note 100% Raw 100% Write 100% ✅ / verify-moat 7/7 ✅

-11. **P2.2 — Floating caret-anchored overlay (`3c513a7` master).** Non-activating NSPanel positioned 8pt below text cursor (AXUIElement), flips y-axis for AppKit coords, falls back silently when CaretLocator returns nil. P2.3 extends this with processing-state preview.

-10. **SM-2/SM-3/PE-3c-V/eval/rubric-scorer — ALL MERGED TO MASTER (`2a66632`).** Three agents ran in parallel:
   - **SM-2** — CC-lens Agent system prompt + 8 realistic developer voice fixtures. Agent eval 91% → 97.04%.
   - **SM-3** — Empty-output guard in `CaptureSession+Cleanup.swift` (was delivering `""` instead of raw fallback). 6 DegradeToRawTests all pass.
   - **PE-3c-V** — 10 LivePanelPromptShapingTests covering all 6 Agent categories.
   - **eval/rubric-scorer** — `RubricChecker` in `EvalScoring.swift`: noFiller, imperativeStart, endsWithQuestion, noMarkdown, conventionalCommitsFormat, preservesTerms:X, maxSentences:N. 8 realistic fixtures now use `checks[]` rubric instead of Jaccard.
   - Gates: build ✅ / test 0-fail ✅ / eval Agent 97.04% Note 100% Raw 100% Write 89.38%.
   - 4 stale spec files removed.

-9. **SM-2 (#12) — Agent-category prompt optimization (branch `pe/sm-2`, committed).** 17/18 fixtures PASS under deterministic eval (greedy decoding). One Write fixture score=0.79 is a confirmed metric artifact (Jaccard punctuation sensitivity). Key decisions: greedy decoding is correct for a cleanup transform [verified SDK 2026-06-30]; few-shot ordering matters — for categories with their own output format (commit, shell, code), suppress the Agent profile's task-form few-shot examples. Gates: build ✅ / test 548,5-skip,0-fail ✅ / lint ✅ / moat ✅.

-8. **Loop #39 cont. — PE-3c-1 live-panel card LANDED + UI-verified live.** Overlay-card model (HUD + destination pill + "Shape this dictation" card). Raw = AI-off passthrough for that dictation (`CaptureSession.forcedRaw` + `SpeakEngine.applyRawOverride`). Commit `4ea4129`; gates build✅/test 548,5-skip,0-fail✅. **User confirmed live: card embeds in overlay, opens/selects/closes.**

-7. **Loop #39 (2026-06-29) — PE-3 live panel: plumbing + click spike landed.** Category seam live end-to-end (`CleanupMode.profile` carries `category` → `FoundationModelsCleaner` → `PromptBuilder.instructions`).
   - **PE-3a `b6a8c57`** — `CaptureSession.overrideCleanupMode` + `SpeakEngine.applyProfileOverride`. Race-free: engine mode rebuilt ONCE at stop before `endDictation()`.
   - **PE-3b `5cd9840`** — `FirstMouseHostingView` (acceptsFirstMouse→true) so SwiftUI Button registers click in `.nonactivatingPanel` without focus-steal.

### Layering (immutable — never invert)
- **Base core:** double-press activate / single-press stop; raw voice → text ALWAYS available.
- **Default:** `Clean` profile (on-device neat-writing); AI off ⇒ raw passthrough.
- **Extension:** the Profile Engine (north star).

### Next actions (in order)
- **Reconcile roadmap checklists (mechanical, do first)** — P2/P3/P5/P6/P7 sub-checkboxes in `docs/roadmap.md` under-report actual test coverage; tick verified items, keep `[deferred — needs human verification]` tags for anything not exercised live.
- **P13 — Dogfood (critical path, not started)** — the one substantive TODO left on the critical path. Requires live human verification first:
  - macOS 26.4 Terminal paste-provenance prompt (project's #1 `[unverified]`) — test in Terminal/iTerm.
  - Hotkey false-trigger rate in real typing (Notes, 30 min sessions).
  - Live paste across TextEdit/Slack/Terminal.
  - Permission prompts + System Settings deep-links firing correctly live.
- **P11-b — signed/notarized `.dmg`** — blocked on a Developer ID cert (open question #4).
- **PE-3.1/#51, PE-3.2/#52** — Profile Engine voice-override + pin-to-context (post-v0 north star, not on critical path).

### Orchestration note
Models: **Opus** (judgment/design/review) + **fast worker** (Haiku/WSL2 MiniMax). Design is locked in specs; route mechanical multi-file implementation to the worker; orchestrator reviews diffs + owns commits.

---

## Open questions

| # | Question | Status |
|---|---|---|
| V1 | Did Phase 1A (`val-oss-compare`) and 1B (`val-skill-sdk`) agents complete? | Unknown — check progress notes or re-run |
| 3 | Does write+`Cmd+V` avoid the paste prompt incl. macOS 26.4 Terminal provenance check? | `[unverified]` — test in Terminal (human) |
| 4 | Developer ID signing cert for notarization? | Unverified — needed for P11 |
