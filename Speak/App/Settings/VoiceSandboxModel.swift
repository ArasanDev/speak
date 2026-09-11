// App/Settings/VoiceSandboxModel.swift
//
// Drives the Settings ▸ AI Models "Test My Voice" sandbox: hold (or tap) the
// pill → a `VoiceSandbox` session records through the real pipeline (locale,
// vocabulary + corrections, snippet expansion, cleanup mode — everything
// `SpeakEngine.newSession` assembles minus paste and delivery) → the inline
// diff shows exactly what the chosen engine/level does to the user's voice.
//
// The session's partials stream drives the live transcript text; the
// transcriber's AudioCapture level feed (unconsumed in a sandbox — no HUD is
// attached) drives the in-card VU meter.
//
// `@MainActor @Observable` — same pattern as the other app view-models.
// Session/actor hops happen inside `begin`/`end`; UI observes plain vars.

import SpeakCore
import SwiftUI

@MainActor
@Observable
final class VoiceSandboxModel {

    enum Phase: Equatable {
        case idle
        case listening
        case processing
        case done
        case failed(String)

        var isFailure: Bool {
            if case .failed = self { return true }
            return false
        }
    }

    private(set) var phase: Phase = .idle
    /// Live transcript text while listening (partials + finalized so far).
    private(set) var transcriptText = ""
    /// Smoothed perceptual mic level (0…1) for the in-card VU meter.
    private(set) var level: Double = 0
    /// Seconds since capture started, for the elapsed readout.
    private(set) var elapsed: TimeInterval = 0
    /// The finished run — raw + cleaned text for `CleanupDiffView`.
    private(set) var result: TranscriptionResult?
    /// Wall-clock ms spent in `session.stop()` — STT finalize + the LLM pass.
    private(set) var processingMilliseconds: Int?

    /// Safety cap so a latched (tap-mode) recording can't run forever.
    /// [decision: 60 s — a test sentence is ~4 s; the cap exists only to avoid
    ///  an orphaned session if the user walks away with the pill latched]
    static let maxRecordingSeconds: TimeInterval = 60

    private var sandbox: VoiceSandbox?
    private var session: CaptureSession?
    private var partialsTask: Task<Void, Never>?
    private var levelsTask: Task<Void, Never>?
    private var clockTask: Task<Void, Never>?
    private var accumulator = OverlayTextAccumulator()

    /// Begin a sandbox recording. No-op unless idle/done/failed.
    func begin(settings: SettingsStore, snippetStore: SnippetStore?) async {
        guard phase == .idle || phase == .done || phase.isFailure else { return }

        let sandbox = VoiceSandbox(settings: settings, snippetStore: snippetStore)
        let session = sandbox.makeSession()
        self.sandbox = sandbox
        self.session = session
        result = nil
        processingMilliseconds = nil
        transcriptText = ""
        level = 0
        elapsed = 0

        accumulator.reset()
        partialsTask = Task { [weak self] in
            let stream = await session.partials()
            for await chunk in stream {
                guard let self, !Task.isCancelled else { return }
                self.transcriptText = self.accumulator.next(chunk)
            }
        }

        do {
            try await session.start()
        } catch {
            phase = .failed("Couldn't start capture: \(error.localizedDescription)")
            teardown()
            return
        }
        phase = .listening
        startLevelFeed(sandbox)
        startClock()
    }

    /// Live level feed — only flows when the resolved transcriber exposes one.
    private func startLevelFeed(_ sandbox: VoiceSandbox) {
        levelsTask = Task { [weak self] in
            guard let levels = sandbox.levelStream() else { return }
            for await rms in levels {
                guard let self, !Task.isCancelled else { return }
                let perceptual = levelPerceptual(rms: rms)
                self.level = levelSmoothedAsymmetric(previous: self.level, target: perceptual)
            }
        }
    }

    /// Elapsed readout + the latched-recording safety cap.
    private func startClock() {
        clockTask = Task { [weak self] in
            let start = Date()
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard let self, !Task.isCancelled else { return }
                self.elapsed = Date().timeIntervalSince(start)
                if self.elapsed >= Self.maxRecordingSeconds, self.phase == .listening {
                    await self.end()
                    return
                }
            }
        }
    }

    /// Stop recording and run the cleanup pass. No-op unless listening.
    func end() async {
        guard phase == .listening, let session else { return }
        phase = .processing
        partialsTask?.cancel()
        partialsTask = nil
        levelsTask?.cancel()
        levelsTask = nil
        clockTask?.cancel()
        clockTask = nil

        let started = ContinuousClock.now
        do {
            let finished = try await session.stop()
            processingMilliseconds = Int(
                (ContinuousClock.now - started).components.attoseconds / 1_000_000_000_000_000
            )
            result = finished
            transcriptText = finished.rawText
            phase = .done
        } catch {
            phase = .failed("Cleanup failed: \(error.localizedDescription)")
        }
        level = 0
        self.session = nil
        sandbox = nil
    }

    /// Return to idle from a finished/failed run, clearing the displayed result.
    /// No-op while a run is in flight (listening/processing).
    func reset() {
        switch phase {
        case .listening, .processing:
            return
        case .idle, .done, .failed:
            teardown()
            phase = .idle
            transcriptText = ""
            result = nil
            processingMilliseconds = nil
            elapsed = 0
        }
    }

    /// Abandon a run (view disappearing mid-record). Safe from any phase.
    func cancel() async {
        if let session {
            await session.cancel()
        }
        teardown()
        phase = .idle
    }

    private func teardown() {
        partialsTask?.cancel()
        partialsTask = nil
        levelsTask?.cancel()
        levelsTask = nil
        clockTask?.cancel()
        clockTask = nil
        session = nil
        sandbox = nil
        level = 0
    }
}
