// SpeakCore/Conversation/VoiceTurnCoordinator.swift
//
// The first production consumer of `VoiceActivityDetector`, and the object that
// makes `ConversationMode.fullDuplex` reachable.
//
// FLUSH ON ENDPOINT, DO NOT PREDICT IT
// The obvious wiring — VAD says `.speechEnded`, so commit whatever text the loop
// manager is holding — is wrong, and E7 says why. Partials arrive on a ~1.04 s
// grid anchored to analyzer start, so at the moment the VAD fires (endpoint +
// 600 ms) the transcript is still missing the utterance's last word on a slow
// tail: measured arrivals ran +222…+753 ms after the acoustic endpoint.
// `ConversationLoopManager.handleVADSilenceDetected` commits the text in state
// at that instant, so wiring it directly would truncate exactly the utterances
// that most need protecting.
//
// The endpoint therefore does not *read* the transcript, it *causes* it:
//
//   VAD .speechEnded  ->  finalize the STT stream  ->  commit the final
//        (acoustic)         (forces the flush)          (complete text)
//
// E6 measured drained-input -> final at 40–80 ms, so a turn costs ~680 ms
// deterministically instead of racing a straggler. This is also why the
// predecessor policy type (`EndpointDecider`, deleted in the same series) is not
// replaced by another policy: there is nothing to decide once the flush is on
// demand. See `specs/verification-ledger.md` §7–7b.
//
// HALF DUPLEX, DELIBERATELY
// The detector is attached for the listening phase and detached before the agent
// speaks. Keeping it attached through TTS is what would require acoustic echo
// cancellation, and enabling AEC renegotiates the input format that
// `AudioCapture` reads at :119 — a change to the path used for dictation every
// day. Barge-in is therefore out of scope here and arrives with its own gated
// change; `.bargeIn` is logged and dropped rather than half-handled.
//
// WHAT THIS TOUCHES: nothing dictation uses. `AudioCapture` already runs
// `vadBox.get()?.processBuffer(buffer)` on every tap buffer (:178) against a nil
// box, so attaching a detector activates a seam that already ships rather than
// adding one.

import Foundation

/// The capture operations a voice turn needs, narrowed to four verbs.
///
/// Exists so the coordinator can be tested without a microphone, speech model,
/// or TCC grant. `SpeakEngine` conforms in `VoiceTurnCoordinator+Engine.swift`;
/// tests supply a recording double.
public protocol VoiceTurnCapturing: Sendable {
    /// Open the microphone and begin transcribing. Throws exactly as
    /// `SpeakEngine.beginDictation` does — notably `SpeakError.microphoneMuted`,
    /// which must remain a refusal and never be downgraded to a warning.
    func beginTurnCapture() async throws

    /// Attach (or, with nil, detach) the detector for the live capture.
    /// Returns false when there is no session able to host it.
    @discardableResult
    func attachTurnDetector(_ detector: VoiceActivityDetector?) async -> Bool

    /// Force the transcriber to finalize and return the completed text. This is
    /// the flush the whole design depends on, not a convenience wrapper.
    func finalizeTurnCapture() async throws -> String

    /// Abandon the capture without delivering a turn.
    func cancelTurnCapture() async
}

/// Bridges microphone energy to a conversation turn.
///
/// `@MainActor` because `ConversationLoopManager` is, and because the detector's
/// events are consumed off its `AsyncStream` rather than its synchronous
/// callbacks — `VoiceActivityDetector.emit` invokes those callbacks inline on
/// the CoreAudio render thread (:268-270), where doing anything at all is a
/// real-time violation. The stream yield is non-blocking; the work happens here.
@MainActor
public final class VoiceTurnCoordinator {

    /// Why a turn stopped listening. Reported so a caller can distinguish "the
    /// human spoke and finished" from "nobody ever said anything", which look
    /// identical from the outside but mean opposite things to an agent.
    public enum TurnOutcome: Equatable, Sendable {
        /// The human spoke, stopped, and the finalized transcript is attached.
        case committed(String)
        /// Listening ended with no usable speech — silence, or noise the
        /// detector opened on but the transcriber found nothing in.
        case silent
        /// The watchdog expired before the detector ever reported speech.
        case timedOut
        /// Capture failed to start or to finalize.
        case failed(String)
    }

