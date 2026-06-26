# AGENTS.md — Operating Manual for `speak`

> **Read this FIRST. Every session. Before any other file.**
> This is not documentation about the product — it is the **operating system**
> for any agent (human or AI) working on `speak`. It defines the mission, the
> hard rules, the loading protocol, and the autonomous loop.

> **If you are an AI agent beginning work on this repo, the rest of this file is addressed to you.**

---

## 0. The mission

You are building **`speak`**: a macOS-native, local-first, free, open-source
voice dictation app — the private, free, open alternative to cloud dictation
(Wispr Flow). It sits in the menubar, captures the microphone on a hotkey,
transcribes speech **on-device**, **cleans it into finished text with a local
model**, and pastes the result at the cursor. Speech→text *and* AI neat-writing
are both core, both on-device, both pluggable.

**There is no deadline.** This is an autonomous, agent-driven build: the loop
runs — across as many cycles as it takes, hours or days — until the **complete
product** exists. "Done" is defined by testable criteria in `benchmark.md` and
`quality.md`, never by dates, effort estimates, or hours. Operate
**autonomously**: read the state, pick the next dependency-ready task, execute,
verify, update state, repeat. Push your limit. Be opinionated. Build the whole
thing.

**What you are NOT building** (do not drift here):
- Not an agentic coding tool. (That was abandoned `deepvoice`; see
  `research/sample-ideation.md`.)
- Not a chatbot, voice assistant, or meeting scribe.
- Not cross-platform in v0. Mac + Apple Silicon only.
- Not cloud. No accounts, login, or telemetry.

---

## 1. How to navigate this repo

```
deepvoice/
├── AGENTS.md            ← you are here. The operating loop. Read first.
├── README.md            # human-facing summary + status snapshot
│
├── docs/                # the active source of truth (read these for direction)
│   ├── product.md       # WHAT + WHY. The destination + the full version ladder.
│   ├── architecture.md  # HOW. Modules, types, signatures, data flow.
│   ├── roadmap.md       # ORDER. Dependency-ordered build sequence (no dates).
│   ├── benchmark.md     # DONE. Parity vs the frontier; the definition of done.
│   ├── quality.md       # VERIFY. Tests, risks, ship gates.
│   ├── progress.md      # NOW. Living state. YOU rewrite this every session.
│   └── agent-tooling.md # BUILD HARNESS. Team, skills, MCP, verification backbone.
│
├── .claude/             # the autonomous build harness (how agents are equipped)
│   ├── skills/          # on-demand skills: build, code-review, per-seam API pointers
│   └── agents/team/     # standing specialist team (one per architecture seam) — see its README
│
├── .mcp.json            # project MCP servers: xcode (mcpbridge) + apple-docs
│
└── research/            # WHY-evidence archive. Read-only. Never the direction.
    └── README.md        # start here if you ever touch this folder
```

### The loading protocol (every session)

1. **Read `AGENTS.md`** (this file) — refresh mission, constraints, conventions.
2. **Read `docs/progress.md`** — learn where the project is right now.
3. **Read `docs/roadmap.md`** — find the next undone task with met dependencies.
4. **Read the specific `docs/` file(s)** the task needs (architecture? quality?).
5. **Execute the task.** Write code + tests. Verify against `docs/quality.md`.
6. **Update `docs/progress.md`** — mark done, note what's next, log decisions.
7. **Commit** if the task is verifiably complete (see §7).
8. **Repeat from step 3** until blocked or done.

Do **not** read `research/` unless a `docs/` decision seems wrong and you need
the evidence trail. It is 4,000+ lines of historical reasoning that will
distract you from building.

### What each doc is for

