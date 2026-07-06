// SpeakCore/VoiceActions/VoiceActionsCoordinator.swift
//
// H-1 (specs/horizon-voice-os.md, Pillar 1): ties the router (`ActionRouting`),
// the action executor (`ActionExecuting`), and the existing `CommandModeService`
// together behind ONE entry point — `handle(transcript:knownActionNames:)`.
//
// THE ONE HARD CONTRACT (task brief, restated because it is easy to violate by
// accident): mis-route, mis-match, or ANY failure ALWAYS degrades to plain
// dictation — the original transcript is never dropped. Concretely, every
// non-`.replaced`/non-`.success` outcome below returns `.degradedToDictation`
// carrying the UNSTRIPPED original transcript, not just `.command`/`.action`
// failures. `CommandModeOutcome.noSelection` / `.modelUnavailable` are
// legitimate no-ops for CommandModeService's own contract (it never blanks a
// selection it can't safely transform) — but for a voice-routed dictation there
// is no selection to fall back to, so those two ALSO degrade to dictation here
// rather than silently discarding the user's words.
//
// SCOPE: this coordinator is a self-contained SpeakCore unit. Wiring it into
// the live pipeline (CaptureSession/SpeakEngine/DictationController) is
// [deferred] — see the task OUTPUT notes. `dictation` → the existing pipeline
// stays completely untouched, matching "H-1 skeleton, no new perms" (spec
// Sequencing #1). Live command execution additionally needs the App-layer AX
// `SelectionAccessing` conformer (`AccessibilitySelection`), already
// `[deferred — human verification]` for `CommandModeController`.

import Foundation

// MARK: - VoiceActionOutcome

/// What `VoiceActionsCoordinator.handle` decided/did for one transcript.
public enum VoiceActionOutcome: Sendable, Equatable {
    /// No routing applied (prefix absent, or Voice Actions disabled). Run the
    /// transcript through the normal dictation pipeline exactly as before.
    case dictation(text: String)
    /// `CommandModeService` transformed the selection and replaced it.
    /// `result` is the replacement text (matches `CommandModeOutcome.replaced`).
    case commandExecuted(result: String)
    /// The named action ran successfully via `ActionExecuting`.
    case actionExecuted(name: String)
    /// Routing selected `.command` or `.action` but resolving it failed for
    /// `reason` — paste `text` (the ORIGINAL, unstripped transcript) exactly as
    /// plain dictation. Never lose the user's words.
    case degradedToDictation(text: String, reason: String)
}

// MARK: - VoiceActionsCoordinator

public struct VoiceActionsCoordinator: Sendable {

    private let router: any ActionRouting
    private let executor: (any ActionExecuting)?
    private let commandService: CommandModeService?
    /// Master toggle — `SettingsStore.voiceActionsEnabled`. `false` (default):
    /// `handle` always returns `.dictation(text:)` immediately, without
    /// consulting the router, so behavior is byte-identical to no Voice Actions
    /// existing at all. [decision H-1: default false, per task brief]
    private let enabled: Bool

    /// - Parameters:
    ///   - router: The intent classifier. `PrefixActionRouter` in production.
    ///   - executor: `nil` disables the `.action` route (always degrades to
    ///     dictation) — e.g. when Shortcuts execution itself is unavailable.
    ///   - commandService: `nil` disables the `.command` route (always degrades
    ///     to dictation) — e.g. when no AX selection conformer is wired yet.
    ///   - enabled: `SettingsStore.voiceActionsEnabled`. Read once per session by
    ///     the caller (same pattern as other settings — see `SpeakEngine.newSession()`).
    public init(
        router: any ActionRouting,
        executor: (any ActionExecuting)? = nil,
        commandService: CommandModeService? = nil,
        enabled: Bool
    ) {
        self.router = router
        self.executor = executor
        self.commandService = commandService
        self.enabled = enabled
    }

    /// Classify and (attempt to) act on `transcript`. Never throws — every
    /// failure path resolves to `.degradedToDictation`.
    ///
    /// - Parameters:
    ///   - transcript: The finalized dictation transcript.
    ///   - knownActionNames: The current action catalog in canonical casing
    ///     (e.g. `executor.listActionNames()`, fetched by the caller). Pass `[]`
    ///     when unavailable — matches never resolve to `.action`.
    public func handle(transcript: String, knownActionNames: [String] = []) async -> VoiceActionOutcome {
        guard enabled else {
            return .dictation(text: transcript)
        }

        switch router.route(transcript, knownActionNames: knownActionNames) {
        case .dictation:
            return .dictation(text: transcript)

        case .command(let instruction):
            return await handleCommand(instruction: instruction, originalTranscript: transcript)

        case .action(let name):
            return await handleAction(name: name, originalTranscript: transcript)
        }
    }

    // MARK: - Route handlers (split out to keep `handle` simple — one job each)

    private func handleCommand(instruction: String, originalTranscript: String) async -> VoiceActionOutcome {
        guard let commandService else {
            SpeakLog.voiceActions.info(
                "VoiceActions: routed to command but no CommandModeService is configured — degrading to dictation."
            )
            return .degradedToDictation(text: originalTranscript, reason: "no command service configured")
        }
        do {
            switch try await commandService.run(instruction: instruction) {
            case .replaced(let result):
                SpeakLog.voiceActions.info("VoiceActions: command executed.")
                return .commandExecuted(result: result)

            case .noSelection:
                // No selection to transform — there is nothing coherent to
                // "command" against, so the words must survive as dictation.
                return .degradedToDictation(text: originalTranscript, reason: "no selection to transform")

            case .modelUnavailable:
                return .degradedToDictation(text: originalTranscript, reason: "cleanup model unavailable")
            }
        } catch {
            SpeakLog.voiceActions.error(
                "VoiceActions: command execution threw — \(error.localizedDescription, privacy: .public)"
            )
            return .degradedToDictation(text: originalTranscript, reason: error.localizedDescription)
        }
    }

    private func handleAction(name: String, originalTranscript: String) async -> VoiceActionOutcome {
        guard let executor else {
            SpeakLog.voiceActions.info(
                "VoiceActions: routed to action '\(name, privacy: .public)' but no executor is configured — degrading to dictation."
            )
            return .degradedToDictation(text: originalTranscript, reason: "no action executor configured")
        }
        switch await executor.run(named: name) {
        case .success:
            SpeakLog.voiceActions.info("VoiceActions: action '\(name, privacy: .public)' executed.")
            return .actionExecuted(name: name)

        case .notFound, .failed:
            SpeakLog.voiceActions.info(
                "VoiceActions: action '\(name, privacy: .public)' failed to run — degrading to dictation."
            )
            return .degradedToDictation(text: originalTranscript, reason: "action '\(name)' failed to run")
        }
    }
}
