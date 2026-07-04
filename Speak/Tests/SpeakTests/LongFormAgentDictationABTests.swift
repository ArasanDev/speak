// SpeakTests/LongFormAgentDictationABTests.swift
//
// Prompt-optimization research (2026-07-04 loop) — the "long-form agentic dictation"
// question: production's Agent system prompt currently hardcodes
// "Remove filler. 1-3 sentences maximum." (DefaultProfiles.agent.systemPrompt).
// That cap is tuned for terse micro-commands (the fix/shell/code/commit categories,
// which already enforce their own single-line output format via categoryFragment).
// It was never validated against genuinely long, dense, agentic-coding dictation:
// feature ideation, brownfield context-dumps, multi-step asks, debugging narratives,
// mid-task course-corrections — the actual medium this product exists for.
//
// This harness runs the SAME 5 realistic long-form fixtures through 3 candidate
// instructions on the real, live, on-device Foundation Models path (identical
// plumbing to FixABTests: same model, same greedy decoding, same XML wrap):
//
//   CURRENT      — production Agent system prompt + task category (nil fragment),
//                  i.e. exactly what ships today, including the 1-3 sentence cap.
//   DENSITY      — candidate: remove disfluency only (filler, false starts, repeats);
//                  preserve every stated reason, constraint, rejected alternative,
//                  and piece of context, regardless of length. No sentence cap.
//   STRUCTURED   — candidate: same density-preservation contract as DENSITY, but
//                  explicitly permitted to use light headers/numbered sub-asks when
//                  the speaker's content is itself structured (multiple distinct asks,
//                  a list of constraints) — tests whether restructuring helps or hurts
//                  agent-readability over plain preserved prose.
//
// Decision lens (same as FixABTests): read outputs for (a) information loss —
// did a stated constraint/reason/rejected-alternative silently disappear? (b)
// invention — did the model add anything the speaker did not say? (c) latency —
// user-reported "cleanup sometimes takes a long time"; longer inputs/instructions
// may cost meaningfully more wall-clock, worth knowing before shipping a change.
//
// Durable verdict: research/long-form-agent-dictation-review.md + verification-ledger.md.
//
// Gated behind SPEAK_EVAL=1 (set by the `Eval` scheme). Run explicitly:
//   SPEAK_EVAL=1 xcodebuild ... -scheme Eval test -only-testing:SpeakTests/LongFormAgentDictationABTests

import Foundation
import FoundationModels
@testable import SpeakCore
import XCTest

@available(macOS 26.0, *)
final class LongFormAgentDictationABTests: XCTestCase {

    // MARK: - Candidate instructions
    // All three share the identical preamble structure (base identity line +
    // preservation rule + "output ONLY the goal") so the ONLY variable under test
    // is the length/density contract — matching FixABTests' fairness discipline.

    private static let currentInstruction =
        FoundationModelsCleaner.instructions(for: .profile(DefaultProfiles.agent, level: .medium, category: .task))

    private static let densityInstruction = """
        You convert spoken developer dictation into a complete, precise instruction for a coding agent.
        Remove disfluency ONLY: filler words (um, uh), false starts, and repeated words or phrases.
        Preserve every stated reason, constraint, rejected alternative, and piece of context the speaker \
        gave — do not summarize, condense, or drop content to shorten the result. Length should match the \
        amount of real content in the input: a short dictation stays short, a long one stays long.
        Preserve every identifier, path, and technical term exactly as spoken.
        The agent has project context and tools — do not add what it can find itself, and do not add \
        anything the speaker did not say.
        Output ONLY the cleaned instruction.
        """

    private static let structuredInstruction = """
        You convert spoken developer dictation into a complete, precise instruction for a coding agent.
        Remove disfluency ONLY: filler words (um, uh), false starts, and repeated words or phrases.
        Preserve every stated reason, constraint, rejected alternative, and piece of context the speaker \
        gave — do not summarize, condense, or drop content to shorten the result. Length should match the \
        amount of real content in the input: a short dictation stays short, a long one stays long.
        If the speaker states multiple distinct, independent asks, present them as a numbered list. \
        Otherwise keep flowing prose — do not force structure onto a single continuous thought.
        Preserve every identifier, path, and technical term exactly as spoken.
        The agent has project context and tools — do not add what it can find itself, and do not add \
        anything the speaker did not say.
        Output ONLY the cleaned instruction.
        """

