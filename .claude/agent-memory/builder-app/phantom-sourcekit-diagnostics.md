---
name: phantom-sourcekit-diagnostics
description: SourceKit/LSP shows type-mismatch errors and "cannot find type" after xcodegen regenerate — these are phantom stale-index artifacts, not real compiler errors
metadata:
  type: feedback
---

After `xcodegen generate` (which `make build` always runs), SourceKit's index can lag behind the regenerated project. This produces phantom diagnostics like:

- "cannot find type 'OverlayController' in scope" (in test files that @testable import Speak)
- Type-mismatch errors on lines that are actually correct

**Why:** The clean `xcodebuild` compiler build is the authoritative check. SourceKit reads its own stale index until it re-indexes, which can take seconds to minutes after a project change.

**How to apply:** Never trust inline IDE/SourceKit errors after a `make build` that succeeded. If `make build` + `make test` both pass clean, the code is correct — the SourceKit errors are stale. Reload the LSP (`make lsp`) if you need the editor to catch up. Do NOT revert or second-guess code based solely on SourceKit diagnostics when the compiler build is green.

[[debug-verification-surface]]
