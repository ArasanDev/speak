// SpeakCore/CLI/CLIPortServer+Layer4.swift
//
// Layer 4 askUser / streamSpeech handlers and session note helpers for CLIPortServer.

import Foundation

extension CLIPortServer {
    func handleAskUser(_ request: CLIRequest, handler: any CLICommandHandler) -> CLIReply {
        guard let prompt = request.prompt ?? request.question, !prompt.isEmpty else {
            return .failure("askUser requires a non-empty prompt")
        }
        let modeString = request.mode?.rawValue
        let sessionNote = CLIPortServer.pumpedSessionNote(sessionId: request.sessionId, handler: handler)

        // Dispatch askUser asynchronously on @MainActor without blocking the C message port callback
        Task { @MainActor in
            _ = await handler.cliAskUser(prompt: prompt, mode: modeString)
        }

        // Return immediately so the C message port callback exits in < 1ms,
        // preventing AppKit main thread blocking and cursor hanging.
        return .accepted(sessionNote: sessionNote)
    }

    func handleStreamSpeech(_ request: CLIRequest, handler: any CLICommandHandler) -> CLIReply {
        guard let text = request.text, !text.isEmpty else {
            return .failure("streamSpeech requires non-empty text")
        }
        let isFinal = request.interrupt ?? true
        let sessionNote = CLIPortServer.pumpedSessionNote(sessionId: request.sessionId, handler: handler)

        let box = CLIPendingResultBox<String>()
        Task { @MainActor in
            let result = await handler.cliStreamSpeech(text: text, isFinal: isFinal)
            box.set(result)
        }
        guard let result = CLIPortServer.pumpUntilResult(timeoutSeconds: 5.0, poll: box.get) else {
            return .failure("speak_stream_speech did not complete")
        }
        return .asked(result, sessionNote: sessionNote)
    }

    /// Resolve the optional "unregistered session" note for a request that
    /// carries `sessionId`. `nil` when no `sessionId` was supplied (today's
    /// behavior, unchanged) or when it was supplied and is a known session.
    /// Bridges the actor-isolated `AgentSessionRegistry` the same way
    /// `handleRegisterSession` does. [decision: AVB-6]
    static func pumpedSessionNote(sessionId: String?, handler: any CLICommandHandler) -> String? {
        guard let sessionId else { return nil }
        let box = CLIPendingResultBox<Bool>()
        Task { @MainActor in
            let known = await handler.cliTouchSession(sessionId)
            box.set(known)
        }
        guard let known = pumpUntilResult(timeoutSeconds: 5.0, poll: box.get) else {
            SpeakLog.cli.error("CLIPortServer: sessionId touch pump exhausted — omitting note.")
            return nil
        }
        return known ? nil : BridgeOutcome<Void>.unregisteredSessionNote(sessionId)
    }
}
