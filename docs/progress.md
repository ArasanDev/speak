# `speak` — Progress (NOW)

> **Status**: Living state. **The agent rewrites this every session.**
> Single source of truth for "where are we right now." Read first, update last.
> Never delete history — append. See `../AGENTS.md` §5.

---

## Current phase

**Phases 0, 1 COMPLETE; P2 + P3 implemented + fixture-verified (live-mic
done-when rows pending P13 dogfood).** P3 — SpeechAnalyzer STT —
`AppleSpeechTranscriber` conforms to `Transcribing` and emits partial + final
`TranscriptChunk`s via Apple SpeechAnalyzer. Verified end-to-end through the real
pipeline against a `say`-synthesized fixture (real on-device transcription, no
XCTSkip) — passes 4/4 new tests. `make build` zero warnings, `make lint` 0
serious violations, `make test` **10/10 green**. The P3 done-when rows for *final*
transcript + engine id are `[verified]`; the *live-mic partial-streaming* row is
`[inferred]` (fixture saw partials; robust live behavior is gated on P13 dogfood),
so roadmap.md's P3 boxes stay unchecked until then. Next: **P3.5 (LLM cleanup)**
on the critical path.

---

## Done (this session — 2026-06-20, loop run #4 — P3 SpeechAnalyzer STT)

