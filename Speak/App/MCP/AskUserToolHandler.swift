// Speak/App/MCP/AskUserToolHandler.swift
//
// Layer 4 of the Bidirectional Voice Architecture: Ask User Tool Handler.
//
// Responsibilities:
//   - Implements MCP tool `speak_ask_user(prompt: String, mode: String)` which triggers
//     the floating overlay in Magenta conversation mode.
//   - Connects user responses directly back to the calling agent via async continuation
//     (bypassing NSPasteboard completely per AGENTS.md §2.6 and §2.27).
//   - Manages turn lifecycle with `ConversationLoopManager` and `OverlayController`.

import Foundation
import os
import SpeakCore

/// Custom error types for `AskUserToolHandler`.
enum AskUserError: Error, Sendable, CustomStringConvertible, Equatable {
    case alreadyInFlight
    case cancelled
    case invalidPrompt
    case timeout

    var description: String {
        switch self {
        case .alreadyInFlight:
            return "Another ask_user request is already active."
        case .cancelled:
            return "User cancelled or interrupted the prompt."
        case .invalidPrompt:
            return "Prompt text cannot be empty."
        case .timeout:
            return "ask_user request timed out waiting for user response."
        }
    }
}

/// `@MainActor` handler for the `speak_ask_user` tool execution.
@MainActor
final class AskUserToolHandler {

    // MARK: - State

    private var activeContinuation: CheckedContinuation<String, Error>?
    private var currentLoopManager: ConversationLoopManager?

    // MARK: - Init

    init() {}

    // MARK: - Ask User Execution

    /// Execute `speak_ask_user` tool call.
    ///
    /// - Parameters:
    ///   - prompt: Spoken and displayed prompt text for the user.
    ///   - modeString: Optional raw mode string ("fullDuplex", "pushToTalk", "gatedTurn").
    ///   - overlayController: Main app `OverlayController`.
    ///   - voiceOut: TTS synthesizer instance.
    ///   - settingsStore: App settings store.
    /// - Returns: The user's spoken or typed response string.
    func askUser(
        prompt: String,
        modeString: String?,
        overlayController: OverlayController,
        voiceOut: any SpeechSynthesizing,
        settingsStore: SettingsStore
    ) async throws -> String {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else {
            SpeakLog.agentBridge.error("AskUserToolHandler: prompt is empty.")
            throw AskUserError.invalidPrompt
        }

        guard activeContinuation == nil else {
            SpeakLog.agentBridge.error("AskUserToolHandler: another ask_user call is already in flight.")
            throw AskUserError.alreadyInFlight
        }

        // Map mode string to ConversationMode (default: .fullDuplex)
        let mode = parseMode(modeString)

        SpeakLog.agentBridge.info(
            "AskUserToolHandler: ask_user starting with mode=\(mode.rawValue, privacy: .public), prompt length=\(trimmedPrompt.count, privacy: .public)."
        )

        // Construct ConversationLoopManager for Magenta overlay mode
        let loopManager = ConversationLoopManager(initialMode: mode)
        self.currentLoopManager = loopManager

        // Attach loopManager to OverlayViewModel so OverlayRootView renders ConversationOverlayView
        overlayController.overlayModel.conversationLoopManager = loopManager
        overlayController.overlayModel.overlayState = .listening

        return try await withCheckedThrowingContinuation { continuation in
            self.activeContinuation = continuation

            // Setup 120-second timeout task to guarantee continuation never hangs indefinitely
            let timeoutTask = Task { @MainActor [weak self, weak overlayController] in
                do {
                    try await Task.sleep(for: .seconds(120))
                } catch {
                    return // Task was cancelled (user committed or interrupted) — exit cleanly
                }
                guard let self = self, self.activeContinuation != nil else { return }
                SpeakLog.agentBridge.warning("AskUserToolHandler: request timed out after 120 seconds.")
                self.finish(with: .failure(AskUserError.timeout), overlayController: overlayController)
            }

            // Setup callbacks on loopManager
            loopManager.onUserTurnCommitted = { [weak self, weak overlayController] userText in
                Task { @MainActor [weak self, weak overlayController] in
                    guard let self = self else { return }
                    timeoutTask.cancel()
                    SpeakLog.agentBridge.info(
                        "AskUserToolHandler: user response committed via continuation (bypassing pasteboard)."
                    )
                    self.finish(with: .success(userText), overlayController: overlayController)
                }
            }

            loopManager.onInterrupt = { [weak self, weak overlayController] _ in
                Task { @MainActor [weak self, weak overlayController] in
                    guard let self = self else { return }
                    timeoutTask.cancel()
                    SpeakLog.agentBridge.info("AskUserToolHandler: user interrupted prompt.")
                    self.finish(with: .failure(AskUserError.cancelled), overlayController: overlayController)
                }
            }

            // Begin prompt speech readback & transition overlay state
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                loopManager.handleAgentSpeakingStarted(speechText: trimmedPrompt)

                await voiceOut.speak(
                    trimmedPrompt,
                    voiceIdentifier: settingsStore.ttsVoiceIdentifier,
                    rate: settingsStore.ttsSpeechRate,
                    pitch: settingsStore.ttsPitchMultiplier,
                    volume: settingsStore.ttsVolume,
                    locale: settingsStore.language
                )

                if self.activeContinuation != nil {
                    loopManager.handleAgentSpeakingFinished()
                    // Transition to listening state so user can speak or type response
                    loopManager.handleVADSpeechStarted()
                }
            }

            // Present the overlay panel
            overlayController.start(
                partialsProvider: { nil },
                levelsProvider: { nil },
                isCleaningUp: false
            )
        }
    }

    /// Cancel active in-flight request if any.
    func cancel(overlayController: OverlayController?) {
        guard activeContinuation != nil else { return }
        SpeakLog.agentBridge.info("AskUserToolHandler: explicitly cancelling active request.")
        finish(with: .failure(AskUserError.cancelled), overlayController: overlayController)
    }

    // MARK: - Private Helpers

    private func finish(
        with result: Result<String, Error>,
        overlayController: OverlayController?
    ) {
        guard let continuation = activeContinuation else { return }
        self.activeContinuation = nil

        // Clean up conversation loop manager and overlay
        if let loopManager = currentLoopManager {
            loopManager.resetToIdle()
            self.currentLoopManager = nil
        }

        if let overlayController = overlayController {
            overlayController.overlayModel.conversationLoopManager = nil
            overlayController.stop()
        }

        switch result {
        case .success(let text):
            continuation.resume(returning: text)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }

    private func parseMode(_ raw: String?) -> ConversationMode {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return .fullDuplex
        }
        switch raw.lowercased() {
        case "pushtotalk", "push_to_talk":
            return .pushToTalk
        case "gatedturn", "gated_turn":
            return .gatedTurn
        default:
            return .fullDuplex
        }
    }
}
