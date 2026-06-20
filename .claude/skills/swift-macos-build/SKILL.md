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

Run `xcodebuild -version` and `swift --version` first. As of the current state,
**only Command Line Tools may be present** (no full Xcode) — in which case
`xcodebuild`/`.app` bundling is **unavailable** and must be reported as a
verification gap, not faked. The CLT SDK still typechecks `import
Speech`/`FoundationModels`/`AVFoundation`/`SQLite3` (`swiftc -typecheck`), so
framework-agnostic `SpeakCore` logic can be checked even without Xcode. Mandated
build system is the **`.xcodeproj`** (no SwiftPM detour — Open Q#5, resolved).

The native **Xcode 26.3 MCP** (build/test/diagnostics/SwiftUI-preview verify) and
the **`swift-lsp`** plugin (SourceKit-LSP) become available once full Xcode is
installed — prefer them over hand-parsing build logs. See `docs/agent-tooling.md`.

## P0 setup deliverables (roadmap P0 done-when)

- `make build` produces a runnable `.app` from a clean clone
- `SpeakCore.framework` is a **separate build target** (the portability seam)
- CI (GitHub Actions) runs on every push: `xcodebuild build` + `swiftlint`
- `LICENSE` MIT; `.gitignore` covers `DerivedData/`, `.build/`, `*.xcuserstate`, `.DS_Store`

## The verification gate — run before marking ANY task done (`AGENTS.md` §6)

1. **Compiles clean** — `make build` exits 0, no warnings treated as errors.
2. **Tests pass** — new code has tests; all existing tests green (`make test`).
3. **Done-when met** — the specific binary criterion from `roadmap.md` for this task is satisfied (not "basically works").
4. **No regressions** — `progress.md` notes no new failures.
5. **Constraints honored** — re-read `AGENTS.md` §2; confirm none violated (run `swift-code-review`).

If you cannot verify (e.g. no mic/Xcode in this environment), say so **explicitly**
in `progress.md` and flag the gap. Never claim done what you can't prove. Commit
per completed roadmap task: `[P<N>] <task>: <what changed>`.
