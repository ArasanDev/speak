// Speak/Tests/SpeakTests/ConversationInputPresenterTests.swift
//
// Unit tests for Magenta conversation presentation under speak_request_input
// (not an MCP tool surface). [decision: MCP redesign 2026-07-30]

import XCTest
@testable import Speak
@testable import SpeakCore

@MainActor
final class ConversationInputPresenterTests: XCTestCase {

    private var overlayController: OverlayController!
    private var settingsStore: SettingsStore!

    override func setUp() async throws {
        try await super.setUp()
        settingsStore = SettingsStore()
        overlayController = OverlayController(settingsStore: settingsStore)
    }

    override func tearDown() async throws {
        overlayController = nil
        settingsStore = nil
        try await super.tearDown()
    }

    func testAttachMountsConversationLoopManager() throws {
        let presenter = ConversationInputPresenter()
        XCTAssertFalse(presenter.isAttached)
        XCTAssertNil(overlayController.overlayModel.conversationLoopManager)

        try presenter.attach(
            overlayController: overlayController,
            prompt: "What should we do next?",
            maxListeningDuration: 30,
            onUserCommitted: { _ in },
            onInterrupted: {}
        )

        XCTAssertTrue(presenter.isAttached)
        XCTAssertNotNil(overlayController.overlayModel.conversationLoopManager)
        XCTAssertEqual(
            overlayController.overlayModel.conversationLoopManager?.mode,
            .gatedTurn
        )
        XCTAssertTrue(
            overlayController.overlayModel.conversationLoopManager?.state.isAgentSpeaking == true
        )

        presenter.detach()
        XCTAssertFalse(presenter.isAttached)
        XCTAssertNil(overlayController.overlayModel.conversationLoopManager)
    }

    func testDoubleAttachThrows() throws {
        let presenter = ConversationInputPresenter()
        try presenter.attach(
            overlayController: overlayController,
            prompt: "Hello",
            maxListeningDuration: 10,
            onUserCommitted: { _ in },
            onInterrupted: {}
        )
        XCTAssertThrowsError(
            try presenter.attach(
                overlayController: overlayController,
                prompt: "Again",
                maxListeningDuration: 10,
                onUserCommitted: { _ in },
                onInterrupted: {}
            )
        ) { error in
            XCTAssertEqual(error as? ConversationPresentationError, .alreadyAttached)
        }
        presenter.detach()
    }

    func testMarkListeningTransitionsFromAgentSpeaking() throws {
        let presenter = ConversationInputPresenter()
        try presenter.attach(
            overlayController: overlayController,
            prompt: "Prompt",
            maxListeningDuration: 30,
            onUserCommitted: { _ in },
            onInterrupted: {}
        )
        presenter.markListening()
        XCTAssertTrue(
            overlayController.overlayModel.conversationLoopManager?.state.isListening == true
        )
        presenter.detach()
    }
}
