// Speak/Tests/SpeakTests/ConversationLoopManagerTests.swift
//
// Unit tests for Layer 2 Bidirectional Voice State Machine and Loop Manager
// (`ConversationState`, `ConversationMode`, `ConversationLoopManager`).

import XCTest
@testable import SpeakCore

final class ConversationLoopManagerTests: XCTestCase {

    // MARK: - ConversationMode Tests

    func testConversationModeEnum() {
        XCTAssertEqual(ConversationMode.fullDuplex.rawValue, "fullDuplex")
        XCTAssertEqual(ConversationMode.pushToTalk.rawValue, "pushToTalk")
        XCTAssertEqual(ConversationMode.gatedTurn.rawValue, "gatedTurn")

        XCTAssertFalse(ConversationMode.fullDuplex.label.isEmpty)
        XCTAssertFalse(ConversationMode.pushToTalk.label.isEmpty)
        XCTAssertFalse(ConversationMode.gatedTurn.label.isEmpty)

        XCTAssertEqual(ConversationMode.allCases.count, 3)
    }

    // MARK: - ConversationState Tests

    func testConversationStateProperties() {
        let idle = ConversationState.idle
        XCTAssertTrue(idle.isIdle)
        XCTAssertFalse(idle.isListening)
        XCTAssertNil(idle.currentText)

        let listening = ConversationState.listening(userText: "Hello computer")
        XCTAssertTrue(listening.isListening)
        XCTAssertEqual(listening.currentText, "Hello computer")

        let processing = ConversationState.processing(prompt: "Search the web")
        XCTAssertTrue(processing.isProcessing)
        XCTAssertEqual(processing.currentText, "Search the web")

        let agentSpeaking = ConversationState.agentSpeaking(speechText: "Here is the answer", progress: 0.5)
        XCTAssertTrue(agentSpeaking.isAgentSpeaking)
        XCTAssertEqual(agentSpeaking.currentText, "Here is the answer")

        let interrupted = ConversationState.interrupted(partialUserText: "Wait stop")
        XCTAssertTrue(interrupted.isInterrupted)
        XCTAssertEqual(interrupted.currentText, "Wait stop")

        let paused = ConversationState.paused
        XCTAssertTrue(paused.isPaused)
        XCTAssertNil(paused.currentText)
    }

    // MARK: - ConversationLoopManager State Machine Tests

    @MainActor
    func testInitialState() {
        let manager = ConversationLoopManager()
        XCTAssertEqual(manager.state, .idle)
        XCTAssertEqual(manager.mode, .fullDuplex)
        XCTAssertFalse(manager.isMuted)
    }

    @MainActor
    func testVADSpeechStartAndTranscriptUpdate() {
        let manager = ConversationLoopManager(initialMode: .pushToTalk)

        manager.handleVADSpeechStarted()
        XCTAssertEqual(manager.state, .listening(userText: ""))

        manager.handleVADTranscriptUpdated("Testing 1 2 3")
        XCTAssertEqual(manager.state, .listening(userText: "Testing 1 2 3"))
    }

    @MainActor
    func testVADSilenceDetectionAndTurnCommit() {
        let manager = ConversationLoopManager(initialMode: .pushToTalk)

        let expectation = expectation(description: "Turn committed callback")
        var committedPrompt = ""

        manager.onUserTurnCommitted = { prompt in
            committedPrompt = prompt
            expectation.fulfill()
        }

        manager.handleVADSpeechStarted()
        manager.handleVADTranscriptUpdated("What is the weather today?")
        manager.handleVADSilenceDetected()

        XCTAssertEqual(manager.state, .processing(prompt: "What is the weather today?"))

        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(committedPrompt, "What is the weather today?")
    }

    @MainActor
    func testAgentSpeakingLifecycle() {
        let manager = ConversationLoopManager()

        manager.handleAgentSpeakingStarted(speechText: "The weather is sunny.")
        XCTAssertEqual(manager.state, .agentSpeaking(speechText: "The weather is sunny.", progress: 0.0))

        manager.handleAgentSpeakingProgress(speechText: "The weather is sunny.", progress: 0.5)
        XCTAssertEqual(manager.state, .agentSpeaking(speechText: "The weather is sunny.", progress: 0.5))

        manager.handleAgentSpeakingFinished()
        XCTAssertEqual(manager.state, .idle)
    }

    @MainActor
    func testUserInterruptsAgentSpeaking() {
        let manager = ConversationLoopManager()

        var interruptedText = ""
        manager.onInterrupt = { text in
            interruptedText = text
        }

        manager.handleAgentSpeakingStarted(speechText: "Long response being spoken...")
        XCTAssertTrue(manager.state.isAgentSpeaking)

        // User starts speaking while agent is speaking
        manager.handleVADSpeechStarted()

        XCTAssertEqual(interruptedText, "Long response being spoken...")
        XCTAssertTrue(manager.state.isListening)
    }


    @MainActor
    func testManualInterruptOverride() {
        let manager = ConversationLoopManager()

        manager.transitionToProcessing(prompt: "Calculating...")
        XCTAssertTrue(manager.state.isProcessing)

        manager.handleInterrupt()
        XCTAssertTrue(manager.state.isInterrupted)
    }

    @MainActor
    func testMuteOverride() {
        let manager = ConversationLoopManager()

        manager.handleVADSpeechStarted()
        manager.handleVADTranscriptUpdated("Some voice input")
        XCTAssertTrue(manager.state.isListening)

        manager.setMuted(true)
        XCTAssertTrue(manager.isMuted)
        XCTAssertEqual(manager.state, .paused)

        // VAD inputs should be ignored when muted
        manager.handleVADSpeechStarted()
        XCTAssertEqual(manager.state, .paused)

        manager.setMuted(false)
        XCTAssertFalse(manager.isMuted)
        XCTAssertEqual(manager.state, .idle)
    }

    @MainActor
    func testSilenceTimerAutoCommitInFullDuplex() async throws {
        // Fast silence timeout of 0.05 seconds for test speed
        let manager = ConversationLoopManager(initialMode: .fullDuplex, silenceTimeoutDuration: 0.05)

        manager.handleVADSpeechStarted()
        manager.handleVADTranscriptUpdated("Auto commit prompt")
        XCTAssertTrue(manager.state.isListening)

        // Wait slightly longer than 0.05 seconds
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(manager.state, .processing(prompt: "Auto commit prompt"))
    }

    @MainActor
    func testModeSwitching() {
        let manager = ConversationLoopManager(initialMode: .fullDuplex)
        XCTAssertEqual(manager.mode, .fullDuplex)

        manager.setMode(.pushToTalk)
        XCTAssertEqual(manager.mode, .pushToTalk)

        manager.setMode(.gatedTurn)
        XCTAssertEqual(manager.mode, .gatedTurn)
    }

    @MainActor
    func testObservationStreams() async throws {
        let manager = ConversationLoopManager()
        let stream = manager.stateStream

        var iterator = stream.makeAsyncIterator()

        let initial = await iterator.next()
        XCTAssertEqual(initial, .idle)

        manager.handleVADSpeechStarted()
        let listeningState = await iterator.next()
        XCTAssertEqual(listeningState, .listening(userText: ""))
    }
}
