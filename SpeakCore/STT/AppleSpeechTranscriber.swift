// SpeakCore/STT/AppleSpeechTranscriber.swift
//
// v0 default speech-to-text engine: Apple SpeechAnalyzer (macOS 26+, Apple Silicon).
// Conforms to `Transcribing`. Engine id: "apple-speech-en-US".
//
// Audio injection model
// ─────────────────────
// `startStream(locale:)` in the `Transcribing` protocol is non-async and carries
// no audio parameter. An `AudioBufferProducer` is injected at init (defaulting to
// a live `AudioCapture`). Tests inject a fixture-backed producer. The no-arg
// factory `AppleSpeechTranscriber()` remains valid — it uses the live mic.
//
// Seam note for the orchestrator
// ───────────────────────────────
// CaptureSession (P5+) wires audio to the transcriber. It must pass a concrete
// `AudioBufferProducing` to `AppleSpeechTranscriber(audioProducer:)`, or rely
// on the no-arg default which allocates its own `AudioCapture`. The protocol
// has no audio channel by design (pluggability), so the wiring is CaptureSession's
// responsibility, not the transcriber's.
//
// Authoritative analyzer lifecycle ([verified] WWDC25 #277 + arm64e swiftinterface)
// ─────────────────────────────────────────────────────────────────────────────────
// 1. Build SpeechTranscriber + SpeechAnalyzer.
// 2. `try await analyzer.start(inputSequence:)` — returns AFTER SETUP, not after
//    all input is consumed. The analyzer then processes buffers asynchronously.
// 3. Feed AnalyzerInput(buffer:) via the inputStream continuation as audio arrives.
// 4. When all input is fed (file EOF / producer.stop()):
//    a. Await the bridge task (confirms all AnalyzerInputs are queued).
//    b. `try await analyzer.finalizeAndFinishThroughEndOfInput()` — flushes
//       remaining volatile results and CLOSES transcriber.results.
// 5. Await the results task — it drains whatever results remain, then exits
//    because transcriber.results is now closed.
//
// NOT calling finalizeAndFinishThroughEndOfInput() leaves transcriber.results
// open forever → testTranscribesFixture hangs. [verified: coordinator diagnosis]
//
// SpeechAnalyzer API used — all [verified] from arm64e-apple-macos.swiftinterface
// ─────────────────────────────────────────────────────────────────────────────────
// • SpeechTranscriber.isAvailable: Bool
// • SpeechTranscriber.supportedLocale(equivalentTo:) async -> Locale?
// • SpeechTranscriber(locale:preset:) — preset: .progressiveTranscription
// • AssetInventory.status(forModules:) async -> .unsupported/.supported/.downloading/.installed
// • AssetInventory.assetInstallationRequest(supporting:) async throws -> AssetInstallationRequest?
// • AssetInstallationRequest.downloadAndInstall() async throws
// • SpeechAnalyzer(modules:) convenience init
// • SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith:) async -> AVAudioFormat?
// • SpeechAnalyzer.start(inputSequence:) async throws — RETURNS AFTER SETUP
// • SpeechAnalyzer.finalizeAndFinishThroughEndOfInput() async — CLOSES results
// • SpeechAnalyzer.cancelAndFinishNow() async — hard cancel
// • SpeechTranscriber.results: AsyncSequence<SpeechTranscriber.Result, Error>
// • SpeechTranscriber.Result.text: AttributedString
// • SpeechTranscriber.Result.isFinal: Bool (from SpeechModuleResult extension)
// • AnalyzerInput(buffer:) — wraps AVAudioPCMBuffer
//
// Format note ([verified at runtime]):
// bestAvailableAudioFormat returns 16kHz mono Int16 interleaved on this device.
// P2 outputs 16kHz mono Float32 non-interleaved. An AVAudioConverter bridges them.

import AVFoundation
import Speech
import os

// MARK: - Audio buffer source abstraction

/// Provides a stream of PCM buffers. Production impl uses `AudioCapture`;
/// tests inject a fixture-backed producer.
public protocol AudioBufferProducing: Sendable {
    /// Start and return a stream of PCM buffers. The stream finishes when
    /// `stop()` is called on the producer, or on file EOF in test mode.
    func start() throws -> AsyncStream<AVAudioPCMBuffer>
    /// Stop producing buffers and finish the stream.
    func stop()
}

/// Default live-mic implementation — delegates directly to `AudioCapture`.
final class LiveAudioCapture: AudioBufferProducing, @unchecked Sendable {
    private let capture = AudioCapture()
    func start() throws -> AsyncStream<AVAudioPCMBuffer> { try capture.start() }
    func stop() { capture.stop() }
}

