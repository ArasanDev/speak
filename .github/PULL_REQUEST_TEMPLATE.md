<!--
Thanks for contributing to speak. Please read CONTRIBUTING.md and AGENTS.md
before opening a PR if you haven't already — the hard rules below are
non-negotiable and enforced by CI, not just style preference.
-->

## What does this PR do?

<!-- One or two sentences. Link the roadmap task / issue if there is one. -->

## Checklist

- [ ] `make preflight` passes (moat + lint + compile — the same checks CI runs on this PR)
- [ ] `make gates` passes locally if you have a full dev environment (build -> test -> lint -> verify-moat)
- [ ] New/changed code has test coverage (XCTest or Swift Testing)
- [ ] Commit messages are clear and imperative (the `[P<N>]` convention is internal tooling — not required)

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
