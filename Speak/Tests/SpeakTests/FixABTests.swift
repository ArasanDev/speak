// SpeakTests/FixABTests.swift
//
// SM-2 Phase 2 / D1 — the `fix` category A/B, decided by READING outputs, not Jaccard.
//
// Two candidate fix fragments are scored on the SAME live Foundation Models path
// over the same fix-style spoken inputs. Only the category fragment differs; the
// surrounding production prompt (agent system prompt + guard + few-shot + greedy
// decoding + XML wrap) is byte-identical between A and B.
//
// RESULT (decided): A is the SHIPPED imperative fragment; B is the bug-report alternative
// it beat. Kept rerunnable so the A/B reproduces against production.
//   A ("imperative" + F3 anti-invention guard): rewrite as an imperative instruction to
//      the agent, with an explicit prohibition on inventing details. NOW SHIPPED.
//   B ("bug-report"): the prior production form — structured bug report; lost the A/B
//      (inconsistent verb-less / malformed fragments; see research/fix-fragment-ab-result.md).
//
// The decision criterion was NOT "which matches a reference" — it is the
// preserve-don't-invent lens (F3): does either framing make the model INVENT a
// fix / file path / symptom the speaker never uttered? That poisons the downstream
// coding agent with false context. We print raw → A → B side by side; the human
// (and the orchestrator) read them and decide. Durable verdict:
// research/fix-fragment-ab-result.md + verification-ledger.md §5.
//
// Gated behind SPEAK_EVAL=1 (set by the `Eval` scheme). Run explicitly:
//   xcodebuild ... -scheme Eval test -only-testing:SpeakTests/FixABTests

@testable import SpeakCore
import Foundation
import FoundationModels
import XCTest

@available(macOS 26.0, *)
final class FixABTests: XCTestCase {

    /// Candidate A — the SHIPPED fix fragment, verbatim from PromptBuilder.categoryFragment(.fix).
    /// (Imperative form, chosen via this A/B and approved by the user — SM-2 D1.)
    private static let fragmentA =
        "Rewrite the spoken words as a single clear imperative instruction telling the coding agent "
        + "what to fix and where. Do not write the fix, propose a solution, or add any file, function, "
        + "error, or detail the speaker did not say."

    /// Candidate B — the bug-report alternative that A/B'd against A (the prior production form).
    private static let fragmentB =
        "Output ONLY a structured bug report: state what is broken and where. Do not propose a fix or suggest a solution."

    /// Fix-style spoken inputs. Mix of: the existing fixture, verbose/filler, terse,
    /// and ones that TEMPT invention (vague target → does the model fabricate specifics?).
    private static let inputs: [String] = [
        "fix the bug in capture session where paste only works the first time",
        "um the the paste isn't working after the first dictation can you fix that",
        "there's a crash when i open the history pane fix it",
        "the login button on the settings page doesn't do anything fix it",
        "fix the off by one in the loop counter",
        "something's wrong with the audio it cuts out sometimes please fix"
    ]

    func testFixFragmentABLive() async throws {
        guard ProcessInfo.processInfo.environment["SPEAK_EVAL"] == "1" else {
            throw XCTSkip("Set SPEAK_EVAL=1 (Eval scheme) to run the live fix A/B. Skip ≠ pass.")
        }

        // Build the real production instruction for the Agent profile, fix category, medium intensity.
        // This contains fragmentA verbatim; instruction B is the same string with A → B substituted,
        // so the ONLY difference between the two runs is the fix fragment. Fairness guaranteed.
        let agent = DefaultProfiles.agent
        let modeA = CleanupMode.profile(agent, level: .medium, category: .fix)
        let instructionA = FoundationModelsCleaner.instructions(for: modeA)

        guard instructionA.contains(Self.fragmentA) else {
            XCTFail("Production fix fragment changed — update FixABTests.fragmentA to match PromptBuilder.")
            return
        }
        let instructionB = instructionA.replacingOccurrences(of: Self.fragmentA, with: Self.fragmentB)

        // Same session config as FoundationModelsCleaner: permissive guardrails, greedy decoding.
        let model = SystemLanguageModel(useCase: .general, guardrails: .permissiveContentTransformations)
        guard case .available = model.availability else {
            throw XCTSkip("Foundation Models not available on this device. Skip ≠ pass.")
        }
        let options = GenerationOptions(sampling: .greedy)

        func clean(_ text: String, with instruction: String) async throws -> String {
            let session = LanguageModelSession(model: model, instructions: Instructions(instruction))
            let wrapped = FoundationModelsCleaner.wrapTranscript(text)
            let response = try await session.respond(to: Prompt(wrapped), options: options)
            return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        print("FIXAB::BEGIN")
        for (i, input) in Self.inputs.enumerated() {
            let outA = try await clean(input, with: instructionA)
            let outB = try await clean(input, with: instructionB)
            print("FIXAB::CASE \(i + 1)")
            print("FIXAB::RAW \(input)")
            print("FIXAB::A   \(outA.replacingOccurrences(of: "\n", with: "\\n"))")
            print("FIXAB::B   \(outB.replacingOccurrences(of: "\n", with: "\\n"))")
        }
        print("FIXAB::END")
    }
}