    public struct Configuration: Sendable {
        /// Passed to the detector. The defaults are `VoiceActivityDetector`'s
        /// own, which are **unmeasured** — 0.03 RMS opens a turn on a cough or a
        /// keyboard burst, and a quiet talker may never cross it. Acceptable
        /// only while this path is off by default; needs a measured replacement
        /// before it is ever on.
        public var detector: VoiceActivityDetector.Configuration

        /// Ceiling on a single turn's listening phase, covering the case the
        /// detector structurally cannot: if the human never speaks, silence is
        /// never accumulated (`VoiceActivityDetector.processBuffer` only counts
        /// it once `speechActive`, :159) and `.speechEnded` can never fire.
        ///
        /// **Must stay well above `detector.silenceThresholdDuration`.** This is a
        /// backstop for "the detector said nothing", not a second endpointer.
        /// Tuning it near the silence window re-creates the race this design
        /// exists to remove — the detector is authoritative. Not enforced by the
        /// initializer (tests need tight watchdogs to reach the timeout path);
        /// `VoiceTurnCoordinator.init` logs an error when it is violated.
        public var watchdog: TimeInterval

        public init(
            detector: VoiceActivityDetector.Configuration = .init(),
            watchdog: TimeInterval = 30.0
        ) {
            self.detector = detector
            self.watchdog = watchdog
        }

        /// The rule above stated as code, so a test can assert it and `init` can
        /// complain about it rather than a comment asking politely.
        public var watchdogClearsDetector: Bool {
            watchdog >= detector.silenceThresholdDuration * 2
        }
    }

    private let capture: any VoiceTurnCapturing
    private let loop: ConversationLoopManager
    private let metrics: TurnMetricsRecorder
    private let configuration: Configuration

    /// Non-nil only while a turn is listening. Its presence is what makes a
    /// second concurrent `listen()` refuse rather than interleave.
    private var activeTurn: Task<TurnOutcome, Never>?

    public init(
        capture: any VoiceTurnCapturing,
        loop: ConversationLoopManager,
        metrics: TurnMetricsRecorder = TurnMetricsRecorder(),
        configuration: Configuration = Configuration()
    ) {
        self.capture = capture
        self.loop = loop
        self.metrics = metrics
        self.configuration = configuration

        // The watchdog invariant is documented on `Configuration` but cannot be
        // enforced there — tests legitimately construct tight watchdogs to reach
        // the timeout path in bounded time. Say so loudly instead of pretending
        // the type guarantees it.
        if !configuration.watchdogClearsDetector {
            SpeakLog.conversation.error(
                """
                VoiceTurnCoordinator: watchdog \(configuration.watchdog, privacy: .public)s is inside 2x the \
                detector's \(configuration.detector.silenceThresholdDuration, privacy: .public)s silence window \
                — it will act as a second endpointer and truncate slow tails.
                """
            )
        }
    }

    public var isListening: Bool { activeTurn != nil }

    /// Run one human turn: open the mic, wait for the human to stop, flush the
    /// transcriber, and commit the finalized text.
    ///
    /// Serialized deliberately. Two overlapping turns would contend for one
    /// microphone and one loop-manager state machine, so a second call while a
    /// turn is in flight is refused rather than queued — a queued turn would
    /// capture audio the caller no longer expects to be captured.
    public func listen() async -> TurnOutcome {
        guard activeTurn == nil else {
            SpeakLog.conversation.info("VoiceTurnCoordinator: listen() refused — a turn is already in flight.")
            return .failed("a turn is already listening")
        }

        let turn = Task { await runTurn() }
        activeTurn = turn
        let outcome = await turn.value
        activeTurn = nil
        return outcome
    }

    /// Stop the in-flight turn without committing it. Used by the hotkey, which
    /// always outranks and interrupts an agent-driven capture.
    public func cancel() async {
        guard let turn = activeTurn else { return }
        turn.cancel()
        _ = await turn.value
        activeTurn = nil
    }

    // MARK: - The turn