| Doc | Purpose | When to read | Who edits |
|---|---|---|---|
| `product.md` | What `speak` is + the full version ladder | Once, upfront; refer back | Human (the destination) |
| `architecture.md` | How it's built | When implementing | Agent, with human approval on structural change |
| `roadmap.md` | What order to build (dependency, no dates) | Every session, to find next task | Agent, with human approval on phase change |
| `benchmark.md` | The definition of done (parity vs frontier) | To know when v0 is complete | Agent, append measured results |
| `quality.md` | How to verify | Before declaring anything done | Agent, append test cases as discovered |
| `progress.md` | Where we are now | Every session, first | **Agent — you rewrite this every session** |

---

## 2. Hard constraints (non-negotiable)

These are the **moat**. Do not trade them away for speed, features, or
convenience. If a constraint blocks a task, surface the conflict explicitly
and ask — do not silently violate it.

1. **100% local by default.** No cloud audio. No telemetry to a server. No
   accounts. No login. (Cloud STT is a v1 *opt-in* escape hatch only.)
2. **Two OS permissions, no more**: Microphone + Accessibility. (The global-hotkey
   `CGEventTap` is `.defaultTap` → Accessibility-gated; Input Monitoring is NOT used
   in v0.) Onboarding must explain *why* each is needed and deep-link to System Settings.
3. **Swift 5.9+ / SwiftUI**, deployment target **macOS 26.0**,
   **Apple Silicon only** in v0.
4. **No third-party dependencies in v0.** Apple frameworks only. WhisperKit /
   Ollama arrive in v0.1+.
5. **Single Swift codebase.** No Rust core. No FFI. No cross-platform
   abstraction. (This debate is settled — see `architecture.md` §1 and
   `research/TECH_STACK_JUDGMENT.md` for why.)
6. **Never read the pasteboard** — only write to it. (macOS 26.4 paste
   protection.)
7. **Hardware mute impossible to bypass** — when muted, no audio is captured,
   period.
8. **v0 is the complete core, not a time-box.** v0 is done when `benchmark.md`'s
   MATCH gate and all BEAT rows pass — however many loop cycles that takes. No
   deadlines, no effort estimates, no hours anywhere in the docs.
9. **AI neat-writing is core, not optional.** The default cleanup engine is
   Apple's on-device `Foundation Models` (an Apple framework — does **not**
   violate the no-third-party-deps rule). Cleanup is pluggable (`LLMCleaning`);
   Ollama/MLX are later alternatives, never the default dependency.

---

## 3. Coding conventions (non-negotiable)

- **No `print`** for logging. Use `os.Logger` (OSLog) from day one. Define log
  categories in `SpeakCore/Logging/`.
- **No force-unwraps, no `try!`, no `as!`** in production code. Use `guard
  let` / `if let` / `throws`. Exceptions only in test code.
- **No global mutable state.** All state is owned by an actor or injected via
  SwiftUI environment.
- **Never block the main thread.** Audio on background queues; UI on
  `@MainActor`.
- **No `[weak self]` omissions** in long-lived closures.
- **Every public type has a real Swift signature**, not pseudocode.
- **Every "done when" is testable** (binary pass/fail).
- **Match the surrounding code**: comment density, naming, idiom. Read before
  you write.

---

## 4. The autonomous loop

You operate in **cycles**. Each cycle = pick → execute → verify → record.

```
┌─────────────────────────────────────────────────────────┐
│  1. Read progress.md → identify next task               │
│  2. Read the relevant docs/ for that task               │
│  3. Implement (code + tests together)                   │
│  4. Verify (compile, run tests, check done-when)        │
│  5. Update progress.md (done / blocked / next / notes)  │
│  6. Commit if verifiably complete                       │
└─────────────────────────────────────────────────────────┘
```

### When to ACT autonomously (no asking)

- Implementing a roadmap task whose dependencies are met and whose design is
  specified in `architecture.md`.
- Writing tests for code you just wrote.
- Fixing a bug you can reproduce, within the existing architecture.
- Updating `docs/progress.md` (always).
- Refactoring within a module without changing its public API.

### When to STOP and ask the human

