# `speak` — Product Transformation Master Checklist & Daily Tracker

> **Purpose**: Tracked a "Slack-replacement Human-Agent Workspace" UI (channels, DMs, Voice Huddles, approval cards) — the feature it describes was built, then deliberately deleted. · **Audience**: none currently — the described feature no longer exists · **Status**: superseded by `roadmap.md` (North star / Agent Voice Bridge track); the codebase it tracked was purged in `3425443` (2026-07-24) — see `docs/README.md` known-issues entry and the reorg report for the full evidence trail · **Last reviewed**: 2026-07-30 (reviewed today)

> **Master Execution Register & Daily Progress Log**
> **Location**: `docs/speak_transformation_master_checklist.md`
> **Authority**: Primary living register for tracking the transformation of `speak` into the world's leading local-first Human-Agent Workspace.

---

## 1. The Vision & How `speak` Transforms

### The Final Outcome

`speak` transforms from a voice dictation utility into the **ultimate local-first, privacy-guaranteed Human-Agent Workspace**:

1. **Voice-First Input Substrate**: Voice is the primary interaction layer. Speak naturally to dictate text system-wide OR issue high-level intent directives to agent swarms.
2. **Dual-Mode Ergonomics**:
   - **⚡ Dictation Engine Mode**: Dedicated sidebar for dictation insights, custom vocabulary, and AI neat-writing profiles.
   - **💬 Agent Workspace Mode**: Single-sidebar Slack-replacement workspace featuring channels (`#general`, `#core-engine`), 1-on-1 agent DMs (`@Claude`, `@builder-qa`, `@terminal`), and real-time Voice Huddles.
3. **Traceability & Human-in-the-Loop Safety**:
   - **Interactive Approval Cards**: Explicit consent gates for mutating shell/git commands.
   - **Pronged Action Triggers**: Monospaced directive pills (`⚡ Run`, `🔍 Inspect`, `🛡️ Audit`, `🗣️ Speak`) for instant execution dispatch.
   - **Code Diff Inspector**: Syntax-highlighted line-by-line code patch reviews inside rich evidence cards.
4. **100% Local Privacy Moat**: Zero cloud audio egress, no accounts, free & open-source (MIT), Apple Silicon optimized.

---

## 2. Master Execution Checklist

### Completed Workstreams
- [x] **Task 1: Dual-Mode Dashboard Header Navigation & Sidebar Isolation**
  - Mode switcher (`TopSegmentedBarView`) in `DashboardView.swift`. Hides dictation sidebar when in Workspace mode.
- [x] **Task 2: Slack-Replacement Channel & DM Workspace**
  - Channel list (`#general`, `#core-engine`), 1-on-1 DMs (`@Claude`, `@builder-qa`, `@terminal`), and spoken thread canvas in `WorkspaceMainView.swift`.
- [x] **Task 3: Voice Huddles (Real-time Audio Room with Verbal Readbacks)**
  - Live huddle header bar, active participant roster (`👤 @tamil`, `🤖 @Claude`), and automatic verbal speech readbacks via `AppleSpeechSynthesizer`.
- [x] **Task 4: Quick Switcher (`Cmd+K`) & Pinned Channel Canvas**
  - Spotlight search modal (`QuickSwitcherModalView.swift`) and persistent right-hand project spec side-sheet (`ChannelCanvasView.swift`).
- [x] **Task 5: Interactive Action Approval Cards**
  - Human-in-the-loop safety cards (`ApprovalCardView.swift`) with interactive **[Approve Action]** and **[Decline]** buttons for high-risk commands.
- [x] **Task 6: Pronged Action Trigger System**
  - Replaced legacy text emojis with monospaced directive pills (`⚡ Run`, `🔍 Inspect`, `🛡️ Audit`, `🗣️ Speak`) in `WorkspaceMainView.swift`.
- [x] **Task 7: Interactive Code Diff Inspector**
  - Built `CodeDiffInspectorView.swift` with green (`+`) / red (`-`) syntax highlighting and line count toggles inside `EvidenceCardView.swift`.
- [x] **Task 8: User Profile Modal & Full-Screen Polish**
  - Built `UserProfileModalView.swift` with consistent `#23272F` card borders, `.easeInOut(0.2)` transitions, and responsive full-screen layout.
- [x] **Task 9: SQLite FTS5 Full-Text Search Engine Integration**
  - Implemented `searchMessagesFTS` in `WorkspaceStore.swift` for instant zero-latency message and evidence searching.

---

### Active & Upcoming Workstreams
- [x] **Task 10: Multi-Agent Swarm Broadcaster (`@team` & `@engineers`)**
  - Added `resolveSwarmTags` in `TagRegistry.swift`. Broadcasts single spoken/typed turn to `@Claude`, `@builder-qa`, and `@terminal`.
- [ ] **Task 11: Real-Time Terminal Streaming & Live Task Indicators**
  - Live stdout/stderr streaming lines and progress bar spinners (`0% -> 100%`) for long-running agent tasks (`make test`, `swiftc`).
- [ ] **Task 12: Custom Spoken Command Shortcuts & Voice Dictation Profiles**
  - User-defined voice macros ("Deploy staging" $\rightarrow$ `@terminal git push origin main && make deploy`) in `SettingsStore` & `VoiceCommandParser`.
- [ ] **Task 13: Local MCP Connector Hub Expansion (`speak-mcp`)**
  - Add `speak_publish_card`, `speak_create_channel`, and `speak_request_approval` JSON-RPC tools to `SpeakMCP`.
- [ ] **Task 14: One-Click Channel & Evidence Card Markdown Exporter**
  - Export channel thread feed, evidence cards, and task checklists to Markdown files in `ChannelCanvasView`.

---

## 3. Daily Execution Protocol

1. Pick the next uncompleted task from Section 2.
2. Implement code & unit tests together.
3. Run verification loop: `make build` $\rightarrow$ `make test` $\rightarrow$ `make verify-moat` $\rightarrow$ `make run`.
4. Update checkbox `[ ]` $\rightarrow$ `[x]` in `docs/speak_transformation_master_checklist.md`.
5. Commit changes with clear task tags.
6. Proceed to the next task.
