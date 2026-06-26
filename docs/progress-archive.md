# `speak` — Progress Archive

> Sessions #1–#25 and all old handoff banners, archived from `progress.md` on
> 2026-06-26 to keep the live file fast for cold-start agents.
> See `progress.md` for current state and sessions #26+.

---

## Archived handoff banners (Wave 0 → Phase 2)

> ## OLD BANNER (handoff banner — 2026-06-22, Wave 0 live-bug cleanup — MERGED)
> **Two live bugs fixed + integrated to master. ALL 4 GATES GREEN on combined master.**
> Per `specs/acceleration-roadmap.md` Wave 0. The core loop works live (owner dictated this session).
>
> **0.1 — HUD "Cleaning up…" hang FIXED** (`SpeakCore/Engine/CaptureSession.swift`):
>   - Root cause: `runCleanup()` called `cleaner.clean()` (Foundation Models `respond()`) with no
>     timeout; if FM hangs, the `await` never returns → `endDictation()` blocked → overlay stuck in
>     `.processing` forever. Secondary: a thrown cleanup error surfaced an un-dismissable error HUD.
>   - Fix: `runCleanup()` is now `async` (never throws). `clean()` is raced against `T_cleanup = 10 s`
>     (unstructured `Task` + `CheckedContinuation`, double-resume guarded by `OSAllocatedUnfairLock<Bool>`).
>     ALL outcomes — off / unavailable / timeout / throw — fall back to raw transcript → session reaches
>     `.done` → overlay always hides. `T_cleanup = 10 s` (4× architecture p95 budget) added to `benchmark.md §7`.
>   - +4 tests in `CaptureSessionTests.swift` (throw→raw, generic-error→raw, hang→timeout→raw, slow-but-valid→cleaned).
>
> **0.2 — Input Monitoring REMOVED** → onboarding asks **Microphone + Accessibility only** (matches VoiceInk/Wispr):
>   - Why: the CGEventTap is `.defaultTap` → gated on Accessibility alone; IM was vestigial scaffolding from
>     an earlier listen-only-tap design, and the onboarding step *falsely* claimed IM was needed for the hotkey.
>     Empirically confirmed: the hotkey fires with IM NOT granted on the live machine. The tap itself was NOT touched.
>   - New step order: **welcome → microphone → accessibility → hotkey → done** (4 steps, was 5).
>   - Removed across 15 files: `PermissionKind.inputMonitoring`, `requestInputMonitoring()`, `IOHIDCheckAccess`/
>     `IOHIDRequestAccess`/`import IOKit.hid`, `SpeakError.inputMonitoringDenied`, the onboarding step + false copy,
>     the debug route, and all IM tests (`IOKit.hid` dropped from the moat allowlist).
>   - **Docs re-grounded by orchestrator (this commit):** `AGENTS.md §2.2`, `.claude/skills/swift-code-review.md`,
>     `docs/architecture.md`, `docs/product.md §7.3`, `specs/verification-ledger.md` — all updated to "Mic + Accessibility only".

> ## OLD BANNER (handoff banner — 2026-06-22, secure-field paste guard)
> **SECURE-FIELD PASTE GUARD — BUILT & ALL 4 GATES GREEN.**
> Build ✅ · Tests ✅ (374 tests / 5 XCTSkip / 0 failures; +4 new secure-field guard tests) · Lint ✅ (0 serious) · Moat ✅ (7/7).
> Problem: paste into password fields. Fix: `SecureFieldDetector` + `PasteboardWriter` gate (step 3); AX subrole check; fail-safe always pastes on ambiguous result. UX: routes to Scratchpad + HUD error. +4 tests.

> ## OLD BANNER (handoff banner — 2026-06-22, P0 correctness fix: long-dictation truncation)
> **P0 TRUNCATION BUG FIX — BUILT & ALL 4 GATES GREEN.**
> Bug: Long dictation pasted only the last few words. Root cause: `CaptureSession.ingest()` did `latestChunk = chunk` (replace) on every chunk. Fix: `finalizedText` accumulator, `stop()` uses it when non-empty. +2 regression tests.

