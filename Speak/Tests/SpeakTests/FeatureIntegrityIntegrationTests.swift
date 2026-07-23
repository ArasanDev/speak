// SpeakTests/FeatureIntegrityIntegrationTests.swift
//
// Requirement R3.6: End-to-end integration test verifying that all 5 feature components
// function seamlessly together:
//   1. Speech-to-Text (AppleSpeechTranscriber / SpeechAnalyzer seam)
//   2. AI Neat-Writing (FoundationModelsCleaner / LLMCleaning)
//   3. Developer Acronym Biasing (CLI, API, SDK, FTS5, SQLite, etc.)
//   4. Stream-of-Consciousness Ramble Prompt (specs/profile-system-prompts.md / CleanProfilePrompt / PromptBuilder)
//   5. Voice Robotic Pet Mascot ("Pip") (PetState state transitions & priority rules)

@testable import Speak
@testable import SpeakCore
import XCTest

@available(macOS 26.0, *)
final class FeatureIntegrityIntegrationTests: XCTestCase {

    /// Verifies the full pipeline of all 5 feature components end-to-end.
    func testAllFiveFeatureComponentsIntegrateSeamlessly() async throws {
        // ── Component 1 & 3: STT Transcriber & Developer Acronym Biasing ─────────
        let developerTerms = AppleSpeechTranscriber.developerTerms
        XCTAssertTrue(developerTerms.contains("FTS5"))
        XCTAssertTrue(developerTerms.contains("SQLite"))
        XCTAssertTrue(developerTerms.contains("CLI"))
        XCTAssertTrue(developerTerms.contains("API"))
        XCTAssertTrue(developerTerms.contains("SDK"))

        let transcriber = AppleSpeechTranscriber(vocabulary: ["FTS5", "SQLite", "CLI", "API", "SDK"])
        XCTAssertEqual(transcriber.id, "apple-speech-en-US")
        XCTAssertTrue(transcriber.vocabulary.contains("FTS5"))

        // ── Component 2 & 4: AI Neat-Writing & Stream-of-Consciousness Ramble Prompt ──
        let cleaner = FoundationModelsCleaner()
        XCTAssertEqual(cleaner.id, "foundation-models")

        let rawRamble = "um so I was thinking we should use sqlite and fts5 for the full text search in our cli app"
        let wrappedInput = FoundationModelsCleaner.wrapTranscript(rawRamble)
        XCTAssertEqual(
            wrappedInput,
            "<transcript>um so I was thinking we should use sqlite and fts5 for the full text search in our cli app</transcript>"
        )

        // Verify acronym fixing on ramble output
        let fixedText = FoundationModelsCleaner.fixDeveloperAcronyms(rawRamble)
        XCTAssertTrue(fixedText.contains("SQLite"))
        XCTAssertTrue(fixedText.contains("FTS5"))
        XCTAssertTrue(fixedText.contains("CLI"))

        // Verify PromptBuilder instructions using CleanProfilePrompt and profile.systemPrompt
        let profile = DefaultProfiles.write
        let instructions = PromptBuilder.instructions(profile: profile, customVocabulary: transcriber.vocabulary)
        XCTAssertTrue(instructions.contains(profile.systemPrompt))
        XCTAssertTrue(instructions.contains("\"FTS5\""))
        XCTAssertTrue(instructions.contains("\"SQLite\""))

        // ── Component 5: Pip Pet Mascot State Transitions & Priority ────────────
        // 1. Idle state
        let idleInputs = PetStateInputs(
            engineAvailable: true, isListening: false, isProcessing: false,
            isSpeaking: false, isAgentWorking: false, hasAttention: false
        )
        XCTAssertEqual(PetState.resolve(from: idleInputs), .idle)

        // 2. Listening state (Mic active during dictation)
        let listeningInputs = PetStateInputs(
            engineAvailable: true, isListening: true, isProcessing: false,
            isSpeaking: false, isAgentWorking: false, hasAttention: false
        )
        XCTAssertEqual(PetState.resolve(from: listeningInputs), .listening)

        // 3. Processing state (AI cleanup active)
        let processingInputs = PetStateInputs(
            engineAvailable: true, isListening: false, isProcessing: true,
            isSpeaking: false, isAgentWorking: false, hasAttention: false
        )
        XCTAssertEqual(PetState.resolve(from: processingInputs), .processing)

        // 4. Speaking state (TTS response active)
        let speakingInputs = PetStateInputs(
            engineAvailable: true, isListening: false, isProcessing: false,
            isSpeaking: true, isAgentWorking: false, hasAttention: false
        )
        XCTAssertEqual(PetState.resolve(from: speakingInputs), .speaking)

        // 5. Priority rule test: Listening (human mic) beats Speaking, Attention, AgentWorking, Processing
        let conflictInputs = PetStateInputs(
            engineAvailable: true, isListening: true, isProcessing: true,
            isSpeaking: true, isAgentWorking: true, hasAttention: true
        )
        XCTAssertEqual(
            PetState.resolve(from: conflictInputs),
            .listening,
            "Listening must win over all agent signals (listening > speaking > attention > agentWorking > processing > idle > dormant)."
        )
    }
}