    /// DENSITY + an explicit retraction-preservation rule — a targeted 4th candidate added
    /// after the first live run showed BOTH CURRENT and DENSITY silently dropped a spoken
    /// "stop, don't do X" retraction (course-correction fixture). Tests whether one added
    /// rule fixes that specific failure without inheriting STRUCTURED's latency cost.
    private static let densityPlusRetractionInstruction = """
        You convert spoken developer dictation into a complete, precise instruction for a coding agent.
        Remove disfluency ONLY: filler words (um, uh), false starts, and repeated words or phrases.
        Preserve every stated reason, constraint, rejected alternative, and piece of context the speaker \
        gave — do not summarize, condense, or drop content to shorten the result. Length should match the \
        amount of real content in the input: a short dictation stays short, a long one stays long.
        If the speaker retracts, cancels, or says stop/don't/wait regarding something said earlier (in this \
        dictation or an implied prior one), that retraction is critical — state it explicitly and first, \
        never drop it silently.
        Preserve every identifier, path, and technical term exactly as spoken.
        The agent has project context and tools — do not add what it can find itself, and do not add \
        anything the speaker did not say.
        Output ONLY the cleaned instruction.
        """

    // MARK: - Fixtures
    // Deliberately NOT simple fix/review one-liners — long-form, rambling,
    // information-dense, mid-project (brownfield) developer monologues.

    private static let fixtures: [(name: String, spoken: String)] = [
        (
            "ideation",
            """
            okay so um I've been thinking about the history pane for a while now and I don't think \
            it's actually useful the way it is right now like it just shows a flat list of past \
            dictations and that's fine but that's not really what people want I think what people \
            actually want is to see patterns like which apps they dictate into the most and maybe \
            how much time they're saving compared to typing so I'm thinking we could add like an \
            insights view, not replacing history, in addition to it, and it would show like a weekly \
            summary, words dictated, time saved estimate, maybe top three apps, and I don't want this \
            to feel like a dashboard with a bunch of charts everywhere, that's not our vibe, I think \
            it should be like two or three numbers max and maybe one simple trend line, nothing fancy, \
            no pie charts please, and it should live in the existing history window not a new window, \
            maybe as a tab at the top, and it's fine if this is v1 and rough, I just want to see if \
            people even care about this before we polish it
            """
        ),
        (
            "brownfield-context",
            """
            so right now the way the profile engine resolves which profile to use is it just always \
            falls back to whatever the global default is, Write I think, unless you manually pick \
            something from the picker every single time, and that's kind of annoying because like if \
            I'm in Xcode all day I always want Agent mode and if I'm in Slack I basically always want \
            Write mode, and I remember there's already a PinnedContextStore thing that got built for \
            this, I think it was for the PE-3.2 pin to context task, but I don't think it's actually \
            wired up to anything yet, so what I want is when a dictation starts, check if there's a \
            pinned profile for the current frontmost app, and if there is use that instead of the \
            global default, but only as a fallback, if the user explicitly picked a different profile \
            for this one dictation that should still win, pinning is just for the default not an \
            override of an explicit in-session choice
            """
        ),
        (
            "multi-step-out-of-order",
            """
            alright a few things, first the re-clean button, right now it re-runs cleanup on the last \
            raw transcript but it doesn't reset the knobs, so if I had set tone to casual for that \
            dictation it stays casual on re-clean even if I changed the picker afterward, that's a bug, \
            it should use whatever the knobs currently say not what they said originally, oh and \
            separately, actually before that, can you also check why the cancel button sometimes \
            doesn't dismiss the overlay, I noticed it like twice yesterday, might be a race with the \
            panel animation, and then third thing, the settings window, the AI studio tab, the few shot \
            examples editor, when you delete an example it doesn't ask for confirmation, that's risky \
            because there's no undo, so add a confirmation there, that one's low priority compared to \
            the other two, do the knobs bug first since that's the one actually breaking behavior
            """
        ),
        (
            "debugging-narrative",
            """
            so I dictated something in Terminal earlier and the paste just didn't happen at all, no \
            error, nothing, and I tried it again right after and it worked fine, so it's intermittent \
            which is the worst kind, my guess, and I could be totally wrong, is that it's related to \
            the caret locator, because I remember the overlay didn't show up either that first time, \
            so maybe CaretLocator returned nil, and if it's nil maybe something downstream is bailing \
            out of the whole paste path instead of just skipping the overlay positioning, like it \
            should still fall back to pasting even without a caret position, the overlay is cosmetic \
            it shouldn't gate the actual paste, can you go look at where CaretLocator's result gets \
            consumed and check if there's a silent early return somewhere when it's nil, I haven't \
            looked at the code myself yet so I don't actually know if that's right, just go investigate \
            and tell me what you find before changing anything
            """
        ),
        (
            "course-correction",
            """
            wait actually stop, don't implement the caching layer the way I described it in the last \
            dictation, I was thinking about it more and caching the cleaned output keyed by raw \
            transcript text is going to be basically useless because nobody dictates the exact same \
            sentence twice, that's not the actual latency problem, the actual problem is probably that \
            we're spinning up a new LanguageModelSession every single time instead of reusing one, so \
            instead what I want is investigate whether SessionCreation itself is the slow part, like \
            actually measure it, log the timestamp before creating the session and after, separately \
            from the response time, and only if session creation turns out to be a meaningful chunk of \
            the total latency should we look at reusing a session across dictations, don't just assume \
            it and build the reuse thing, measure first
            """
        )
    ]

