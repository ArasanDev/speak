// SpeakTests/RequestInputWorkflowTests.swift
//
// AVB-5 (specs/agent-voice-bridge.md §6 `speak_request_input`): unit coverage for
// the MCP-independent domain layer — `HumanResponseOutcome` Codable round-trips,
// `RequestInputExtractor`'s mode-aware extraction and pure lifecycle-decision
// rules, and the CLI wire's `requestInput` encode/decode + outcome mapping.
// `AgentBridgeServerTests.swift` covers the MCP tool-call layer (ambiguous-answer
// → tool execution error, schema/validation). The live CFMessagePort run-loop
// pump itself is out of scope here for the same reason `ask`/`confirm`'s pump is
// — see the note at the bottom of `CLIContractTests.swift`.

import Foundation
@testable import Speak
@testable import SpeakCore
import Testing

// MARK: - HumanResponseOutcome Codable

@Suite("HumanResponseOutcome codec")
struct HumanResponseOutcomeCodecTests {
    @Test("answered with text and choice round-trips")
    func answeredWithBoth() throws {
        let outcome = HumanResponseOutcome.answered(text: "rollback please", choice: "rollback")
        let data = try JSONEncoder().encode(outcome)
        let decoded = try JSONDecoder().decode(HumanResponseOutcome.self, from: data)
        #expect(decoded == outcome)
    }

    @Test("answered with nil text/choice round-trips (ambiguous case)")
    func answeredAmbiguous() throws {
        let outcome = HumanResponseOutcome.answered(text: nil, choice: nil)
        let data = try JSONEncoder().encode(outcome)
        let decoded = try JSONDecoder().decode(HumanResponseOutcome.self, from: data)
        #expect(decoded == outcome)
    }

    @Test("declined/cancelled/timedOut/busy each round-trip",
          arguments: [HumanResponseOutcome.declined, .cancelled, .timedOut, .busy])
    func lifecycleOutcomes(outcome: HumanResponseOutcome) throws {
        let data = try JSONEncoder().encode(outcome)
        let decoded = try JSONDecoder().decode(HumanResponseOutcome.self, from: data)
        #expect(decoded == outcome)
    }
}

// MARK: - RequestInputExtractor: mode-aware extraction

@Suite("RequestInputExtractor.extract")
struct RequestInputExtractorTests {
    @Test("freeform mode always answers with the raw transcript, never declines")
    func freeformAlwaysAnswers() {
        for transcript in ["no", "cancel", "I don't know", "blue"] {
            let outcome = RequestInputExtractor.extract(transcript: transcript, mode: .freeform, choices: [])
            #expect(outcome == .answered(text: transcript, choice: nil))
        }
    }

    @Test("approval mode: an affirmative answer is answered with choice 'approved'")
    func approvalYes() {
        let outcome = RequestInputExtractor.extract(transcript: "yes", mode: .approval, choices: [])
        #expect(outcome == .answered(text: "yes", choice: "approved"))
    }

    @Test("approval mode: a refusal declines")
    func approvalNo() {
        let outcome = RequestInputExtractor.extract(transcript: "nope", mode: .approval, choices: [])
        #expect(outcome == .declined)
    }

    @Test("approval mode: a spoken 'cancel' phrase is ambiguous (answered, nil choice), not .cancelled")
    func approvalCancelPhraseIsAmbiguous() {
        let outcome = RequestInputExtractor.extract(transcript: "cancel", mode: .approval, choices: [])
        #expect(outcome == .answered(text: "cancel", choice: nil))
    }

    @Test("approval mode: unrecognized speech is ambiguous (answered, nil choice)")
    func approvalUnclearIsAmbiguous() {
        let outcome = RequestInputExtractor.extract(transcript: "banana", mode: .approval, choices: [])
        #expect(outcome == .answered(text: "banana", choice: nil))
    }

    @Test("choice mode: exact match returns the matched choice")
    func choiceExactMatch() {
        let outcome = RequestInputExtractor.extract(
            transcript: "rollback", mode: .choice, choices: ["rollback", "forward"]
        )
        #expect(outcome == .answered(text: "rollback", choice: "rollback"))
    }

    @Test("choice mode: the transcript containing a choice's words still matches")
    func choiceContainedMatch() {
        let outcome = RequestInputExtractor.extract(
            transcript: "let's go with rollback please", mode: .choice, choices: ["rollback", "forward"]
        )
        #expect(outcome == .answered(text: "let's go with rollback please", choice: "rollback"))
    }

    @Test("choice mode: an explicit refusal declines regardless of the choice list")
    func choiceRefusalDeclines() {
        let outcome = RequestInputExtractor.extract(
            transcript: "no", mode: .choice, choices: ["rollback", "forward"]
        )
        #expect(outcome == .declined)
    }

    @Test("choice mode: a non-matching answer is ambiguous (answered, nil choice)")
    func choiceNoMatchIsAmbiguous() {
        let outcome = RequestInputExtractor.extract(
            transcript: "something entirely different", mode: .choice, choices: ["rollback", "forward"]
        )
        #expect(outcome == .answered(text: "something entirely different", choice: nil))
    }

