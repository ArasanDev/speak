# `speak` — Plugin-as-Tag API Architecture & Dual-Panel UI Design

**Status:** superseded/rejected — the `@tag` plugin dispatch system and dual-panel UI
this designs were built under AVB-8..AVB-19 then fully purged (`3425443`, `3e35137`) ·
**Binds:** nothing — no inbound references · **Owner:** orchestrator · **Depends on:**
`specs/open-tag-system.md` · **Superseded by:** `specs/agent-voice-bridge.md` §4 ("Tools
are semantic workflows," not generic plugin/channel primitives) · **Last substantive
change:** 2026-07-21

> **Strategic API & UI Blueprint (2026-07-21)**
> **Core Concept**: Every channel, tool, and plugin integration (GitHub, Terminal, Datadog, Xcode, Browser, AI Agents) becomes a **Spoken Tag (`@tag`)**.

---

## 1. The "Plugin-as-Tag" Paradigm

In traditional apps, plugins live in buried dropdown menus or complex webhooks. In `speak`, **every plugin and channel integration is an active Spoken Tag (`@tag`)**.

```text
  SPOKEN / TYPED INPUT                              TAG RESOLUTION & DISPATCH
  "Hey @github summarize recent PRs"         ───►  @github    ➔ GitHub MCP Plugin
  "Tag @terminal run `make verify-moat`"    ───►  @terminal  ➔ Local Subprocess Plugin
  "Tag @datadog check latency spike"        ───►  @datadog   ➔ Datadog Channel Adapter
  "Tag @xcode build Speak.xcodeproj"        ───►  @xcode     ➔ Xcode Automation Plugin
  "Tag @Claude review AudioCapture.swift"   ───►  @Claude    ➔ Claude Code Agent
```

### Tag Types
1. **Agent Tags**: `@Claude`, `@codex`, `@builder-audio`, `@builder-qa`
2. **Channel / Tool Plugins**: `@github`, `@terminal`, `@xcode`, `@datadog`, `@figma`, `@slack`
3. **Team Tags**: `@engine-team`, `@qa-team`, `@design-team`
4. **Scope Tags**: `@channel`, `@here`

---

## 2. API & Architecture Specifications (`SpeakCore`)

To support this unified Plugin-as-Tag system, we define four core `SpeakCore` APIs:

```text
 ┌────────────────────────┐
 │      TagRegistry       │  Stores registered agent & plugin tags
 └───────────┬────────────┘
             │
             ▼
 ┌────────────────────────┐
 │    WorkspaceRouter     │  Parses `@tag` from voice turns & dispatches
 └───────────┬────────────┘
             │
             ▼
 ┌────────────────────────┐
 │   PluginTagAdapter     │  Unified protocol for MCP/REST/Local plugins
 └───────────┬────────────┘
             │
             ▼
 ┌────────────────────────┐
 │   EvidencePayload      │  Standardized Rich Media Card output
 └────────────────────────┘
```

### A. `TagRegistry` (Dynamic Tag Discovery)
- **Role**: Maintains a thread-safe registry of all active tags, their capabilities, icons, and invocation handlers.
- **Registration**: Plugins and MCP servers register their tag name (`@github`, `@terminal`) on launch over MCP or local IPC.

### B. `PluginTagAdapter` (Unified Integration Protocol)
Every plugin (whether a local CLI runner, an MCP tool server, or a remote REST service) conforms to a single protocol contract:
- `tagName: String` (e.g. `@github`)
- `description: String`
- `capabilities: [TagCapability]` (`.read`, `.execute`, `.notify`, `.requestApproval`)
- `handleTurn(turn: VoiceTurn) async throws -> TagTurnOutcome`

### C. `WorkspaceRouter` (Intent & Tag Parser)
- Extends `VoiceCommandParser` to extract tag handles (`@tag`) from raw speech or typed input.
- Isolates task context so invoking `@github` or `@terminal` does not pollute the main conversation context.

### D. `EvidencePayload` (Rich Media Card Contract)
Standardized Swift struct and JSON wire format for outputs:
- `summary: String` (short spoken line for `AVSpeechSynthesizer`)
- `checklist: [TaskChecklistItem]` (`[Done]`, `[In Progress]`, `[Blocked]`)
- `images: [URL]` (screenshots, mockups)
- `videos: [URL]` (screen recordings)
- `diffs: [CodeDiffBlock]` (patch diffs)
- `audio: URL?` (audio snippets)

---

## 3. Smart Dual-Panel Workspace UI Architecture

The main interface features a clean **Top Segmented Navigation Control** allowing instant switching between the two core modes:

```text
┌────────────────────────────────────────────────────────────────────────────────────────┐
│  SPEAK  │  [ ⚡ DICTATION ENGINE ]  │  [ 💬 AGENT WORKSPACE ]  │      ⚙️ Settings (Cmd+,) │
├────────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                        │
│  MODE 1: DICTATION ENGINE MODE (Focused Quick Input)                                   │
│  - Clean visual orb (Voice Desktop Pet pet) breathing with mic audio                                  │
│  - Partial transcript streaming live near cursor or floating capsule                    │
│  - Quick steer chips (Raw, Clean, Commit, Code, Task)                                   │
│  - Instant write-only paste into active focused app (Terminal, Xcode, Slack, etc.)     │
│                                                                                        │
├────────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                        │
│  MODE 2: AGENT WORKSPACE MODE (The Full Slack Replacement)                             │
│  ┌──────────────────────┬───────────────────────────────────────────────────────────┐  │
│  │ CHANNELS & TAGS      │ # feature-audio-capture                                   │  │
│  │  # core-engine       │ ───────────────────────────────────────────────────────── │  │
│  │  # qa-regressions    │ 👤 @tamil (Voice Turn):                                  │  │
│  │                      │    "Tag @terminal run `make test` & tag @Claude review"   │  │
│  │ PLUGINS (@TAGS)      │                                                           │  │
│  │  ⚡ @terminal        │ 🤖 @terminal: Command `make test` complete.               │  │
│  │  🐙 @github          │    📄 [Diff: 269 passed]                                  │  │
│  │  📊 @datadog         │                                                           │  │
│  │                      │ 🤖 @Claude: Live Checklist:                               │  │
│  │ AGENT ROSTER         │    ├─ [Done] Inspected AudioCapture.swift                 │  │
│  │  🟢 @Claude (Working)│    ├─ [Done] Verified tap guard                           │  │
│  │  🟢 @codex (Idle)    │    └─ [In Progress] Updating specs                        │  │
│  │  🟡 @builder-qa      │    📸 [Evidence: screenshot.png]                          │  │
│  └──────────────────────┴───────────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────────────────────────────────┘
```

---

## 4. Summary of API & UI Refinements

1. **Top Segmented Bar**: Switches cleanly between **Dictation Engine (Mode 1)** and **Agent Workspace (Mode 2)**.
2. **Plugins as Tags**: GitHub, Terminal, Xcode, and Agents are all `@tags` accessible via speech or text.
3. **Unified Evidence Cards**: Every plugin/agent returns structured checklists and media evidence.
4. **4 Streamlined Views**: Workspace Canvas, Agent Profiles, Vocabulary Rules, and Preferences Sheet (`Cmd+,`).
