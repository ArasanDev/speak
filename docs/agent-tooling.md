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

**Authored, thin pointers** (Apple API not yet ground-truthed — each says "verify
against live Apple docs at implementation time, tag `[verified]`"):
`speechanalyzer-stt`, `foundation-models-cleanup`, `cgeventtap-hotkey`,
`macos-paste-pipeline`, `permissions-onboarding`.

**Vendored from the community** (`.claude/skills/vendored/`, MIT, attributed) — see §4.

---

## 3. MCP servers & plugins to wire up (native-first)

All are **dev-time only** — they never become app dependencies.

| Tool | What it gives agents | Status / gate |
|---|---|---|
| **`swift-lsp`** (official plugin) | Live SourceKit-LSP diagnostics + navigation for `.swift` | Confirmed in marketplace cache. Install: `/plugin install swift-lsp@claude-plugins-official`. Needs the Swift toolchain (present: `swift` 6.3.2). |
| **Xcode native MCP** (Apple) | Xcode exposes build/test/diagnostics/Swift-REPL + **visual verify via SwiftUI Previews** over MCP; integrates Claude Agent directly | `[verified]` present locally: **Xcode 26.5 installed**; bridge binary at `$(xcode-select -p)/usr/bin/mcpbridge`. Wired in `.mcp.json` as server `xcode` (`xcrun mcpbridge`). **Status: connects but tools-fetch times out until a one-time Xcode-side authorization** — open the project in Xcode and approve the agent (Xcode Settings → Intelligence / Agent Client Protocol). Needs Xcode running. |
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

**Language-agnostic official plugins worth enabling**: `code-review`,
`security-guidance` (reviews each edit for vulns), `feature-dev`.

**Setup state**: `.mcp.json` configures `xcode` + `apple-docs` (project scope —
approve on first prompt). `swiftlint` ✔ installed; **`xcbeautify` not yet** (`brew
install xcbeautify`). Still optional: `/plugin install swift-lsp@claude-plugins-official`
(SourceKit-LSP). One-time Xcode auth needed to unblock the `xcode` bridge tools.

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
