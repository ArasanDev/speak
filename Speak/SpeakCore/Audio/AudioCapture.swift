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

import Accelerate
import AudioToolbox
@preconcurrency import AVFoundation
import CoreAudio
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

    private var engine = AVAudioEngine()
    private let bus: AVAudioNodeBus = 0
    private var converter: AVAudioConverter?
    /// Throwing stream: a CLEAN finish means `stop()` ran (normal teardown);
    /// a THROWING finish means the input died underneath us (route change with
    /// no valid format, engine restart failure). CaptureSession keys off that
    /// distinction — a clean finish while `.listening` is indistinguishable
    /// from mock/fast-path completion, but a thrown finish is an unambiguous
    /// "torn down externally" signal. [fix: wedge — positive teardown signal]
    private var continuation: AsyncThrowingStream<AVAudioPCMBuffer, Error>.Continuation?

    // W2.1: Parallel level stream. Carried alongside the PCM buffer stream so the
    // HUD can drive live waveform bars without consuming the single-consumer
    // transcriber stream.
    private var levelsContinuation: AsyncStream<Double>.Continuation?
    /// Holds the level `AsyncStream` between `start()` and the caller's `startLevelStream()` call.
    private var pendingLevelStream: AsyncStream<Double>?
    /// Observer for hardware configuration changes (device plug/unplug, Bluetooth route changes).
    private var configObserver: (any NSObjectProtocol)?
    /// Observer token for CoreAudio HAL default input device changes.
    private var monitorToken: UUID?
    /// Observer token for HAL topology changes — lets a pinned-device
    /// preference re-resolve when hardware appears/disappears mid-capture
    /// (the "user's preferred mic reconnects mid-dictation" path).
    private var topologyToken: UUID?

    /// The device the input unit is currently pinned to. `stateQueue`-guarded;
    /// `kAudioDeviceUnknown` while no capture is live.
    private var effectiveDeviceID: AudioDeviceID = kAudioDeviceUnknown

    /// stateQueue-scoped rebuild trigger, bound at `setupObservers` time with
    /// the live tap-install captures. Preference/topology re-resolution calls
    /// it instead of duplicating the rebuild-arg plumbing.
    private var rebuildRequest: (@Sendable () -> Void)?

    /// Lock-guarded storage for `preferredInputDeviceUID` — the property is
    /// written from the main thread (Settings picker) while capture machinery
    /// reads it on `stateQueue`.
    private let preferenceLock = NSLock()
    private var _preferredInputDeviceUID: String?

    /// Pins capture to a specific input device by its stable hardware UID.
    /// `nil` = follow the system default (the pre-preference behavior).
    ///
    /// Resolution + fallback live in `CoreAudioDeviceMonitor.resolvedInputDevice`:
    /// a stored UID whose device is unplugged transparently falls back to the
    /// system default rather than failing the session. Setting this while a
    /// capture is live re-resolves on `stateQueue` and rebuilds the tap only
    /// when the *effective* device actually differs — the "user picked Jabra
    /// in Settings mid-dictation" path. [decision: pinned-device selection]
    public var preferredInputDeviceUID: String? {
        get {
            preferenceLock.lock()
            defer { preferenceLock.unlock() }
            return _preferredInputDeviceUID
        }
        set {
            preferenceLock.lock()
            _preferredInputDeviceUID = newValue
            preferenceLock.unlock()
            stateQueue.async { [weak self] in
                self?.reResolveInputLocked()
            }
        }
    }

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

    /// Tracks the peak RMS level seen across the current capture — the "did
    /// the mic actually hear anything" signal. The tap updates it on the
    /// audio thread; `peakInputLevel` reads it post-stop. A session that
    /// produces no transcript AND never crossed the audible floor means the
    /// input delivered silence (muted headset, wrong pinned device, dead
    /// mic) — distinguishable from "user didn't speak" only via this.
    /// [fix: silent-mic sessions surfaced as silent .done]
    private final class PeakLevelBox: @unchecked Sendable {
        private let lock = NSLock()
        private var value: Double = 0
        func note(_ rms: Double) {
            lock.lock(); defer { lock.unlock() }
            if rms > value { value = rms }
        }
        func peak() -> Double { lock.lock(); defer { lock.unlock() }; return value }
        func reset() { lock.lock(); value = 0; lock.unlock() }
    }
    private let peakLevelBox = PeakLevelBox()

    /// Peak input RMS observed this session (0 = nothing heard). Read after
    /// `stop()` — or anytime; it's a best-effort signal, not a guarantee.
    public var peakInputLevel: Double { peakLevelBox.peak() }

    /// Lock-protected holder for the active `AVAudioConverter` — see the
    /// usage note at its call sites in `start()`.
    final class ConverterBox: @unchecked Sendable {
        private let lock = NSLock()
        private var value: AVAudioConverter
        init(_ value: AVAudioConverter) { self.value = value }
        func get() -> AVAudioConverter { lock.lock(); defer { lock.unlock() }; return value }
        func set(_ newValue: AVAudioConverter) { lock.lock(); value = newValue; lock.unlock() }
    }

    /// Throttles per-buffer fault logging on the real-time audio thread. A
    /// persistent converter failure or a stalled stream consumer would
    /// otherwise emit an os_log per buffer (~90/s). `note()` returns the
    /// 1-based ordinal; callers log the first few and then every 64th.
    /// [fix: audit — RT-thread log spam]
    private final class TapFaultLog: @unchecked Sendable {
        private let lock = NSLock()
        private var conversionFailures = 0
        private var droppedBuffers = 0

        func noteConversionFailure() -> Int {
            lock.lock(); defer { lock.unlock() }
            conversionFailures += 1
            return conversionFailures
        }

        func noteDroppedBuffer() -> Int {
            lock.lock(); defer { lock.unlock() }
            droppedBuffers += 1
            return droppedBuffers
        }

        func resetConversionFailures() {
            lock.lock(); conversionFailures = 0; lock.unlock()
        }
    }

    public init() {}

    deinit {
        stop()
    }

    /// Starts capture and returns a stream of 16 kHz mono PCM buffers.
    /// The stream finishes cleanly when `stop()` is called; it finishes
    /// THROWING `SpeakError.captureInterrupted` when the input route dies
    /// underneath the session (see `teardownLocked(throwing:)`).
    ///
    /// W2.1: Also starts the parallel level stream (accessible via `startLevelStream()`).
    public func start() throws -> AsyncThrowingStream<AVAudioPCMBuffer, Error> {
        // Bounded streams: an unbounded buffer grows ~11 MB/min of PCM if the
        // analyzer stalls (a real stall is on record). 64 buffers ≈ seconds of
        // audio — drops only happen under a stall the 5 s watchdog already
        // tears down, and each drop is logged via `faultLog`.
        // [fix: audit — unbounded AsyncStream]
        let (stream, continuation) = AsyncThrowingStream<AVAudioPCMBuffer, Error>.makeStream(
            bufferingPolicy: .bufferingNewest(64)
        )
        self.continuation = continuation

        // A VU meter only ever needs the latest level — never backlog.
        let (levelStream, levelsContinuation) = AsyncStream<Double>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        self.levelsContinuation = levelsContinuation
        self.pendingLevelStream = levelStream

        // The whole reset → pin → format → tap → observe → start sequence runs
        // on `stateQueue` so a route-change rebuild event can never interleave
        // mid-setup — before this, `installTap` ran on the caller thread while
        // a queued `reconfigureAfterRouteChangeLocked` could removeTap
        // underneath it, leaving a torn engine graph. [fix: audit — start/rebuild race]
        do {
            try stateQueue.sync {
                self.engine.reset()
                let input = self.engine.inputNode

                // Pin the input unit to the persisted preference BEFORE reading
                // the hardware format — `outputFormat` must describe the device
                // actually feeding us. `nil` preference or an unplugged
                // preferred device resolves to the system default.
                // [decision: pinned-device selection]
                self.resolveAndPinInput(on: input)

                let inputFormat = try self.resolveInputFormat(for: input)
                let (targetFormat, converter) = try self.makeTargetFormatAndConverter(from: inputFormat)
                self.converter = converter

                let converterBox = ConverterBox(converter)
                let installTap = self.makeTapInstaller(
                    input: input,
                    targetFormat: targetFormat,
                    converterBox: converterBox,
                    continuation: continuation,
                    levelsContinuation: levelsContinuation
                )
                _ = installTap(inputFormat)

                self.setupObservers(
                    input: input,
                    targetFormat: targetFormat,
                    converterBox: converterBox,
                    installTap: installTap
                )

                self.engine.prepare()
                try self.engine.start()

                SpeakLog.audio.info("""
                    AudioCapture started: \(inputFormat.sampleRate, privacy: .public)Hz \
                    \(inputFormat.channelCount, privacy: .public)ch → \
                    \(Constants.targetSampleRate, privacy: .public)Hz mono
                    """)
            }
        } catch {
            // Shared teardown (removes the config-change observer AND the HAL
            // monitor token — the old path left both bound to the stale input
            // node, so a later device event would "rebuild" a ghost engine with
            // no consumer). [fix: audit — observer leak on start failure]
            stateQueue.sync { self.teardownLocked(throwing: nil) }
            self.engine = AVAudioEngine()
            // Carry the OSStatus code — error.localizedDescription for a raw
            // CoreAudio NSError renders the generic "operation couldn't be
            // completed" boilerplate, which reads as truncated in the HUD.
            let nsError = error as NSError
            throw SpeakError.unknown(
                "Audio engine failed to start (CoreAudio error \(nsError.code)). Check the input device in Settings."
            )
        }

        return stream
    }

    private func makeTargetFormatAndConverter(
        from inputFormat: AVAudioFormat
    ) throws -> (AVAudioFormat, AVAudioConverter) {
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Constants.targetSampleRate,
            channels: Constants.targetChannels,
            interleaved: false
        ) else {
            throw SpeakError.unknown("Could not build 16 kHz mono target format")
        }
        // The tap downmixes to mono BEFORE converting — the converter's input
        // format is mono at the hardware rate, not the raw device format.
        guard let monoFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: inputFormat.sampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw SpeakError.unknown("Could not build mono source format")
        }
        guard let converter = AVAudioConverter(from: monoFormat, to: targetFormat) else {
            throw SpeakError.unknown("Could not create audio converter")
        }
        return (targetFormat, converter)
    }

    private func resolveInputFormat(for input: AVAudioInputNode) throws -> AVAudioFormat {
        // `inputFormat(forBus:)` is the TRUE hardware format; `outputFormat`
        // is the engine's client/presentation format, which can misreport the
        // hardware stream (documented on macOS 26: taps bound to outputFormat
        // receive zeroed buffers while inputFormat delivers real audio).
        // [fix: audit — inputFormat over outputFormat]
        var inputFormat = input.inputFormat(forBus: bus)
        if inputFormat.sampleRate <= 0 || inputFormat.channelCount <= 0 {
            for _ in 0..<3 {
                Thread.sleep(forTimeInterval: 0.05)
                inputFormat = input.inputFormat(forBus: bus)
                if inputFormat.sampleRate > 0 && inputFormat.channelCount > 0 { break }
            }
        }
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw SpeakError.unknown("No audio input device available")
        }
        return inputFormat
    }

    private func makeTapInstaller(
        input: AVAudioInputNode,
        targetFormat: AVAudioFormat,
        converterBox: ConverterBox,
        continuation: AsyncThrowingStream<AVAudioPCMBuffer, Error>.Continuation,
        levelsContinuation: AsyncStream<Double>.Continuation
    ) -> @Sendable (AVAudioFormat) -> Bool {
        let vadBox = self.vadBox
        let bus = self.bus
        let faultLog = TapFaultLog()
        // Bind the box directly — the tap must never capture `self` (a queued
        // block dropping the last strong ref on stateQueue caused the
        // deinit→sync-on-own-queue trap). [fix: audit — deinit trap]
        let peakLevelBox = self.peakLevelBox
        peakLevelBox.reset()

        return { format in
            guard format.sampleRate > 0, format.channelCount > 0 else {
                SpeakLog.audio.error("""
                    AudioCapture: refusing to install tap — invalid format \
                    (\(format.sampleRate, privacy: .public)Hz / \(format.channelCount, privacy: .public)ch).
                    """)
                return false
            }
            input.removeTap(onBus: bus)
            // Explicit format = the resolved HARDWARE input format — not nil
            // (which binds the tap to outputFormat, a documented macOS 26
            // source of zeroed buffers). [fix: audit — inputFormat over outputFormat]
            input.installTap(onBus: bus, bufferSize: Constants.tapBufferSize, format: format) { buffer, _ in
                // Downmix EVERY channel to mono before anything reads it.
                // Channel 0 alone is not guaranteed to carry speech: while
                // another process holds a VoiceProcessingIO session, the mic
                // presents extra streams and ch0 can carry post-AEC gated
                // silence with real audio on ch1/ch2. RMS, VAD, and the STT
                // converter must all see the same mixed signal.
                // [fix: multi-channel mic — speech not always on ch0]
                guard let mono = Self.downmixToMono(buffer) else { return }
                let rms = Self.rmsLevel(buffer: mono)
                peakLevelBox.note(rms)
                levelsContinuation.yield(rms)
                vadBox.get()?.processBuffer(mono)

                var activeConv = converterBox.get()
                if mono.format.sampleRate != activeConv.inputFormat.sampleRate ||
                   mono.format.channelCount != activeConv.inputFormat.channelCount {
                    if let newConv = AVAudioConverter(from: mono.format, to: targetFormat) {
                        converterBox.set(newConv)
                        activeConv = newConv
                        SpeakLog.audio.info("AudioCapture: dynamic format re-sync to \(mono.format.sampleRate, privacy: .public)Hz")
                    } else {
                        SpeakLog.audio.error("AudioCapture: dynamic format re-sync FAILED — dropping buffer.")
                        return
                    }
                }

                Self.convert(
                    mono,
                    to: targetFormat,
                    using: activeConv,
                    faultLog: faultLog,
                    yielding: continuation
                )
            }
            return true
        }
    }

    private func setupObservers(
        input: AVAudioInputNode,
        targetFormat: AVAudioFormat,
        converterBox: ConverterBox,
        installTap: @escaping @Sendable (AVAudioFormat) -> Bool
    ) {
        let bus = self.bus
        if configObserver == nil {
            configObserver = NotificationCenter.default.addObserver(
                forName: .AVAudioEngineConfigurationChange,
                object: nil,
                queue: nil
            ) { [weak self] notification in
                guard let self else { return }
                if let object = notification.object as AnyObject?, object !== self.engine { return }
                // .async, not .sync: the rebuild sleeps (format-retry) and does
                // engine stop/reset/start — it must not block the CoreAudio
                // callback thread that posted the notification. The serial
                // queue still orders it against stop(). [fix: audit — RT-thread]
                //
                // The enqueued block MUST weak-capture self: a strong capture
                // retains AudioCapture until the block runs on stateQueue —
                // if that's the last reference, deinit → stop() →
                // stateQueue.sync fires ON stateQueue itself and dispatch
                // traps (DISPATCH_WAIT_FOR_QUEUE). [fix: audit — deinit trap]
                // scheduleRebuild arms the coalescing flag off-queue, then
                // enqueues the drain — bursts collapse to one rebuild.
                self.scheduleRebuild(
                    input: input,
                    bus: bus,
                    targetFormat: targetFormat,
                    converterBox: converterBox,
                    installTap: installTap
                )
            }
        }

        if monitorToken == nil {
            monitorToken = CoreAudioDeviceMonitor.shared.registerCallback { [weak self] _ in
                guard let self else { return }
                self.scheduleRebuild(
                    input: input,
                    bus: bus,
                    targetFormat: targetFormat,
                    converterBox: converterBox,
                    installTap: installTap
                )
            }
        }

        // Bind the stateQueue-scoped rebuild trigger so preference changes and
        // topology events can re-resolve the effective device without
        // duplicating this argument list. [decision: pinned-device selection]
        rebuildRequest = { [weak self] in
            self?.requestRebuildLocked(
                input: input,
                bus: bus,
                targetFormat: targetFormat,
                converterBox: converterBox,
                installTap: installTap
            )
        }

        // Topology listener: fires on ANY plug/unplug, not just default changes.
        // When a pinned preference is set, this is how "preferred mic
        // reconnects mid-dictation" switches the capture back to it — the
        // default-device callback alone can't see that event.
        if topologyToken == nil {
            topologyToken = CoreAudioDeviceMonitor.shared.registerTopologyCallback { [weak self] _ in
                guard let self else { return }
                self.stateQueue.async { [weak self] in
                    self?.reResolveInputLocked()
                }
            }
        }
    }

    /// Re-resolves the effective input device after a preference change or a
    /// topology event. Rebuilds only when the resolved device actually differs
    /// from what's pinned — an unrelated device plug/unplug during capture is
    /// correctly a no-op. Must run on `stateQueue`.
    private func reResolveInputLocked() {
        guard continuation != nil else { return }
        let resolved = CoreAudioDeviceMonitor.shared.resolvedInputDevice(
            preferredUID: preferredInputDeviceUID
        )
        guard let resolved, resolved.id != effectiveDeviceID else { return }
        SpeakLog.audio.info(
            "AudioCapture: effective input now \(resolved.name, privacy: .public) — rebuilding."
        )
        rebuildRequest?()
    }

    /// Reads the input node's format after a route change, retrying briefly
    /// while the HAL settles — a newly attached device can report a
    /// zero/invalid format for a beat. Returns nil when no valid format
    /// materializes (the device is truly gone).
    private func readSettledInputFormat(on input: AVAudioInputNode, bus: AVAudioNodeBus) -> AVAudioFormat? {
        // Hardware format, not the engine's presentation format — same
        // inputFormat-vs-outputFormat reasoning as resolveInputFormat.
        // [fix: audit — inputFormat over outputFormat]
        var format = input.inputFormat(forBus: bus)
        if format.sampleRate <= 0 || format.channelCount <= 0 {
            for _ in 0..<3 {
                Thread.sleep(forTimeInterval: 0.05)
                format = input.inputFormat(forBus: bus)
                if format.sampleRate > 0 && format.channelCount > 0 { break }
            }
        }
        guard format.sampleRate > 0, format.channelCount > 0 else { return nil }
        return format
    }

    /// Pins the engine's input unit to `deviceID` via
    /// `kAudioOutputUnitProperty_CurrentDevice` — the HAL device-selection
    /// hook on macOS. Must run while the engine is stopped and before the tap
    /// is (re)installed. Always sets explicitly so a cleared preference
    /// deterministically re-pins to the system default. On failure the error
    /// is logged and `effectiveDeviceID` is left stale so the next
    /// re-resolution retries rather than believing the pin landed.
    /// Returns true when the pin was applied (or the unit already targeted
    /// this device). On failure the input unit keeps its current device —
    /// i.e. the system default — which is the graceful-degradation path: a
    /// present-but-unpinnable preferred device must not break capture.
    /// [fix: pin failure degraded into engine-start -10868]
    @discardableResult
    private func pinInputDevice(_ deviceID: AudioDeviceID, on input: AVAudioInputNode) -> Bool {
        guard let audioUnit = input.audioUnit else { return false }
        var id = deviceID
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &id,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        if status == noErr {
            effectiveDeviceID = deviceID
        } else {
            SpeakLog.audio.error(
                "AudioCapture: pinning input device \(deviceID, privacy: .public) failed — \(status, privacy: .public)."
            )
        }
        return status == noErr
    }

    /// Resolve the preferred input (or system default) and pin it. When the
    /// resolved device is present but unpinnable (e.g. an output-only device
    /// persisted before the roster fix), degrade to the system default
    /// rather than letting the session start against a device the unit can't
    /// deliver. Logs the device that will actually feed this session — the
    /// single most useful fact when a dictation comes back empty.
    /// [fix: unpinnable preference → graceful default fallback]
    /// [fix: silent-mic diagnosis needs the live source logged]
    private func resolveAndPinInput(on input: AVAudioInputNode) {
        let monitor = CoreAudioDeviceMonitor.shared
        var resolved = monitor.resolvedInputDevice(preferredUID: preferredInputDeviceUID)
        if let target = resolved,
           !pinInputDevice(target.id, on: input),
           preferredInputDeviceUID != nil,
           let fallback = monitor.currentDefaultInputDevice(),
           fallback.id != target.id {
            // The unit keeps its current device when a pin fails, which is
            // already the system default — pin it explicitly anyway so
            // `effectiveDeviceID` is truthful for the rebuild dedup check.
            SpeakLog.audio.warning(
                "AudioCapture: preferred device '\(target.name, privacy: .public)' unpinnable — falling back to system default '\(fallback.name, privacy: .public)'."
            )
            pinInputDevice(fallback.id, on: input)
            resolved = fallback
        }
        if let target = resolved {
            SpeakLog.audio.info(
                "AudioCapture input: \(target.name, privacy: .public) (uid \(target.uid, privacy: .public), preferred=\(self.preferredInputDeviceUID != nil, privacy: .public))"
            )
        }
    }

    /// Coalescing state for route-change rebuilds — guarded by `rebuildLock`
    /// because `scheduleRebuild` runs on arbitrary CoreAudio callback threads
    /// while the drain runs on `stateQueue`.
    /// [fix: coalescing flag was never armed — serial-queue blocks each ran
    ///  a full rebuild; one physical plug event cost 2–3 engine restarts]
    private let rebuildLock = NSLock()
    private var rebuildQueuedOrInFlight = false
    private var rebuildRequestedAgain = false

    /// Schedules a route-change rebuild from ANY thread. The flag is armed
    /// BEFORE the work is enqueued, so a burst of events (one physical plug
    /// fires both `.AVAudioEngineConfigurationChange` and the HAL default
    /// callback) coalesces into at most one extra rebuild — events arriving
    /// while a rebuild is queued or running only re-arm `rebuildRequestedAgain`.
    private func scheduleRebuild(
        input: AVAudioInputNode,
        bus: AVAudioNodeBus,
        targetFormat: AVAudioFormat,
        converterBox: ConverterBox,
        installTap: @escaping @Sendable (AVAudioFormat) -> Bool
    ) {
        rebuildLock.lock()
        if rebuildQueuedOrInFlight {
            rebuildRequestedAgain = true
            rebuildLock.unlock()
            SpeakLog.audio.info("AudioCapture: route-change burst coalesced into in-flight rebuild.")
            return
        }
        rebuildQueuedOrInFlight = true
        rebuildLock.unlock()
        stateQueue.async { [weak self] in
            self?.requestRebuildLocked(
                input: input,
                bus: bus,
                targetFormat: targetFormat,
                converterBox: converterBox,
                installTap: installTap
            )
        }
    }

    /// Drains rebuild requests on `stateQueue`. Rebuilds once per drain pass;
    /// if a hardware event arrived mid-rebuild (`rebuildRequestedAgain`),
    /// runs once more against the *final* hardware state. Events still
    /// arriving after the drain exits enqueue a fresh pass via
    /// `scheduleRebuild`. Also callable directly on `stateQueue` (the
    /// preference/topology path) — the flag bookkeeping is harmless there.
    private func requestRebuildLocked(
        input: AVAudioInputNode,
        bus: AVAudioNodeBus,
        targetFormat: AVAudioFormat,
        converterBox: ConverterBox,
        installTap: @escaping @Sendable (AVAudioFormat) -> Bool
    ) {
        defer {
            rebuildLock.lock()
            rebuildQueuedOrInFlight = false
            rebuildLock.unlock()
        }
        while continuation != nil {
            rebuildLock.lock()
            rebuildRequestedAgain = false
            rebuildLock.unlock()
            reconfigureAfterRouteChangeLocked(
                input: input,
                bus: bus,
                targetFormat: targetFormat,
                converterBox: converterBox,
                installTap: installTap
            )
            rebuildLock.lock()
            let again = rebuildRequestedAgain
            rebuildLock.unlock()
            if !again { break }
        }
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
            teardownLocked(throwing: nil)
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
        // The handler now dispatches `.async` onto stateQueue — an event queued
        // BEFORE stop()'s teardown can run AFTER it. Without this guard that
        // late rebuild would reinstall a tap and restart an engine with no
        // consumer (the ghost-engine leak). [fix: audit — async rebuild race]
        guard continuation != nil else {
            SpeakLog.audio.info("AudioCapture: route change arrived after teardown — ignoring.")
            return
        }

        SpeakLog.audio.info("AudioCapture: route/device change received — rebuilding tap for new hardware format.")

        // Tear down first — the OS may have already invalidated the old
        // tap/engine graph.
        input.removeTap(onBus: bus)
        if engine.isRunning {
            engine.stop()
        }
        engine.reset()
        // reset() tears down the input AUHAL — the device pin does not
        // provably survive it. Invalidate BEFORE re-resolving so the pin is
        // re-applied unconditionally: skipping it when resolved ==
        // effectiveDeviceID leaves capture on the system default while the
        // code believes the pinned device is live — and the stale
        // effectiveDeviceID masks the drift from every later re-resolution.
        // [fix: pin dropped by engine.reset() never restored]
        effectiveDeviceID = kAudioDeviceUnknown
        resolveAndPinInput(on: input)

        guard let newInputFormat = readSettledInputFormat(on: input, bus: bus) else {
            SpeakLog.audio.error("AudioCapture: no valid input format after configuration change — input lost.")
            failRebuild("input device disappeared or reported an invalid format after a route change")
            return
        }
        // Source format is mono — the tap downmixes before converting.
        // [fix: multi-channel mic — converter input is the mono mix]
        guard let monoFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: newInputFormat.sampleRate,
            channels: 1,
            interleaved: false
        ), let newConverter = AVAudioConverter(from: monoFormat, to: targetFormat) else {
            SpeakLog.audio.error("""
                AudioCapture: could not rebuild converter for new format \
                \(newInputFormat.sampleRate, privacy: .public)Hz — input lost.
                """)
            failRebuild("no converter for the post-route-change format \(newInputFormat.sampleRate)Hz")
            return
        }
        converterBox.set(newConverter)

        guard installTap(newInputFormat) else {
            failRebuild("could not reinstall the input tap on the new route")
            return
        }

        engine.prepare()
        do {
            try engine.start()
            SpeakLog.audio.info("AudioCapture: engine restarted with tap reinstalled at \(newInputFormat.sampleRate, privacy: .public)Hz.")
        } catch {
            SpeakLog.audio.error("""
                AudioCapture: failed to restart engine after configuration change — \
                \(error.localizedDescription, privacy: .public). Input lost.
                """)
            failRebuild("engine restart after route change failed: \(error.localizedDescription)")
        }
    }

    /// Route-rebuild failure path: ends capture with `.captureInterrupted`
    /// so the consumer settles `.error` instead of wedging `.listening`.
    private func failRebuild(_ message: String) {
        teardownLocked(throwing: SpeakError.captureInterrupted(message))
    }

    /// Actual teardown body. Must only be called while already holding
    /// `stateQueue` (either via `stop()`, or from inside the
    /// `.AVAudioEngineConfigurationChange` handler, which runs its whole body
    /// under `stateQueue`) — calling this directly from `stop()` without
    /// the queue would reintroduce the config-change-handler race.
    ///
    /// `throwing`: non-nil when the input died underneath the consumer — the
    /// PCM stream finishes with that error instead of cleanly, which is the
    /// positive signal CaptureSession uses to settle `.error` rather than
    /// wedge `.listening` forever. [fix: wedge]
    private func teardownLocked(throwing error: Error?) {
        if let observer = configObserver {
            NotificationCenter.default.removeObserver(observer)
            configObserver = nil
        }
        if let token = monitorToken {
            CoreAudioDeviceMonitor.shared.unregisterCallback(token)
            monitorToken = nil
        }
        if let token = topologyToken {
            CoreAudioDeviceMonitor.shared.unregisterCallback(token)
            topologyToken = nil
        }
        rebuildRequest = nil
        rebuildLock.lock()
        rebuildQueuedOrInFlight = false
        rebuildRequestedAgain = false
        rebuildLock.unlock()
        effectiveDeviceID = kAudioDeviceUnknown
        engine.inputNode.removeTap(onBus: bus)
        if engine.isRunning { engine.stop() }
        engine.reset()
        if let error {
            continuation?.finish(throwing: error)
        } else {
            continuation?.finish()
        }
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

    /// Downmix a (possibly multi-channel) buffer to mono by averaging all
    /// channels. Channel 0 alone is NOT guaranteed to carry the mic signal —
    /// while another process holds a VoiceProcessingIO session, the built-in
    /// mic presents a reshaped layout where speech can live on later channels
    /// (observed live: ch0 ≈ gated silence, RMS 0.001, while another dictation
    /// app captured normally). Averaging every channel is safe for a mic
    /// array (in-phase content survives) and rescues speech on ANY channel.
    /// Runs on the audio render thread — allocation-free beyond the one
    /// output buffer, vector adds via vDSP. [fix: multi-channel mic]
    static func downmixToMono(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard buffer.frameLength > 0,
              let channelData = buffer.floatChannelData,
              let monoFormat = AVAudioFormat(
                  commonFormat: .pcmFormatFloat32,
                  sampleRate: buffer.format.sampleRate,
                  channels: 1,
                  interleaved: false
              ),
              let mono = AVAudioPCMBuffer(
                  pcmFormat: monoFormat,
                  frameCapacity: buffer.frameCapacity
              ) else {
            return nil
        }
        mono.frameLength = buffer.frameLength
        let channelCount = Int(buffer.format.channelCount)
        let frames = vDSP_Length(buffer.frameLength)
        guard let out = mono.floatChannelData?[0] else { return nil }
        // Zero the accumulator, then add each channel's samples into it.
        // Interleaved buffers expose a single channel pointer — channel c's
        // samples live at offset c with stride channelCount. Dropping such a
        // buffer would silently discard every frame (the original bug class),
        // so handle both layouts. [fix: interleaved input]
        vDSP_vclr(out, 1, frames)
        if buffer.format.isInterleaved {
            for ch in 0..<channelCount {
                vDSP_vadd(out, 1, channelData[0] + ch, channelCount, out, 1, frames)
            }
        } else {
            for ch in 0..<channelCount {
                vDSP_vadd(out, 1, channelData[ch], 1, out, 1, frames)
            }
        }
        if channelCount > 1 {
            var scale = Float(1.0 / Double(channelCount))
            vDSP_vsmul(out, 1, &scale, out, 1, frames)
        }
        return mono
    }

    static func rmsLevel(buffer: AVAudioPCMBuffer) -> Double {
        guard buffer.frameLength > 0,
              let channelData = buffer.floatChannelData else {
            return 0.0
        }
        // vDSP_measqv computes mean-of-squares in one vectorized pass —
        // replaces a scalar Double loop per buffer on the real-time thread.
        // Channel 0 only — mono-sufficient for a VU indicator.
        // [fix: audit — RT-thread hygiene]
        var meanSquare: Float = 0
        vDSP_measqv(channelData[0], 1, &meanSquare, vDSP_Length(buffer.frameLength))
        // Clamp to [0, 1] — in practice rms ≤ 1 for 32-bit float samples in [-1, 1].
        return Double(min(max(sqrt(meanSquare), 0.0), 1.0))
    }

    /// Converts one input buffer to the target format and yields it. Runs on the
    /// audio render thread — touches only the passed-in (Sendable/immutable) args.
    private static func convert(_ buffer: AVAudioPCMBuffer,
                                to targetFormat: AVAudioFormat,
                                using converter: AVAudioConverter,
                                faultLog: TapFaultLog,
                                yielding continuation: AsyncThrowingStream<AVAudioPCMBuffer, Error>.Continuation) {
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
            let n = faultLog.noteConversionFailure()
            if n <= 3 || n % 64 == 0 {
                SpeakLog.audio.error(
                    "PCM conversion failed (x\(n, privacy: .public)): \(conversionError.localizedDescription, privacy: .public)"
                )
            }
            return
        }
        faultLog.resetConversionFailures()
        guard status != .error, output.frameLength > 0 else { return }
        if case .dropped = continuation.yield(output) {
            let n = faultLog.noteDroppedBuffer()
            if n <= 3 || n % 64 == 0 {
                SpeakLog.audio.error(
                    "PCM stream consumer stalled — dropped buffer (x\(n, privacy: .public))"
                )
            }
        }
    }
}