- A `docs/` decision contradicts a primary source you can verify (surface it,
  don't paper over it).
- A hard constraint (§2) blocks progress.
- You need to change a public API in `architecture.md`.
- You need to change the roadmap (reorder phases, add/remove scope).
- A task's "done when" criterion is ambiguous and you can't resolve it from
  the docs.
- You're about to do something hard to reverse (delete user data, rewrite a
  module, change license).
- You've been blocked on the same task for 2 failed attempts.

**Rule of thumb**: act freely *within* the rails; ask before *moving* the
rails.

---

## 5. Conventions for `docs/progress.md`

This file is your working memory. Treat it as sacred — a lost `progress.md`
means a lost session. Rules:

- **Update it at the end of every work cycle**, not just at session end.
- Structure it as: `Current Phase` → `Done (this session)` → `In Progress` →
  `Blocked` → `Next Up` → `Decisions Logged` → `Open Questions`.
- **Be specific.** "Worked on hotkey" is useless. "`HotkeyMonitor` now detects
  double-tap Fn within 400ms window; flaky on external keyboards — see open
  question #3" is useful.
- **Log decisions with rationale.** Future-you (or another agent) needs to
  know *why*, not just *what*.
- **Keep open questions visible.** Don't let them rot in your head.
- **Never delete history** — append. If the file gets long, archive old
  entries to `docs/progress-archive.md` monthly.

---

## 6. Verification discipline

**Code is not done when it's written. Code is done when it's verified.**

Before marking any roadmap task complete:
1. **Compiles clean** — `xcodebuild build` exits 0, no warnings treated as
   errors.
2. **Tests pass** — new code has tests; all existing tests green.
3. **Done-when met** — the specific testable criterion from `roadmap.md` is
   satisfied (not "basically works").
4. **No regressions** — `progress.md` notes no new failures.
5. **Constraints honored** — re-read §2; confirm none violated.

If you can't verify (e.g., no mic access in CI), say so explicitly in
`progress.md` and flag the verification gap. Don't claim done what you can't
prove.

---

## 6b. Research methodology (how to find current truth)

The loop runs on a model with a knowledge cutoff. Every session, assume your
training knowledge about Apple frameworks, Swift packages, and AI APIs may be
wrong. The right response is not to guess — it is to research.

### The question to ask before every task

"What does this task require me to know that was released, changed, or updated
after mid-2025?"

High-risk domains (always verify):
- Any Apple framework mentioned in WWDC26 (Core AI, Foundation Models provider
  API, SpeechAnalyzer DictationTranscriber, AppIntents/App Schemas)
- Any third-party package pinned to a version (WhisperKit, MLX, FluidAudio)
- Any external API (Sarvam, Ollama) — endpoints, request format, pricing, models
- Any deprecation (SiriKit → AppIntents; CoreML → Core AI for LLM/generative work)

### The trust hierarchy

1. `swiftc -typecheck` against the local SDK — absolute ground truth
2. `apple-docs` MCP — official Apple docs, searchable by symbol
3. `[verified]` skill claim with source URL — trusted, but re-fetch if > 2 weeks old
4. Official GitHub README at the current release tag
5. WebSearch from `developer.apple.com` or official org repos
6. `[inferred]` skill claim — a hypothesis; verify before shipping it
7. Training memory — a starting point for searches, never a fact to ship

### Web search patterns that find authoritative sources

For Apple APIs:
- `"[SymbolName]" site:developer.apple.com`
- `WWDC26 [FrameworkName] developer.apple.com`
- `"import [FrameworkName]" swift macos26 2026`

For packages:
- WebFetch `github.com/<org>/<repo>/releases` → find latest tag → fetch README at that tag
- `[PackageName] swift [MethodName] site:github.com`

