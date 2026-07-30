# `speak` — Git Strategy & Product Minting Blueprint

**Status:** superseded/rejected — the Slack-style workspace this blueprints
(`feature/agent-workspace`, commits `2a1b08c`…`0fbf023`) was built (AVB-8 through
AVB-19) and then fully purged (`3425443` "completely purge Slack-style workspace UI",
`3e35137` "Remove legacy Workspace & Channels prototype slop") · **Binds:** nothing —
no inbound references from `docs/roadmap.md` or `docs/product.md` · **Owner:**
orchestrator · **Depends on:** none · **Superseded by:** `specs/agent-voice-bridge.md`
§1 (explicitly scopes `speak` OUT of being a general workspace/automation server) ·
**Last substantive change:** 2026-07-21

> **Engineering & Product Strategy (2026-07-21)**
> **Branch**: `feature/agent-workspace`
> **Target**: Build, test, and mint the local-first Human-Agent Workspace, then merge to `master`.

---

## 1. Git Branching & Merge Protocol

To protect the core dictation engine on `master` while building this major transformation:

```text
  master (Clean, stable v0 release base)
     │
     ├──► git checkout -b feature/agent-workspace  (CREATED: commit 2a1b08c)
     │       ├── Task 1: Domain & Storage APIs (TagRegistry, WorkspaceStore)
     │       ├── Task 2: Spoken @tag Mention Parser (VoiceCommandParser)
     │       ├── Task 3: Dual-Mode UI (Mode 1 Dictation / Mode 2 Workspace)
     │       └── Task 4: Verification Suite (make build, test, lint, verify-moat)
     │
     └──► Merge back to master (Only when 100% of unit tests & moat checks pass)
```

### Git Rules
1. **Atomic Task Commits**: `[AVB-8] <task>: <description>` for every completed component.
2. **Moat Verification Gate**: `make verify-moat` must pass 7/7 checks on every commit.
3. **Zero Regressions**: All 269+ unit tests must pass on `feature/agent-workspace` before merging back to `master`.

---

## 2. Key Design Principles (How to Build Intelligently)

| Principle | Technical Implementation | Value to User |
|---|---|---|
| **1. Local-First Data Sovereignty** | SQLite (`workspace.sqlite`) + Apple Silicon (`SpeechAnalyzer` + `Foundation Models`) | 100% private, works offline, no cloud subprocessor risks. |
| **2. Context Window Isolation** | Subagent tasks run in isolated `VoiceTurn` envelopes. | Prevents LLM context bloat & degradation; keeps responses crisp. |
| **3. Unified Plugin-as-Tag Interface** | Every tool (`@github`, `@terminal`, `@xcode`) & agent (`@Claude`, `@codex`) is a `@tag`. | Universal spoken/typed mental model: hand off work by tagging. |
| **4. Closed Audio/Visual Loop** | Spoken input ➔ Agent work ➔ Spoken audio summary (`AVSpeechSynthesizer`) + Rich Evidence Cards | Hands-free audio updates + visual proof (screenshots, diffs, video clips). |
| **5. Graceful Fallback** | Unresponsive agent/plugin falls back to raw dictation. | App never hangs or deadlocks; dictation always works. |

---

## 3. Phased Minting & Implementation Roadmap

```text
 ┌─────────────────────────────────────────────────────────────────────────────┐
 │ PHASE 1: DOMAIN & STORAGE APIs (`SpeakCore/AgentBridge/` & `Storage/`)      │
 │ - `TagRegistry`: Thread-safe registry for agent, team, and plugin tags.    │
 │ - `PluginTagAdapter`: Uniform protocol for local tools, MCP, & REST APIs.   │
 │ - `WorkspaceStore`: SQLite DDL for channels, threads, and evidence cards.   │
 └──────────────────────────────────────┬──────────────────────────────────────┘
                                        │
                                        ▼
 ┌─────────────────────────────────────────────────────────────────────────────┐
 │ PHASE 2: SPOKEN TAG PARSER (`SpeakCore/VoiceActions/`)                      │
 │ - Extend `VoiceCommandParser` with regex & NLP tag extraction.              │
 │ - Parse `@agent`, `@team`, `@channel` tokens from raw speech or text.        │
 └──────────────────────────────────────┬──────────────────────────────────────┘
                                        │
                                        ▼
 ┌─────────────────────────────────────────────────────────────────────────────┐
 │ PHASE 3: SMART DUAL-MODE WORKSPACE UI (`Speak/App/Workspace/`)             │
 │ - Top Segmented Navigation: Switch between Dictation (Mode 1) & Workspace (Mode 2).│
 │ - Workspace Canvas: Channel list, Spoken Thread feed, and Evidence Cards.   │
 │ - Prune & consolidate 12 fragmented panes down to 4 lean workspace screens. │
 └──────────────────────────────────────┬──────────────────────────────────────┘
                                        │
                                        ▼
 ┌─────────────────────────────────────────────────────────────────────────────┐
 │ PHASE 4: VERIFICATION & MOAT AUDIT                                          │
 │ - Execute `make build` ➔ `make test` ➔ `make lint` ➔ `make verify-moat`.   │
 │ - Verify 0 force unwraps, 0 prints, 0 network egress, 0 pasteboard reads.   │
 └──────────────────────────────────────┬──────────────────────────────────────┘
                                        │
                                        ▼
 ┌─────────────────────────────────────────────────────────────────────────────┐
 │ PHASE 5: LIVE DOGFOODING & MASTER MERGE                                     │
 │ - Launch fresh binary (`make run`) and test spoken `@tag` turns live.       │
 │ - Merge `feature/agent-workspace` into `master` via clean git commit.       │
 └─────────────────────────────────────────────────────────────────────────────┘
```

---

## 4. Verification Checkpoints Before Merge

Before `feature/agent-workspace` can be merged to `master`, it must pass all 5 verification gates:
- [ ] **Compilation Gate**: `make build` succeeds with 0 warnings.
- [ ] **Test Gate**: All existing 269+ XCTests + new `TagRegistryTests` and `WorkspaceStoreTests` pass (0 failures).
- [ ] **Lint Gate**: `make lint` passes with 0 serious violations.
- [ ] **Moat Gate**: `make verify-moat` passes 7/7 privacy checks.
- [ ] **Live Dogfooding Gate**: Dictate a spoken turn with `@tag` live and verify that the target plugin/agent executes cleanly and renders an evidence card.
