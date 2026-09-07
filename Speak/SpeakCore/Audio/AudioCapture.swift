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
//
// VAD FEED (output-conversation-reconnect):
//   A `VoiceActivityDetector` can be attached/detached at any time via
//   `attachVoiceActivityDetector(_:)`, mirroring the W2.1 pattern: the tap
//   callback hands the same raw input buffer to `VoiceActivityDetector.processBuffer`
//   as a read-only side channel, alongside (not instead of) the RMS level feed and
//   the PCM buffer stream. Unlike `levelsContinuation` (rebuilt each `start()`),
//   the VAD attachment is held in `vadBox`, a lock-protected box that survives
//   across `start()`/`stop()` calls so a caller (e.g. agent-bridge capture path) can
//   attach before capture begins or at any point during an already-running
//   session. [decision]

@preconcurrency import AVFoundation
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
    /// Observer for hardware configuration changes (device plug/unplug, Bluetooth route changes).
    private var configObserver: (any NSObjectProtocol)?

    /// Serializes `stop()` against the `.AVAudioEngineConfigurationChange`
    /// handler, which fires on an arbitrary CoreAudio callback thread. Without
    /// this, a config-change-triggered `stop()` can race a caller-triggered
    /// `stop()` and mutate `converter`/`continuation`/`configObserver`
    /// concurrently. [fix: config-change thread race]
    private let stateQueue = DispatchQueue(label: "com.speak.audiocapture.state")

    /// Lock-protected holder for an attached `VoiceActivityDetector`. Unlike
    /// `levelsContinuation`, this survives across `start()`/`stop()` calls — a
    /// caller can attach before capture begins or while it is already running.
    private final class VADBox: @unchecked Sendable {
        private let lock = NSLock()
        private var vad: VoiceActivityDetector?

        func set(_ newValue: VoiceActivityDetector?) {
            lock.lock()
            vad = newValue
            lock.unlock()
        }

        func get() -> VoiceActivityDetector? {
            lock.lock()
            defer { lock.unlock() }
            return vad
        }
    }

    private let vadBox = VADBox()

    /// Lock-protected holder for the active `AVAudioConverter` — see the
    /// usage note at its call sites in `start()`.
    final class ConverterBox: @unchecked Sendable {
        private let lock = NSLock()
        private var value: AVAudioConverter
        init(_ value: AVAudioConverter) { self.value = value }
        func get() -> AVAudioConverter { lock.lock(); defer { lock.unlock() }; return value }
        func set(_ newValue: AVAudioConverter) { lock.lock(); value = newValue; lock.unlock() }
    }

    public init() {}

    deinit {
        stop()
    }

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

        // Thread-safe state capture for tap callback & dynamic format re-sync.
        // `ConverterBox` (declared below, at class scope so it can also be a
        // parameter type on `reconfigureAfterRouteChangeLocked`) is a
        // lock-protected reference so the tap callback (real-time audio
        // thread) and the config-change closure (arbitrary CoreAudio thread)
        // can both read/replace the active converter without racing.
        let converterBox = ConverterBox(converter)
        let currentContinuation = continuation
        let currentLevelsContinuation = levelsContinuation
        let vadBox = self.vadBox
        let bus = self.bus

        // Installs (or reinstalls) the tap for `format`. Defensively guards
        // against invalid/zero-rate formats — calling `installTap` with such
        // a format is what raises an uncatchable NSException in AVFoundation.
        // Returns `false` if `format` is not usable (caller must not proceed
        // to `engine.start()` in that case).
        let installTap: @Sendable (AVAudioFormat) -> Bool = { format in
            guard format.sampleRate > 0, format.channelCount > 0 else {
                SpeakLog.audio.error("""
                    AudioCapture: refusing to install tap — invalid format \
                    (\(format.sampleRate, privacy: .public)Hz / \(format.channelCount, privacy: .public)ch).
                    """)
                return false
            }
            input.removeTap(onBus: bus)
            input.installTap(onBus: bus, bufferSize: Constants.tapBufferSize, format: format) { buffer, _ in
                let rms = Self.rmsLevel(buffer: buffer)
                currentLevelsContinuation.yield(rms)

                // VAD feed: read-only side channel on the same raw input buffer,
                // independent of the RMS level feed and the PCM buffer stream.
                vadBox.get()?.processBuffer(buffer)

                // Defensive guard: a malformed/zero-rate buffer format must
                // never reach AVAudioConverter — building or using a
                // converter with such a format is another uncatchable
                // NSException path.
                guard buffer.format.sampleRate > 0, buffer.format.channelCount > 0 else {
                    return
                }

                // Dynamic format re-sync: if device sample rate changed mid-stream
                // (e.g. Bluetooth profile switch from 48kHz to 16kHz SCO), rebuild converter on the fly.
                var activeConv = converterBox.get()
                if buffer.format.sampleRate != activeConv.inputFormat.sampleRate ||
                   buffer.format.channelCount != activeConv.inputFormat.channelCount {
                    if let newConv = AVAudioConverter(from: buffer.format, to: targetFormat) {
                        converterBox.set(newConv)
                        activeConv = newConv
                        SpeakLog.audio.info("AudioCapture: dynamic format re-sync to \(buffer.format.sampleRate, privacy: .public)Hz")
                    } else {
                        // Rebuild failed (e.g. incompatible channel layout). Do
                        // NOT fall through to convert() with the stale
                        // converter — that mismatch is the other uncatchable
                        // NSException path (AVAudioConverterFillComplexBuffer).
                        // Drop this buffer; the config-change handler (or the
                        // next buffer, if the mismatch was transient) will
                        // recover the converter.
                        SpeakLog.audio.error("""
                            AudioCapture: dynamic format re-sync FAILED for \
                            \(buffer.format.sampleRate, privacy: .public)Hz/\(buffer.format.channelCount, privacy: .public)ch — dropping buffer.
                            """)
                        return
                    }
                }

                Self.convert(buffer, to: targetFormat, using: activeConv, yielding: currentContinuation)
            }
            return true
        }

        _ = installTap(inputFormat)

        // Register for engine configuration changes (Bluetooth headphones
        // connect/disconnect, sample-rate/route changes). Rebuilds the tap
        // AND the converter against the new hardware format before
        // restarting the engine — restarting with a stale tap/converter is
        // the confirmed crash root cause.
        if configObserver == nil {
            configObserver = NotificationCenter.default.addObserver(
                forName: .AVAudioEngineConfigurationChange,
                object: nil, // nil (not `engine`): lets tests post a synthetic
                             // notification without reflection access to the
                             // private `engine` ivar; in production there is
                             // one `AudioCapture`/engine per active session so
                             // this is not meaningfully broader in practice.
                queue: nil
            ) { [weak self] notification in
                guard let self else { return }
                // Ignore notifications that are unambiguously about a
                // *different* engine instance (production safety net now
                // that we listen broadly).
                if let object = notification.object as AnyObject?,
                   object !== self.engine {
                    return
                }
                // Runs on an arbitrary CoreAudio thread — serialize against
                // `stop()` via `stateQueue`.
                self.stateQueue.sync {
                    self.reconfigureAfterRouteChangeLocked(
                        input: input,
                        bus: bus,
                        targetFormat: targetFormat,
                        converterBox: converterBox,
                        installTap: installTap
                    )
                }
            }
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
    ///
    /// Deliberately does NOT clear `vadBox` — an attached VAD is a caller-owned
    /// attachment, not tied to a single capture session's lifetime, and detaching
    /// is the caller's explicit responsibility via `attachVoiceActivityDetector(nil)`.
    public func stop() {
        stateQueue.sync {
            stopLocked()
        }
    }

    /// Rebuilds the tap and converter against the (possibly new) hardware
    /// input format after a `.AVAudioEngineConfigurationChange` notification,
    /// then restarts the engine. Must only be called while already holding
    /// `stateQueue` (see the call site in `start()`).
    ///
    /// This is the fix for the confirmed crash root cause: the old handler
    /// called `engine.start()` again after a route change WITHOUT removing/
    /// reinstalling the tap against the new format or rebuilding the
    /// converter, which can raise an uncatchable NSException on a format
    /// mismatch. Every step here is guarded so an invalid/zero-rate format
    /// (e.g. the device was fully removed) stops capture cleanly instead of
    /// calling into AVFoundation with bad state.
    private func reconfigureAfterRouteChangeLocked(
        input: AVAudioInputNode,
        bus: AVAudioNodeBus,
        targetFormat: AVAudioFormat,
        converterBox: ConverterBox,
        installTap: @escaping @Sendable (AVAudioFormat) -> Bool
    ) {
        SpeakLog.audio.info("AudioCapture: AVAudioEngineConfigurationChange received — rebuilding tap for new hardware format.")

        // Tear down first — the OS may have already invalidated the old
        // tap/engine graph.
        input.removeTap(onBus: bus)
        if engine.isRunning {
            engine.stop()
        }

        let newInputFormat = input.outputFormat(forBus: bus)
        guard newInputFormat.sampleRate > 0, newInputFormat.channelCount > 0 else {
            SpeakLog.audio.error("AudioCapture: no valid input format after configuration change — stopping capture.")
            stopLocked()
            return
        }
        guard let newConverter = AVAudioConverter(from: newInputFormat, to: targetFormat) else {
            SpeakLog.audio.error("""
                AudioCapture: could not rebuild converter for new format \
                \(newInputFormat.sampleRate, privacy: .public)Hz — stopping capture.
                """)
            stopLocked()
            return
        }
        converterBox.set(newConverter)

        guard installTap(newInputFormat) else {
            stopLocked()
            return
        }

        engine.prepare()
        do {
            try engine.start()
            SpeakLog.audio.info("AudioCapture: engine restarted with tap reinstalled at \(newInputFormat.sampleRate, privacy: .public)Hz.")
        } catch {
            SpeakLog.audio.error("""
                AudioCapture: failed to restart engine after configuration change — \
                \(error.localizedDescription, privacy: .public). Stopping capture.
                """)
            stopLocked()
        }
    }

    /// Actual teardown body. Must only be called while already holding
    /// `stateQueue` (either via `stop()`, or from inside the
    /// `.AVAudioEngineConfigurationChange` handler, which runs its whole body
    /// under `stateQueue.sync`) — calling this directly from `stop()` without
    /// the queue would reintroduce the config-change-handler race.
    private func stopLocked() {
        if let observer = configObserver {
            NotificationCenter.default.removeObserver(observer)
            configObserver = nil
        }
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

    /// Attaches or detaches a `VoiceActivityDetector` to receive the same raw
    /// input buffers the RMS level feed sees. Pass `nil` to detach. Safe to call
    /// before `start()`, while capture is running, or after `stop()`.
    public func attachVoiceActivityDetector(_ vad: VoiceActivityDetector?) {
        vadBox.set(vad)
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

        final class InputBox: @unchecked Sendable {
            var supplied = false
            let buffer: AVAudioPCMBuffer
            init(buffer: AVAudioPCMBuffer) { self.buffer = buffer }
        }

        let box = InputBox(buffer: buffer)
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
            if box.supplied {
                inputStatus.pointee = .noDataNow
                return nil
            }
            box.supplied = true
            inputStatus.pointee = .haveData
            return box.buffer
        }

        if let conversionError {
            SpeakLog.audio.error("PCM conversion failed: \(conversionError.localizedDescription, privacy: .public)")
            return
        }
        guard status != .error, output.frameLength > 0 else { return }
        continuation.yield(output)
    }
}
