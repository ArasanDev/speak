// SpeakCore/AgentBridge/AgentBridgeServer+Layer4.swift
//
// Layer 4 MCP tool handlers for AgentBridgeServer.

import Foundation

extension AgentBridgeServer {
    func runAskUserTool(_ call: MCPToolCallRequest, sessionId: String?) async -> MCPToolCallResult {
        guard let prompt = call.arguments["prompt"]?.stringValue, !prompt.isEmpty else {
            return .error("speak_ask_user requires a non-empty 'prompt' argument.")
        }
        let mode = call.arguments["mode"]?.stringValue
        switch await backend.askUser(prompt: prompt, mode: mode, sessionId: sessionId) {
        case .success(let outcome):
            return .text(Self.appendingNote(outcome.value, outcome.sessionNote))

        case .failure(let reason):
            return .error(reason.description)
        }
    }

    func runStreamSpeechTool(_ call: MCPToolCallRequest, sessionId: String?) async -> MCPToolCallResult {
        guard let text = call.arguments["text"]?.stringValue, !text.isEmpty else {
            return .error("speak_stream_speech requires a non-empty 'text' argument.")
        }
        let isFinal = call.arguments["isFinal"]?.boolValue ?? true
        switch await backend.streamSpeech(text: text, isFinal: isFinal, sessionId: sessionId) {
        case .success(let outcome):
            return .text(Self.appendingNote(outcome.value, outcome.sessionNote))

        case .failure(let reason):
            return .error(reason.description)
        }
    }
}
