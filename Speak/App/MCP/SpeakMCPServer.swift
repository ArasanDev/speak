// Speak/App/MCP/SpeakMCPServer.swift
//
// Layer 4 of the Bidirectional Voice Architecture: Speak MCP Server.
//
// Responsibilities:
//   - Hosts Layer 4 MCP tools `speak_ask_user` and `speak_stream_speech`.
//   - Bridges autonomous AI agents directly into the Speak overlay UI and TTS engine.
//   - Connects user responses directly back to calling agents via async continuation.

import Foundation
import os
import SpeakCore

/// `@MainActor` server managing Layer 4 MCP tool execution and state.
@MainActor
final class SpeakMCPServer {

    // MARK: - Dependencies

    private let askUserHandler: AskUserToolHandler
    private weak var overlayController: OverlayController?
    private weak var settingsStore: SettingsStore?
    private let voiceOut: any SpeechSynthesizing
    private let agentSpeechQueue: AgentSpeechQueue

    // MARK: - Initialization

    init(
        overlayController: OverlayController,
        settingsStore: SettingsStore,
        voiceOut: any SpeechSynthesizing,
        agentSpeechQueue: AgentSpeechQueue
    ) {
        self.askUserHandler = AskUserToolHandler()
        self.overlayController = overlayController
        self.settingsStore = settingsStore
        self.voiceOut = voiceOut
        self.agentSpeechQueue = agentSpeechQueue
        SpeakLog.agentBridge.info("SpeakMCPServer initialized for Layer 4 Bidirectional Voice Architecture.")
    }

    // MARK: - Tool Registrations

    /// Catalog of Layer 4 tools exposed by SpeakMCPServer.
    static var layer4Tools: [MCPTool] {
        [
            MCPTool(
                name: "speak_ask_user",
                description: "Ask the user a question via speech readback and the Magenta overlay UI. " +
                    "Listens for the user's spoken or typed answer and returns it directly to the agent via async continuation (bypassing pasteboard). " +
                    "Requires speak.app to be running.",
                inputSchema: AgentBridgeTools.askUserInputSchema
            ),
            MCPTool(
                name: "speak_stream_speech",
                description: "Stream agent text response to the TTS engine and update the overlay UI text display. " +
                    "Renders readback in real-time and updates conversation loop state.",
                inputSchema: AgentBridgeTools.streamSpeechInputSchema
            )
        ]
    }

    // MARK: - Tool Dispatch

    /// Execute a tool call for Layer 4 MCP tools.
    ///
    /// - Parameter call: MCPToolCallRequest containing tool name and arguments.
    /// - Returns: `MCPToolCallResult` with text outcome or error.
    func handleToolCall(_ call: MCPToolCallRequest) async -> MCPToolCallResult {
        switch call.name {
        case "speak_ask_user":
            return await handleAskUser(call)
        case "speak_stream_speech":
            return await handleStreamSpeech(call)
        default:
            return .error("SpeakMCPServer: Unknown tool '\(call.name)'.")
        }
    }

    // MARK: - Tool Implementations

    /// Handler for `speak_ask_user(prompt: String, mode: String)`
    private func handleAskUser(_ call: MCPToolCallRequest) async -> MCPToolCallResult {
        guard let prompt = call.arguments["prompt"]?.stringValue, !prompt.isEmpty else {
            return .error("speak_ask_user requires a non-empty 'prompt' argument.")
        }
        let modeString = call.arguments["mode"]?.stringValue

        guard let overlay = overlayController, let settings = settingsStore else {
            return .error("Speak app components unavailable for speak_ask_user.")
        }

        do {
            let userResponse = try await askUserHandler.askUser(
                prompt: prompt,
                modeString: modeString,
                overlayController: overlay,
                voiceOut: voiceOut,
                settingsStore: settings
            )
            SpeakLog.agentBridge.info("speak_ask_user succeeded — returning response via continuation.")
            return .text(userResponse)
        } catch {
            SpeakLog.agentBridge.error("speak_ask_user failed: \(error.localizedDescription, privacy: .public)")
            return .error("speak_ask_user error: \(error.localizedDescription)")
        }
    }

    /// Handler for `speak_stream_speech(text: String, isFinal: Bool)`
    private func handleStreamSpeech(_ call: MCPToolCallRequest) async -> MCPToolCallResult {
        guard let text = call.arguments["text"]?.stringValue, !text.isEmpty else {
            return .error("speak_stream_speech requires a non-empty 'text' argument.")
        }
        let isFinal = call.arguments["isFinal"]?.boolValue ?? true

        SpeakLog.agentBridge.info(
            "speak_stream_speech streaming text (\(text.count, privacy: .public) chars, isFinal=\(isFinal, privacy: .public))."
        )

        // Stream speech to TTS engine
        await agentSpeechQueue.submit(
            text: text,
            locale: settingsStore?.language ?? Locale.current,
            interrupt: false
        )

        // Update overlay model if active conversation loop manager exists
        if let overlay = overlayController, let loopManager = overlay.overlayModel.conversationLoopManager {
            if isFinal {
                loopManager.handleAgentSpeakingProgress(speechText: text, progress: 1.0)
                loopManager.handleAgentSpeakingFinished()
            } else {
                loopManager.handleAgentSpeakingStarted(speechText: text)
            }
        }

        return .text(isFinal ? "speech stream completed." : "speech chunk queued.")
    }
}
