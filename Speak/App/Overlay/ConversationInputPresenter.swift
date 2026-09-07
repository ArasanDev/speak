// Speak/App/Overlay/ConversationInputPresenter.swift
//
// Internal presentation helper for agent-initiated capture (`speak_request_input`).
// Attaches ConversationLoopManager so Magenta ConversationOverlayView renders
// during the round-trip. This is NOT an MCP tool — conversation mode stays a
// local Speak concern. [decision: MCP redesign 2026-07-30]

import Foundation
import SpeakCore

/// Shared mutable interrupt flag for conversation-presentation callbacks during
/// `speak_request_input`. `@unchecked Sendable` because all writers are hopped
/// onto `@MainActor` via `ConversationInputPresenter` callbacks.
final class RequestInputInterruptFlag: @unchecked Sendable {
    var value = false
}

/// Errors from conversation presentation attach (not MCP protocol errors).
enum ConversationPresentationError: Error, Sendable, CustomStringConvertible, Equatable {
    case alreadyAttached

    var description: String {
        switch self {
        case .alreadyAttached:
            return "Conversation presentation is already attached."
        }
    }
}

/// `@MainActor` helper that mounts conversation-loop UI for one request_input
/// capture and tears it down afterward.
@MainActor
final class ConversationInputPresenter {

    private var loopManager: ConversationLoopManager?
    private weak var overlayController: OverlayController?

    init() {}

    /// Whether a presentation is currently attached.
    var isAttached: Bool { loopManager != nil }

    /// Attach Magenta conversation presentation for an in-flight capture.
    ///
    /// Uses `.gatedTurn` so silence VAD cannot auto-commit and race the AVB-5
    /// poll loop — the human still commits typed text via Send, and Escape
    /// still interrupts via `onInterrupted`.
    ///
    /// - Parameters:
    ///   - overlayController: App overlay controller.
    ///   - prompt: Agent prompt shown during TTS / agentSpeaking state.
    ///   - maxListeningDuration: Upper bound for the loop's listening timer
    ///     (typically the request timeout). Does not replace AVB-5's own deadline.
    ///   - onUserCommitted: Typed Send from the conversation overlay.
    ///   - onInterrupted: Escape / interrupt — caller should stop capture.
    func attach(
        overlayController: OverlayController,
        prompt: String,
        maxListeningDuration: TimeInterval,
        onUserCommitted: @escaping (String) -> Void,
        onInterrupted: @escaping () -> Void
    ) throws {
        guard loopManager == nil else {
            throw ConversationPresentationError.alreadyAttached
        }

        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let loopManager = ConversationLoopManager(
            initialMode: .gatedTurn,
            maxListeningDuration: max(1.0, maxListeningDuration) // [decision: AVB-5 — loop requires positive bound; 1s floor]
        )
        self.loopManager = loopManager
        self.overlayController = overlayController
        overlayController.overlayModel.conversationLoopManager = loopManager

        loopManager.onUserTurnCommitted = { text in
            Task { @MainActor in
                onUserCommitted(text)
            }
        }
        loopManager.onInterrupt = { _ in
            Task { @MainActor in
                onInterrupted()
            }
        }

        SpeakLog.agentBridge.info(
            "ConversationInputPresenter: attached gatedTurn presentation (prompt length=\(trimmedPrompt.count, privacy: .public))."
        )
        loopManager.handleAgentSpeakingStarted(speechText: trimmedPrompt.isEmpty ? " " : trimmedPrompt)
    }

    /// Mark agent TTS finished and show listening UI (no fullDuplex silence auto-commit).
    func markListening() {
        guard let loopManager else { return }
        loopManager.handleAgentSpeakingFinished()
        loopManager.handleVADSpeechStarted()
    }

    /// Mirror streaming STT partials into the conversation overlay text.
    func updateUserTranscript(_ text: String) {
        loopManager?.handleVADTranscriptUpdated(text)
    }

    /// Tear down conversation presentation. Idempotent.
    func detach() {
        guard loopManager != nil || overlayController != nil else { return }
        SpeakLog.agentBridge.info("ConversationInputPresenter: detaching conversation presentation.")
        loopManager?.resetToIdle()
        loopManager = nil
        if let overlayController {
            overlayController.overlayModel.conversationLoopManager = nil
        }
        overlayController = nil
    }
}