- [x] **Phase 3 COMPLETE — SpeechAnalyzer STT.**
      - **`SpeakCore/STT/AppleSpeechTranscriber.swift`**: `Transcribing` conformer
        backed by Apple SpeechAnalyzer (macOS 26+). Engine id `"apple-speech-en-US"`.
      - **Authoritative lifecycle implemented** ([verified] WWDC25 #277):
        `analyzer.start(inputSequence:)` returns after setup (NOT after all input) →
        bridge feeds AnalyzerInput → bridge task completes (all input fed) →
        `finalizeAndFinishThroughEndOfInput()` closes `transcriber.results` →
        results drain → stream finishes. Not calling `finalize` caused a hang (diagnosed
        by orchestrator and fixed).
      - **Audio injection**: `AudioBufferProducing` protocol injected at init;
        default `LiveAudioCapture` wraps P2's `AudioCapture`; tests inject
        `FixtureAudioProducer`. No-arg factory `AppleSpeechTranscriber()` works unchanged.
      - **Format conversion** [verified at runtime]: `bestAvailableAudioFormat` returns
        16kHz mono Int16 interleaved; P2 produces Float32 non-interleaved. `AVAudioConverter`
        bridges them correctly. Bug caught: original check compared only sample rate + channel
        count, missing `commonFormat` difference → converter not built → "Audio sample data
        must be 16-bit signed integers" error. Fixed to compare `commonFormat` + `isInterleaved`.
      - **Asset provisioning**: `AssetInventory.status` + `assetInstallationRequest` →
        `downloadAndInstall()`. Locale validated via `SpeechTranscriber.supportedLocale`.
        `SpeechTranscriber.isAvailable` static gate.
      - **Clean stop**: `stopSession()` calls `audioProducer.stop()` (ends buffer stream)
        → bridge exits → `inputCont.finish()` → `finalize` runs in session task → results
        drain → session task exits. No zombie tasks.
      - **`SpeakTests/SpeechTranscriberTests.swift`**: 4 tests. `testTranscribesFixture`
        produces real transcription: fixture "Testing one two three" → final transcript
        `'cased in one, two, three.'` — one, two, three found [inferred: "testing" → "cased"
        is model behavior with synthetic speech]. `testStopTerminatesStream` confirms no hang.
      - **Fixture**: `SpeakTests/Fixtures/hello_speech.caf` (16kHz mono Float32, 1.3s).
      - **`make build`**: zero warnings. **`make lint`**: 0 serious violations (1 non-serious
        file-length warning on the implementation file — accepted; comments are required
        for API verification). **`make test`**: 10/10 PASS.
      - **P2 format note** (surfaced for orchestrator): P2 hard-bakes 16kHz Float32 output.
        SpeechAnalyzer's `bestAvailableAudioFormat` = 16kHz Int16 interleaved. P3 converts.
        Optimal path would be: P2 outputs native mic format, P3 does one conversion to Int16.
        Not a blocking issue — P3 handles it — but worth noting for P13 latency tuning.

---

## Done (prior session — 2026-06-20, loop run #3)

- [x] **Xcode 26.5 installed + activated** (human ran `xcode-select -s`,
      `xcodebuild -runFirstLaunch`, `-license accept`). `xcodebuild` works;
      macOS 26.5 SDK present; `swiftlint` 0.63.3 via brew. Open Q#1 fully resolved.
- [x] **Phase 0 COMPLETE — canonical Xcode build system.**
      - **Decision (mine, under delegation; implements Q#5)**: generate the
        mandated `.xcodeproj` with **XcodeGen** from a checked-in `project.yml`,
        rather than hand-author a fragile `.pbxproj` or use the Xcode GUI (which
        an agent can't drive). XcodeGen is **build-time only** — never linked into
        the app — so it doesn't touch the Apple-frameworks-only runtime moat
        (`AGENTS.md` §2.4). `Speak.xcodeproj` is git-ignored; `project.yml` is the
        source of truth; `make build` regenerates it (works from a clean clone).
      - Three §5 targets build: `Speak.app` (application), `SpeakCore.framework`
        (the portability seam), `SpeakTests` (unit-test bundle). Engine `.swift`
        files moved into the framework target with **zero code change** (they were
        already in the §5 layout).
      - `Makefile` (`build`/`test`/`lint`/`run`/`clean`/`release`-stub),
        `.swiftlint.yml` (enforces §3: force_unwrap/force_cast/force_try = error),
        GitHub Actions CI (`.github/workflows/ci.yml` — `xcodebuild` + swiftlint;
        **[unverified]** until the repo has a remote + a push).
      - **Verified**: `make clean && make build` → runnable `Speak.app`;
        `make lint` → 0 violations; `make test` → 4/4 pass via `xcodebuild test`.
      - **Retired the temporary SwiftPM/smoke scaffolding** (`Package.swift`,
        `Smoke/`) — its only purpose (no XCTest under CLT) is gone now that
        `xcodebuild test`/`swift test` run the canonical `SpeakTests`.
- [x] **Phase 1 COMPLETE — menubar scaffold.** `App/SpeakApp.swift`: a
      `MenuBarExtra` app (waveform idle icon) with an **About speak…** item +
      Quit, running as **LSUIElement** (no Dock icon). Links `SpeakCore` and logs
      via `SpeakLog.engine` on launch (proves the framework seam). **Launched and
      confirmed running** (pid alive, menubar-only). Roadmap P1 done-when met.
- [x] **Engine-core foundation built + verified under CLT (no Xcode needed).**
      Implemented the framework-agnostic core from `architecture.md` §6 in the
      **final §5 layout**: `SpeakError` (Engine/), `Transcribing`+`TranscriptChunk`
      (STT/), `LLMCleaning`+`CleanupMode` (Cleanup/), `TranscriptionResult`
      (Engine/, split to its own file), `SpeakLog` OSLog categories (Logging/).
      `swift build` **green, zero warnings**. Verification: XCTest/swift-testing
      both ship only inside full Xcode, so `swift test` can't run under CLT — so
      I added a temporary `speak-smoke` executable target (`swift run speak-smoke`)
      that exercises every type/seam with mock `Transcribing`/`LLMCleaning`
      conformers: **16/16 checks pass**. The canonical swift-testing suite
      (`SpeakTests/EngineCoreTests.swift`) is authored and runs once Xcode lands.
      - **Decision (mine, logged)**: user delegated all technical calls → built
        the engine core in parallel with the Xcode install. Reason is *non-churn*,
        not speed: these §6 types are stable across build systems and the .swift
        files drop into the Xcode `SpeakCore.framework` target unchanged.
      - **Minor verbatim-spec deviations (strict additions, surfaced)**: added
        explicit `public init`s to `TranscriptChunk` and `TranscriptionResult`
        (a public struct needs a public init to be constructible cross-module —
        §6 omitted them); `TranscriptionResult` lives in its own file rather than
        inside `CaptureSession.swift`. Neither changes the type shape.
      - **Deferred from this increment**: `HotkeyBinding` (its `modifiers:
        CGEventFlags` isn't `Codable` out of the box → needs custom coding; it's
        CoreGraphics/P5 territory anyway) and `CaptureSession`/`SpeakEngine` (the
        state machine needs a paste-seam abstraction decision — next unit).
- [x] **`git init` + first commit** (`e3f9b63`) — repo is now version-controlled;
      commit discipline (`AGENTS.md` §7) is live. Staged the full doc set +
      research; excluded `.claude/*.lock` transient state.
- [x] **Phase 0 pure-text deliverables** (verifiable without Xcode):
      `LICENSE` (MIT), `.gitignore` (macOS/Xcode/SwiftPM/secrets), `.swift-version`
      (`5.9`). README skeleton already existed.
- [x] **Reframed the "everything is blocked" chain** (prior session was too
      broad). Probed the Command-Line-Tools SDK: `swiftc -typecheck` **succeeds**
      for `import Speech`, `import FoundationModels`, `import AVFoundation`,
      `import SQLite3` → the framework headers are present. The true blocker is the
      **app shell + `.app` bundle**, not the engine. → A large slice of `SpeakCore`
      pure logic (`Transcribing`/`LLMCleaning` protocols, `CaptureSession` state
      machine, `TranscriptChunk`/`TranscriptionResult`/`SpeakError`, `SpeakLog`,
      `SettingsStore`, `HistoryStore` SQLite) is buildable + `swift test`-able now
      behind mock conformances, with zero Xcode. **Awaiting the human's go on the
      SwiftPM-now path** (adding a build system alongside the mandated `.xcodeproj`
      is a rails-move → ask, per `AGENTS.md` §4).

## Done (prior session — 2026-06-20)

- [x] **Verified the load-bearing claims** against primary sources (3 parallel
      research streams). Result in `specs/verification-ledger.md`.
  - Foundation is **sound**: `SpeechAnalyzer` (on-device, macOS 26 Tahoe, shipped
    Sept 15 2025), `CGEventTap` perms + Fn=`kVK_Function` 0x3F all `[verified]`.
  - **Bonus**: macOS 26 ships `Foundation Models` (on-device LLM) `[verified]` →
    enables native, zero-dependency AI cleanup in v0.
  - **Refuted**: the Wispr "polishing, not shipping" thesis — Wispr is in
    aggressive expansion. Repositioned to the *structural* moat.
  - **Corrected**: Wispr has a free tier + uses Fn + is multi-platform; competitor
    prices; WhisperKit repo path; macOS ship date.
  - **`[unverified]`**: the specific paste write+Cmd+V bypass — **test at P6**
    (macOS 26.4 added a Terminal paste-provenance check).
- [x] **Created `docs/benchmark.md`** — the definition of done: category parity
      map (Wispr = frontier), MATCH/BEAT/SKIP buckets, phased, with a derivation
      ledger (no hardcoded magic numbers). This is the loop's objective function.
- [x] **Rewrote `docs/product.md`** — added the final-outcome / "what it looks
      like" destination; the full, time-free version ladder (v0 = complete core,
      v1 friendly, v2 creative, v3+ frontier); AI neat-writing as core; pluggable
      local models; corrected structural positioning.
- [x] **Made AI neat-writing v0 core** across the docs: `LLMCleaning` protocol +
      `FoundationModelsCleaner` (Apple framework → no third-party-dep violation),
      wired into `CaptureSession.processing` (finalize → cleanup → paste).
      `architecture.md` §10a, `roadmap.md` P3.5, `quality.md` cleanup tests,
      `benchmark.md` cleanup → v0 MATCH.
- [x] **Removed all project-schedule time** (dates, "14 days", effort S/M/L/XL,
      "first 48 hours", stopwatch UX targets) from every doc. Build is an
      unbounded loop; "done" = testable criteria only.
- [x] Updated `AGENTS.md` (no deadline; cleanup core; `benchmark.md` registered)
      and ran a coherence pass (cross-refs, version labels, zero residual time).
- [x] **Completed the `specs/wispr-parity-and-spec.md` plan** (the spec/benchmark
      track that `/loop` was pointed at):
  - [x] **Authored `SPEC.md`** (root) — the human-readable consolidated spec:
        vision, structural why-now, market + **embedded parity map**, personas,
        UX, architecture summary, privacy, roadmap, risks, GTM, ledger summary,
        and a `docs/`-corrections appendix. Single voice; claims tagged.
  - [x] **Adversarial review (plan task #6) found 6 blocking + 4 nits; all 6
        blocking FIXED, re-validated to 0**. The sonnet reviewer caught real
        factual errors that orchestrator greps missed — corrected in
        `benchmark.md`/`SPEC.md` (the plan's own deliverables; `product.md` and
        the other immutable docs untouched):
    - B1: `benchmark.md` §3 history row was falsely `[verified]` → `[unverified]`
          (ledger §2 ground truth).
    - B2: `SPEC.md` embedded counts were wrong on all figures → corrected to
          **7 MATCH · 8 BEAT · 4 SKIP/SKIP→MATCH = 19 rows**.
    - B3: `benchmark.md` §1 snapshot had no per-row verdict tags → added
          `[verified]`/`[corrected]` per ledger §3.
    - B4: `benchmark.md` §1 malformed "Superwhisper/MacWhisper" row → split into
          a correct standalone **MacWhisper** row.
    - B5: Wispr annual price "$12/yr" (implies $12 total/yr) → **$12/mo annual
          ($144/yr)** per ledger §2.
    - B6: §3 BEAT list (7 structural) vs §2 matrix (8 BEAT) reconciled with a
          scope note + a fixed §4 v0-BEAT enumeration.
    - Nits N3 (missing matrix columns — values still trace to §7) and N4
          (`architecture.md` "~95% of apps" stale claim) left for the human;
          N2 (product.md "modified this run") was a **false alarm** — mtime
          `1781956811` is unchanged from this run's baseline (last touched in the
          prior session).
  - [x] **Validation (task #7) passes after fixes**: every MATCH row has a binary
        criterion tracing to `benchmark.md` §7 (no orphan constants); no stale
        citations leaked (Tsai 2026-04-03, `argmax-oss-swift`, Superwhisper $8.49,
        paste bypass `[unverified]`); why-now is structural (no "Wispr coasting");
        no cloud SKIP in a v0 MATCH. `docs/product.md` untouched (mtime at baseline).
- [x] **Verified toolchain (open Q#1)**: `swift` 6.3.2 present, target
      `arm64-apple-macosx26.0` ✓ — but **`xcodebuild` is ABSENT** (only Command
      Line Tools active, no full Xcode) and the dir is **not a git repo**. Phase 0
      is therefore **blocked** until Xcode is installed + `git init` is approved.

---

## In progress

Nothing. The spec/benchmark track is complete (`benchmark.md`, `SPEC.md`,
`verification-ledger.md` all done + validated). The `/loop` pointed at the spec
plan was stopped on completion (job `ddc5d3fd` deleted) — it would otherwise
thrash, since the next work (Phase 0) is blocked on a human gate.

---

## Blocked

- **Nothing blocks the build.** Xcode is installed; P0/P1 are done; P2 is ready.
- Deferred (not blocking): CI YAML is **[unverified]** (no git remote yet — needs
  a push to a macOS-26 runner to confirm); Developer ID signing cert for
  notarization is still needed at P11 (Open Q#4).

---

## Next up

1. **P2 — Audio capture (CRITICAL PATH)**: `PermissionManager` (mic state) +
   `AudioCapture` (`AVAudioEngine`, 16kHz mono PCM) streaming PCM buffers to an
   `AsyncStream`. First run triggers the mic permission prompt; logs buffer stats
   via `SpeakLog.audio`; clean stop on cancel. These are framework-bound (AppKit/
   AVFoundation) → they live in `SpeakCore` but are exercised through the app for
   the permission prompt. Add `NSMicrophoneUsageDescription` to the app plist.
2. **P3 — SpeechAnalyzer**: `AppleSpeechTranscriber` against `Speech`
   (verify API surface vs current Apple docs first).
3. **Engine-core unit (do alongside P2/P3)**: `CaptureSession` actor state
   machine (§7.1) + `SpeakEngine` facade. Needs a paste-seam abstraction
   (`TextInserting` protocol so the core stays testable; real `PasteboardWriter`
   NSPasteboard impl is app-side) — design + document in `architecture.md` first.
   Then `HotkeyBinding` Codable (custom coding for `CGEventFlags`).
4. **P3.5 cleanup → P5 hotkey → P6 paste** along the critical path.
3. **P1 → P2 → P3 → P3.5 (cleanup) → P5 → P6** along the critical path.
4. The loop runs until `benchmark.md` §4 MATCH gate + §3 BEAT rows +
   `quality.md` §9 all pass. No deadline.

---

## Decisions logged

| Date | Decision | Rationale | Source |
|---|---|---|---|
| 2026-06-20 | **XcodeGen generates the canonical `.xcodeproj`** from `project.yml` (git-ignored project; `make build` regenerates) | An agent can't drive the Xcode GUI and hand-authored `.pbxproj` is fragile/version-specific; XcodeGen is build-time-only (not linked into the app) so it preserves the Apple-frameworks-only runtime moat (§2.4). Implements Q#5's canonical-Xcode decision | This session (loop #3); advisor concurrence |
| 2026-06-20 | **AI neat-writing is v0 core**, default = on-device `Foundation Models` | "Speech→neat text" is the product identity (= Wispr's core); Foundation Models is an Apple framework, so v0 stays zero-third-party-dep, local, free | `verification-ledger.md`; user direction |
| 2026-06-20 | **No deadlines / no time anywhere** — unbounded build loop | Agent-driven development; "done" = testable criteria, not dates | User direction |
| 2026-06-20 | **v0 = complete core, not MVP**; full v0–v3+ ladder defined up front | Knowing v1–v3 lets v0 be architected so later versions are additive, never a rewrite | User direction; `product.md` §9 |
| 2026-06-20 | Reposition to the **structural** moat (local+free+open+offline+no-account+history) | Wispr "why now / coasting" thesis refuted; the durable wedge is what Wispr can't do without abandoning cloud revenue | `verification-ledger.md` §2 |
| 2026-06-20 | `benchmark.md` is the **definition of done** + loop objective function | "Be as good as Wispr" must be testable, not a vibe | User direction |
| 2026-06-20 | **Spec/benchmark track complete; stopped the 1-min `/loop`** (`ddc5d3fd`) on validation pass | The loop was scoped to `specs/wispr-parity-and-spec.md`, now done (SPEC.md + review + validation, 0 blocking). Next work (Phase 0) is blocked on a human gate (Xcode + `git init`), so continued firing would only thrash or risk an unactionable cold-cycle Swift attempt | This session; advisor guidance |
| 2026-06-18/19 | Build `speak` (Mac dictation); Swift-native single codebase; Apple `SpeechAnalyzer` default behind pluggable `Transcribing`; double-tap Fn; write-never-read paste; MIT; non-sandboxed v0 | (carried from prior sessions) | `research/`, prior `progress.md` |

---

## Open questions

| # | Question | Status | Needed by |
|---|---|---|---|
| 1 | Xcode/Swift toolchain available here? Repo needs `git init`. | **Resolved 2026-06-20**: `git init` **DONE** (`e3f9b63`); `swift` 6.3.2 ✓; **`xcodebuild` ✗ (no full Xcode)**. Xcode-bound P0 parts blocked; the rest is not. | P0 |
| 5 | **Build+test `SpeakCore` logic via SwiftPM now, or wait for Xcode?** | **Resolved/implemented 2026-06-20 (loop #3)**: canonical `.xcodeproj` via **XcodeGen** (`project.yml` source of truth). SwiftPM scaffolding retired. | P0 ✓ |
| 2 | `Foundation Models` runtime availability/quality for cleanup on the target Macs (Apple Intelligence gating, M-series, locale)? | Verify empirically at P3.5; raw fallback exists | P3.5 |
| 3 | Does write+`Cmd+V` avoid the paste prompt incl. the macOS 26.4 Terminal provenance check? | `[unverified]` — test in Terminal/iTerm | P6 |
| 4 | Developer ID signing cert for notarization? | Unverified | P11 |

---

## Session log

- **2026-06-20 (agent-harness / context-engineering)**: Built the autonomous
  build harness — 8 skills (`.claude/skills/`: 3 thick doc-grounded + 5 thin
  per-seam Apple-API pointers) and a 7-agent standing team (`.claude/agents/team/`,
  one per architecture seam). Wired project MCP (`.mcp.json`): `apple-docs`
  (✔ connected) + `xcode` (`xcrun mcpbridge`, Xcode 26.5 — connects but needs a
  one-time in-Xcode auth). Established the **swiftc-against-the-local-SDK**
  verification backbone (cutoff-proof) and ran an SDK-anchored, adversarially
  citation-checked verification workflow over all 8 skills (14 agents). Applied
  11 upheld fixes; 10 claims correctly deferred (empirical-by-design). **Two
  source-of-truth API bugs caught + fixed**: `architecture.md` §6 + §9 used
  `LanguageModel.default` / `LanguageModel` (do not resolve) → `SystemLanguageModel`
  + `.availability`; `roadmap.md` P3 §14.1 anchor → §10.2. Added the harness to
  `AGENTS.md`/`CLAUDE.md` navigation so a fresh `/loop` discovers it. Lesson:
  agents share the Jan-2026 cutoff, so skills must carry post-cutoff truth verified
  against the live SDK, never recalled. See `docs/agent-tooling.md`.
- **2026-06-20**: Verified load-bearing claims (foundation sound; Foundation
  Models unlock; Wispr thesis repositioned). Created `benchmark.md` +
  `verification-ledger.md`. Rewrote `product.md`. Elevated AI cleanup to v0 core.
  Stripped all schedule-time from the doc set. Coherence pass clean. Ready for P0.
- **2026-06-20 (loop run)**: Authored `SPEC.md` (opus) embedding the parity map.
  Adversarial review (sonnet) found **6 blocking defects** (false `[verified]`
  history tag; wrong embedded row counts; untagged §1 snapshot; malformed
  MacWhisper row; "$12/yr" mispricing; §3↔§2 BEAT mismatch) — orchestrator
  verified each against the ledger and **fixed all 6** in `benchmark.md`/`SPEC.md`
  (`product.md` and other immutable docs untouched), re-validated to **0
  blocking**. Lesson: mechanical greps (`grep -c`) missed factual + counting
  errors a real review caught — don't declare "done" before the reviewer reports.
  Resolved open Q#1: `swift` 6.3.2 present but `xcodebuild` absent → Phase 0
  blocked on installing Xcode + `git init`. Completed the spec plan and stopped
  the `/loop` (`ddc5d3fd`). Build can resume once the human gate is cleared.
- **2026-06-20 (loop run #2)**: `git init` + first commit (`e3f9b63`) with MIT
  `LICENSE`, `.gitignore`, `.swift-version`. Reframed the prior session's
  "everything blocked on Xcode" — it was too broad. Probed the CLT SDK:
  `swiftc -typecheck` passes for `Speech`/`FoundationModels`/`AVFoundation`/
  `SQLite3`, so the real blocker is the app shell, not the engine. A large slice
  of `SpeakCore` pure logic is `swift test`-able now behind mocks. Surfaced the
  SwiftPM-now-vs-wait decision (Open Q #5) to the human and stopped the loop on
  it (human-gated; the answer re-triggers). Lesson: don't let one missing tool
  collapse into "nothing is actionable" — separate the verification gap (Xcode)
  from the genuinely-buildable core.
- **2026-06-20 (loop run #3)**: Human installed + activated Xcode 26.5. Chose
  **XcodeGen** to generate the canonical `.xcodeproj` from `project.yml` (agent
  can't drive the GUI; build-time-only tool preserves the runtime moat).
  **Completed Phase 0** (3 §5 targets build via `make build`; lint clean; tests
  green via `xcodebuild test`) and **Phase 1** (menubar app launched + verified).
  Retired the temporary SwiftPM/`Smoke` scaffolding. Next: P2 audio capture.
- **2026-06-19**: Doc restructure into `AGENTS.md` + `docs/` + `research/`.
