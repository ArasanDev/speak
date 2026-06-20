# `speak` — Progress (NOW)

> **Status**: Living state. **The agent rewrites this every session.**
> Single source of truth for "where are we right now." Read first, update last.
> Never delete history — append. See `../AGENTS.md` §5.

---

## Current phase

**Pre-build.** The full doc set now describes the **real, complete product** —
time-free, destination-first, with AI neat-writing as v0 core and the
load-bearing claims verified against primary sources. Ready for **Phase 0**.
No Swift code exists yet.

---

## Done (this session — 2026-06-20)

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

- **Phase 0 (and the whole build) is blocked on the local toolchain.**
  `xcodebuild` is absent (Command Line Tools only — full **Xcode not installed**),
  so `make build`/the Xcode project cannot be created here. The repo is also not
  git-initialized. **Needs the human**: install Xcode (App Store / developer.apple.com)
  and approve `git init`. Until then there is no agent-actionable build work.

---

## Next up

0. **HUMAN GATE (blocks everything below)**: install full **Xcode** (only
   Command Line Tools are present → `xcodebuild` missing) and approve **`git init`**.
   `swift` 6.3.2 / macOS 26 target is already confirmed available.
1. **`git init`** (repo is not yet a git repo) — verify toolchain done:
   `swift` ✓, `xcodebuild` ✗ (see gate above).
2. **Phase 0 (repo setup)** — Xcode project, `SpeakCore.framework` target,
   layout, CI, MIT license. Done when `make build` works from a clean clone.
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
| 1 | Xcode/Swift toolchain available here? Repo needs `git init`. | **Resolved 2026-06-20**: `swift` 6.3.2 ✓ (macOS 26 target); **`xcodebuild` ✗ (no full Xcode)**; not a git repo. → Phase 0 blocked on human (install Xcode + `git init`). | P0 |
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
- **2026-06-19**: Doc restructure into `AGENTS.md` + `docs/` + `research/`.
