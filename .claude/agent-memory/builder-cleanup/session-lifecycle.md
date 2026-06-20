---
name: session-lifecycle
description: Deliberate decision to use fresh LanguageModelSession per clean() call instead of reusing across dictations
metadata:
  type: feedback
---

Use a **fresh `LanguageModelSession` per `clean()` call**, not a shared instance across dictations. This deliberately deviates from architecture §10a.2 which says "reuse across dictations."

**Why:** `LanguageModelSession` is stateful — it accumulates a transcript. Reusing one session for independent cleanup requests (a) lets earlier dictations bias later ones and (b) risks `exceededContextWindowSize` as context grows. For a stateless transform task, per-call sessions are more correct. Also enables mode-specific instructions at init time (the system-prompt slot).

**How to apply:** `FoundationModelsCleaner` is a stateless value type (`Sendable`). Instantiate `LanguageModelSession` inside `clean()`, not in `init()`. If P13 dogfood shows per-call latency exceeds the 1.5s target, revisit with prewarm strategy. See `[decision]` comment in `FoundationModelsCleaner.swift`.
