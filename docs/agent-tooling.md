# `speak` — Agent Tooling & Skills (the build harness)

> **Status**: How the *agents* that build `speak` are equipped — skills, MCP
> servers, plugins, and the standing team. This is build-harness infra, **not**
> product architecture (that's `architecture.md`). The product's no-third-party-
> **runtime**-deps rule does **not** restrict dev/agent tooling (linters, LSP,
> MCP servers) — those never ship in the app. **Updated**: 2026-06-20.

Verified against primary sources this session (Anthropic docs + GitHub + Apple
Newsroom); see `specs/verification-ledger.md` for the load-bearing claims.

---

## 1. The standing team (`.claude/agents/team/`)

Seven specialists mirroring the `architecture.md` §5 seams. Roster per task is
dynamic (`plan_w_team` selects the subset). See `.claude/agents/team/README.md`
for the full ownership table. Each agent has `memory: project` (per-agent
persistent learning) and is wired to the skills for its seam.

---

## 2. Skills (`.claude/skills/`)

**Authored, doc-grounded (thick):**
- `swift-code-review` — the `AGENTS.md` §2–3 convention gate (no print, no
  force-unwrap, no global mutable state, never-read-pasteboard, Apple-only).
- `swift-macos-build` — build/test/lint commands + the §6 verification gate.
- `signing-notarization-release` — P11 sign/notarize/dmg/cask.

**Authored, thin pointers — v0** (Apple API not yet ground-truthed — each says "verify
against live Apple docs at implementation time, tag `[verified]`"):
`speechanalyzer-stt`, `foundation-models-cleanup`, `cgeventtap-hotkey`,
`macos-paste-pipeline`, `permissions-onboarding`.

**Authored, thin pointers — v0.1+ (post-cutoff APIs, all claims tagged `[inferred]` or `[unverified]` — agents MUST verify before coding):**
- `whisperkitv1-stt` — WhisperKit v1.0.0 `Transcribing` impl pointer; SPM setup; streaming + language-detect API shape; model download flow. Use for V01-1.
- `ollama-http-cleanup` — Ollama `localhost:11434` REST API; availability check; chat-completion shape; model picker; fallback/error HUD. Use for V01-2.
- `per-app-context-awareness` — NSWorkspace bundle-ID detection; 8 `AppContext` categories; AX selected-text read; prompt injection strings; bundle-ID reference table. Use for V01-0 + V01-3.
- `foundation-models-provider-api` — WWDC26 provider API (Anthropic/Google/MLX behind `LanguageModelSession`); **all shapes `[unverified]` — verify via local SDK before writing any code**. Use for V1-13.
- `mlx-swift-cleanup` — MLX Swift in-process LLM; SPM target discovery; Qwen3 model IDs; first-use download flow; RAM gating. Use for V1-1.

**Vendored from the community** (`.claude/skills/vendored/`, MIT, attributed) — see §4.

---

## 3. MCP servers & plugins to wire up (native-first)

All are **dev-time only** — they never become app dependencies.

| Tool | What it gives agents | Status / gate |
|---|---|---|
| **`swift-lsp`** (official plugin) | Live SourceKit-LSP diagnostics + navigation for `.swift` | Confirmed in marketplace cache. Install: `/plugin install swift-lsp@claude-plugins-official`. Needs the Swift toolchain (present: `swift` 6.3.2). |
| **Xcode native MCP** (Apple) | Xcode exposes build/test/diagnostics/Swift-REPL + **visual verify via SwiftUI Previews** over MCP; integrates Claude Agent directly | `[verified — LIVE 2026-06-21]`: **Xcode 26.5**, bridge `xcrun mcpbridge`, server `xcode` in `.mcp.json`. Authorized + working: `XcodeListWindows` → `windowtab2` (`Speak.xcodeproj`); `RenderPreview` produced real snapshots (Onboarding/Settings) **and caught a real defect** (HistoryView `List` assertion crash). Needs Xcode running with the project open. **Operating protocol: §3.1.** |
| **`apple-docs-mcp`** (community) | Query real Apple framework docs + WWDC sessions — **kills API hallucination** for SpeechAnalyzer / Foundation Models / CGEvent | `[verified]` `@kimsungwhee/apple-docs-mcp@1.0.26`. Wired in `.mcp.json` as `apple-docs` — **✔ connected**. Dev tooling only; never a runtime dep. |
| **`XcodeBuildMCP`** (getsentry) | 80+ build/test/simulator tools; installable via Homebrew (no Node) | Optional — overlaps Apple's native MCP. Prefer the native `xcode` bridge. |

### Verification backbone (cutoff-proof) — `swiftc` against the local SDK

The building agents share a Jan-2026 knowledge cutoff, but macOS 26 / SpeechAnalyzer
/ Foundation Models finalized around/after it. The authoritative, **available-now**
oracle for "does this symbol exist / what's its shape" is the **local SDK** (Xcode
26.5), not training memory and not JS-rendered web docs. Probe it:

```sh
swiftc -typecheck -sdk "$(xcrun --show-sdk-path)" -target arm64-apple-macosx26.0 probe.swift
```

This already caught a real bug: `architecture.md` §6 used `LanguageModel.default`
(does **not** resolve) — the correct symbol is `SystemLanguageModel.default`
(resolves). Agents must verify Apple-API claims this way (or via `apple-docs`)
before tagging `[verified]`.

### 3.1 Live Xcode MCP — operating protocol (autonomy) — [verified 2026-06-21]

The bridge is the **live-runtime oracle**: it drives the *running* Xcode, so it
sees the real (cert-anchored) DerivedData and renders real UI. Use it to push
claims from `[inferred]`/`[deferred]` toward `[verified]` without a human.

**Always start by discovering the tab:** `XcodeListWindows` → use the returned
`tabIdentifier` (currently `windowtab2`) in every other call. `sourceFilePath` is
project-relative (e.g. `App/History/HistoryView.swift`).

**The toolbelt and what each *actually* verifies:**

| Tool | Verifies | Does NOT verify |
|---|---|---|
| `BuildProject` / `RunAllTests` / `RunSomeTests` / `GetTestList` | Build + tests in **Xcode's own DerivedData** — the cert-anchored path that **preserves TCC grants** (vs `make`'s separate DerivedData; see agent-memory `dev-codesigning-for-tcc`) | — |
| `RenderPreview` | **Static view appearance with preview/sample data**: does the view compile, lay out, and render without crashing | Window-server behavior, live timing, real data |
| `ExecuteSnippet` | Apple-API **shape + simple runtime** in real file context (kills `[unverified]`-from-memory) | **Gated-model behavior** — Foundation Models / SpeechAnalyzer still need Apple Intelligence + entitlements live |
| `XcodeRefreshCodeIssuesInFile` / `GetBuildLog` / `XcodeListNavigatorIssues` | Live compiler diagnostics for a file / build | — |

**RenderPreview scope — do NOT overclaim (the precision matters).** A passing
preview closes the *static-appearance* subset of a `[deferred — visual]` row and
nothing more. Classify each visual row by **one discriminating test**: *does it
depend on the window server, the system menubar, a system panel, or live data
timing?*

- **No → RenderPreview closes it** (e.g. "Settings screen lays out correctly",
  "onboarding step renders"). Agent-verifiable now.
- **Yes → stays live/human** — e.g. the overlay's `.nonactivatingPanel` /
  `canBecomeKey=false` / floats-over-other-apps / bottom-center / hide-on-done
  *timing* (NSPanel behavior, not view content); the **menubar SF-Symbol color**
  (the system templates symbols to monochrome regardless of what the preview
  renders — a concrete false-pass trap); permission dialogs, Settings deep-links,
  `NSSavePanel`, hotkey-rebind recording.
- **Third bucket — unit-testable config:** some of the "live" mechanics are
  assertable in code without the window server (the panel's `canBecomeKey` /
  `collectionBehavior` flags). Prefer a unit test there; reserve "live" for the
  irreducible over-app *visual*.

Classify **per-row, not per-surface** — a single surface (the overlay) has rows in
all three buckets.

**Worktree vs the live bridge (hard constraint).** The bridge is bound to the
**main checkout's `Speak.xcodeproj`**. An agent editing in a `git worktree` is
invisible to it — Xcode would render/build *stale* main-tree code. Therefore:

- An agent that must verify via `RenderPreview`/`BuildProject` works in the **main
  tree, no isolation** (run it as the *sole* writer to avoid collisions).
- Parallel file-mutating agents use `worktree` isolation and verify **headlessly
  via `make`** (XcodeGen + `xcodebuild` regenerate/build the worktree copy fine);
  they do **not** get the live bridge.
- Pick one per agent up front: live-Xcode verification **or** worktree isolation,
  never both.

**Language-agnostic official plugins worth enabling**: `code-review`,
`security-guidance` (reviews each edit for vulns), `feature-dev`.

**Setup state**: `.mcp.json` configures `xcode` + `apple-docs` (project scope —
approve on first prompt). `swiftlint` ✔ installed; **`xcbeautify` not yet** (`brew
install xcbeautify`). Still optional: `/plugin install swift-lsp@claude-plugins-official`
(SourceKit-LSP). **The one-time Xcode auth is DONE — the `xcode` bridge is live (§3.1).**

---

## 4. Vendored community skills — provenance & verdicts

Both source repos are **MIT**. Policy: vendor only macOS-relevant, dep-clean
content; **sanitize `print()` → `os.Logger`** and verify any LLM-generated API
before trusting it. Skipped anything iOS-only, dep-violating, or fabricated.

**Vendored as-is (curated, clean)** — from `vabole/apple-skills` (MIT):
- `guide-swift-concurrency` (orig. Paul Hudson / twostraws) — structured
  concurrency, no `@unchecked Sendable` band-aids; aligns with our actor rules.
- `guide-swift-testing` (orig. Paul Hudson / twostraws) — Swift Testing patterns.
- `guide-macos-spm-packaging` (orig. Thomas Ricouard / Dimillian) — macOS
  notarization failure table; `LSUIElement` menu-bar note.

**Vendored with adaptation (sanitized)**:
- `foundation-models` (from `rshankras/claude-code-apple-skills`, MIT) — correct
  `import FoundationModels` / `LanguageModelSession` / `@Generable` usage + a
  ship checklist. **9 `print()` calls stripped → `os.Logger`.** Note: no
  streaming example (fetch from Apple docs). Cross-references our
  `foundation-models-cleanup` skill.

**Deliberately NOT vendored** (and why — keep this list; it's the audit trail):
- `mlx-framework.md` (rshankras) — imports **MLX, a third-party dep** → violates
  `AGENTS.md` §2.4. Hard no.
- `apple-intelligence.md` (rshankras/macos) — uses a **fabricated
  `import AppleIntelligence`** framework. Would actively mislead.
- All iOS-only skills (`ios-liquid-glass`, `uikit`, `corehaptics`,
  `simulator-utils`, etc.) — wrong platform.
- The API-reference *mirrors* (`swiftui`/`swift-concurrency` raw docs) — **not
  vendored on purpose**: `apple-docs-mcp` serves live, always-current Apple docs,
  so a stale snapshot in-repo is worse than the MCP. Use the MCP instead.

Deferred to v1+ scope (revisit when the feature lands): SwiftData skills,
sandboxing guide (v0 is non-sandboxed), security/keychain, HIG macOS deep-dive.
