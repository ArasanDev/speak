// SpeakCore/Audio/AudioCapture.swift
//
// AVAudioEngine microphone wrapper. Installs a tap on the input node, converts
// each buffer to 16 kHz mono Float32 PCM, and streams the converted buffers via
// an AsyncStream for the transcriber to consume (architecture.md §5, §9).
//
// Not an actor: the tap callback runs on a real-time audio thread, so the hot
// path captures only the (thread-safe) AsyncStream continuation and an immutable
// converter — never actor-isolated state. start()/stop() are driven serially by
// the owning session.
//
// W2.1 LEVEL FEED:
//   A parallel `AsyncStream<Double>` (`levelStream`) carries RMS-derived level
//   values (0…1) from the tap callback to the overlay HUD. The tap callback
//   computes RMS on the **input** buffer (pre-conversion, on the audio thread) and
//   yields the result to `levelsContinuation`. This is a read-only side channel —
//   it does NOT consume the PCM buffer stream (which is single-consumer for the
//   transcriber). The level computation is isolated to `Self.rmsLevel(buffer:)`,
//   a pure static helper that touches only immutable buffer data. [decision W2.1]

import AVFoundation
import os

public final class AudioCapture: @unchecked Sendable {

    public enum Constants {
        // 16 kHz mono is the standard ASR input rate (Apple SpeechAnalyzer /
        // Whisper family operate at 16 kHz); resampling here keeps downstream
        // engines uniform. [decision] — revisit if an engine wants native rate.
        public static let targetSampleRate: Double = 16_000
        public static let targetChannels: AVAudioChannelCount = 1
        // Tap buffer size: a common low-latency frame count (~256 ms at 16 kHz
        // equivalent); large enough to avoid overhead, small enough for live
        // partials. [decision] — tune against latency budget (§12) at P13.
        public static let tapBufferSize: AVAudioFrameCount = 4096
        // Level update throttle: emit a new level sample at most once per frame
        // budget. At 16 kHz/4096 frames one tap fires ≈ every 256 ms; at the
        // native input rate (48 kHz) it fires ≈ every 85 ms. Both are fast
        // enough for the HUD waveform — no additional throttle is needed.
        // [decision W2.1: tap cadence drives level updates; no extra timer needed]
    }

    private let engine = AVAudioEngine()
    private let bus: AVAudioNodeBus = 0
    private var converter: AVAudioConverter?
    private var continuation: AsyncStream<AVAudioPCMBuffer>.Continuation?

    // W2.1: Parallel level stream. Carried alongside the PCM buffer stream so the
    // HUD can drive live waveform bars without consuming the single-consumer
    // transcriber stream.
    private var levelsContinuation: AsyncStream<Double>.Continuation?
    /// Holds the level `AsyncStream` between `start()` and the caller's `startLevelStream()` call.
    private var pendingLevelStream: AsyncStream<Double>?

    public init() {}

