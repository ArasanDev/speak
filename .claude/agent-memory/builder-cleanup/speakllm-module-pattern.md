---
name: speakllm-module-pattern
description: Any cleanup engine that needs networking or Keychain (Ollama/cloud LLM presets) must put that code in the separate SpeakLLM framework target, not SpeakCore/App/CLI.
metadata:
  type: project
---

`scripts/verify-moat.sh` and `SpeakTests/MoatAuditTests.swift` grep `SpeakCore/`,
`App/`, and `CLI/` (line-by-line, including comments) for networking symbols
(`URLSession`, `URLRequest`, `dataTask(`, `NWConnection`, `getaddrinfo`, …) and
identity/auth symbols (`SecItemAdd(`, `SecItemCopyMatching(`, `LAContext`, …) to
make "100% local/offline, no account" (benchmark.md §3 #1/#4/#7) a *structural*
guarantee, not a policy. There is no per-file exemption mechanism — the grep is
blanket across those three directories.

V01-2 (universal OpenAI-compatible cleanup engine — Ollama/Sarvam/OpenAI/Groq/
OpenRouter/custom) needed real HTTP + Keychain code. The resolution (confirmed
with the advisor, and consistent with hints already in the codebase — the old
`OllamaCleaner.swift` stub's own migration note, and V01-1's WhisperKit roadmap
entry): add a **new `SpeakLLM` framework target** in `project.yml`, sources
`SpeakLLM/`, deliberately *not* one of the three audited directories.
`SpeakLLM` holds `OpenAICompatibleClient` (URLSession) and `LLMKeychainStore`
(SecItem*). `SpeakCore/Cleanup/OpenAICompatibleCleaner.swift` holds only preset
*data* (base URL, auth style, default model — no networking symbols of its own)
and calls into `SpeakLLM` for the actual request/keychain read. `SpeakCore`
depends on `SpeakLLM` in `project.yml`; `import SpeakLLM` was added to the
import allowlist in both `scripts/verify-moat.sh` and `MoatAuditTests.swift` —
that only permits the *import statement*, it does NOT exempt any symbol from
the networking/auth greps, which still scan every line of SpeakCore/App/CLI.

**Why:** an audit that gets "fixed" by loosening its own grep (e.g. exempting
`SpeakCore/Cleanup/*.swift` from the network-symbol check) would make the
audit's assertion false while staying green — that's hollowing out a BEAT row,
not satisfying it. Moving the networking code to an unaudited target keeps the
assertion honest: `SpeakCore` genuinely has zero networking/Keychain symbols.

**How to apply:** any future cleanup/STT engine that needs real networking or
Keychain (WhisperKit model download, MLX model download, another cloud LLM
preset, [[speakllm-module-pattern]]-adjacent work) should extend the *existing*
`SpeakLLM` target rather than inventing a new one or trying to sneak networking
into `SpeakCore`. Check `project.yml` for the target before assuming it doesn't
exist — this memory may be written before or after it lands; verify by reading
`project.yml`'s `targets:` section and `ls SpeakLLM/`.

Also: `.swiftlint.yml`'s `included:` list needed `SpeakLLM` added explicitly —
it is not auto-included by virtue of being a new target dir.