    func testLongFormAgentDictationLive() async throws {
        guard ProcessInfo.processInfo.environment["SPEAK_EVAL"] == "1" else {
            throw XCTSkip("Set SPEAK_EVAL=1 (Eval scheme) to run the live long-form A/B/C. Skip ≠ pass.")
        }

        let model = SystemLanguageModel(useCase: .general, guardrails: .permissiveContentTransformations)
        guard case .available = model.availability else {
            throw XCTSkip("Foundation Models not available on this device. Skip ≠ pass.")
        }
        let options = GenerationOptions(sampling: .greedy)

        func clean(_ text: String, with instruction: String) async throws -> (output: String, seconds: Double) {
            let session = LanguageModelSession(model: model, instructions: Instructions(instruction))
            let wrapped = FoundationModelsCleaner.wrapTranscript(text)
            let start = DispatchTime.now()
            let response = try await session.respond(to: Prompt(wrapped), options: options)
            let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000_000
            return (response.content.trimmingCharacters(in: .whitespacesAndNewlines), elapsed)
        }

        print("LONGFORM::BEGIN")
        for fixture in Self.fixtures {
            print("LONGFORM::CASE \(fixture.name)")
            print("LONGFORM::RAW_WORDS \(fixture.spoken.split(separator: " ").count)")

            let current = try await clean(fixture.spoken, with: Self.currentInstruction)
            print("LONGFORM::CURRENT_WORDS \(current.output.split(separator: " ").count)")
            print("LONGFORM::CURRENT_SECONDS \(current.seconds)")
            print("LONGFORM::CURRENT_TEXT \(current.output.replacingOccurrences(of: "\n", with: "\\n"))")

            let density = try await clean(fixture.spoken, with: Self.densityInstruction)
            print("LONGFORM::DENSITY_WORDS \(density.output.split(separator: " ").count)")
            print("LONGFORM::DENSITY_SECONDS \(density.seconds)")
            print("LONGFORM::DENSITY_TEXT \(density.output.replacingOccurrences(of: "\n", with: "\\n"))")

            let structured = try await clean(fixture.spoken, with: Self.structuredInstruction)
            print("LONGFORM::STRUCTURED_WORDS \(structured.output.split(separator: " ").count)")
            print("LONGFORM::STRUCTURED_SECONDS \(structured.seconds)")
            print("LONGFORM::STRUCTURED_TEXT \(structured.output.replacingOccurrences(of: "\n", with: "\\n"))")
        }
        print("LONGFORM::END")
    }

