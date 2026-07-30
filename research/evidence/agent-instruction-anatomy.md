# Research — The Anatomy of an Effective Instruction TO a Coding Agent (per category)

> **Research header** — Question: "what should a ~3B Apple Foundation Models cleanup
> model emit, per category, so the downstream coding agent succeeds?" · Date:
> 2026-06-30 · Status: **evidence** (cited by `AGENTS.md`)

> **Status**: read-only evidence (`research/`). Does NOT edit specs/, prompts, or
> fixtures. Feeds SM-2 (#50, Agent-mode prompt optimization) and the eval harness.
> **Date**: 2026-06-30. **Author frame**: every finding below is bound to one
> question — *what should a small (~3B) Apple Foundation Models cleanup model EMIT
> so that the downstream coding agent (Claude Code / Cursor / Aider) succeeds?*
> Findings that wouldn't change a `PromptBuilder.categoryFragment` are cut.

---

## 0. The frame, stated once (read before the rest)

speak's **Agent** destination does not write code and does not answer questions.
It transforms dictated speech → **a well-formed natural-language instruction FOR a
coding agent**, and that transform runs on a **~3B on-device model** (`profile-
engine.md §6`). So:

- **"Quality" = downstream-agent success, not good prose.** A finding only counts
  if it changes what instruction the model should emit *because that makes the
  agent do the right thing*. Example: the `ask` fragment's "do not convert to a
  task" rule is not style — if a question becomes a task, the downstream agent
  starts *editing code* instead of *explaining*. Every good finding has that shape.
- **The model PRESERVES specificity; it cannot INVENT it.** Every web source below
  ("be specific: name the file, the edge case, the acceptance test") is written for
  a *human* composing an instruction, or for a *frontier* model receiving one. Our
  model is neither. It must not fabricate a file path, a test case, or an error
  message the speaker never said — that is hallucination, and it poisons the
  downstream agent with false context. The implication inverts the generic advice:
  **our prompts should command faithful preservation of any specifics the speaker
  *did* utter (paths, identifiers, numbers, error strings), and forbid inventing
  ones they didn't.** [inferred]
- **Two structural classes of genre** (this split drives "output shape" below):
  - **Artifact genres — Commit, Shell, Code**: the output IS the final text, pasted
    and used verbatim. The model is a transcriber/formatter, not a reasoner. There is
    one right string → the eval scores these `equalsExpected` (exact match). Failure
    = prose / markdown fences / wrong case leaking in. [verified — `eval-fixtures.json`
    marks code+shell `equalsExpected`; `EvalScoring.evaluateFixture` forces exact match]
  - **Instruction genres — Task, Fix, Ask**: the output is an NL instruction the
    agent then acts on. Scored by Jaccard ≥ 0.80 + format checks, not exact match
    [verified — `EvalScoring.swift` `correctnessThreshold: 0.80`]. This is where
    "include acceptance criteria / exclude prescribed implementation" has teeth.

  This maps onto small-model rule 5 ("deterministic formatting beats reasoning",
  `profile-engine.md §6`): artifact genres lean fully on rule 5; instruction genres
  still need a little structure but tolerate Jaccard wobble.

**Doc-version note (so the reader isn't confused):** `specs/profile-system-prompts.md`
describes the *older* 7-profile taxonomy (Clean / Chat / Code / CLI / Prompt / Commit).
That is superseded by the shipped **4-destination + 6-category** model. The authority
for "what the model is told today" is the code: `SpeakCore/Profiles/DefaultProfiles.swift`
(`agent` base prompt) + `PromptBuilder.categoryFragment(_:)` (the six fragments). Every
proposed delta in §3 is anchored to that code, never to the old spec doc.

---

## 1. Executive summary — cross-category principles of a good agent instruction

1. **Specificity drives success — but for us that means PRESERVE, not GENERATE.**
   Anthropic and Cursor both show the same jump: `"add tests for auth.ts"` →
   `"write a test for foo.py covering the edge case where the user is logged out.
   avoid mocks."` [verified — code.claude.com, cursor.com]. Our model can only carry
   forward the specifics the speaker spoke; it must never manufacture them.
2. **Name the location.** Good instructions point at files/areas (`src/auth/`,
   `ExecutionFactory`, `HotDogWidget.php`). The model must transcribe spoken
   identifiers/paths *exactly* — already the Agent base prompt's first rule. [verified]
3. **Describe the outcome and constraints; don't prescribe the implementation.**
   Anthropic's fix example ends "address the root cause, **don't suppress the
   error**" — a constraint, not a prescribed patch. [verified — code.claude.com]
4. **Give the agent a way to verify ("what 'fixed' looks like").** Anthropic's
   single strongest lever: embed a check — a test case, expected output, "write a
   failing test that reproduces the issue, then fix it." [verified — code.claude.com]
   For us: *preserve any acceptance criterion the speaker stated*; don't invent one.
5. **One unit of work per instruction.** Cursor: "one logical unit of work per
   conversation." Aider: "break your goal down into bite sized steps … do them one
   at a time." [verified] → for multi-item dictations, a numbered list keeps the
   units separable for the agent.
6. **Match the genre's mood.** Tasks & fixes are imperative ("Add…", "Fix…");
   asks are interrogative ("How…?"); commits are imperative summaries; shell/code
   are literal. Mood collision is the dominant failure (a fix phrased as a passive
   report, a question rewritten as a task).
7. **The speak-specific guard that none of the web sources need: "rewrite, don't
   execute."** Every external guide assumes the recipient SHOULD act. Our model is
   the *composer*, so the Agent base prompt's "Do NOT perform the task — only
   rewrite it" is load-bearing and must survive every category fragment. The two
   genres that most tempt a small model to break it are **Ask** (answer the
   question) and **Fix** (solve the bug). [inferred, repo-grounded by the SM-2
   `[decision]` comments in `categoryFragment`]
8. **Strip dictation noise, keep technical tokens.** Remove "um/uh/like/you know"
   and conversational scaffolding; never reword an identifier, flag, path, or number.
   [verified — Agent base prompt; corroborated by Aider "too much irrelevant code
   will distract and confuse the LLM" — noise hurts the downstream agent.]
9. **Output contract is non-negotiable for a small model.** "Output ONLY the result
   — no preamble, no quotes, no explanation." Small models chatter; chatter pasted
   into a terminal/agent is a defect. [verified — `profile-engine.md §6` rule 4]
10. **House style ≠ external spec — flag where we add rules the spec doesn't.**
    e.g. Conventional Commits v1.0.0 does *not* mandate lowercase type or 50/72
    limits ("Any casing may be used"). Our lowercase rule is a deliberate house
    `[decision]`, and the doc should say so rather than imply the spec requires it.
    [verified — conventionalcommits.org v1.0.0]

---

## 2. Per-category anatomy

For each genre: ideal shape · 3 `spoken → ideal cleaned` examples (realistic Mac-dev
dictations, written to PASS the existing eval checks so they're drop-in fixture seeds)
· top failure modes. Current shipped fragment quoted from `PromptBuilder.categoryFragment`.

### 2.1 Task — "Implement / refactor / add a feature" (instruction genre, default)

**Current fragment:** `"Focus on a concrete implementation task or refactoring request."`

**Ideal shape:** one imperative summary line; if the speaker enumerated multiple
deliverables, a numbered list (one work-unit per line); preserve every named file,
identifier, and any acceptance criterion the speaker stated ("…and write a test for
it", "…it should return 404 on miss"); exclude conversational framing; **invent
nothing**. Output is prose, not code. Anchored to Anthropic's "Scope the task" /
"Reference existing patterns" rows and Cursor's specificity contrast. [verified]

**Examples (drop-in fixture seeds):**
- spoken: `okay so um add a retry with exponential backoff to the network client and like cap it at five retries`
  → `Add retry with exponential backoff to the network client, capped at 5 retries.`
- spoken: `i need you to first extract the parsing logic into its own function and then uh add a unit test that covers the empty input case`
  → multi-unit → numbered:
  ```
  1. Extract the parsing logic into its own function.
  2. Add a unit test covering the empty-input case.
  ```
- spoken: `refactor the user service to use the repository pattern like we do in order service`
  → `Refactor UserService to use the repository pattern, following OrderService.`

**Top failure modes:**
- **Model answers/implements instead of rewriting** (writes the code). Guard: base
  prompt's "Do NOT perform the task."
- **Collapses a multi-deliverable dictation into one run-on line**, fusing separable
  work-units the agent should tackle one at a time. Guard: numbered-list rule.
- **Invents specificity** (a file name or test case never spoken) → false context.
- **Drops a stated acceptance criterion** ("…and it must be idempotent"), removing the
  agent's verification target.

### 2.2 Fix — "Fix a broken thing" (instruction genre) ⚠ highest-leverage delta

**Current fragment:** `"Output ONLY a structured bug report: state what is broken and
where. Do not propose a fix or suggest a solution."`

**This fragment is wrong for the genre, and the repo already disagrees with itself.**
The `fix` *fixture* expects an **imperative** — `"Fix the bug in capture session
where paste only works the first time."` [verified — `eval-fixtures.json`] — not a
passive bug report. Anthropic's own fix exemplars are imperative too: `"the build
fails with this error: [error]. **fix it** and verify the build succeeds. address the
root cause, don't suppress the error"`; and `"users report that login fails after
session timeout. check the auth flow in src/auth/… write a failing test that
reproduces the issue, then fix it"`. [verified — code.claude.com, 2026]

The SM-2 author's *intent* (per the `[decision SM-2]` comment) was sound — stop the
small model from **pre-solving / prescribing the patch** ("structure clearly" had made
it propose solutions). But the wording overshot: it banned *being an instruction at
all* and demoted the output to a report. The correct target keeps the imperative and
forbids only the *prescribed implementation*. See §3 for the delta.

**The contradiction is live in the repo today, not hypothetical:** the shipped fragment
("bug report") and the shipped `fix` fixture (imperative "Fix the bug…") are mutually
inconsistent right now — a correctly-formatted bug-report output would diverge in mood
from the expected imperative, so the fixture is passing (if at all) only on Jaccard
token overlap, not on producing the intended shape. That is harder evidence than the
Anthropic exemplars: one of the two repo artifacts is already wrong.

**Ideal shape:** imperative "Fix …" + the **symptom** (what's broken, ideally the
exact error string if spoken) + the **location** (file/component if spoken). Optionally
preserve a reproduction or "fixed looks like" cue the speaker gave. Do **not** prescribe
*how* to fix it (no invented root cause, no patch). Mood = imperative.

**Examples (drop-in fixture seeds):**
- spoken: `fix the bug in capture session where paste only works the first time`
  → `Fix the bug in CaptureSession where paste only works on the first dictation.`
- spoken: `uh the build is failing with cannot find type profile store in scope after the rename`
  → `Fix the build failure "cannot find type ProfileStore in scope" after the rename.`
- spoken: `the overlay flickers when you stop recording really fast twice in a row`
  → `Fix the overlay flicker that occurs when recording is stopped twice in quick succession.`

**Top failure modes:**
- **Pre-solving** — model invents and prescribes a root cause/patch the speaker never
  diagnosed (the SM-2 fear; legitimate). Guard: "do not prescribe the implementation."
- **Mood collapse to a passive report** — the *current* fragment's bug (`"X is
  broken"` instead of `"Fix X"`), which strips the actionable verb the agent keys on.
- **Inventing an error string or file** not spoken → false lead for the agent.

### 2.3 Ask — "Explain / how / why" (instruction genre)

**Current fragment:** `"Output ONLY the question. Keep the exact question word from the
input (How, What, Why, etc.) — do not rephrase it. End with '?'. Do not convert to a
task or instruction."`

**Ideal shape:** a single, clean interrogative. Preserve the speaker's question intent
and any named symbol/file. End with `?`. The critical guard is genre-preservation:
keep it a *question* so the agent *explains* rather than *edits*. Anchored to
Anthropic's "Ask codebase questions" examples: `"How does logging work?"`, `"Why does
this code call foo() instead of bar() on line 333?"`, `"What edge cases does
CustomerOnboardingFlowImpl handle?"`. [verified — code.claude.com]

**Examples (drop-in fixture seeds):**
- spoken: `uh how do i make the session restart automatically when recording fails`
  → `How do I make the session restart automatically when recording fails?`
- spoken: `why does capture session call run cleanup before paste instead of after`
  → `Why does CaptureSession call runCleanup before paste instead of after?`
- spoken: `what's the best way to add a custom vocabulary list to the cleanup pipeline`
  → `What's the best way to add a custom vocabulary list to the cleanup pipeline?`

**Top failure modes:**
- **Genre flip to a task** — small models default the Agent profile to imperative
  ("Add a session restart…"), making the agent *act* instead of *explain*. The single
  most important guard for this genre. [verified — `[decision SM-2]` comment]
- **Over-rigid question-word rule.** The fragment forbids rephrasing the question word.
  This is right for guarding intent ("what's the best way" must not silently become
  "how do I") but note Anthropic's accepted forms include "Why does X instead of Y" —
  the constraint should protect *intent*, not freeze surface wording. Low-priority
  watch item, not a confirmed bug. [inferred]
- **Answering the question** (model explains OAuth instead of emitting the question) —
  caught by base "Do NOT perform" + "Output ONLY the question."

### 2.4 Commit — "Conventional Commits message" (artifact genre)

**Current fragment:** `"Output ONLY a Conventional Commits message: type:
imperative-summary (lowercase type). Types: fix, feat, docs, refactor, test, chore.
Examples: 'fix: paste fails on retry' | 'docs: add spec'. No prose, no preamble."`

**Ideal shape (per Conventional Commits v1.0.0):** `<type>[optional scope]:
<description>`, optional blank-line body. [verified — conventionalcommits.org v1.0.0].
`feat`/`fix` are the only spec-mandated types; `docs`/`refactor`/`test`/`chore` come
from the Angular/`@commitlint` recommended set — our list is correct and standard.
**House-style note:** v1.0.0 says *"Any casing may be used"* and does NOT mandate the
50/72 char rule — so our lowercase-type requirement is a deliberate `[decision]`, not a
spec rule. The fragment is well-tuned (inline examples + lowercase per empirical SM-2
findings that the model capitalised "Fix:"). Output IS the commit text, verbatim.

**Examples (drop-in fixture seeds):**
- spoken: `um i fixed the bug where the paste wasn't working after the first dictation`
  → `fix: paste not working after first dictation`
- spoken: `added the new profile engine spec and the system prompts`
  → `docs: add profile engine spec and system prompts`
- spoken: `refactored the prompt builder to append category fragments only for the agent profile`
  → `refactor: append category fragments only for Agent profile`

**Top failure modes:**
- **Capitalised type** (`Fix:`), **wrong/invented type**, or a **prose sentence**
  instead of a commit line (markdown, "Here's a commit:"). Guards present.
- **Over-long first line / pasted body when none was dictated** (model padding).

### 2.5 Shell — "Single terminal command" (artifact genre)

**Current fragment:** `"Output ONLY the exact shell command — no prose, no explanation,
no trailing punctuation. Combine single-char flags (e.g. -a -l → -la). Translate:
'all/hidden files' → '-a', 'long format' → '-l', 'commit everything with message X' →
'git commit -am \"X\"'."`

**Ideal shape:** exactly one runnable command, no prose, no fences, no trailing period.
Map spoken intent → flags; combine single-char flags; preserve paths/args verbatim.
Output IS the command, pasted into a terminal → scored `equalsExpected`. The explicit
flag-mapping hints are the right small-model lever (a 3B won't reliably infer `-la`
from "all files in long format" without them). [verified — `eval-fixtures.json`
`ls -la`, `git commit -am "…"`]

**Examples (drop-in fixture seeds):**
- spoken: `uh list all the files including hidden ones in long format`
  → `ls -la`
- spoken: `git commit everything with the message fix the paste bug`
  → `git commit -am "fix the paste bug"`
- spoken: `show me the last twenty lines of the build log`
  → `tail -n 20 build.log`  *(note: only safe if "build log" → a path is conventional;
  otherwise the model should keep the speaker's exact words — flag for fixture review)*

**Top failure modes:**
- **Prose or explanation** wrapping the command; **markdown fences**; **trailing
  punctuation** that breaks the paste. Guards present.
- **Un-combined flags** (`ls -a -l`) or **dropped flags** (omitting `-m`). The hints
  exist precisely because these were observed empirically. [verified — SM-2 comment]
- **Inventing a path/filename** the speaker didn't say (the `build.log` risk above).

### 2.6 Code — "Literal code — convert notation to syntax" (artifact genre)

**Current fragment:** `"Output ONLY the raw code — no prose, no sentences, no markdown
fences, no spaces around parentheses. Use camelCase identifiers (userName, not
user_name). Translate all notation: 'equals' → '=', 'open paren' → '(', 'close paren'
→ ')', 'dot' → '.', 'dot dot dot' → '...'. Output ALL lines and ALL parts of the
expression."`

**Ideal shape:** literal source code, verbatim notation translation, no fences, no
prose, all statements present. Output IS code, pasted into an editor → `equalsExpected`.
This is the most rule-bound genre; every clause traces to an empirically observed
small-model failure (added ``` fences, snake_case, truncation after line 1). [verified —
SM-2 comment + `eval-fixtures.json` `userName = getCurrentUser()`].

**Examples (drop-in fixture seeds):**
- spoken: `set user name equals get current user open paren close paren`
  → `userName = getCurrentUser()`
- spoken: `import the os module and then call logger dot info`
  → `import os` + newline + `logger.info(...)`
- spoken: `if count greater than zero then return true`
  → `if count > 0 { return true }`  *(language-shape risk — see failure modes)*

**Top failure modes:**
- **Markdown fences / prose** around the code. Guard present ("no markdown fences").
- **snake_case** where camelCase wanted; **spaces around parens**; **truncation** of
  multi-statement expressions after the first line. All explicitly guarded.
- **Language ambiguity** — "if … then return true" has no single right string across
  Swift/Python/JS; the `equalsExpected` scorer can only match one. Risk: code genre may
  need a language hint (from `AppContext`/current file) to be fairly scorable. Flag for
  SM-2 / fixture design. [inferred]

---

## 3. Implications for our small-model category fragments (PROPOSED deltas — NOT applied)

Each anchored to `PromptBuilder.categoryFragment`. Ordered by leverage. **Not applied —
SM-2 (#50) owns the edit + must re-run `make eval` to confirm no regression.**

**D1 (highest leverage) — Rewrite the `fix` fragment from "bug report" to "imperative
fix instruction, no prescribed implementation."** The current fragment contradicts both
the `fix` fixture (imperative) and Anthropic's fix exemplars, and demotes the output
from an instruction to a passive report. Preserve the SM-2 anti-pre-solving intent by
banning the *implementation*, not the *imperative*.
- Current: `"Output ONLY a structured bug report: state what is broken and where. Do
  not propose a fix or suggest a solution."`
- Proposed: `"Output ONLY an imperative fix instruction: start with 'Fix', state the
  symptom (and the exact error text if given) and where it occurs (file/component if
  given). Do not diagnose the root cause or prescribe how to fix it. No preamble."`
- Why it makes the agent succeed: the agent keys on the actionable verb + symptom +
  location to locate and repair; a passive report makes it ask "do you want me to fix
  this?" Verify against the existing `fix` fixture (should now match cleanly).
- **Caveat — this delta reverses an empirically-grounded SM-2 decision.** The
  `[decision SM-2]` comment records that imperative phrasing *empirically* made the 3B
  propose solutions; D1 returns to imperative + a prohibition clause and bets the
  prohibition restrains the model. That is an unproven bet — the prior finding is direct
  evidence it might not hold. The burden is on the reworded fragment to PASS eval on the
  live on-device model; do not treat the reasoning here as sufficient.

**D2 — Strengthen the `task` fragment to preserve enumeration + stated acceptance
criteria.** Current fragment is a bare topic hint; it doesn't tell the model to keep a
numbered list or carry a spoken test/criterion.
- Current: `"Focus on a concrete implementation task or refactoring request."`
- Proposed: `"Output an imperative task. Start with a one-line summary. If the speaker
  lists multiple deliverables, output a numbered list (one per line). Preserve every
  named file, identifier, number, and any acceptance criterion the speaker states
  (e.g. 'write a test for it'). Add nothing not spoken."`
- Why: keeps separable work-units the agent can do one-at-a-time (Cursor/Aider) and
  preserves the verification target the agent self-checks against (Anthropic).

**D3 — Add a cross-fragment "preserve, never invent" guard for the instruction genres
(task/fix/ask).** No current fragment forbids fabricating paths/identifiers/errors —
the dangerous small-model failure that feeds the agent false context. Could live in the
Agent base prompt so all categories inherit it.
- Proposed clause (base prompt or per-instruction-fragment): `"Use only the file names,
  identifiers, numbers, and error text the speaker actually said — never invent or guess
  any."`
- Why: a hallucinated `src/auth/token.swift` sends the agent editing a file that
  doesn't exist. This is the inversion of generic "be specific" advice for a *composer*
  model.

**D4 — Annotate the `commit` fragment's lowercase rule as house-style, and confirm the
type list.** No prompt change to behavior; a `[decision]` comment update so future
editors know v1.0.0 permits any casing and our lowercase is deliberate (avoids someone
"fixing" it to match the spec and regressing the fixtures). Optionally allow a scope:
`type(scope): summary` since the spec supports it and devs dictate scopes. [verified]

**D5 — Give the `code` genre a language signal (or document the scorer limitation).**
`equalsExpected` can only match one language's surface form; "if x then return true" is
unscorable across languages. Either (a) inject the language from `AppContext`/current
file into the code fragment, or (b) restrict code fixtures to notation-translation cases
that are language-stable (assignment, calls, imports) and document the limit. [inferred]

---

## 4. Sources (every claim → URL + date)

- **Anthropic — Best practices for Claude Code.** https://code.claude.com/docs/en/best-practices
  (accessed 2026-06-30). Per-strategy Before/After tables: "Scope the task" (`add tests
  for foo.py` → `write a test for foo.py covering the edge case where the user is logged
  out. avoid mocks.`), "Describe the symptom"/"Address root causes" (the fix exemplars),
  "Provide verification criteria", "Ask codebase questions" (the ask exemplars),
  "Reference existing patterns", the four-phase explore→plan→code→commit workflow.
- **Cursor — Best practices for coding with agents.** https://cursor.com/blog/agent-best-practices
  (published 2026-01-09). Vague-vs-specific contrast (`add tests for auth.ts` → detailed
  form), "one logical unit of work per conversation", outcome+constraints over prescribed
  steps, "ask for plans / push back".
- **Aider — Tips.** https://aider.chat/docs/usage/tips.html (accessed 2026-06-30).
  "Just add the files that need to be edited. Too much irrelevant code will distract and
  confuse the LLM"; `/ask` plan → "go ahead" execute split; "break your goal down into
  bite sized steps … do them one at a time."
- **Conventional Commits v1.0.0.** https://www.conventionalcommits.org/en/v1.0.0/
  (accessed 2026-06-30). Structure `<type>[optional scope]: <description>` + body/footer;
  `feat`/`fix` mandated; `docs/refactor/test/chore/…` from `@commitlint`/Angular; "Any
  casing may be used" (no lowercase or 50/72 mandate); `BREAKING CHANGE:`/`!`.
> Note: every URL above was fetched and read. Three further sources surfaced in web
> search but were NOT opened (Anthropic platform "prompting best practices" page; a
> dbreunig system-prompts post; an arXiv "behavioral drivers of coding agent success"
> PDF). They are deliberately omitted here — no claim or delta in this doc depends on
> them, and project convention is cite-what-you-read, not cite-from-a-snippet.

---

## 5. The single biggest risk / uncertainty

**All external "good instruction" evidence is for the wrong actor — a frontier model
*receiving* an instruction, or a human *writing* one — and the strongest advice ("be
specific: name the file, the test, the error") is a hazard when transplanted onto a 3B
model *composing* the instruction, because the model can only fabricate that specificity,
not retrieve it.** So the highest-value direction (D1–D3) is partly *inverted* from the
literature: command faithful PRESERVATION and forbid INVENTION, rather than push for
more detail. This is a judgment that the eval harness can only partially test —
`equalsExpected`/Jaccard catch format and wording drift, but **no current fixture
checks for hallucinated specifics** (an invented file path would still score well on
Jaccard if most tokens overlap). Recommend SM-2 add adversarial fixtures: a terse
dictation whose *expected* output is equally terse, failing any run that adds unspoken
paths/identifiers/error strings. Until that exists, the "preserve, don't invent" guard
(D3) is asserted by reasoning, not measured. [inferred]
