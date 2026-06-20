# `speak` — Progress (NOW)

> **Status**: Living state. **The agent rewrites this every session.**
> Single source of truth for "where are we right now." Read first, update last.
> Never delete history — append. See `../AGENTS.md` §5.

---

## Current phase

**Phase 0 — partially landed.** Repo is now **git-initialized** (first commit
`e3f9b63`) with the pure-text P0 deliverables done (MIT `LICENSE`, `.gitignore`,
`.swift-version`). The Xcode-dependent P0 deliverables (`.xcodeproj`, `make
build` → `.app`, CI) remain **unverifiable** here (no full Xcode) → P0 is **not
done**. No Swift source exists yet. **One decision pending the human**: whether to
build+test the framework-agnostic `SpeakCore` logic via **SwiftPM now** (the CLT
SDK typechecks `import Speech`/`FoundationModels`/`AVFoundation`/`SQLite3`, so a
large slice of P3/P3.5/P9/P10 core logic is `swift build`/`swift test`-able with
zero Xcode) or **wait for Xcode** and keep everything in one mandated `.xcodeproj`.

---

## Done (this session — 2026-06-20, loop run #2)

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

- **Xcode-dependent P0 work** (`.xcodeproj`, `make build` → runnable `.app`, CI
  `xcodebuild` step, sign/notarize) needs full **Xcode** installed — only Command
  Line Tools are present. Authoring the Makefile/CI/`.xcodeproj` blind is possible
  but **cannot be verified** here, so it stays not-done with a named gap; don't
  fake it.
- **`SpeakCore` core-logic build (the unblocked-but-pending slice)** waits on the
  human's answer to the **SwiftPM-now vs wait-for-Xcode** decision (Open Q #5).
  This is the *only* thing gating real Swift progress — not Xcode.
- `git init` is **DONE** (was previously listed here as blocked — it wasn't; the
  project `CLAUDE.md` directs it. Resolved this run.)

---

## Next up

0. **WAITING ON XCODE INSTALL** (human is installing full Xcode). Loop polls for
   `xcodebuild`. Decision Q#5 = canonical `.xcodeproj` path, **no SwiftPM**.
0b. **Next engine-core unit (buildable now under CLT)**: `CaptureSession` actor
   state machine (§7.1) + `SpeakEngine` facade. Needs a paste-seam abstraction
   (a `TextInserting` protocol so the core stays testable; real `PasteboardWriter`
   NSPasteboard impl lives app-side) — design + document in `architecture.md`
   before coding. Then `HotkeyBinding` Codable (custom coding for `CGEventFlags`).
1. **When `xcodebuild` is present**: build the mandated Xcode project per
   `architecture.md` §5 — app target (`Speak.app`) + **`SpeakCore.framework`**
   target + `SpeakTests`; directory layout; `Makefile` (`build`/`test`/`release`);
   `swiftlint` config (install via brew); GitHub Actions CI (`xcodebuild build` +
   `swiftlint`). Done when `make build` produces a runnable `.app` from a clean
   clone (roadmap P0 done-when).
3. **P1 → P2 → P3 → P3.5 (cleanup) → P5 → P6** along the critical path.
4. The loop runs until `benchmark.md` §4 MATCH gate + §3 BEAT rows +
   `quality.md` §9 all pass. No deadline.

---

## Decisions logged

| Date | Decision | Rationale | Source |
|---|---|---|---|
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
| 5 | **Build+test `SpeakCore` logic via SwiftPM now, or wait for Xcode?** | **Resolved 2026-06-20 (loop #2)**: human chose **install Xcode, then continue** — proceed straight into the canonical `.xcodeproj`-based Phase 0, **no SwiftPM detour**. Loop now polls for `xcodebuild`. | P0 |
| 2 | `Foundation Models` runtime availability/quality for cleanup on the target Macs (Apple Intelligence gating, M-series, locale)? | Verify empirically at P3.5; raw fallback exists | P3.5 |
| 3 | Does write+`Cmd+V` avoid the paste prompt incl. the macOS 26.4 Terminal provenance check? | `[unverified]` — test in Terminal/iTerm | P6 |
| 4 | Developer ID signing cert for notarization? | Unverified | P11 |

---

## Session log

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
- **2026-06-19**: Doc restructure into `AGENTS.md` + `docs/` + `research/`.
