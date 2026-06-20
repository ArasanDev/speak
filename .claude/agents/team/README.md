# `speak` standing team

Seven specialist agents mirroring the architecture seams (`docs/architecture.md` §5).
The team is **stable**; the roster per task is **dynamic** — `plan_w_team` picks the
right subset for each job. The orchestrator (main thread) reviews diffs and owns
commits; agents do bounded implementation work and update `docs/progress.md`.

Each agent reads `AGENTS.md` + the relevant `docs/` first and runs the
`swift-code-review` + `swift-macos-build` gates before declaring done. None of these
files duplicate `AGENTS.md` — they point at it.

| Agent | Owns | Skills | Critical path |
|---|---|---|---|
| `builder-engine` | `SpeakCore/Engine/` (facade, state machine, errors), `Logging/` | swift-code-review, swift-macos-build | core seam |
| `builder-audio-stt` | `Audio/` (AVAudioEngine) + `STT/` (SpeechAnalyzer) | speechanalyzer-stt, swift-code-review | **P2 → P3** |
| `builder-cleanup` | `Cleanup/` (Foundation Models neat-writing) | foundation-models-cleanup, swift-code-review | **P3.5** |
| `builder-input` | `Hotkey/` + `Paste/` + `Permissions/` | cgeventtap-hotkey, macos-paste-pipeline, swift-code-review | **P5 → P6** |
| `builder-app` | `App/` (SwiftUI shell) + `Storage/` (SQLite/settings) | permissions-onboarding, swift-code-review | P1, P4, P7–P10 |
| `builder-release` | `.xcodeproj`, Makefile, CI, sign/notarize/dmg/cask | swift-macos-build, signing-notarization-release | **P0, P11** |
| `builder-qa` | `SpeakTests/`, benchmark + quality gates, dogfood | swift-code-review, swift-macos-build | **P13** |

## Skills (`.claude/skills/`)

- **Thick, doc-grounded**: `swift-code-review` (the §2–3 convention gate),
  `swift-macos-build` (build/test/lint + the verification gate),
  `signing-notarization-release` (P11 distribution).
- **Thin pointers** (Apple API not yet ground-truthed — verify against live Apple
  docs at implementation time, tag `[verified]`): `speechanalyzer-stt`,
  `foundation-models-cleanup`, `cgeventtap-hotkey`, `macos-paste-pipeline`,
  `permissions-onboarding`.

See `docs/agent-tooling.md` for the native MCP / plugin setup (swift-lsp, Xcode 26.3
MCP, apple-docs-mcp) and the provenance of any vendored community skills.
