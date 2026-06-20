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
    }

    private let engine = AVAudioEngine()
    private let bus: AVAudioNodeBus = 0
    private var converter: AVAudioConverter?
    private var continuation: AsyncStream<AVAudioPCMBuffer>.Continuation?

    public init() {}

    /// Starts capture and returns a stream of 16 kHz mono PCM buffers.
    /// The stream finishes when `stop()` is called.
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

        input.installTap(onBus: bus, bufferSize: Constants.tapBufferSize, format: inputFormat) { buffer, _ in
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

    /// Stops capture, removes the tap, and finishes the stream. Idempotent.
    public func stop() {
        engine.inputNode.removeTap(onBus: bus)
        if engine.isRunning { engine.stop() }
        continuation?.finish()
        continuation = nil
        converter = nil
        SpeakLog.audio.info("AudioCapture stopped")
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
