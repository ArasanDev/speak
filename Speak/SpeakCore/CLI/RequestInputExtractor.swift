// SpeakCore/CLI/RequestInputExtractor.swift
//
// AVB-5 (specs/agent-voice-bridge.md §6): deterministic mode-aware extraction
// from a raw spoken-answer transcript to a `HumanResponseOutcome`. Pure
// function, no LLM — extends `YesNoCancelExtractor`'s phrase-list approach
// rather than duplicating it, so `speak_confirm`'s adapter (approval mode) and
// `speak_request_input`'s approval mode agree by construction.
//
// Scope: this extractor only ever produces `.answered` or `.declined` — it
// never returns `.cancelled`/`.timedOut`/`.busy` (those are capture-lifecycle
// outcomes decided by the caller before a transcript exists at all). A spoken
// "cancel" phrase or genuinely unrecognized speech in `.choice`/`.approval`
// mode is *not* `.declined` — it comes back as `.answered(text:, choice: nil)`
// so the raw transcript is preserved; the MCP tool layer (AgentBridgeServer)
// treats a nil `choice` in `.choice`/`.approval` mode as an ambiguous-answer
// tool execution error rather than a false success. [decision: AVB-5 — locked
// per the orchestrator's final rule: ambiguity is never one of the five
// canonical outcomes on its own, it rides inside `.answered`]

import Foundation

public enum RequestInputExtractor {

    /// Pure decision rule for the empty-transcript case (`DictationController
    /// .cliRequestInput`) — no speech was captured, so the outcome depends only on
    /// *why* the capture ended: the request's own deadline was reached while still
    /// listening (`reachedDeadline == true`, the caller then stops the capture
    /// itself) → `.timedOut`; the human stopped the capture on their own
    /// (Escape/hotkey/user stop) before the deadline → `.cancelled`. Factored out
    /// as a pure function (mirrors `CLIContractTests.idempotencyDecision`'s pure-
    /// mirror pattern) so this rule is directly unit-testable without a live
    /// `DictationController`/mic/HUD. [decision: AVB-5]
    public static func outcomeForEmptyTranscript(reachedDeadline: Bool) -> HumanResponseOutcome {
        reachedDeadline ? .timedOut : .cancelled
    }

    /// Pure decision rule for the busy pre-check: `DictationController
    /// .cliRequestInput` refuses immediately (before speaking or opening the mic)
    /// whenever another agent-initiated or hotkey capture is already in flight —
    /// including a concurrent `requestInput` call re-entering while the first is
    /// still open, regardless of whether it shares the same `idempotencyKey`
    /// (in-flight dedupe only; no queueing). [decision: AVB-5]
    public static func isBusy(icon: MenubarIcon) -> Bool {
        icon != .idle
    }

    /// Extract a `HumanResponseOutcome` from a non-empty spoken-answer transcript.
    /// Callers are responsible for the empty-transcript case (`.cancelled`/
    /// `.timedOut`) — this function assumes an answer was actually captured.
    public static func extract(transcript: String, mode: RequestInputMode, choices: [String]) -> HumanResponseOutcome {
        switch mode {
        case .freeform:
            // Never declines — a refusal in freeform mode is just the content
            // of the answer, not a distinct outcome. [decision: AVB-5]
            return .answered(text: transcript, choice: nil)

        case .approval:
            switch YesNoCancelExtractor.extract(transcript) {
            case .yes:
                return .answered(text: transcript, choice: "approved")
            case .no:
                return .declined
            case .cancel, .unclear:
                return .answered(text: transcript, choice: nil)
            }

        case .choice:
            // An explicit refusal ("no", "nope", ...) declines regardless of
            // the choice list. Otherwise match the normalized transcript
            // against each normalized choice (exact match, or the choice text
            // contained in what was said — e.g. answering "the second one,
            // rollback" when the choice is "rollback").
            if YesNoCancelExtractor.extract(transcript) == .no {
                return .declined
            }
            let normalizedTranscript = YesNoCancelExtractor.normalize(transcript)
            for choice in choices {
                let normalizedChoice = YesNoCancelExtractor.normalize(choice)
                guard !normalizedChoice.isEmpty else { continue }
                if normalizedTranscript == normalizedChoice || normalizedTranscript.contains(normalizedChoice) {
                    return .answered(text: transcript, choice: choice)
                }
            }
            return .answered(text: transcript, choice: nil)
        }
    }
}
