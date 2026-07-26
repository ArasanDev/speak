// SpeakTests/SpeechSynthesizerStreamTests.swift
//
// Unit tests for SpeechSynthesizerStream (Layer 1 Bidirectional Voice).

import AVFoundation
import XCTest
@testable import SpeakCore

final class SpeechSynthesizerStreamTests: XCTestCase {

    func testInitialState() {
        let stream = SpeechSynthesizerStream()
        XCTAssertEqual(stream.currentState, .idle, "Initial state should be idle")
        XCTAssertFalse(stream.isSpeaking, "Initial speaking state should be false")
    }

    func testStopImmediatelyExecutionTimeSub100ms() {
        let stream = SpeechSynthesizerStream()
        let executionTimeMs = stream.stopImmediately()

        XCTAssertLessThan(executionTimeMs, 100.0, "stopImmediately must complete in sub-100ms")
        XCTAssertEqual(stream.currentState, .stopped, "State must transition to .stopped after stopImmediately()")
    }

    func testSpeakEmptyTextIsNoOp() {
        let stream = SpeechSynthesizerStream()
        stream.speak("   \n\t  ")

        XCTAssertEqual(stream.currentState, .idle, "Empty text speak must remain idle")
        XCTAssertFalse(stream.isSpeaking)
    }

    func testConfigurationUpdate() {
        let stream = SpeechSynthesizerStream()
        var newConfig = SpeechStreamConfiguration()
        newConfig.rate = 0.6
        newConfig.pitch = 1.2
        newConfig.volume = 0.8
        stream.configuration = newConfig

        XCTAssertEqual(stream.configuration.rate, 0.6)
        XCTAssertEqual(stream.configuration.pitch, 1.2)
        XCTAssertEqual(stream.configuration.volume, 0.8)
    }

    func testSpeakStreamCancellation() async {
        let stream = SpeechSynthesizerStream()
        let (textStream, continuation) = AsyncStream<String>.makeStream()

        stream.speakStream(textStream)
        continuation.yield("Hello world")

        let elapsedTimeMs = stream.stopImmediately()
        XCTAssertLessThan(elapsedTimeMs, 100.0, "Sub-100ms cancellation requirement")
        XCTAssertEqual(stream.currentState, .stopped)
    }
}