    /// Starts capture and returns a stream of 16 kHz mono PCM buffers.
    /// The stream finishes when `stop()` is called.
    ///
    /// W2.1: Also starts the parallel level stream (accessible via `startLevelStream()`).
    public func start() throws -> AsyncStream<AVAudioPCMBuffer> {
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: bus)
        guard inputFormat.sampleRate > 0 else {
            throw SpeakError.unknown("No audio input device available")
        }
        guard let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                               sampleRate: Constants.targetSampleRate,
                                               channels: Constants.targetChannels,
                                               interleaved: false) else {
            throw SpeakError.unknown("Could not build 16 kHz mono target format")
        }
        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw SpeakError.unknown("Could not create audio converter")
        }
        self.converter = converter

        let (stream, continuation) = AsyncStream<AVAudioPCMBuffer>.makeStream()
        self.continuation = continuation

        // W2.1: Prepare the level stream continuation so the tap can yield levels
        // from the very first buffer. The stream itself is handed to callers via
        // `startLevelStream()`, which must be called after `start()`.
        let (levelStream, levelsContinuation) = AsyncStream<Double>.makeStream()
        self.levelsContinuation = levelsContinuation
        // levelStream is retained for callers — stored as ivar so `startLevelStream`
        // can return it. We rebuild it each `start()` call.
        self.pendingLevelStream = levelStream

        input.installTap(onBus: bus, bufferSize: Constants.tapBufferSize, format: inputFormat) { buffer, _ in
            // W2.1: Compute RMS from the input buffer (pre-conversion) and yield to
            // the level stream. Runs on the audio render thread — only captures
            // Sendable values (the continuation, immutable buffer data).
            let rms = Self.rmsLevel(buffer: buffer)
            levelsContinuation.yield(rms)
            Self.convert(buffer, to: targetFormat, using: converter, yielding: continuation)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: bus)
            continuation.finish()
            self.continuation = nil
            self.converter = nil
            throw SpeakError.unknown("AVAudioEngine failed to start: \(error.localizedDescription)")
        }

        SpeakLog.audio.info("""
            AudioCapture started: \(inputFormat.sampleRate, privacy: .public)Hz \
            \(inputFormat.channelCount, privacy: .public)ch → \
            \(Constants.targetSampleRate, privacy: .public)Hz mono
            """)
        return stream
    }

    /// W2.1: Returns the live level stream (0…1 RMS values). Must be called after
    /// `start()` — returns `nil` if `start()` has not been called yet.
    ///
    /// The stream finishes when `stop()` is called. Single-consumer: calling this
    /// more than once replaces the prior consumer (the level stream is used only by
    /// the overlay HUD, so single-consumer is sufficient).
    public func startLevelStream() -> AsyncStream<Double>? {
        guard let stream = pendingLevelStream else { return nil }
        pendingLevelStream = nil
        return stream
    }

    /// Stops capture, removes the tap, and finishes the stream. Idempotent.
    public func stop() {
        engine.inputNode.removeTap(onBus: bus)
        if engine.isRunning { engine.stop() }
        continuation?.finish()
        continuation = nil
        levelsContinuation?.finish()
        levelsContinuation = nil
        pendingLevelStream = nil
        converter = nil
        SpeakLog.audio.info("AudioCapture stopped")
    }

    // MARK: - W2.1: RMS level computation

    /// Compute the RMS (root-mean-square) amplitude of a PCM buffer and return it
    /// as a linear value in [0, 1].
    ///
    /// - Runs on the audio render thread — only reads immutable buffer channel data.
    /// - Returns 0.0 when the buffer has no frames or no channel data.
    /// - The result is a raw linear amplitude. Callers should apply
    ///   `levelSmoothed(previous:target:)` before driving bar heights.
    ///
    /// Formula: RMS = sqrt( sum(sample²) / N ). At silence, ≈ 0; at full scale, ≈ 1.
    /// [decision W2.1: RMS on channel 0 only (mono after conversion; input buffer
    ///  may be stereo but channel 0 is sufficient for a VU indicator)]
    static func rmsLevel(buffer: AVAudioPCMBuffer) -> Double {
        guard buffer.frameLength > 0,
              let channelData = buffer.floatChannelData else {
            return 0.0
        }
        let frames = Int(buffer.frameLength)
        let channel = channelData[0]   // channel 0 — mono-sufficient for a VU indicator
        var sumOfSquares: Double = 0.0
        for i in 0 ..< frames {
            let sample = Double(channel[i])
            sumOfSquares += sample * sample
        }
        let rms = sqrt(sumOfSquares / Double(frames))
        // Clamp to [0, 1] — in practice rms ≤ 1 for 32-bit float samples in [-1, 1].
        return min(max(rms, 0.0), 1.0)
    }

    /// Converts one input buffer to the target format and yields it. Runs on the
    /// audio render thread — touches only the passed-in (Sendable/immutable) args.
    private static func convert(_ buffer: AVAudioPCMBuffer,
                                to targetFormat: AVAudioFormat,
                                using converter: AVAudioConverter,
                                yielding continuation: AsyncStream<AVAudioPCMBuffer>.Continuation) {
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1
        guard capacity > 0,
              let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else {
            return
        }

        var supplied = false
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
            if supplied {
                inputStatus.pointee = .noDataNow
                return nil
            }
            supplied = true
            inputStatus.pointee = .haveData
            return buffer
        }

        if let conversionError {
            SpeakLog.audio.error("PCM conversion failed: \(conversionError.localizedDescription, privacy: .public)")
            return
        }
        guard status != .error, output.frameLength > 0 else { return }
        continuation.yield(output)
    }
}
