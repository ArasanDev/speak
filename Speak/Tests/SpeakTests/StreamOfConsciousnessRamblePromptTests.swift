// SpeakTests/StreamOfConsciousnessRamblePromptTests.swift
//
// Requirement R3.4: Stream-of-Consciousness Ramble Prompt unit tests.
// Verifies `specs/profile-system-prompts.md`, `CleanProfilePrompt`, `LLMSystemPrompts`,
// and `PromptBuilder` prompt assembly logic.

@testable import SpeakCore
import XCTest

@available(macOS 26.0, *)
final class StreamOfConsciousnessRamblePromptTests: XCTestCase {

    func testLLMSystemPromptsContractMatchesSpec() {
        XCTAssertTrue(
            LLMSystemPrompts.transcriptGuard.contains("stream of consciousness"),
            "transcriptGuard must explicitly mention stream of consciousness ramble"
        )
        XCTAssertTrue(
            CleanProfilePrompt.cleanProfilePrompt.contains("Remove filler words"),
            "cleanProfilePrompt must instruct filler word removal"
        )
        XCTAssertTrue(
            LLMSystemPrompts.chatProfilePrompt.contains("AI assistant"),
            "chatProfilePrompt must specify AI assistant target"
        )
        XCTAssertTrue(
            LLMSystemPrompts.codeProfilePrompt.contains("software developer"),
            "codeProfilePrompt must target software developer"
        )
        XCTAssertTrue(
            LLMSystemPrompts.cliProfilePrompt.contains("terse shell command"),
            "cliProfilePrompt must target terse shell command"
        )
    }

    func testFoundationModelsCleanerWrapsTranscriptInXML() {
        let raw = "um so i think we should use sqlite and fts5 for searching"
        let wrapped = FoundationModelsCleaner.wrapTranscript(raw)
        XCTAssertEqual(wrapped, "<transcript>um so i think we should use sqlite and fts5 for searching</transcript>")
    }

    func testFoundationModelsCleanerInstructionsIncludeGuard() {
        let instructions = FoundationModelsCleaner.instructions(for: .styled(.default, .medium))
        XCTAssertTrue(
            instructions.contains("stream of consciousness"),
            "Instructions for FoundationModelsCleaner must include the stream of consciousness guard"
        )
    }

    func testPromptBuilderAssemblesCleanProfilePromptWithRambleInput() {
        let profile = DefaultProfiles.write
        let ramble = "um like I want to write a blog post about sqlite fts5 indexing and performance"
        let builtPrompt = PromptBuilder.build(profile: profile, rawTranscript: ramble)

        XCTAssertTrue(builtPrompt.contains(profile.systemPrompt))
        XCTAssertTrue(builtPrompt.contains(ramble))
    }
}