// MARK: - AppleSpeechTranscriber

/// `Transcribing` conformer backed by Apple's SpeechAnalyzer (macOS 26+).
///
/// Threading: `startStream` launches a background Task and returns immediately.
/// All SpeechAnalyzer/actor interactions are awaited inside that Task (off-main).
/// Mutable state is protected by the private `actor SessionState`.
@available(macOS 26.0, *)
public final class AppleSpeechTranscriber: Transcribing {

    public let id = "apple-speech-en-US"

    private let audioProducer: any AudioBufferProducing
    private let state = SessionState()

    /// Default no-arg init: uses the live microphone.
    /// The §10.1 factory `AppleSpeechTranscriber()` calls this.
    public init() {
        self.audioProducer = LiveAudioCapture()
    }

    /// Designated init for testing: inject any AudioBufferProducing.
    public init(audioProducer: any AudioBufferProducing) {
        self.audioProducer = audioProducer
    }

    // MARK: Transcribing

    public func startStream(locale: Locale) -> AsyncThrowingStream<TranscriptChunk, Error> {
        let state = self.state
        let producer = self.audioProducer

        let (stream, continuation) = AsyncThrowingStream<TranscriptChunk, Error>.makeStream()

        let task = Task<Void, Never>(priority: .userInitiated) {
            do {
                try await Session(locale: locale, audioProducer: producer, state: state)
                    .run(continuation: continuation)
                continuation.finish()
            } catch {
                SpeakLog.stt.error(
                    "transcription session error: \(error.localizedDescription, privacy: .public)"
                )
                continuation.finish(throwing: error)
            }
        }

        Task { await state.setSessionTask(task) }
        return stream
    }

    public func stop() async {
        await state.stopSession()
    }
}

// MARK: - Session

/// Encapsulates one transcription session's logic. Extracted from `run` to
/// keep cyclomatic complexity within lint limits (≤10 per function).
@available(macOS 26.0, *)
private struct Session: Sendable {
    let locale: Locale
    let audioProducer: any AudioBufferProducing
    let state: SessionState

    // MARK: run — the authoritative lifecycle

    func run(continuation: AsyncThrowingStream<TranscriptChunk, Error>.Continuation) async throws {
        let transcriber = try await makeTranscriber()
        let analyzerFormat = try await resolveAnalyzerFormat(transcriber: transcriber)
        let analyzer = SpeechAnalyzer(modules: [transcriber]) // [verified]

        // The input stream bridges PCM buffers → AnalyzerInput.
        // We hold the continuation in SessionState so stop() can end it.
        let (inputStream, inputCont) = AsyncStream<AnalyzerInput>.makeStream()
        await state.setInputContinuation(inputCont)

        // Start audio capture and store the producer stop closure so stopSession()
        // can end the buffer stream (which ends the bridge, which triggers finalize).
        let bufferStream = try audioProducer.start()
        let producer = audioProducer
        await state.setStopProducer { producer.stop() }
        SpeakLog.stt.info("Audio capture started.")

        // Bridge task: reads PCM buffers, converts format, feeds AnalyzerInput.
        // Exits when bufferStream finishes (producer.stop() called or file EOF).
        let bridgeTask = buildBridgeTask(
            bufferStream: bufferStream,
            analyzerFormat: analyzerFormat,
            inputCont: inputCont
        )
        await state.setBridgeTask(bridgeTask)

        // Results task: reads transcriber.results until the sequence closes.
        // It closes only after finalizeAndFinishThroughEndOfInput() is called.
        let resultsTask = buildResultsTask(transcriber: transcriber, continuation: continuation)
        await state.setResultsTask(resultsTask)

        // ── Authoritative lifecycle ────────────────────────────────────────────
        // Step 1: start(inputSequence:) returns AFTER SETUP, not after all input.
        // [verified] The analyzer begins consuming from inputStream asynchronously.
        do {
            try await analyzer.start(inputSequence: inputStream) // [verified]
        } catch {
            await state.cancelAll(analyzer: analyzer)
            throw error
        }

        // Step 2: Await the bridge task — guarantees all AnalyzerInputs have been
        // queued before we signal the analyzer that input is done.
        await bridgeTask.value

        // Step 3: Finalize — flushes remaining volatile results and CLOSES
        // transcriber.results. Without this, resultsTask loops forever. [verified]
        try await analyzer.finalizeAndFinishThroughEndOfInput()
        SpeakLog.stt.info("Analyzer finalized; awaiting remaining results.")

        // Step 4: Drain remaining results (resultsTask exits because results closed).
        _ = try await resultsTask.value
        SpeakLog.stt.info("Transcription session completed normally.")
    }

