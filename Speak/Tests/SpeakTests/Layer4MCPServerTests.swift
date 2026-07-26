// Speak/Tests/SpeakTests/Layer4MCPServerTests.swift
//
// Unit tests for Layer 4 Bidirectional Voice Architecture — SpeakMCPServer & AskUserToolHandler.

@testable import Speak
import SpeakCore
import XCTest

private final class StubSpeechSynthesizer: SpeechSynthesizing, @unchecked Sendable {
    var isSpeaking: Bool = false

    func speak(_ text: String, locale: Locale) async {
        isSpeaking = true
        isSpeaking = false
    }

    // swiftlint:disable:next function_parameter_count
    func speak(
        _ text: String,
        voiceIdentifier: String?,
        rate: Float,
        pitch: Float,
        volume: Float,
        locale: Locale
    ) async {
        await speak(text, locale: locale)
    }

    func stop() async {
        isSpeaking = false
    }
}

@MainActor
final class Layer4MCPServerTests: XCTestCase {

    private var overlayController: OverlayController!
    private var settingsStore: SettingsStore!
    private var voiceOut: StubSpeechSynthesizer!
    private var agentSpeechQueue: AgentSpeechQueue!
    private var server: SpeakMCPServer!

    override func setUp() async throws {
        try await super.setUp()
        settingsStore = SettingsStore()
        overlayController = OverlayController(settingsStore: settingsStore)
        voiceOut = StubSpeechSynthesizer()
        agentSpeechQueue = AgentSpeechQueue(synthesizer: voiceOut)
        server = SpeakMCPServer(
            overlayController: overlayController,
            settingsStore: settingsStore,
            voiceOut: voiceOut,
            agentSpeechQueue: agentSpeechQueue
        )
    }

    override func tearDown() async throws {
        server = nil
        agentSpeechQueue = nil
        voiceOut = nil
        overlayController = nil
        settingsStore = nil
        try await super.tearDown()
    }

    // MARK: - Catalog Test

    func testLayer4ToolsCatalog() {
        let tools = SpeakMCPServer.layer4Tools
        XCTAssertEqual(tools.count, 2)
        XCTAssertTrue(tools.contains(where: { $0.name == "speak_ask_user" }))
        XCTAssertTrue(tools.contains(where: { $0.name == "speak_stream_speech" }))
    }

    // MARK: - Stream Speech Tool Test

    func testStreamSpeechTool_queuesSpeechAndUpdatesProgress() async {
        let request = MCPToolCallRequest(
            params: .object([
                "name": .string("speak_stream_speech"),
                "arguments": .object([
                    "text": .string("Streaming agent response text..."),
                    "isFinal": .bool(true)
                ])
            ])
        )
        XCTAssertNotNil(request)

        guard let request = request else { return }
        let result = await server.handleToolCall(request)
        XCTAssertFalse(result.isError)
        XCTAssertEqual(result.content.count, 1)

        if case .text(let responseText) = result.content.first {
            XCTAssertTrue(responseText.contains("speech stream completed"))
        } else {
            XCTFail("Expected text content response")
        }
    }

    // MARK: - Ask User Invalid Prompt Test

    func testAskUser_emptyPromptFails() async {
        let request = MCPToolCallRequest(
            params: .object([
                "name": .string("speak_ask_user"),
                "arguments": .object([
                    "prompt": .string("   ")
                ])
            ])
        )
        XCTAssertNotNil(request)

        guard let request = request else { return }
        let result = await server.handleToolCall(request)
        XCTAssertTrue(result.isError)
    }

    // MARK: - Ask User Execution Test

    func testAskUser_completesViaTurnCommitment() async throws {
        let handler = AskUserToolHandler()

        let askTask = Task { @MainActor in
            try await handler.askUser(
                prompt: "What is your name?",
                modeString: "fullDuplex",
                overlayController: overlayController,
                voiceOut: voiceOut,
                settingsStore: settingsStore
            )
        }

        // Give the task a moment to register continuation & configure overlay
        try await Task.sleep(nanoseconds: 50_000_000)

        // Verify overlay model received conversationLoopManager
        XCTAssertNotNil(overlayController.overlayModel.conversationLoopManager)

        let loopManager = overlayController.overlayModel.conversationLoopManager
        XCTAssertNotNil(loopManager)

        // Commit turn directly (simulating user speech / typed response)
        loopManager?.commitUserTurn(prompt: "Tamil")

        let answer = try await askTask.value
        XCTAssertEqual(answer, "Tamil")

        // Verify overlay model is cleaned up
        XCTAssertNil(overlayController.overlayModel.conversationLoopManager)
    }

    // MARK: - Ask User Interrupt Test

    func testAskUser_cancelsOnInterrupt() async throws {
        let handler = AskUserToolHandler()

        let askTask = Task { @MainActor in
            try await handler.askUser(
                prompt: "Should I proceed?",
                modeString: "fullDuplex",
                overlayController: overlayController,
                voiceOut: voiceOut,
                settingsStore: settingsStore
            )
        }

        try await Task.sleep(nanoseconds: 50_000_000)

        let loopManager = overlayController.overlayModel.conversationLoopManager
        XCTAssertNotNil(loopManager)

        // Simulate user clicking Interrupt
        loopManager?.handleInterrupt()

        do {
            _ = try await askTask.value
            XCTFail("Expected askUser to throw AskUserError.cancelled")
        } catch let err as AskUserError {
            XCTAssertEqual(err, .cancelled)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertNil(overlayController.overlayModel.conversationLoopManager)
    }
}
