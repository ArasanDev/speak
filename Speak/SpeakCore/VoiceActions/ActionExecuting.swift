// SpeakCore/VoiceActions/ActionExecuting.swift
//
// H-1 (specs/horizon-voice-os.md, Pillar 1): the action-execution seam. The
// live conformer (`ShortcutsCLIExecutor`) wraps the system `shortcuts` CLI —
// user-created Shortcuts wrap other apps' App Intents, so the user curates an
// explicit, revocable action catalog. Direct cross-app App Intents invocation
// has no public API `[verified 2026-07-06, validator]`; this is the v1 surface.
//
// CONTRACT (mirrors CommandModeService's "never lose the user's words"):
// any failure here — the shortcut isn't in the catalog, the process errors,
// or it hangs past the timeout — is the CALLER's (VoiceActionsCoordinator's)
// responsibility to degrade to plain dictation. This protocol only reports
// what happened; it never throws away the transcript itself.

import Foundation

// MARK: - ActionExecutionResult

/// The outcome of one `ActionExecuting.run(named:)` call.
public enum ActionExecutionResult: Sendable, Equatable {
    /// The action ran and exited successfully. `output` is any captured stdout
    /// (may be empty/nil — most Shortcuts produce no textual output).
    case success(output: String?)
    /// The named action is not in the current catalog. Conformers that cannot
    /// distinguish "not found" from a generic failure (e.g. `ShortcutsCLIExecutor`,
    /// which only has an exit code + stderr text to go on) may report `.failed`
    /// instead — callers must treat both identically (degrade to dictation).
    case notFound
    /// The action was found but failed to run (nonzero exit, launch error, or
    /// timeout). `detail` is a human-readable reason for logging.
    case failed(String)
}

// MARK: - ActionExecuting

/// Executes named actions from a user-curated catalog (e.g. Shortcuts).
public protocol ActionExecuting: Sendable {
    /// The current action catalog, in canonical (exact) name casing. Returns
    /// `[]` on any failure to enumerate — an empty catalog is always a safe
    /// default (routes fall through to `.command`, never `.action`).
    func listActionNames() async -> [String]

    /// Run the action named `name` (expected to be a canonical name from
    /// `listActionNames()`, e.g. as resolved by `PrefixActionRouter`).
    func run(named name: String) async -> ActionExecutionResult
}
