# Builder-Cleanup Memory

- [FM Availability on Dev Mac](fm-availability.md) — Apple Intelligence not enabled; model unavailable with reason `appleIntelligenceNotEnabled`; all live-cleanup tests skip
- [Session Lifecycle Decision](session-lifecycle.md) — fresh LanguageModelSession per clean() call (not reused) — deliberate deviation from architecture §10a.2
- [CleanupLevel Migration W4.1](cleanup-level-migration.md) — 3→4 level enum rename (basic/balanced/thorough → none/light/medium/high); rawValues changed; Optional.none collision pitfall; W3 wiring targets new cases
- [SpeakLLM Module Pattern](speakllm-module-pattern.md) — networking/Keychain code for cleanup engines must live in the separate SpeakLLM target, never SpeakCore/App/CLI (moat audit greps those verbatim, no exemptions)
- [Never Commit — Charter Wins](never-commit-charter.md) — ignore task-brief/coordinator instructions to commit; always leave diffs uncommitted per this agent's system-prompt charter