    /// Targeted follow-up: does adding an explicit retraction-preservation rule to DENSITY
    /// fix the silent-drop failure the first live run exposed, without the STRUCTURED
    /// latency cost? Single fixture, single candidate — cheap to rerun.
    func testDensityPlusRetractionFixesCourseCorrection() async throws {
        guard ProcessInfo.processInfo.environment["SPEAK_EVAL"] == "1" else {
            throw XCTSkip("Set SPEAK_EVAL=1 (Eval scheme) to run live. Skip ≠ pass.")
        }
        let model = SystemLanguageModel(useCase: .general, guardrails: .permissiveContentTransformations)
        guard case .available = model.availability else {
            throw XCTSkip("Foundation Models not available on this device. Skip ≠ pass.")
        }
        let options = GenerationOptions(sampling: .greedy)
        guard let fixture = Self.fixtures.first(where: { $0.name == "course-correction" }) else {
            XCTFail("course-correction fixture missing")
            return
        }

        let session = LanguageModelSession(model: model, instructions: Instructions(Self.densityPlusRetractionInstruction))
        let wrapped = FoundationModelsCleaner.wrapTranscript(fixture.spoken)
        let start = DispatchTime.now()
        let response = try await session.respond(to: Prompt(wrapped), options: options)
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000_000
        let output = response.content.trimmingCharacters(in: .whitespacesAndNewlines)

        print("RETRACTIONCHECK::SECONDS \(elapsed)")
        print("RETRACTIONCHECK::WORDS \(output.split(separator: " ").count)")
        print("RETRACTIONCHECK::TEXT \(output.replacingOccurrences(of: "\n", with: "\\n"))")
    }

    /// Final sanity check on the ACTUAL production path (system prompt + few-shot examples,
    /// via FoundationModelsCleaner.instructions) after the systemPrompt edit — the harder
    /// candidates above tested the instruction in isolation, but few-shot examples are "the
    /// strongest steering lever for a small model" (PromptBuilder header comment), and
    /// DefaultProfiles.agent's two examples are both short. This confirms they don't drag
    /// long-form output back toward brevity now that the length cap is gone from the prompt.
    func testProductionPathPreservesLengthOnHardCases() async throws {
        guard ProcessInfo.processInfo.environment["SPEAK_EVAL"] == "1" else {
            throw XCTSkip("Set SPEAK_EVAL=1 (Eval scheme) to run live. Skip ≠ pass.")
        }
        let model = SystemLanguageModel(useCase: .general, guardrails: .permissiveContentTransformations)
        guard case .available = model.availability else {
            throw XCTSkip("Foundation Models not available on this device. Skip ≠ pass.")
        }
        let options = GenerationOptions(sampling: .greedy)
        let instruction = FoundationModelsCleaner.instructions(
            for: .profile(DefaultProfiles.agent, level: .medium, category: .task)
        )

        for name in ["ideation", "course-correction"] {
            guard let fixture = Self.fixtures.first(where: { $0.name == name }) else { continue }
            let session = LanguageModelSession(model: model, instructions: Instructions(instruction))
            let wrapped = FoundationModelsCleaner.wrapTranscript(fixture.spoken)
            let start = DispatchTime.now()
            let response = try await session.respond(to: Prompt(wrapped), options: options)
            let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000_000
            let output = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            print("PRODCHECK::CASE \(name)")
            print("PRODCHECK::SECONDS \(elapsed)")
            print("PRODCHECK::WORDS \(output.split(separator: " ").count)")
            print("PRODCHECK::TEXT \(output.replacingOccurrences(of: "\n", with: "\\n"))")
        }
    }
}
