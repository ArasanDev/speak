# research/

> Read-only evidence layer. Never build direction from this folder alone.
> Primary docs (`docs/`, `specs/`) supersede all content here.

## Access policy

Do not read `archive/`. It contains superseded pre-build specs and one false claim.

Read `evidence/` only when a specific file is referenced by another doc.

If anything in `docs/` contradicts something here, `docs/` wins.

> WARNING: `archive/SPEAK_ARCHITECTURE_VERIFICATION.md` contains a false claim
> ("Claude Code is rewritten in Rust+WASM"). This is factually wrong. Do not read it.

## evidence/ — may read when referenced

| File | What it contains | Cited by |
|------|-----------------|----------|
| `dictation-stacks-verified.md` | Verified Swift-native stacks for 8 Mac dictation apps | `docs/architecture.md` |
| `agent-instruction-anatomy.md` | Anatomy of effective agent instructions and briefing patterns | `AGENTS.md` |
| `small-model-prompting-eval.md` | Prompting eval data for small on-device models | `docs/benchmark.md` |
| `tech-stack-judgment.md` | Meta-lesson: Rust recommendation was a category error; Swift verdict | `docs/architecture.md` |
| `agent-mode-prompting-synthesis.md` | Synthesis of agent-mode prompting strategies | `AGENTS.md` |

## archive/ — do not read

These are superseded pre-build specs from the 2026-06-18 research pass. Kept for provenance only.

One file (`SPEAK_ARCHITECTURE_VERIFICATION.md`) contains a false claim. Treat the entire folder as off-limits.
