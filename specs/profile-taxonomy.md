# `speak` — Profile Taxonomy (LOCKED 2026-06-29)

> Supersedes the flat 7-profile set in `profile-system-prompts.md` / `profile-engine.md §2`.
> Organize profiles by **destination** (who you're talking to), with **depth only where
> it pays** — the coding/agent case. This is the coding-agents-first wedge made structural
> (see memory `coding-agents-first-positioning`).

## The model: few destinations, categories only inside Agent

| Profile | Destination | System-prompt mission | Categories |
|---------|-------------|-----------------------|------------|
| **Agent** ⭐ | A coding agent / dev tool (CC, Cursor, Copilot, terminal agents, AI assistants you instruct) | "My speech is an instruction for an agent. Rewrite it as a clean, well-formed prompt the agent can act on." | **Yes — the only profile with categories** |
| **Write** | Prose for humans — email, Slack, Messages, docs | "Clean my dictated speech into polished written prose." | none (light tone modifier only) |
| **Note** | Capture for myself — lists, todos, quick thoughts | "Tidy my speech into a concise note/list. Don't expand or explain." | none |
| **Raw** | Verbatim passthrough (immutable base core; AI off ⇒ Raw) | (no prompt — identity) | none |

3 destinations + Raw. No `Clean`/`Chat`/`Code`/`CLI`/`Prompt`/`Commit` as siblings — those
were never separate destinations.

## Agent categories (the depth)

A per-dictation modifier that applies **only when the destination is Agent**. Modeled like
`CleanupLevel` — an enum whose selected case appends a prompt fragment to the Agent system
prompt (NOT a separate `Profile`). Default = `task`.

| Category | When | Was | Visibility |
|----------|------|-----|------------|
| **Task** | "implement / refactor / add X" | Prompt | primary |
| **Fix** | "this is broken, here's the error/symptom" | (new) | primary |
| **Ask** | "explain / how / why" | Chat (coding side) | primary |
| **Commit** | a commit / PR message | Commit | primary |
| **Shell** | a single terminal command | CLI | primary |
| **Code** | literal code dictated as notation | Code | `⌄more` (rare) |

Mapping the old set → new structure: `Prompt→Agent·Task`, `Commit→Agent·Commit`,
`CLI→Agent·Shell`, `Code→Agent·Code`, `Chat→Agent·Ask` (or `Write` for human chat),
`Clean→Write`, `Raw→Raw`.

## Resolution: app → destination (not app → category)

An app maps to a **destination**; the **category is chosen by the user in the moment**,
because the app cannot see the nested target (e.g. Claude Code running inside Cursor's
terminal — the frontmost app is Cursor, the real target is an agent).

| Frontmost app (bundle id family) | Destination |
|----------------------------------|-------------|
| IDEs / editors / terminals / agent UIs (Cursor, VSCode, Xcode, Zed, Terminal, iTerm, Ghostty, …) | **Agent** |
| Mail, Slack, Messages, Discord, browsers (default) | **Write** |
| Notes, Obsidian, Notion, Bear | **Note** |
| (no match) | **Write** (global default) |

Category never auto-resolves from the app — it defaults to `task` for Agent and is
overridden per-dictation by tap or voice. A user may **Pin** a category to a context
(one-click) to make it sticky for that app.

## Live panel consequence (adaptive)

The live panel's top strip shows **one row normally, two only for Agent**:
- Row 1 — destination chips (`Agent · Write · Note`), usually pre-selected by resolution.
- Row 2 — Agent categories (`Task Fix Ask Commit Shell  ⌄more`), shown **only when Agent
  is active**. Write/Note show no second row.

Complexity scales with the destination. Full live-panel interaction spec is a follow-up
(`live-panel-prompt-shaper`, PE-3).

## Constraints carried over

- Built-ins (Agent/Write/Note/Raw) are non-deletable, resettable (PE-2 ProfileStore).
- Every default prompt + category fragment is small-model-shaped (`profile-engine.md §6`)
  and earns its place against the **SM-0 eval harness** before/after edits.
- Raw is the immutable base-core bypass; AI off ⇒ Raw.
