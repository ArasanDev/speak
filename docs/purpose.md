# `speak` — Purpose, Philosophy, and System Behavior

> **Status**: Living foundational document. Authority: defines the *why*, the human philosophy, the transformation contract, and the evaluation principles of `speak`.

---

## 1. The Core Philosophy: What Is Human Voice?

Human voice is the highest-bandwidth, most natural channel through which a human expresses complex intent:
- **Typing speed**: ~40 words per minute. High cognitive friction, constant editing, physical constraint.
- **Speaking speed**: ~150 words per minute. Direct tap into working memory and stream-of-consciousness thought.

However, spoken human thought has distinct characteristics:
1. **Exploratory & Non-Linear**: Humans often think aloud. They describe a problem, propose an approach, reject an alternative (*"wait, don't do that, do this instead"*), add context, recall a reference (*"like in T3 code"*), and specify fine-grained constraints.
2. **Acoustic & Disfluent**: Natural speech contains filler words (*"um"*, *"uh"*), stammering, repetitions, false starts, and acoustic slips that ASR models mishear (*"Delhi guitar"* for *"delegator"*, *"lines of coke"* for *"lines of code"*).
3. **Rich in Nuance & Architecture**: Inside the sprawling stream of words are exact numbers, file names, placements (*"settings in bottom-left corner"*), architectural rationale, and critical decisions.

---

## 2. The True Purpose of `speak`: Thought-to-Articulation

Existing speech systems make one of two opposite, catastrophic errors:
- **Error 1: The Raw Tape Recorder (Traditional ASR)**: Dumps raw, rambling, unpunctuated text with phonetically corrupted terms and stutters directly into the editor or terminal. The reader or receiving agent is overwhelmed with noise.
- **Error 2: The Aggressive Lossy Summarizer**: Treats dictation as a text-compression problem, throwing away 80% to 90% of what the speaker said to output a generic 1-sentence headline (*"Fix the side panel"*), completely erasing the user's specific designs, references, and reasoning.

### The `speak` Standard: High-Fidelity Articulation

`speak` is a **Thought-to-Articulation Engine**:

1. **100% Substance Fidelity**: Every stated decision, rejected alternative, file path, number, technical constraint, and architectural placement is **strictly preserved**. Nothing is dropped or summarized away.
2. **Complete Disfluency Dissolution**: False starts, throat-clearing preambles (*"Okay so basically what I want to tell is..."*), repetitions, stammers, and apologies (*"sorry"*) are cleanly excised.
3. **Grammatical & Structural Elevation**: Long run-on spoken clauses are transformed into beautifully articulated English. Where multiple steps, options, or requirements are dictated, `speak` structures them into logical paragraphs or clean bulleted lists.
4. **Deterministic Acoustic Lexicon Healing**: Resolves phonetic mishearings into correct developer and project terminology (*"Git repository"*, *"worktree"*, *"3B"*, *"800 lines of code"*).

---

## 3. Harnessing the On-Device 3B Model (4K Context Window)

We reject the false assumption that an on-device 3B model is weak or must be constrained to tiny outputs:
- On Apple Silicon with unified memory, the local 3B Foundation Model runs at **80–120 tokens/second**.
- It possesses a full **4K context window**.
- It is fully capable of **sophisticated grammatical reasoning, structural formatting, and high-fidelity articulation**.

We do not use the model to compress speech into a soundbite. We use the model to **elevate the speech into articulate, structured, professional prose and crisp directives**.

---

## 4. Architectural Behavior of the Application

To deliver instantaneous responsiveness without sacrificing full-thought articulation, `speak` operates across three deterministic tiers:

```
           ACTIVE SPEAKING                                     STOP
───────────────────────────────────────────────────────────────────────────►
 ┌───────────────┐ ┌───────────────┐ ┌───────────────┐     ┌───────────────┐
 │ Micro-Chunk 1 │ │ Micro-Chunk 2 │ │ Micro-Chunk 3 │ ... │ Trailing Text │
 │ (3–10 words)  │ │ (3–10 words)  │ │ (3–10 words)  │     └───────┬───────┘
 └───────┬───────┘ └───────┬───────┘ └───────┬───────┘             │
         │ (parallel)      │ (parallel)      │ (parallel)          │
         ▼                 ▼                 ▼                     │
   Scale 1: Live HUD Streaming & Acoustic Normalization            │
         │                 │                 │                     ▼
         └─────────────────┼─────────────────┴──────────────► Stitched Draft
                                                                   │
                                                                   ▼
                                                     Scale 3: Macro-Articulation Pass
                                                     (Full-Utterance Holistic Transformation
                                                      Grammar, Structure, Substance Fidelity)
                                                                   │
                                                                   ▼
                                                      High-Fidelity Output Pasted
```

1. **Scale 1 (Micro-Chunks, ~3–10 words)**: Progressive, real-time acoustic normalization and live streaming in the floating HUD overlay as the user speaks.
2. **Scale 2 (Medium Thought Units, ~20–35 words)**: Natural clause and sentence boundary tracking.
3. **Scale 3 (Full-Utterance Macro-Articulation Pass, whole turn)**:
   - Evaluates the stitched thought as a unified whole.
   - Resolves mid-sentence course corrections and train-of-thought exploration across the entire dictation.
   - Formats the output with pristine grammar, paragraphs, or bullet points matching the complexity of the spoken input.

---

## 5. The Verification Protocol: Personal, Creative Review

Automated scoring must never be used to declare false confidence or justify lossy truncation. Every evaluation is a creative discovery loop that requires **personal verification**:

1. **Substance Audit**: Compare the output against the raw dictation. Did any specific constraint, number, file name, or design detail get lost? If yes, the prompt or pipeline failed.
2. **Articulation Audit**: Is the language elevated, structured, and easy to read? Does it flow naturally?
3. **Disfluency Audit**: Are false starts, stammers, and conversational throat-clearing removed without touching the core thoughts?
4. **Actionability Audit**: Is the result immediately useful at the destination (e.g. in the Cursor terminal, editor, or document)?

---

*This document serves as the governing purpose for all prompt design, architecture decisions, and evaluation runs in `speak`.*
