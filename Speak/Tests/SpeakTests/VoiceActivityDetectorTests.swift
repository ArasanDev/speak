// SpeakTests/VoiceActivityDetectorTests.swift
//
// Unit tests for VoiceActivityDetector (Layer 1 Bidirectional Voice).

import AVFoundation
import XCTest
@testable import SpeakCore

private final class EventBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _events: [VoiceActivityDetector.Event] = []

    var events: [VoiceActivityDetector.Event] {
        lock.lock()
        defer { lock.unlock() }
        return _events
    }

    func append(_ event: VoiceActivityDetector.Event) {
        lock.lock()
        _events.append(event)
        lock.unlock()
    }

    func removeAll() {
        lock.lock()
        _events.removeAll()
        lock.unlock()
    }
}

private final class BoolBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: Bool

    init(value: Bool = false) {
        self._value = value
    }

    var value: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _value
        }
        set {
            lock.lock()
            _value = newValue
            lock.unlock()
        }
    }
}

final class VoiceActivityDetectorTests: XCTestCase {

    private func createPCMBuffer(amplitude: Float, frameLength: AVAudioFrameCount = 1024, sampleRate: Double = 16000) -> AVAudioPCMBuffer? {
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameLength),
              let channelData = buffer.floatChannelData else {
            return nil
        }

        buffer.frameLength = frameLength
        let channel = channelData[0]
        for i in 0..<Int(frameLength) {
            channel[i] = amplitude
        }
        return buffer
    }

    func testRMSCalculationSilenceAndSignal() {
        guard let silentBuffer = createPCMBuffer(amplitude: 0.0),
              let loudBuffer = createPCMBuffer(amplitude: 0.5) else {
            XCTFail("Failed to create PCM test buffers")
            return
        }

        let silentRMS = VoiceActivityDetector.calculateRMS(buffer: silentBuffer)
        let loudRMS = VoiceActivityDetector.calculateRMS(buffer: loudBuffer)

        XCTAssertEqual(silentRMS, 0.0, accuracy: 1e-5, "Silence buffer must yield 0.0 RMS")
        XCTAssertEqual(loudRMS, 0.5, accuracy: 1e-3, "Constant 0.5 amplitude buffer must yield 0.5 RMS")

        let silentDB = VoiceActivityDetector.calculateDB(buffer: silentBuffer)
        let loudDB = VoiceActivityDetector.calculateDB(buffer: loudBuffer)

        XCTAssertEqual(silentDB, -100.0, "Silence buffer must yield -100 dBFS floor")
        XCTAssertGreaterThan(loudDB, -10.0, "0.5 amplitude buffer should be > -10 dBFS")
    }

    func testSpeechStartAndSilenceThresholdGating() {
        let config = VoiceActivityDetector.Configuration(
            energyThreshold: 0.03,
            silenceThresholdDuration: 0.2, // 200ms for fast unit testing
            minSpeechDuration: 0.05
        )
        let vad = VoiceActivityDetector(configuration: config)

        let box = EventBox()
        vad.onEvent = { event in
            box.append(event)
        }

        guard let silentBuffer = createPCMBuffer(amplitude: 0.0, frameLength: 800, sampleRate: 16000), // 50ms per buffer
              let loudBuffer = createPCMBuffer(amplitude: 0.2, frameLength: 800, sampleRate: 16000) else {
            XCTFail("Failed to create PCM test buffers")
            return
        }

        // Process silence initial
        vad.processBuffer(silentBuffer)
        XCTAssertFalse(vad.isSpeechActive, "Speech should not be active initially")

        // Process loud buffer -> speech start
        vad.processBuffer(loudBuffer)
        vad.processBuffer(loudBuffer)

        XCTAssertTrue(vad.isSpeechActive, "Speech must be active after exceeding energy threshold for min duration")
        XCTAssertTrue(box.events.contains(.speechStarted), "speechStarted event must be emitted")

        // Process continuous silence to trigger speech end
        box.removeAll()
        // Send 5 silent buffers (250ms total, exceeding 200ms silence threshold)
        for _ in 0..<5 {
            vad.processBuffer(silentBuffer)
        }

        XCTAssertFalse(vad.isSpeechActive, "Speech must end after silence threshold duration")
        let speechEndEvent = box.events.first { event in
            if case .speechEnded = event { return true }
            return false
        }
        XCTAssertNotNil(speechEndEvent, "speechEnded event must be emitted")
    }

    func testBargeInDetectionWhenTTSPlaying() {
        let config = VoiceActivityDetector.Configuration(
            energyThreshold: 0.03,
            silenceThresholdDuration: 0.2,
            minSpeechDuration: 0.02
        )
        let vad = VoiceActivityDetector(configuration: config)

        let bargeInBox = BoolBox(value: false)
        vad.onBargeIn = {
            bargeInBox.value = true
        }

        vad.isTTSPlaying = true
        XCTAssertTrue(vad.isTTSPlaying)

        guard let loudBuffer = createPCMBuffer(amplitude: 0.3, frameLength: 800, sampleRate: 16000) else {
            XCTFail("Failed to create PCM test buffer")
            return
        }

        vad.processBuffer(loudBuffer)

        XCTAssertTrue(bargeInBox.value, "onBargeIn must be triggered when user speaks while TTS is playing")
    }

    func testResetAndPropertyConcurrency() {
        let vad = VoiceActivityDetector()
        vad.isTTSPlaying = true

        guard let loudBuffer = createPCMBuffer(amplitude: 0.3, frameLength: 800, sampleRate: 16000) else {
            XCTFail("Failed to create PCM test buffer")
            return
        }
        vad.processBuffer(loudBuffer)
        XCTAssertTrue(vad.isSpeechActive)

        vad.reset()
        XCTAssertFalse(vad.isSpeechActive, "reset() must clear active speech state")
    }
}