    // MARK: Setup helpers

    /// Validates availability, resolves locale, provisions model asset, and
    /// returns an initialized `SpeechTranscriber`.
    private func makeTranscriber() async throws -> SpeechTranscriber {
        guard SpeechTranscriber.isAvailable else { // [verified]
            throw SpeakError.transcriberUnavailable(
                "SpeechTranscriber is not available on this device or OS version."
            )
        }

        guard let resolvedLocale = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
            // [verified]
            throw SpeakError.transcriberUnavailable(
                "Locale '\(locale.identifier)' is not supported by SpeechTranscriber."
            )
        }

        // .progressiveTranscription includes volatileResults for partial transcripts. [verified]
        let transcriber = SpeechTranscriber(locale: resolvedLocale, preset: .progressiveTranscription)
        try await provisionAsset(for: transcriber)
        return transcriber
    }

    /// Ensures the speech model is installed, triggering download if needed.
    private func provisionAsset(for transcriber: SpeechTranscriber) async throws {
        let status = await AssetInventory.status(forModules: [transcriber]) // [verified]
        SpeakLog.stt.info("AssetInventory status: \(String(describing: status), privacy: .public)")

        switch status {
        case .unsupported:
            throw SpeakError.transcriberUnavailable(
                "Speech model not supported on this device."
            )
        case .installed:
            SpeakLog.stt.info("Speech model already installed.")
        default:
            // .supported, .downloading, or any future Status value: attempt install.
            try await installAsset(for: transcriber)
        }
    }

    private func installAsset(for transcriber: SpeechTranscriber) async throws {
        SpeakLog.stt.info("Speech model not installed — requesting download.")
        // [verified] Returns nil if install is already in progress.
        guard let request = try await AssetInventory.assetInstallationRequest(
            supporting: [transcriber]
        ) else {
            SpeakLog.stt.info("Install request nil — already in progress or complete.")
            return
        }
        SpeakLog.stt.info("Downloading and installing speech model…")
        try await request.downloadAndInstall() // [verified]
        SpeakLog.stt.info("Speech model installed successfully.")
    }

    /// Queries the analyzer's preferred format. Builds the conversion note if
    /// P2's Float32 output differs from the analyzer's expected format. [inferred]
    private func resolveAnalyzerFormat(transcriber: SpeechTranscriber) async throws -> AVAudioFormat {
        // [verified] Returns nil when model is not installed.
        guard let best = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])
        else {
            throw SpeakError.transcriberUnavailable(
                "SpeechAnalyzer.bestAvailableAudioFormat nil — model may not be installed."
            )
        }
        // [verified at runtime] Returns 16kHz mono Int16 interleaved.
        // P2 outputs 16kHz mono Float32 non-interleaved. Converter bridges them.
        let p2Rate = AudioCapture.Constants.targetSampleRate
        let isP2Exact = best.sampleRate == p2Rate
            && best.channelCount == AudioCapture.Constants.targetChannels
            && best.commonFormat == .pcmFormatFloat32
            && !best.isInterleaved
        if !isP2Exact {
            SpeakLog.stt.info("""
                Format conversion needed: P2=\(p2Rate, privacy: .public)Hz Float32 mono; \
                analyzer=\(best.sampleRate, privacy: .public)Hz \
                fmt=\(best.commonFormat.rawValue, privacy: .public) \
                interleaved=\(best.isInterleaved, privacy: .public).
                """)
        } else {
            SpeakLog.stt.info("Analyzer format matches P2 exactly — no conversion needed.")
        }
        return best
    }

    // MARK: Tasks

    private func buildBridgeTask(
        bufferStream: AsyncStream<AVAudioPCMBuffer>,
        analyzerFormat: AVAudioFormat,
        inputCont: AsyncStream<AnalyzerInput>.Continuation
    ) -> Task<Void, Never> {
        let p2Format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: AudioCapture.Constants.targetSampleRate,
            channels: AudioCapture.Constants.targetChannels,
            interleaved: false
        )
        // Build converter only when format dimensions differ.
        // [verified at runtime] P2=Float32 non-interleaved; analyzer=Int16 interleaved.
        let converter: AVAudioConverter? = {
            guard let src = p2Format else { return nil }
            let identical = src.sampleRate == analyzerFormat.sampleRate
                && src.channelCount == analyzerFormat.channelCount
                && src.commonFormat == analyzerFormat.commonFormat
                && src.isInterleaved == analyzerFormat.isInterleaved
            guard !identical else { return nil }
            return AVAudioConverter(from: src, to: analyzerFormat)
        }()

        return Task<Void, Never>(priority: .userInitiated) {
            for await pcmBuffer in bufferStream {
                let target: AVAudioPCMBuffer
                if let conv = converter,
                   let converted = Self.convert(pcmBuffer, using: conv, to: analyzerFormat) {
                    target = converted
                } else {
                    target = pcmBuffer
                }
                inputCont.yield(AnalyzerInput(buffer: target)) // [verified]
            }
            // bufferStream ended (file EOF or producer.stop()) — finish input.
            inputCont.finish()
            SpeakLog.stt.info("Bridge task: all input fed to analyzer.")
        }
    }

    private func buildResultsTask(
        transcriber: SpeechTranscriber,
        continuation: AsyncThrowingStream<TranscriptChunk, Error>.Continuation
    ) -> Task<Void, Error> {
        Task<Void, Error>(priority: .userInitiated) {
            for try await result in transcriber.results { // [verified]
                let text = String(result.text.characters) // [verified] text: AttributedString
                guard !text.isEmpty else { continue }
                let chunk = TranscriptChunk(
                    text: text,
                    isFinal: result.isFinal, // [verified] SpeechModuleResult extension
                    timestamp: Date()
                )
                SpeakLog.stt.debug(
                    "chunk isFinal=\(result.isFinal, privacy: .public): \(text.prefix(80), privacy: .private)"
                )
                continuation.yield(chunk)
            }
        }
    }

    // MARK: Format conversion

    private static func convert(
        _ buffer: AVAudioPCMBuffer,
        using converter: AVAudioConverter,
        to targetFormat: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1
        guard capacity > 0,
              let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity)
        else { return nil }

        var supplied = false
        var convError: NSError?
        let status = converter.convert(to: output, error: &convError) { _, inputStatus in
            if supplied {
                inputStatus.pointee = .noDataNow
                return nil
            }
            supplied = true
            inputStatus.pointee = .haveData
            return buffer
        }
        if let err = convError {
            SpeakLog.stt.error(
                "STT format conversion error: \(err.localizedDescription, privacy: .public)"
            )
            return nil
        }
        guard status != .error, output.frameLength > 0 else { return nil }
        return output
    }
}