    private func runTurn() async -> TurnOutcome {
        metrics.reset()

        let detector = VoiceActivityDetector(configuration: configuration.detector)

        do {
            try await capture.beginTurnCapture()
        } catch {
            SpeakLog.conversation.error(
                "VoiceTurnCoordinator: capture failed to start — \(error.localizedDescription, privacy: .public)"
            )
            return .failed(error.localizedDescription)
        }

        guard await capture.attachTurnDetector(detector) else {
            // No session could host the detector. Finishing without it would
            // silently degrade to a blind timeout, which is worse than saying so.
            await releaseMicrophone()
            SpeakLog.conversation.error("VoiceTurnCoordinator: no session accepted the detector — turn abandoned.")
            return .failed("capture session would not accept a detector")
        }

        loop.setMode(.fullDuplex)

        let endpoint = await awaitEndpoint(on: detector)

        // Detach before anything downstream can start speaking. Half-duplex is
        // the whole reason this path needs no echo cancellation.
        await capture.attachTurnDetector(nil)

        switch endpoint {
        case .cancelled:
            await releaseMicrophone()
            loop.resetToIdle()
            return .failed("cancelled")

        case .timedOut:
            await releaseMicrophone()
            loop.resetToIdle()
            SpeakLog.conversation.info("VoiceTurnCoordinator: watchdog expired with no speech — turn abandoned.")
            return .timedOut

        case .speechEnded:
            return await commitFinalizedTurn()
        }
    }

    /// Release the capture, in a task that does not inherit cancellation.
    ///
    /// `cancel()` cancels the turn task, and every teardown below then runs
    /// *inside* a cancelled task. Anything on the way to the microphone that
    /// honours cancellation would no-op there and leave the mic open — a failure
    /// mode with no user-visible symptom other than a recording indicator that
    /// never goes away. An unstructured `Task` inherits actor context and
    /// priority but **not** cancellation, so this always completes.
    private func releaseMicrophone() async {
        let capture = self.capture
        await Task { await capture.cancelTurnCapture() }.value
    }

    /// Wait for the human to stop, or for the watchdog, whichever comes first.
    ///
    /// Consumes `eventStream` rather than the synchronous callbacks so no work
    /// lands on the render thread.
    private func awaitEndpoint(on detector: VoiceActivityDetector) async -> EndpointResult {
        let watchdog = configuration.watchdog

        return await withTaskGroup(of: EndpointResult.self) { group in
            group.addTask { [metrics] in
                for await event in detector.eventStream {
                    switch event {
                    case .speechStarted:
                        await metrics.markOnMain(.userSpeechStarted)

                    case .speechEnded:
                        await metrics.markOnMain(.userSpeechEnded)
                        return .speechEnded

                    case .bargeIn:
                        // Cannot occur: the detector is detached before TTS and
                        // `isTTSPlaying` is never set on this path. Logged rather
                        // than handled so that if it ever does fire, it surfaces
                        // as a design violation instead of silent behaviour.
                        SpeakLog.conversation.error("VoiceTurnCoordinator: unexpected .bargeIn in half-duplex turn — ignoring.")
                    }
                }
                return .cancelled
            }

            group.addTask {
                try? await Task.sleep(for: .seconds(watchdog))
                return Task.isCancelled ? .cancelled : .timedOut
            }

            let first = await group.next() ?? .cancelled
            group.cancelAll()
            return first
        }
    }

    /// The flush. Finalization is what makes the transcript complete; committing
    /// before it is what E7 forbids.
    private func commitFinalizedTurn() async -> TurnOutcome {
        metrics.mark(.endpointDeclared)

        let text: String
        do {
            text = try await capture.finalizeTurnCapture()
        } catch {
            loop.resetToIdle()
            SpeakLog.conversation.error(
                "VoiceTurnCoordinator: finalize failed — \(error.localizedDescription, privacy: .public)"
            )
            return .failed(error.localizedDescription)
        }

        metrics.mark(.transcriptFinalized)

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            loop.resetToIdle()
            SpeakLog.conversation.info("VoiceTurnCoordinator: finalized transcript was empty — no turn committed.")
            return .silent
        }

        // Hand the loop manager the *finalized* text and commit it explicitly.
        // `commitUserTurn(prompt:)` is used rather than `handleVADSilenceDetected`
        // precisely because the latter would commit whatever partial text the
        // loop already held (ConversationLoopManager.swift:249).
        loop.handleVADTranscriptUpdated(trimmed)
        loop.commitUserTurn(prompt: trimmed)

        metrics.logReport()
        return .committed(trimmed)
    }

    private enum EndpointResult: Sendable {
        case speechEnded
        case timedOut
        case cancelled
    }
}

private extension TurnMetricsRecorder {
    /// `mark` is thread-safe, but the call sites above run inside a detached
    /// stream consumer; this keeps the ordering of marks tied to the actor that
    /// owns the turn rather than to task scheduling.
    func markOnMain(_ stage: TurnStage) async {
        await MainActor.run { self.mark(stage) }
    }
}
