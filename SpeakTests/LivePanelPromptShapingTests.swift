// SpeakTests/LivePanelPromptShapingTests.swift
//
// PE-3c-V: unit tests verifying that Agent-mode category selection correctly
// reshapes the assembled instructions via PromptBuilder. All tests are purely
// deterministic — no live Foundation Models pass required.

@testable import SpeakCore
import Testing

@Suite("LivePanelPromptShaping")
struct LivePanelPromptShapingTests {

    // MARK: - Category fragment presence

    @Test func testAgentTaskBuildsNoFragment() {
        let instructions = PromptBuilder.instructions(
            profile: DefaultProfiles.agent, category: .task
        )
        // Base system prompt must be present.
        #expect(instructions.contains("coding agent"))
        // Task fragment is nil — no extra clause appended beyond the base prompt.
        #expect(PromptBuilder.categoryFragment(.task) == nil)
    }

    @Test func testAgentFixBuildsFixFragment() {
        let instructions = PromptBuilder.instructions(
            profile: DefaultProfiles.agent, category: .fix
        )
        // The fix fragment explicitly instructs a structured bug report.
        #expect(instructions.contains("bug report"))
    }

    @Test func testAgentAskBuildsAskFragment() {
        let instructions = PromptBuilder.instructions(
            profile: DefaultProfiles.agent, category: .ask
        )
        // Ask fragment forces question output and mandates a trailing '?'.
        #expect(instructions.contains("question"))
        #expect(instructions.contains("'?'"))
    }

    @Test func testAgentCommitBuildsCommitFragment() {
        let instructions = PromptBuilder.instructions(
            profile: DefaultProfiles.agent, category: .commit
        )
        #expect(instructions.contains("Conventional Commits"))
    }

    @Test func testAgentShellBuildsShellFragment() {
        let instructions = PromptBuilder.instructions(
            profile: DefaultProfiles.agent, category: .shell
        )
        #expect(instructions.contains("shell command"))
        #expect(instructions.contains("no markdown"))
    }

    @Test func testAgentCodeBuildsCodeFragment() {
        let instructions = PromptBuilder.instructions(
            profile: DefaultProfiles.agent, category: .code
        )
        #expect(instructions.contains("raw code"))
    }

    // MARK: - Non-Agent profiles ignore category

    @Test func testWriteProfileIgnoresCategory() {
        for category in AgentCategory.allCases {
            let instructions = PromptBuilder.instructions(
                profile: DefaultProfiles.write, category: category
            )
            #expect(!instructions.contains("Conventional Commits"),
                    "Write profile must not include commit fragment (category: \(category))")
            #expect(!instructions.contains("shell command"),
                    "Write profile must not include shell fragment (category: \(category))")
            #expect(!instructions.contains("raw code"),
                    "Write profile must not include code fragment (category: \(category))")
        }
    }

    // MARK: - Raw profile bypass

    @Test func testRawProfileBypassesBuilder() {
        let transcript = "raw spoken words unchanged"
        let result = PromptBuilder.build(
            profile: DefaultProfiles.raw, rawTranscript: transcript
        )
        #expect(result == transcript)
    }

    // MARK: - Few-shot example suppression [decision SM-2 round 4]

    @Test func testExamplesSupressedForCommitCategory() {
        let instructions = PromptBuilder.instructions(
            profile: DefaultProfiles.agent, category: .commit
        )
        // Task-format few-shot examples contaminate commit output — must be suppressed.
        #expect(!instructions.contains("Input:"))
        #expect(!instructions.contains("Output:"))
    }

    @Test func testExamplesIncludedForTaskCategory() {
        let instructions = PromptBuilder.instructions(
            profile: DefaultProfiles.agent, category: .task
        )
        // Task/fix/ask share the task-prose format; examples must anchor the pattern.
        #expect(instructions.contains("Input:"))
    }
}
