// SpeakCore/Audio/MicLevelMonitor.swift
//
// Level-only microphone monitor for the Settings ▸ General mic card and the
// "Test My Voice" sandbox — a second, lightweight `AudioCapture` instance that
// runs while the card is visible so the VU meter proves the mic is live before
// the user ever dictates.
//
// Design:
//   - Owns a private `AudioCapture`; the PCM buffer stream is drained and
//     discarded (an unconsumed AsyncStream buffers unboundedly — the drain task
//     is mandatory, not optional). Only the W2.1 RMS `levelStream` is forwarded
//     to the caller's handler.
//   - Route recovery is inherited, not reimplemented: `AudioCapture` already
//     rebuilds its tap + converter on `.AVAudioEngineConfigurationChange` and
//     on CoreAudio HAL default-input changes, so AirPods connect/disconnect
//     keeps the meter alive without a CoreAudio -10868 surfacing here.
//   - `@unchecked Sendable` + NSLock for `running`/`levelHandler`, matching the
//     C-backed-type concurrency pattern used elsewhere in SpeakCore.

@preconcurrency import AVFoundation
import Foundation

public final class MicLevelMonitor: @unchecked Sendable {

    private let capture: AudioCapture
    private var pcmDrainTask: Task<Void, Never>?
    private var levelDrainTask: Task<Void, Never>?

    private let lock = NSLock()
    private var running = false
    private var levelHandler: (@Sendable (Double) -> Void)?

    public init(capture: AudioCapture = AudioCapture()) {
        self.capture = capture
    }

    deinit { stop() }

    /// `true` while the underlying capture is running.
    public var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return running
    }

    /// Start monitoring. `onLevel` receives raw linear RMS values (0…1) on the
    /// audio tap cadence (≈ every 85 ms at 48 kHz input) — apply
    /// `levelPerceptual` + `levelSmoothedAsymmetric` before driving UI.
    ///
    /// Throws whatever `AudioCapture.start()` throws (no input device, engine
    /// failure). Idempotent: a second `start()` while running is a no-op.
    public func start(onLevel: @escaping @Sendable (Double) -> Void) throws {
        lock.lock()
        if running {
            lock.unlock()
            return
        }
        levelHandler = onLevel
        lock.unlock()

        let stream: AsyncThrowingStream<AVAudioPCMBuffer, Error>
        do {
            stream = try capture.start()
        } catch {
            lock.lock()
            levelHandler = nil
            lock.unlock()
            throw error
        }

        // Mandatory drain — an unconsumed stream buffers every buffer. A thrown
        // finish (unrecoverable route teardown) just ends the meter; the level
        // stream finishes alongside it, so the VU falls back to rest.
        pcmDrainTask = Task {
            do {
                for try await _ in stream { }
            } catch {
                SpeakLog.audio.error(
                    "MicLevelMonitor: capture stream ended with error — \(error.localizedDescription, privacy: .public)"
                )
            }
        }
        levelDrainTask = Task { [weak self] in
            guard let levels = self?.capture.startLevelStream() else { return }
            for await level in levels {
                self?.deliver(level)
            }
        }

        lock.lock()
        running = true
        lock.unlock()
        SpeakLog.audio.info("MicLevelMonitor: started (settings mic check).")
    }

    /// Stop monitoring and tear down the audio tap. Idempotent.
    public func stop() {
        pcmDrainTask?.cancel()
        pcmDrainTask = nil
        levelDrainTask?.cancel()
        levelDrainTask = nil
        capture.stop()

        lock.lock()
        running = false
        levelHandler = nil
        lock.unlock()
    }

    private func deliver(_ level: Double) {
        lock.lock()
        let handler = levelHandler
        lock.unlock()
        handler?(level)
    }
}