> ## OLD BANNER (2026-06-21, W2.1+W2.2 HUD rebuild)
> **W2.1 + W2.2 — ACTIVE-DICTATION HUD → native-Apple quality — BUILT & ALL 4 GATES GREEN.**
> W2.1: live mic level via RMS on AVAudioEngine buffers → `AsyncStream<Double>`. W2.2: 15-bar `WaveformView`, Monaco font, `.error` red-pill, "Cleaning up…"/"Pasting…" copy, Reduce-Motion aware, VoiceOver announcements, Escape-to-cancel. +7 tests.

> ## OLD BANNER (2026-06-21, Phase 2 build)
> **PHASE 2 (full-product dashboard) — EVERY FEATURE BUILT & GREEN.**
> Build ✅ · 268 tests / 5 XCTSkip / 0 failures · lint 0 serious · moat 7/7. Committed `76d4716`.
>
> Shipped: Monaco theme + KeyCapView + dashboard spine (WaveA.0/A.1) · Style modes (WaveB.1) · InsightsStats + Home recents (WaveA.2) · direction correction from real Wispr screenshot (WaveA.3) · Snippets + Dictionary (WaveB.2+B.3) · duration persist for WPM (#18) · menubar Style+Language submenus (WaveD partial) · Paste Last Transcript Cmd+Ctrl+V · HUD live duration counter · Command Mode end-to-end (CommandModeService, AccessibilitySelection, CommandChordDetector, Fn+Ctrl wiring) · Scratchpad paste-failure fallback · all 8 panes render-verified crash-free.
>
> VISUALLY VERIFIED: full Mac app with app menu, 8-item sidebar, greeting+`fn` keycap, TODAY/YESTERDAY feed, stats rail — matches real Wispr Home in Monaco.
>
> Wave D COMPLETE: menubar Style/Language submenus · Paste Last Transcript · HUD live duration counter · Command Mode full end-to-end · Scratchpad paste-failure fallback.

---

## Done (2026-06-21, loop run #25 — LIVE base verified + full-product acceleration plan)

**Milestone: the v0 base WORKS LIVE.** The user ran `make dev-cert` + `make run`,
granted permissions, and **dictated their development instructions into Claude Code
*using speak itself*** — a recursive feedback loop. Confirmed live (recorded in
`human-verification.md` "LIVE RUN #1", `c9392bd`): double-tap Fn start / single-tap
stop, overlay over other apps, partials streaming live, paste at cursor **into a
terminal surface with no macOS 26.4 paste-prompt**, raw-fallback with Apple
Intelligence off. The user is happy with the base and **pivoted the mission from
"finish v0" to "build the full product, fast."**

**Produced the full-product execution contract — `specs/acceleration-plan.md`
(`bb17491`, then `e60a665`).** Synthesized from **3 parallel scouts**: `scout-architecture`
(seam audit), `scout-product` (full roadmap), `scout-competitors` (Wispr + rivals).
Four locked user decisions: base-hardening-first · local-first + pluggable-later ·
**full-window dashboard** · **Monaco** typographic theme.

---

## Done (2026-06-21, loop run #24 — HotkeyMonitor split + human-gate 3-bucket map)

`HotkeyMonitor.swift` split 775→527 (`3ea2804`). Extracted: `HotkeyBinding.swift`,
`HotkeyDetection.swift`, `BindingStore.swift`. Gates clean. `human-verification.md`
per-row 3-bucket classification (`94e5163`): `[B-render ✓]` / `[B-config → #6]` / `[C-live]`.
Decision: `DictationController` decomposition DEFERRED (non-v0-gating, not in pain).

---

## Done (2026-06-21, loop run #23 — live Xcode-MCP autonomy + History/overlay previews)

Xcode MCP bridge live verification oracle encoded in `agent-tooling.md §3.1`. Drove
`RenderPreview` to agent-verify static appearance of Onboarding + Settings. HistoryView
List crash diagnosed + fixed (preview-only XOJIT defect; production renders correctly —
verified via `--debug-open history` + `screencapture`). 4 static overlay `#Previews` added.

---

## Done (2026-06-21, loop run #22 — P11 release scaffolding + QA ship-gate audit)

P11 release pipeline scaffolded (`d790b72`): full Developer ID pipeline, `scripts/export-options.plist`,
`dist/speak.cask.rb`, `docs/release.md`. CI: concurrency cancel-in-progress + `verify-moat` pre-build.
QA ship-gate audit confirmed: ZERO bucket-(b) unimplemented code paths. Only genuine remaining gaps:
P11 (now scaffolded) and the §6 WER corpus (needs ~20 real-speech clips, human-supplied).

---

## Done (2026-06-21, loop run #21 — Phase D: robust paste)

Phase D of `specs/dictation-flow.md`: clipboard floor unconditional, AX-trust gate, settle delay (100ms),
explicit 4-event Cmd chord, `SpeakError.pasteRequiresAccessibility`, `SecureFieldDetector`. `DictationController`
routes `.pasteRequiresAccessibility` to Scratchpad. 3 new tests. Gates: build + 169 tests + lint + moat 7/7.

---

## Done (2026-06-21, loop run #20 — Phase C: recording HUD visual states + level meter)

`OverlayState` enum, bottom-center positioning, 3 HUD states (listening/processing/done), level meter placeholder
(breathing animation; real feed deferred), `LevelMath.swift` pure functions, `endDictation()` hide-timing fixed,
debug targets extended. 13 unit tests. Gates: 163 tests 0 failures, moat 7/7.

---

## Done (2026-06-21, loop run #19 — Phase B: push-to-talk + trigger mode UI)

`HotkeyBinding.Trigger` cleaned (removed `.singleTapToggle`; String `rawValue`), `holdEdge()` pure function,
`HotkeyMonitor.handle()` dual-mode dispatch, `SettingsStore.triggerMode`, `SettingsView` Activation section,
`DictationController` live trigger-mode wiring (Combine subscription). Tests: `HoldEdgeTests` (5) + Codable tests.
Gates: 175 tests (153 XCTest + 22 Swift Testing), 0 failures, moat 7/7.

---

## Done (2026-06-21, loop run #18 — Phase A: hotkey re-arm + lifecycle fixes)

Non-blocking `HotkeyMonitor.init` (semaphore removed), re-arm watchdog (CFRunLoopTimer, 100ms poll),
`start()` safely re-callable, gate on Accessibility only, IM non-blocking in onboarding, `DictationController`
re-arm wiring, tap-disabled watchdog + `TapRestartRateLimiter`, single-instance guard, `CoreFoundation`
added to moat allowlist. `PhaseARearmTests.swift` (17 tests). Gates: 167 tests, 0 failures, moat 7/7.

---

## Done (2026-06-21, loop run #17 — agent-drivable visual verification)

`#if DEBUG` verification surface (`DebugLaunchDispatcher`, `FixtureAudioProducer`) with 10 targets.
`scripts/verify-visual.sh` harness. All 9 window targets RENDERED ✓ (orchestrator Read every PNG).
Onboarding permission-grant fix: `requestAccessibility()` / `requestInputMonitoring()` now register the app.
CLAUDE.md Commands section de-staled.

---

## Done (2026-06-21, loop run #16 — History window + hardware mute)

History window UI: `HistoryViewModel`, `HistoryView`, `HistoryWindowController` (NSWindow + NSHostingView),
"History…" menu item. Hardware mute: `SpeakEngine.muted` actor flag, `beginDictation()` guard, also cancels
in-flight sessions, `SpeakError.microphoneMuted`, `DictationController.toggleMute()`, mute menu item.
`SpeakEngineMuteTests` (7 XCTest). Gates: 150 tests, 5 XCTSkip, 0 failures, moat 7/7.

---

## Done (2026-06-21, loop run #15 — P12 public docs)

README.md (rewrite), CONTRIBUTING.md (new), CHANGELOG.md (new), `human-verification.md` §5 (demo GIF deferred).

---

## Done (2026-06-21, loop run #14 — P7 Permissions Onboarding)

`OnboardingStateMachine` (pure, headless), `OnboardingViewModel` (@MainActor ObservableObject), `OnboardingView`
(SwiftUI flow), `OnboardingWindowController` (NSWindow), `PermissionManager` IM via `IOHIDCheckAccess`,
`SettingsStore.hasCompletedOnboarding`, `DictationController` wiring. 14 Swift Testing tests. Gates: 143 tests, moat 7/7.

---

## Done (2026-06-21, loop run #13 — P4 overlay + P8 finish)

`TranscriptOverlayPanel` (NSPanel, `.nonactivatingPanel`, joins all spaces), `OverlayTextAccumulator` (11 unit tests),
`DictationController` drains `engine.currentPartials()`. `icon = .processing` wired to menubar. Gates: 123 tests, moat 7/7.

---

## Done (2026-06-21, loop run #12 — P10 Settings, UI build authorized)

`SettingsStore` (typed UserDefaults wrapper, injectable defaults), `EngineFactories` (factory pattern for transcriber/cleaner),
`SpeakEngine` now takes `settings`, `newSession()` gates cleaner by `cleanupEnabled` at call time. Settings window wired.
`SettingsStoreTests`. Gates: 112 tests, 5 XCTSkip, 0 failures, moat 7/7.

---

## Done (2026-06-21, loop run #11 — autonomous BEAT-row verification)

`MoatAuditTests.swift` (9 tests — MIT license, no third-party imports, no network egress, no account/auth, no paywall,
offline-by-construction, no pasteboard-read, no print, no force-unwrap). `scripts/verify-moat.sh` + `make verify-moat`.
`LatencyAndAccuracyTests.swift` (10 tests — first-partial p50=42ms, local-pipeline p95=63ms, WER harness).
Gates: 88 tests, 5 XCTSkip, 0 failures, moat 7/7.

---

## Done (2026-06-21, loop run #10 — app-shell wiring, END-TO-END)

`DictationController` (@MainActor ObservableObject) builds production `SpeakEngine`, owns `HotkeyMonitor`,
consumes `monitor.events`, publishes `MenubarIcon` state. `MenubarIcon.swift` (pure enum, 6 tests).
`make run` exercises full flow (live-gated). Gates: 68 tests, 0 failures.

---

## Done (2026-06-21, loop run #9 — SpeakEngine facade + integration)

`SpeakEngine` actor (assembles transcriber + cleaner + inserter + history, verbs begin/end/cancel, actor-isolated).
`SpeakEngineIntegrationTests` (first real-components end-to-end: AppleSpeechTranscriber → CaptureSession →
FoundationModelsCleaner → HistoryStore → mock inserter; asserts `.done`, raw text, nil cleaned, inserter received,
exactly 1 history entry). Gates: 62 tests, 0 failures.

---

## Done (2026-06-21, loop run #8 — P9 HistoryStore)

`HistoryEntry`, `HistoryStoring` protocol, `HistoryStore` actor (raw SQLite3 C API, no third-party deps,
capacity trim, `SQLITE_TRANSIENT` shim). `HistoryStoreTests` (11 tests — persistence, newest-first, search,
clear, export JSON, capacity trim, nil/non-nil cleanedText). Gates: 61 tests, 5 XCTSkip, 0 failures, moat 7/7.

---

## Done (2026-06-20, loop run #7 — P6 PasteboardWriter)

`TextInserting` protocol, `PasteboardWriter` (NSPasteboard write-only + CGEvent 4-event Cmd chord),
`CaptureSession(inserter:)` wiring. SDK verifications: `CGEvent.post(tap:.cghidEventTap)` [verified],
`kVK_ANSI_V=9` [verified]. `PasteTests` (6 tests). Gates: 50 tests, 5 XCTSkip, 0 failures, moat 7/7.

---

## Done (2026-06-20, loop run #6 — P5 HotkeyMonitor)

`HotkeyMonitor` (CGEventTap, `.flagsChanged` only, `DoubleTapDetector`, `BindingStoring`, CFRunLoop thread,
Unmanaged userInfo, no global state). SDK verifications: `CGEvent.tapCreate` [verified], `maskSecondaryFn`
rawValue=8388608 [verified], `kVK_Function=63` [verified runtime]. `HotkeyMonitorTests` (19 tests).
Gates: 44 tests, 5 XCTSkip, 0 failures.

---

## Done (2026-06-20, loop run #5 — P3.5 CaptureSession)

`CaptureSession` actor (state machine idle→listening→processing→done/error, STT lifecycle, cleanup wiring,
partials stream, stream-failure path). `CaptureSessionTests` (13 tests). Gates: 25 tests, 5 XCTSkip, 0 failures.

---

## Done (2026-06-20, loop run #4 — P3 SpeechAnalyzer STT)

`AppleSpeechTranscriber` backed by Apple `SpeechAnalyzer` (macOS 26+). `AudioBufferProducing` protocol injected.
`AVAudioConverter` format bridge (Float32 non-interleaved → Int16 interleaved). `AssetInventory` + `provisionAsset`.
`SpeechTranscriberTests` (4 tests — real transcription from fixture: "Testing one two three" → `'cased in one, two, three.'`).

---

## Done (2026-06-20, loop run #3 — Phase 0 complete)

Human installed Xcode 26.5. **XcodeGen** generates canonical `.xcodeproj` from `project.yml` (build-time-only tool,
preserves runtime moat). Three §5 targets: `Speak.app`, `SpeakCore.framework`, `SpeakTests`. Phase 0 + Phase 1 complete
(menubar launched + verified). Retired SwiftPM/Smoke scaffolding.

---

## Done (2026-06-20, loop run #2 — git init + core types)

`git init` + first commit (`e3f9b63`). MIT LICENSE, `.gitignore`, `.swift-version`. CLT SDK probe: `swiftc -typecheck`
passes for Speech/FoundationModels/AVFoundation/SQLite3. SwiftPM-now vs Xcode decision surfaced to human (Open Q#5).

---

## Done (2026-06-20 — harness + verification + spec track)

- Built 8 skills + 7-agent team. Wired `.mcp.json` (apple-docs ✔, xcode bridge). SDK-grounded all skills
  via `swiftc -typecheck`. Two API bugs caught: `LanguageModel.default` → `SystemLanguageModel.default`.
- Verified load-bearing claims; created `benchmark.md` + `verification-ledger.md`; rewrote `product.md`.
- Elevated AI cleanup to v0 core. Stripped all schedule-time from docs.
- Authored `SPEC.md`; adversarial review found 6 blocking defects; all 6 fixed and re-validated to 0.

---

## Archived decisions

| Decision | Rationale |
|---|---|
| XcodeGen generates canonical `.xcodeproj` | Agent can't drive Xcode GUI; build-time-only preserves moat |
| AI neat-writing is v0 core, default = on-device Foundation Models | Product identity = speech→neat text; FM is Apple framework (no dep violation) |
| No deadlines / no time anywhere — unbounded loop | Agent-driven; "done" = testable criteria only |
| v0 = complete core, not MVP; full v0–v3+ ladder defined up front | v1–v3 additive architecture from day one |
| Structural moat: local+free+open+offline+no-account | Wispr can't copy without abandoning cloud revenue |
| `benchmark.md` is the definition of done + loop objective | "As good as Wispr" must be testable, not a vibe |
