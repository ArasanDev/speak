// Speak/Tests/SpeakTests/ConversationOverlayViewTests.swift
//
// Unit tests for Layer 3 Bidirectional Voice Architecture — ConversationOverlayView & OverlayRootView.

@testable import Speak
import SpeakCore
import SwiftUI
import XCTest

@MainActor
final class ConversationOverlayViewTests: XCTestCase {

    private var loopManager: ConversationLoopManager!
    private var model: OverlayViewModel!
    private var settingsStore: SettingsStore!

    override func setUp() async throws {
        try await super.setUp()
        loopManager = ConversationLoopManager(initialMode: .fullDuplex)
        model = OverlayViewModel()
        model.conversationLoopManager = loopManager
        settingsStore = SettingsStore()
    }

    override func tearDown() async throws {
        loopManager = nil
        model = nil
        settingsStore = nil
        try await super.tearDown()
    }

    // MARK: - OverlayRootView Wiring Test

    func testOverlayRootView_initializesWithConversationLoopManager() {
        let rootView = OverlayRootView(model: model, settingsStore: settingsStore)
        XCTAssertNotNil(rootView.body, "OverlayRootView body should render when initialized.")
        XCTAssertNotNil(model.conversationLoopManager, "OverlayViewModel should hold the active ConversationLoopManager.")
        XCTAssertEqual(model.conversationLoopManager?.state, .idle, "Initial conversation state should be .idle.")
    }

    // MARK: - ConversationState Transitions in View Hierarchy

    func testConversationOverlayView_handlesAllStates() {
        let overlayView = ConversationOverlayView(
            loopManager: loopManager,
            model: model,
            settingsStore: settingsStore
        )
        XCTAssertNotNil(overlayView)

        // 1. Listening State
        loopManager.handleVADSpeechStarted()
        loopManager.handleVADTranscriptUpdated("Hello Agent")
        XCTAssertTrue(loopManager.state.isListening)

        // 2. Processing State
        loopManager.transitionToProcessing(prompt: "Hello Agent")
        XCTAssertTrue(loopManager.state.isProcessing)

        // 3. Agent Speaking State
        loopManager.handleAgentSpeakingStarted(speechText: "Hello human!")
        loopManager.handleAgentSpeakingProgress(speechText: "Hello human!", progress: 0.5)
        XCTAssertTrue(loopManager.state.isAgentSpeaking)

        // 4. Interrupted State
        loopManager.handleInterrupt()
        XCTAssertTrue(loopManager.state.isInterrupted)

        // 5. Paused State
        loopManager.setMuted(true)
        XCTAssertTrue(loopManager.state.isPaused)
        XCTAssertTrue(loopManager.isMuted)

        // 6. Return to Idle
        loopManager.setMuted(false)
        XCTAssertTrue(loopManager.state.isIdle)
    }

    // MARK: - Mode Switcher Test

    func testModeSwitcher_updatesLoopManagerMode() {
        XCTAssertEqual(loopManager.mode, .fullDuplex)

        loopManager.setMode(.pushToTalk)
        XCTAssertEqual(loopManager.mode, .pushToTalk)

        loopManager.setMode(.gatedTurn)
        XCTAssertEqual(loopManager.mode, .gatedTurn)
    }

    // MARK: - Manual Controls Test

    func testManualControls_muteAndInterrupt() {
        XCTAssertFalse(loopManager.isMuted)

        let muted = loopManager.toggleMute()
        XCTAssertTrue(muted)
        XCTAssertTrue(loopManager.isMuted)
        XCTAssertEqual(loopManager.state, .paused)

        let unmuted = loopManager.toggleMute()
        XCTAssertFalse(unmuted)
        XCTAssertFalse(loopManager.isMuted)
        XCTAssertEqual(loopManager.state, .idle)
    }
}
