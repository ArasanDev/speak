// SpeakCore/VoiceActions/ActionRouting.swift
//
// H-1 (specs/horizon-voice-os.md, Pillar 1): the Voice Actions intent router.
// First stage after a final transcript: classify the utterance as `dictation`
// (default, unchanged), `command` (routes to the existing CommandModeService),
// or `action` (routes to an `ActionExecuting` conformer, e.g. Shortcuts).
//
// THIS SLICE: deterministic prefix gate ONLY — no LLM/3B classification. The
// horizon spec's full design is "deterministic prefix gate + 3B classification"
// (line 22-25); the 3B pass is explicitly out of scope here (H-4/H-3 territory)
// and CS-2 (specs/constraint-split-cs1-finding.md) is the load-bearing prior
// finding for why: gate deterministically first, only add a model pass once
// its fidelity is trustworthy. `NO LLM classification in this slice` per task brief.
//
// [decision H-1] command vs action split, given no 3B pass is available yet:
// after the prefix is stripped, an EXACT (case-insensitive) match against the
// caller-supplied action catalog (`knownActionNames`, e.g. from
// `ActionExecuting.listActionNames()`) routes to `.action`; anything else
// routes to `.command`. This is a deterministic stand-in for the eventual 3B
// classifier — it is NOT a semantic understanding of "is this an OS action,"
// only "does this exact phrase name a user-curated Shortcut." `[deferred]`:
// replace with real classification once a stronger on-device model is
// available (see CS-2's revisit trigger).
//
// PURITY: `PrefixActionRouter` is a pure struct — no I/O, no Date/random, no
// global state — exactly like `VoiceCommandParser` (SpeakCore/Profiles). It is
// unit-testable without `Process`; only `ShortcutsCLIExecutor` touches the OS.

import Foundation

// MARK: - VoiceRoute

/// The routing decision for one finalized transcript.
public enum VoiceRoute: Sendable, Equatable {
    /// No Voice Actions prefix matched (or the feature is disabled). The existing
    /// dictation pipeline runs completely untouched.
    case dictation
    /// The prefix matched and the remainder did not exactly name a known action.
    /// `instruction` is the prefix-stripped, trimmed remainder — the same shape
    /// `CommandModeService.run(instruction:)` already expects.
    case command(instruction: String)
    /// The prefix matched and the remainder exactly named a known action.
    /// `name` is the CANONICAL name as it appeared in the action catalog
    /// (`knownActionNames`), not the user's spoken casing — `shortcuts run`
    /// may be case-sensitive, so callers must run this exact string.
    case action(name: String)
}

// MARK: - ActionRouting

/// Classifies a finalized transcript into a `VoiceRoute`. Conformers must be
/// pure with respect to their inputs (no hidden state affecting the decision)
/// so routing stays independently testable — see `PrefixActionRouter`.
public protocol ActionRouting: Sendable {
    /// Classify `transcript`.
    ///
    /// - Parameters:
    ///   - transcript: The finalized dictation transcript (untrimmed is fine —
    ///     conformers trim internally).
    ///   - knownActionNames: The current action catalog in its CANONICAL casing
    ///     (e.g. the output of `ActionExecuting.listActionNames()`). Pass `[]`
    ///     when the catalog is unavailable — every match falls through to
    ///     `.command` in that case, never `.action`.
    func route(_ transcript: String, knownActionNames: [String]) -> VoiceRoute
}

// MARK: - PrefixActionRouter

/// The deterministic prefix-gate router (H-1). Matches `prefix` case-insensitively
/// against the START of the transcript; everything before the match is ignored
/// (callers pass the transcript as-is). No match → `.dictation`, unconditionally.
///
/// Mirrors `VoiceCommandParser`'s purity contract (SpeakCore/Profiles): given the
/// same inputs, always the same output.
public struct PrefixActionRouter: ActionRouting {

    /// The spoken trigger prefix, e.g. `"hey speak"`. Compared case-insensitively;
    /// leading/trailing whitespace on the configured value is ignored. An empty
    /// (or all-whitespace) prefix disables the gate defensively — every transcript
    /// routes to `.dictation` rather than matching everything.
    public let prefix: String

    public init(prefix: String) {
        self.prefix = prefix
    }

    public func route(_ transcript: String, knownActionNames: [String] = []) -> VoiceRoute {
        let trimmedPrefix = prefix.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmedPrefix.isEmpty else { return .dictation }

        let trimmedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTranscript.isEmpty else { return .dictation }

        let lowerTranscript = trimmedTranscript.lowercased()
        guard lowerTranscript.hasPrefix(trimmedPrefix) else { return .dictation }

        // Strip the matched prefix from the ORIGINAL-cased transcript (preserve the
        // user's casing in whatever gets pasted/executed downstream), matching
        // VoiceCommandParser's convention.
        var remainder = String(trimmedTranscript.dropFirst(trimmedPrefix.count))
        remainder = remainder.trimmingCharacters(in: .whitespacesAndNewlines)
        // A leading comma is common after a spoken address ("hey speak, open
        // downloads") and would otherwise leak into the instruction/action name.
        if remainder.hasPrefix(",") {
            remainder = String(remainder.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // [decision H-1] An empty remainder (the user said only the prefix, e.g.
        // "hey speak" with nothing after it) has no instruction and no action to
        // route — falling through to `.dictation` pastes the (harmless, short)
        // prefix phrase rather than inventing a route for zero content.
        guard !remainder.isEmpty else { return .dictation }

        let lowerRemainder = remainder.lowercased()
        if let canonical = knownActionNames.first(where: { $0.lowercased() == lowerRemainder }) {
            return .action(name: canonical)
        }
        return .command(instruction: remainder)
    }
}
