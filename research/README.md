# research/ — Raw Research Archive (Read-Only)

> **This folder is an evidence archive, not a source of direction.**
> All product direction lives in `../docs/`. Read these files **only** when you
> need to understand *why* a decision was made, not *what* to build.

## What's in here

The 10 research/ideation documents produced during the 2026-06-18 research
pass. They are preserved **verbatim** — do not edit them. They record the
correction arc that produced the final architecture decision.

## The arc (why these exist)

The research went through a self-correction loop. The documents form a
chain where **later files override earlier ones**, and the final synthesis
(`spec.md`) supersedes the conflicting recommendations in the middle of the
chain:

| # | File | What it says | Status |
|---|---|---|---|
| 1 | `sample-ideation.md` | Original `deepvoice` ideation (4 directions; ambient pair-programmer) | **Set aside.** A different product from `speak`. |
| 2 | `CATEGORY_LANDSCAPE.md` | 2026 voice-coding category sweep (5 buckets) | Context. Confirms `speak`'s wedge. |
| 3 | `SPEAK_PRODUCT_SPEC.md` | First `speak` product brief (Swift-native Mac dictation) | **Accurate** — refined into `../docs/product.md` |
| 4 | `SPEAK_PLATFORM_MODEL.md` | "Question this — use Rust core + uniffi" | **REJECTED for v0** — wrong category |
| 5 | `SPEAK_ARCHITECTURE_VERIFICATION.md` | "Rust confirmed — Anthropic + OpenAI both rewrote to Rust" | **Factually wrong** — Claude Code is TS+Bun |
| 6 | `SPEAK_LANGUAGE_CORRECTION.md` | The correction: Claude Code is TS+Bun, not Rust | **The correction that settled the debate** |
| 7 | `SPEAK_DICTATION_STACKS.md` | Verified: all 8 Mac dictation apps are Swift-native | **Definitive evidence** |
| 8 | `TECH_STACK_JUDGMENT.md` | Meta-lesson: Rust rec was a category error | **Final verdict + process** |
| 9 | `OPUS_BUILD_PROMPT.md` | Earlier work-order prompt (5-document deliverable) | **Superseded** by `../AGENTS.md` + `../docs/` |
| 10 | `spec.md` | The synthesis that this restructure replaced | **Superseded** by `../docs/*.md` |

## When to read these

- **Don't read them for direction.** `../docs/` is the source of truth.
- **Read them when:** a decision in `../docs/` seems wrong and you want the
  evidence trail, OR you're researching a new adjacent topic (e.g., extending
  to Windows in v1+) and want the prior research as a starting point.
- **The two most useful for evidence:** `SPEAK_DICTATION_STACKS.md`
  (verified competitor stacks) and `TECH_STACK_JUDGMENT.md` (the meta-process
  lesson). The rest are historical.

## Rule

If anything in `../docs/` contradicts something here, **`../docs/` wins.**
These files are frozen in time; the active docs evolve.