For services:
- WebFetch the `docs:` URL in the skill file directly (don't search; fetch)
- `[ServiceName] API documentation [year]`

### What to do with what you find

- Confirms a skill claim → change tag from `[inferred]` → `[verified from: <URL>]`
- Contradicts a skill claim → update the skill FIRST, then write the code
- Reveals something not in any skill → create a new skill before continuing
- Confirms nothing, all results inconclusive → tag claim `[unverified]`, log open
  question in `progress.md`, try `swiftc -typecheck` as final check

### What good research looks like (concrete example)

Task: implement WhisperKit STT (V01-1).
1. Read `whisperkitv1-stt` skill → notices `[inferred]` tags on streaming API shape
2. WebFetch `github.com/argmaxinc/WhisperKit/blob/main/README.md` → confirms init pattern
3. After SPM resolve: `swiftc -typecheck` with `import WhisperKit` → confirms symbol names
4. Updates skill: `[inferred]` → `[verified via README + swiftc, 2026-06-26]`
5. Now writes the code

This takes 5–10 minutes. It eliminates 2 failed build cycles and a wrong API
call buried in production code. The skill update means the next agent skips steps 1–4.

---

## 6c. Skill-creation protocol (how the loop compounds)

**When you solve a technical problem that required research or experimentation — a verified API shape, a workaround for a platform bug, an integration pattern that wasn't documented — encode it as a skill.**

### When to create a skill

- You verified an API shape via `swiftc -typecheck` or `apple-docs` that wasn't documented in an existing skill
- You found a workaround for a build/runtime issue that took more than 1 attempt
- You integrated a new third-party package and figured out the correct SPM setup
- You solved a problem that any future agent tackling the same seam would get wrong

### How to create a skill

1. Create `.claude/skills/<name>/SKILL.md` (kebab-case name matching the API/seam)
2. Write: architectural seam, hard constraints, API shape (tagged), verification commands
3. Tag EVERY claim: `[verified]` / `[inferred]` / `[unverified]` / `[decision]`
4. Add the skill name to the `skills:` list in the relevant agent's `.md` file in `.claude/agents/team/`
5. Add one line to `docs/agent-tooling.md` skill index under the appropriate section
6. Commit with `[skill] <name>: <what it encodes>`

### The compounding effect

Each skill reduces future agent cycles. A skill written once saves 2–3 verification cycles every time the seam is touched. After 10 loop cycles, the accumulated skills make the next 100 cycles faster. Skills are the mechanism by which the loop gets smarter, not just faster.

---

## 7. Commit discipline

- **Commit per completed roadmap task** (not per file, not per session).
- **Commit message format**: `[P<N>] <task short name>: <what changed>` —
  e.g., `[P2] audio capture: AVAudioEngine 16kHz mono, mic permission flow`.
- **Never commit broken code.** If tests fail, fix before committing.
- **Never commit secrets**, `.env`, credentials, or large binaries.
- **The agent commits autonomously** per the loop; the human reviews via git
  log, not per-commit approval.

---

## 8. When you're stuck

In order of escalation:
1. **Re-read the relevant `docs/` section.** The answer is usually there.
2. **Check `research/`** for the evidence behind the decision (only if a doc
   seems wrong).
3. **Verify the claim against a primary source** (Apple docs, GitHub repo).
4. **Log it as an open question in `progress.md`** and pick the next
   unblocked task.
5. **Ask the human** — only after 1–4 fail. Bring the question with context:
   what you tried, what you found, what you'd do if forced to decide.

---

## 9. The spirit of this project

`speak` is a **small, opinionated, native** Mac app. It does one thing
(dictate speech to text at the cursor) and does it privately, locally, and
for free. The moat is the three-way combination of **local + free + open**,
plus the **developer-first hotkey UX**. Wispr Flow cannot copy this without
abandoning its cloud revenue.

Push hard. Ship fast. Be opinionated. But never lose the moat — a faster
cloud dictation app is just another Wispr Flow. The constraints in §2 are the
product.

---

*End of operating manual. Now go read `docs/progress.md` and continue.*
