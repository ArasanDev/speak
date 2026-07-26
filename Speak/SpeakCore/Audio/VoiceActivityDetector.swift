// SpeakCore/Audio/VoiceActivityDetector.swift
//
// Fast RMS-based Voice Activity Detector (VAD) with silence threshold gating
// and barge-in interruption detection.
//
// Part of Layer 1 of the Bidirectional Voice Architecture.

import AVFoundation
import Foundation
import os

/// Detects voice activity and barge-in interruption events in streaming PCM audio buffers.
public final class VoiceActivityDetector: @unchecked Sendable {

    /// Events emitted by the Voice Activity Detector.
    public enum Event: Equatable, Sendable {
        /// User speech has started.
        case speechStarted

        /// User speech has ended after continuous silence for at least `silenceThresholdDuration`.
        case speechEnded(duration: TimeInterval)

        /// User spoke while TTS readback was active (barge-in interruption event).
        case bargeIn
    }

    /// Configuration options for VoiceActivityDetector.
    public struct Configuration: Sendable {
        /// RMS energy threshold [0.0, 1.0] to declare speech active (default: 0.03).
        public var energyThreshold: Double

        /// Continuous silence duration (in seconds) required to declare speech end (default: 0.6s / 600ms).
        public var silenceThresholdDuration: TimeInterval

        /// Minimum duration (in seconds) above `energyThreshold` before declaring speech start (default: 0.05s / 50ms).
        public var minSpeechDuration: TimeInterval

        public init(
            energyThreshold: Double = 0.03,
            silenceThresholdDuration: TimeInterval = 0.6,
            minSpeechDuration: TimeInterval = 0.05
        ) {
            self.energyThreshold = energyThreshold
            self.silenceThresholdDuration = silenceThresholdDuration
            self.minSpeechDuration = minSpeechDuration
        }
    }

    private let lock = NSLock()
    private var config: Configuration
    private var speechActive = false
    private var ttsPlaying = false
    private var hasEmittedBargeInForCurrentSpeech = false

    private var currentSpeechDuration: Double = 0.0
    private var currentSilenceDuration: Double = 0.0

    // Callback event handlers
    public var onEvent: (@Sendable (Event) -> Void)?
    public var onBargeIn: (@Sendable () -> Void)?
    public var onSpeechStart: (@Sendable () -> Void)?
    public var onSpeechEnd: (@Sendable (TimeInterval) -> Void)?

    private var eventContinuation: AsyncStream<Event>.Continuation?
    public let eventStream: AsyncStream<Event>

    public init(configuration: Configuration = Configuration()) {
        self.config = configuration
        let (stream, continuation) = AsyncStream<Event>.makeStream()
        self.eventStream = stream
        self.eventContinuation = continuation
    }

    deinit {
        eventContinuation?.finish()
    }

    // MARK: - Properties

