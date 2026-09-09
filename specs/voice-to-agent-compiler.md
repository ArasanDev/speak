# Voice-to-Agent Compiler: The Missing 50%

> **Status**: Active Specification & Architecture Guide  
> **Target**: `SpeakCore/Cleanup/` & `Speak/App/Overlay/`  
> **Focus**: Transforming developer stream-of-consciousness speech into high-leverage AI agent instructions.

---

## 1. Problem Statement & The Real 50 / 50 Split

Traditional dictation systems treat voice transcription as a typing exercise:
* Punctuation, capitalization, and removing "um/uh" represent only **45%–50%** of the user need (table stakes).
* The **remaining 50%** is where the actual product value lives: **turning spoken human thought into structured, actionable prompts for AI agents (specifically coding agents).**

When a developer speaks for 60 seconds, they think out loud—laying out constraints, architectural principles, edge cases, and self-corrections. A raw transcript forces the receiving agent to parse verbal stumbles, acoustic mishearings, and backtracking. Speak's core mission is to act as an on-device **Voice-to-Agent Compiler**.

```
Total Goal (100%)
├── 50% (Table Stakes / Machine Layer):
│   ├── Getting words down accurately
│   ├── Basic punctuation & capitalization
│   └── Removing literal filler sounds ("um", "uh")
│
└── 50% (The Real Product: Voice-to-Agent Compilation):
    ├── Stream-of-consciousness → Structured Instruction
    ├── Resolving verbal resets & mid-sentence train-of-thought corrections
    ├── Preserving 100% of technical constraints, numbers, paths, and flags
    └── Delivering text formatted for optimal coding-agent execution
```

---

## 2. The Three Inviolable Principles

### Principle 1: Train-of-Thought Collapse
When a speaker says:
> *"We will have one folder... incense in one full git repo it can be, or one folder... or we can call it a workspace"*
The speaker is converging on their final intended term: **workspace**. The compiler collapses the verbal exploration into the final decision while preserving any articulated rationale.

### Principle 2: Zero Constraint Loss
Never paraphrase away or condense technical constraints:
* File length limits (`under 500 lines`)
* Protocols and flags (`stdio MCP`, `--verbose`, `16 kHz mono`)
* File names, directory paths, and database names (`SQLite3`, `FTS5`, `history.sqlite`)
* Negative instructions (`"do NOT use third-party libraries"`)

### Principle 3: Acoustic Developer Lexicon Healing
Small on-device speech recognizers make predictable phonetic mistakes on software terminology because standard language models lack code context. These are deterministically healed before and after LLM processing:
* `gid hup` / `git hup` $\rightarrow$ **GitHub**
* `gift repository` / `gift repo` $\rightarrow$ **Git repository**
* `work treat` / `work dream` / `what tree` $\rightarrow$ **worktree**
* `lines of coke` $\rightarrow$ **lines of code**
* `studio mcp` $\rightarrow$ **stdio MCP**
* `project dogs` $\rightarrow$ **project docs**
* `full rippo` $\rightarrow$ **full repo**
* `port base` $\rightarrow$ **codebase**
* `dog footing` $\rightarrow$ **dogfooding**
* `qva testing` $\rightarrow$ **QA testing**

---

## 3. Implementation Plan

1. **Acoustic Developer Normalizer Expansion**:
   Enhance `DeveloperAcronymNormalizer.swift` with regex rules targeting the verified acoustic mishearings found in `history.sqlite`.

2. **Agent Instruction Prompt Synthesis**:
   In `FoundationModelPromptBuilder.swift`, craft the dedicated `agentInstruction` prompt mode:
   * Numbered step-by-step guidance:
     1. Unify false starts and verbal resets.
     2. Keep all constraints, numbers, paths, and requirements verbatim.
     3. Remove conversational filler and output a structured, authoritative prompt.
   * Few-shot demonstrations of developer speech compiling to agent prompts.

3. **Ground-Truth Verification**:
   Verify against real production samples (#1 to #16) from `history.sqlite` to ensure:
   * No technical details are dropped.
   * Prompts are immediately ready for Claude Code / Antigravity / Cursor.
   * Latency remains sub-second with streaming chunks.
