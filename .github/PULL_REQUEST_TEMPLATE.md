<!--
Thanks for contributing to speak. Please read CONTRIBUTING.md and AGENTS.md
before opening a PR if you haven't already — the hard rules below are
non-negotiable and enforced by CI, not just style preference.
-->

## What does this PR do?

<!-- One or two sentences. Link the roadmap task / issue if there is one. -->

## Checklist

- [ ] `make gates` passes locally (build -> test -> lint -> verify-moat, in that order)
- [ ] New/changed code has test coverage (XCTest or Swift Testing)
- [ ] `docs/progress.md` updated if this changes project state
- [ ] Commit message(s) follow `[P<N>] <task>: <what changed>`

## Structural privacy rules (the moat audit will fail the build if violated)

`SpeakCore`, the `Speak` app target, and the CLI targets must contain **zero**:
- `URLSession` / other networking symbols
- `SecItem*` / other Keychain-auth symbols
- `print()` calls (use `os.Logger`)
- Force-unwrap (`!`), force-cast (`as!`), or `try!` outside test targets
- Pasteboard **reads** (write-only, `NSPasteboard` write + Cmd+V simulation only)

If your change needs networking or Keychain auth (e.g. a new cloud cleanup
provider), it belongs in `SpeakLLM.framework` — the one target deliberately
excluded from the audited set — not in `SpeakCore`/App/CLI.

## Anything reviewers should focus on?

<!-- Tricky logic, seams touched, things you're unsure about. -->
