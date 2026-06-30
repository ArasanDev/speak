> Living state file. Agents: rewrite the "current" section at end of each loop. Do not delete history — append.
> Archive location: `docs/progress-archive.md`.

# `speak` — Progress (NOW)

---

## Current phase

**Loop #39 (2026-06-30) — PE-4 + P2.3 + re-clean button all merged to master. PE-2 (AI Studio) + P11-a (install targets) agents in flight.**

### What changed this loop (read before doing anything)
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
- **PE-3.1 (#51)** — Voice override: spoken commands reshape the panel.
- **P2.1 (#35)** — CaretLocator (best-effort caret screen position) — parallel with PE-3.1.
- **PE-3.2 (#52)** — Pin-to-context: sticky destination/category per app (after PE-3.1).
- **P2.2 (#36) → P2.3 (#37)** — Floating caret-anchored overlay → dual raw stream.
- **PE-4 (#54)** — Overlay Tier 2/3 knobs + capture controls (after PE-3 complete).

### Orchestration note
Models: **Opus** (judgment/design/review) + **fast worker** (Haiku/WSL2 MiniMax). Design is locked in specs; route mechanical multi-file implementation to the worker; orchestrator reviews diffs + owns commits.

---

## Open questions

| # | Question | Status |
|---|---|---|
| V1 | Did Phase 1A (`val-oss-compare`) and 1B (`val-skill-sdk`) agents complete? | Unknown — check progress notes or re-run |
| 3 | Does write+`Cmd+V` avoid the paste prompt incl. macOS 26.4 Terminal provenance check? | `[unverified]` — test in Terminal (human) |
| 4 | Developer ID signing cert for notarization? | Unverified — needed for P11 |