    @Test("choice mode matching is case/punctuation-insensitive")
    func choiceMatchNormalizes() {
        let outcome = RequestInputExtractor.extract(
            transcript: "Rollback!", mode: .choice, choices: ["rollback"]
        )
        #expect(outcome == .answered(text: "Rollback!", choice: "rollback"))
    }
}

// MARK: - RequestInputExtractor: pure lifecycle decision rules

@Suite("RequestInputExtractor lifecycle decisions")
struct RequestInputLifecycleDecisionTests {
    @Test("empty transcript at the deadline is .timedOut")
    func emptyTranscriptDeadlineReached() {
        #expect(RequestInputExtractor.outcomeForEmptyTranscript(reachedDeadline: true) == .timedOut)
    }

    @Test("empty transcript from an early user-initiated stop is .cancelled")
    func emptyTranscriptEarlyStop() {
        #expect(RequestInputExtractor.outcomeForEmptyTranscript(reachedDeadline: false) == .cancelled)
    }

    @Test("busy check: idle is never busy")
    func idleIsNotBusy() {
        #expect(RequestInputExtractor.isBusy(icon: .idle) == false)
    }

    @Test("busy check: listening/processing/done/error are all busy",
          arguments: [MenubarIcon.listening, .processing, .done, .error])
    func nonIdleIsBusy(icon: MenubarIcon) {
        #expect(RequestInputExtractor.isBusy(icon: icon) == true)
    }
}

// MARK: - DictationStartOutcome.requestInputRefusal (AVB-5 follow-up)

@Suite("DictationStartOutcome.requestInputRefusal")
struct DictationStartOutcomeRefusalTests {
    @Test(".started never refuses — cliRequestInput should continue the capture")
    func startedContinues() {
        #expect(DictationStartOutcome.started.requestInputRefusal == nil)
    }

    @Test(".collided maps to .busy — this is the self-resolving, retry-later cause")
    func collidedIsBusy() {
        #expect(DictationStartOutcome.collided.requestInputRefusal == .busy)
    }

    @Test(".failed (mute/permission/other error) maps to .timedOut, NEVER .busy — a persistent failure must not tell the calling agent to just retry")
    func failedIsTimedOutNotBusy() {
        let refusal = DictationStartOutcome.failed.requestInputRefusal
        #expect(refusal == .timedOut)
        #expect(refusal != .busy)
    }
}

// MARK: - CLIContract wire: requestInput

@Suite("CLIRequest/CLIReply requestInput wire")
struct CLIRequestInputWireTests {
    @Test("CLIRequest encodes and decodes every requestInput field")
    func requestFieldsRoundTrip() throws {
        let req = CLIRequest(
            cmd: .requestInput, timeout: 45,
            requestId: "req-1", idempotencyKey: "idem-1", prompt: "deploy?",
            mode: .approval, choices: ["yes", "no"], consequence: "irreversible",
            spokenSummary: "Should I deploy?"
        )
        let data = try req.encode()
        let decoded = try CLIRequest.decode(data)
        #expect(decoded.cmd == .requestInput)
        #expect(decoded.timeout == 45)
        #expect(decoded.requestId == "req-1")
        #expect(decoded.idempotencyKey == "idem-1")
        #expect(decoded.prompt == "deploy?")
        #expect(decoded.mode == .approval)
        #expect(decoded.choices == ["yes", "no"])
        #expect(decoded.consequence == "irreversible")
        #expect(decoded.spokenSummary == "Should I deploy?")
    }

    @Test("CLIRequest omits optional requestInput fields when absent")
    func requestOptionalFieldsOmitted() throws {
        let req = CLIRequest(cmd: .requestInput, requestId: "r", prompt: "p", mode: .freeform)
        let data = try req.encode()
        let decoded = try CLIRequest.decode(data)
        #expect(decoded.idempotencyKey == nil)
        #expect(decoded.choices == nil)
        #expect(decoded.consequence == nil)
        #expect(decoded.spokenSummary == nil)
        #expect(decoded.timeout == nil)
    }

    @Test("CLIReply.requestInputResult/decodedHumanResponseOutcome round-trip every outcome",
          arguments: [
            HumanResponseOutcome.answered(text: "blue", choice: nil),
            .answered(text: "yes", choice: "approved"),
            .declined, .cancelled, .timedOut, .busy
          ])
    func replyOutcomeRoundTrips(outcome: HumanResponseOutcome) throws {
        let reply = CLIReply.requestInputResult(outcome)
        #expect(reply.ok == true)
        let data = try reply.encode()
        let decoded = try CLIReply.decode(data)
        #expect(decoded.decodedHumanResponseOutcome() == outcome)
    }

    @Test("decodedHumanResponseOutcome is nil when 'outcome' is missing/unrecognized")
    func decodeMissingOutcomeIsNil() {
        let reply = CLIReply.accepted()
        #expect(reply.decodedHumanResponseOutcome() == nil)
    }
}