// MARK: - SessionState actor

/// Actor guarding mutable session handles. Enables clean cancellation from
/// `stop()` without data races.
@available(macOS 26.0, *)
private actor SessionState {
    private var sessionTask: Task<Void, Never>?
    private var bridgeTask: Task<Void, Never>?
    private var resultsTask: Task<Void, Error>?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    /// Closure that stops the audio producer, ending the buffer stream.
    /// This is what causes the bridge task to exit and triggers finalize.
    private var stopProducer: (@Sendable () -> Void)?

    func setSessionTask(_ task: Task<Void, Never>) { sessionTask = task }
    func setInputContinuation(_ cont: AsyncStream<AnalyzerInput>.Continuation) {
        inputContinuation = cont
    }
    func setBridgeTask(_ task: Task<Void, Never>) { bridgeTask = task }
    func setResultsTask(_ task: Task<Void, Error>) { resultsTask = task }
    func setStopProducer(_ closure: @escaping @Sendable () -> Void) { stopProducer = closure }

    /// Stops the session cleanly:
    ///   1. Stops the audio producer → ends the buffer stream → bridge task exits.
    ///   2. The bridge finishing causes inputCont.finish() → analyzer finalize runs.
    ///   3. Awaits the session task (which awaits bridge → finalize → results drain).
    /// No zombie tasks remain after this returns.
    func stopSession() async {
        // Stop the producer first — this ends bufferStream, which ends the bridge,
        // which finishes the input continuation, which triggers finalize in run().
        stopProducer?()
        stopProducer = nil
        inputContinuation = nil  // bridge will finish it; nil here to prevent double-finish

        // Await the session task (which owns the finalize + results drain sequence).
        await sessionTask?.value
        sessionTask = nil
        bridgeTask = nil
        resultsTask = nil
        SpeakLog.stt.info("STT session stopped cleanly.")
    }

    /// Hard cancel — used on analyzer error. Does not await graceful finalize.
    func cancelAll(analyzer: SpeechAnalyzer) async {
        stopProducer?()
        stopProducer = nil
        inputContinuation?.finish()
        inputContinuation = nil
        bridgeTask?.cancel()
        resultsTask?.cancel()
        await analyzer.cancelAndFinishNow() // [verified]
        sessionTask?.cancel()
        bridgeTask = nil
        resultsTask = nil
        sessionTask = nil
        SpeakLog.stt.info("STT session cancelled.")
    }
}