    /// Whether TTS audio is currently active/playing. Setting this to `true` allows VAD
    /// to trigger `bargeIn` events when speech is detected.
    public var isTTSPlaying: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return ttsPlaying
        }
        set {
            lock.lock()
            ttsPlaying = newValue
            if !newValue {
                hasEmittedBargeInForCurrentSpeech = false
            }
            lock.unlock()
        }
    }

    /// Whether speech is currently detected as active.
    public var isSpeechActive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return speechActive
    }

    /// Current VAD configuration.
    public var configuration: Configuration {
        get {
            lock.lock()
            defer { lock.unlock() }
            return config
        }
        set {
            lock.lock()
            config = newValue
            lock.unlock()
        }
    }

    // MARK: - Buffer Processing

    /// Process a PCM audio buffer and update VAD state.
    /// Returns any event generated during buffer processing.
    ///
    /// Non-blocking, thread-safe, and suitable for direct invocation inside real-time audio tap callbacks.
    @discardableResult
    public func processBuffer(_ buffer: AVAudioPCMBuffer) -> Event? {
        let rms = Self.calculateRMS(buffer: buffer)
        let frameRate = buffer.format.sampleRate
        let bufferDuration = frameRate > 0 ? Double(buffer.frameLength) / frameRate : 0.0

        var eventsToEmit: [Event] = []
        var directReturnEvent: Event?

        lock.lock()
        let activeTTS = ttsPlaying

        if rms >= config.energyThreshold {
            currentSilenceDuration = 0.0
            currentSpeechDuration += bufferDuration

            if !speechActive {
                if currentSpeechDuration >= config.minSpeechDuration {
                    speechActive = true
                    eventsToEmit.append(.speechStarted)
                    directReturnEvent = .speechStarted

                    if activeTTS && !hasEmittedBargeInForCurrentSpeech {
                        hasEmittedBargeInForCurrentSpeech = true
                        eventsToEmit.append(.bargeIn)
                        directReturnEvent = .bargeIn
                    }
                }
            } else if activeTTS && !hasEmittedBargeInForCurrentSpeech {
                hasEmittedBargeInForCurrentSpeech = true
                eventsToEmit.append(.bargeIn)
                directReturnEvent = .bargeIn
            }
        } else {
            if speechActive {
                currentSilenceDuration += bufferDuration
                if currentSilenceDuration >= config.silenceThresholdDuration {
                    speechActive = false
                    hasEmittedBargeInForCurrentSpeech = false
                    let totalDuration = currentSpeechDuration
                    currentSpeechDuration = 0.0
                    currentSilenceDuration = 0.0
                    eventsToEmit.append(.speechEnded(duration: totalDuration))
                    directReturnEvent = .speechEnded(duration: totalDuration)
                }
            } else {
                currentSpeechDuration = 0.0
                currentSilenceDuration += bufferDuration
            }
        }
        lock.unlock()

        for event in eventsToEmit {
            emit(event)
        }

        return directReturnEvent
    }

    /// Reset internal speech and silence counters and state.
    public func reset() {
        lock.lock()
        speechActive = false
        hasEmittedBargeInForCurrentSpeech = false
        currentSpeechDuration = 0.0
        currentSilenceDuration = 0.0
        lock.unlock()
    }

    // MARK: - RMS Audio Energy Computation

    /// Calculate RMS (root-mean-square) linear audio amplitude in range [0.0, 1.0] for a PCM buffer.
    public static func calculateRMS(buffer: AVAudioPCMBuffer) -> Double {
        guard buffer.frameLength > 0 else { return 0.0 }

        if let floatData = buffer.floatChannelData {
            return calculateFloatRMS(floatData: floatData, format: buffer.format, frameLength: buffer.frameLength)
        } else if let int16Data = buffer.int16ChannelData {
            return calculateInt16RMS(int16Data: int16Data, format: buffer.format, frameLength: buffer.frameLength)
        }
        return 0.0
    }

    private static func calculateFloatRMS(
        floatData: UnsafePointer<UnsafeMutablePointer<Float>>,
        format: AVAudioFormat,
        frameLength: AVAudioFrameCount
    ) -> Double {
        let channelCount = Int(format.channelCount)
        let frames = Int(frameLength)
        guard channelCount > 0, frames > 0 else { return 0.0 }

        var sumOfSquares: Double = 0.0
        for channel in 0..<channelCount {
            let samples = floatData[channel]
            var channelSum: Double = 0.0
            for i in 0..<frames {
                let sample = Double(samples[i])
                channelSum += sample * sample
            }
            sumOfSquares += channelSum
        }
        let totalSamples = Double(frames * channelCount)
        guard totalSamples > 0 else { return 0.0 }
        let rms = sqrt(sumOfSquares / totalSamples)
        return min(max(rms, 0.0), 1.0)
    }

    private static func calculateInt16RMS(
        int16Data: UnsafePointer<UnsafeMutablePointer<Int16>>,
        format: AVAudioFormat,
        frameLength: AVAudioFrameCount
    ) -> Double {
        let channelCount = Int(format.channelCount)
        let frames = Int(frameLength)
        guard channelCount > 0, frames > 0 else { return 0.0 }

        var sumOfSquares: Double = 0.0
        for channel in 0..<channelCount {
            let samples = int16Data[channel]
            var channelSum: Double = 0.0
            for i in 0..<frames {
                let sample = Double(samples[i]) / 32768.0
                channelSum += sample * sample
            }
            sumOfSquares += channelSum
        }
        let totalSamples = Double(frames * channelCount)
        guard totalSamples > 0 else { return 0.0 }
        let rms = sqrt(sumOfSquares / totalSamples)
        return min(max(rms, 0.0), 1.0)
    }

    /// Calculate decibel level (dBFS) for a PCM buffer, range approx [-100 dB, 0 dB].
    public static func calculateDB(buffer: AVAudioPCMBuffer) -> Double {
        let rms = calculateRMS(buffer: buffer)
        guard rms > 1e-5 else { return -100.0 }
        let db = 20.0 * log10(rms)
        return max(-100.0, min(0.0, db))
    }

    // MARK: - Private Helpers

    private func emit(_ event: Event) {
        eventContinuation?.yield(event)
        onEvent?(event)

        switch event {
        case .speechStarted:
            SpeakLog.audio.info("VAD: Speech started")
            onSpeechStart?()

        case .speechEnded(let duration):
            SpeakLog.audio.info("VAD: Speech ended (duration: \(duration, privacy: .public)s)")
            onSpeechEnd?(duration)

        case .bargeIn:
            SpeakLog.audio.info("VAD: Barge-in interruption detected")
            onBargeIn?()
        }
    }
}
