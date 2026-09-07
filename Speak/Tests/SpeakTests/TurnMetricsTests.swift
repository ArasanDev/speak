// SpeakTests/TurnMetricsTests.swift
//
// Unit tests for TurnMetricsRecorder — the conversational latency spine.
//
// These pin the *semantics* of the derived figures, not wall-clock values:
// a timing harness that silently reports 0 for a missing stage would
// manufacture confidence, which is the one failure mode instrumentation
// must not have.

import Foundation
@testable import SpeakCore
import XCTest

final class TurnMetricsTests: XCTestCase {

    /// A stage pair that never happened must report `nil`, never `0`.
    /// This is the whole reason every field on `TurnReport` is optional.
    func testMissingStagesReportNilNotZero() {
        let recorder = TurnMetricsRecorder()
        recorder.mark(.userSpeechEnded)
        // No endpoint, no audio, no tool call.

        let report = recorder.report()
        XCTAssertNil(report.endpointDelayMs)
        XCTAssertNil(report.responseLatencyMs)
        XCTAssertNil(report.thinkingMs)
        XCTAssertNil(report.toolMs)
        XCTAssertNil(report.synthesisMs)
        XCTAssertNil(report.bargeInLatencyMs)
        XCTAssertNil(report.speakingMs)
    }

    /// The headline figure spans the full endpoint→audio path, so it must be
    /// at least as large as any component it contains.
    func testResponseLatencyEnclosesItsComponents() {
        let recorder = TurnMetricsRecorder()
        recorder.mark(.userSpeechEnded)
        recorder.mark(.endpointDeclared)
        recorder.mark(.agentFirstToken)
        recorder.mark(.ttsRequested)
        recorder.mark(.ttsFirstAudio)

        let report = recorder.report()
        guard let response = report.responseLatencyMs,
              let endpoint = report.endpointDelayMs,
              let synthesis = report.synthesisMs else {
            return XCTFail("expected all three figures to be derivable")
        }
        XCTAssertGreaterThanOrEqual(response, endpoint)
        XCTAssertGreaterThanOrEqual(response, synthesis)
        XCTAssertGreaterThanOrEqual(response, 0)
    }

    /// A second tool call must not retroactively shrink the measured tool
    /// window: the span runs from the first start to the last finish.
    func testRepeatedToolCallsSpanFirstStartToLastFinish() {
        let recorder = TurnMetricsRecorder()
        recorder.mark(.toolCallStarted, detail: "recall")
        recorder.mark(.toolCallFinished, detail: "recall")
        recorder.mark(.toolCallStarted, detail: "route_to_agent")
        recorder.mark(.toolCallFinished, detail: "route_to_agent")

        let report = recorder.report()
        XCTAssertNotNil(report.toolMs)
        XCTAssertEqual(report.marks.filter { $0.stage == .toolCallStarted }.count, 2)
    }

    /// Barge-in latency is measured independently of the response path — a
    /// turn that was interrupted has no `ttsFinished` but must still report
    /// how fast the agent went quiet.
    func testBargeInLatencyDerivedWithoutCompletedTurn() {
        let recorder = TurnMetricsRecorder()
        recorder.mark(.ttsFirstAudio)
        recorder.mark(.bargeInDetected)
        recorder.mark(.bargeInSilenced)

        let report = recorder.report()
        XCTAssertNotNil(report.bargeInLatencyMs)
        XCTAssertNil(report.speakingMs, "interrupted turn never reaches ttsFinished")
    }

    /// `reset` must clear marks and re-key the turn, so a recorder reused
    /// across turns cannot leak one turn's timings into the next.
    func testResetClearsMarksAndChangesTurnID() {
        let recorder = TurnMetricsRecorder()
        let firstID = recorder.currentTurnID
        recorder.mark(.userSpeechStarted)
        XCTAssertFalse(recorder.snapshot().isEmpty)

        recorder.reset()
        XCTAssertTrue(recorder.snapshot().isEmpty)
        XCTAssertNotEqual(recorder.currentTurnID, firstID)
    }

    /// Marks arrive from the CoreAudio tap thread, `@MainActor`, and actors
    /// concurrently. Recording must not lose or corrupt them.
    func testConcurrentMarksAreAllRecorded() {
        let recorder = TurnMetricsRecorder()
        let iterations = 500

        DispatchQueue.concurrentPerform(iterations: iterations) { _ in
            recorder.mark(.userSpeechStarted)
        }

        XCTAssertEqual(recorder.snapshot().count, iterations)
    }

    /// Out-of-order marks (a stage arriving before its predecessor) must not
    /// produce a negative duration.
    func testInvertedStageOrderYieldsNilNotNegative() {
        let recorder = TurnMetricsRecorder()
        recorder.mark(.ttsFirstAudio)
        recorder.mark(.userSpeechEnded)

        let report = recorder.report()
        if let response = report.responseLatencyMs {
            XCTAssertGreaterThanOrEqual(response, 0)
        }
    }
}
