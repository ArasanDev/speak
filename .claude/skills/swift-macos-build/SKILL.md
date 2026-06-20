---
name: swift-macos-build
description: Build, test, and lint the speak macOS app and verify a task against its done-when criteria. Use whenever you need to compile, run tests, check the verification gate, or set up the P0 build toolchain (Xcode project, Makefile, CI, swiftlint).
---

# Build & Verify — `speak` (macOS, Apple Silicon)

The build/verify workflow for `speak`. Code is **not done when written — done when
verified** (`AGENTS.md` §6). This skill encodes the toolchain and the gate.

## Commands (project `CLAUDE.md` / roadmap P0)

- **Build**:   `make build`   — xcodebuild → `Speak.app` + `SpeakCore.framework`
- **Test**:    `make test`    — xcodebuild test (XCTest + Swift Testing + XCUITest)
- **Lint**:    `swiftlint`    — enforce conventions (install via `brew install swiftlint`)
- **Release**: `make release` — Developer ID sign + notarize + `.dmg` + Homebrew cask

Pipe raw `xcodebuild` through **`xcbeautify`** (`brew install xcbeautify`) for
readable output: `xcodebuild ... | xcbeautify`. Both are dev tooling, **not**
runtime deps — they don't violate the no-third-party-deps rule.

## Toolchain reality (check before assuming)

Run `xcodebuild -version` and `swift --version` first. **Xcode 26.5 (Build 17F42)
is installed and active** — the full `xcodebuild` build/test/`.app` path is
available. (The repo is still pre-build per CLAUDE.md — `make build` hasn't been
run clean yet — so phrase it as the toolchain CAN produce a `.app`, not that
`speak` builds clean today.) The SDK also supports `swiftc -typecheck -sdk
"$(xcrun --show-sdk-path)" -target arm64-apple-macosx26.0 <file>` as a fast,
cutoff-proof technique for verifying Apple API symbol availability before writing
code — use it to confirm any `import Speech`/`FoundationModels`/`AVFoundation`
claim rather than relying on recalled API surface. Mandated build system is the
**`.xcodeproj`** (no SwiftPM detour — Open Q#5, resolved).

**XcodeGen:** `Speak.xcodeproj` is **generated** from `project.yml` by XcodeGen
(build-time tooling, git-ignored — see `.gitignore` "Speak.xcodeproj/" and
Makefile L3-9). A clean clone has **no project file** — you must run
`brew install xcodegen` first. `make build` runs `xcodegen generate` automatically
before invoking `xcodebuild` (Makefile L24-29: `build: generate`).

The native **Xcode 26.5 MCP** (build/test/diagnostics/SwiftUI-preview verify) and
the **`swift-lsp`** plugin (SourceKit-LSP) are available — prefer them over
hand-parsing build logs. For live MCP/tooling truth (incl. the `xcode` bridge's
one-time in-Xcode authorization caveat), see `docs/agent-tooling.md` and
`.mcp.json`.

## P0 setup deliverables (roadmap P0 done-when)

- `brew install xcodegen` installed; `xcodegen generate` produces `Speak.xcodeproj` from `project.yml`
- `make build` produces a runnable `.app` from a clean clone (runs `xcodegen generate` first)
- `SpeakCore.framework` is a **separate build target** (the portability seam)
- CI (GitHub Actions) runs on every push: `xcodebuild build` + `swiftlint`
- `LICENSE` MIT; `.gitignore` covers `DerivedData/`, `.build/`, `*.xcuserstate`, `.DS_Store`, `Speak.xcodeproj/`

## The verification gate — run before marking ANY task done (`AGENTS.md` §6)

1. **Compiles clean** — `make build` exits 0, no warnings treated as errors.
2. **Tests pass** — new code has tests; all existing tests green (`make test`).
3. **Done-when met** — the specific binary criterion from `roadmap.md` for this task is satisfied (not "basically works").
4. **No regressions** — `progress.md` notes no new failures.
5. **Constraints honored** — re-read `AGENTS.md` §2; confirm none violated (run `swift-code-review`).

If you cannot verify (e.g. no mic/Xcode in this environment), say so **explicitly**
in `progress.md` and flag the gap. Never claim done what you can't prove. Commit
per completed roadmap task: `[P<N>] <task>: <what changed>`.
