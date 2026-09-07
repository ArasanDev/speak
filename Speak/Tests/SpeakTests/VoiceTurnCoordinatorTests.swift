// SpeakTests/VoiceTurnCoordinatorTests.swift
//
// Tests for the object that turns microphone energy into a conversation turn.
//
// The load-bearing test is `testCommitsFinalizedTextNotThePartialInFlight`.
// Everything else guards a boundary; that one guards the finding the whole
// design came from. E7 measured an utterance's last word arriving up to 753 ms
// after the acoustic endpoint, against a detector that fires at 600 ms — so a
// coordinator that commits the text the loop manager is already holding
// truncates real speech. It must commit what finalization returned instead. If
// that test is ever "simplified" to assert on in-flight text, the bug it exists
// to prevent comes straight back and nothing else here will catch it.
//
// No microphone, no speech model, no TCC grant: the coordinator talks to
// `VoiceTurnCapturing`, and the double below hands back the real
// `VoiceActivityDetector` it was given so a test can drive it with synthesized
// buffers. The detector's stream continuation is created in its initializer, so
// events emitted before the coordinator starts iterating are buffered, not lost
// — that is what makes this deterministic rather than a race.

import AVFoundation
import Foundation
@testable import SpeakCore
import XCTest

@MainActor
final class VoiceTurnCoordinatorTests: XCTestCase {

    // MARK: - Doubles

    /// Records the verbs the coordinator invokes and, crucially, keeps hold of
    /// the detector so a test can feed it audio. An actor rather than a locked
    /// class because every verb in the protocol is already async.
    private actor CaptureDouble: VoiceTurnCapturing {
        enum Verb: Equatable { case begin, attach, detach, finalize, cancel }

        private(set) var verbs: [Verb] = []
        private(set) var attachedDetector: VoiceActivityDetector?

        private let beginError: Error?
        private let finalizeError: Error?
        private let finalizedText: String

        init(finalizedText: String = "the finalized transcript",
             beginError: Error? = nil,
             finalizeError: Error? = nil) {
            self.finalizedText = finalizedText
            self.beginError = beginError
            self.finalizeError = finalizeError
        }

        func beginTurnCapture() async throws {
            verbs.append(.begin)
            if let beginError { throw beginError }
        }

        @discardableResult
        func attachTurnDetector(_ detector: VoiceActivityDetector?) async -> Bool {
            if let detector { attachedDetector = detector }
            verbs.append(detector == nil ? .detach : .attach)
            return true
        }

        func finalizeTurnCapture() async throws -> String {
            verbs.append(.finalize)
            if let finalizeError { throw finalizeError }
            return finalizedText
        }

        /// Deliberately cancellation-honouring. A real teardown reaches audio
        /// hardware through suspension points, and a suspension point inside a
        /// cancelled task can no-op — so if the coordinator ever releases the
        /// microphone from *within* the cancelled turn task, this records nothing
        /// and the assertions below fail. That is exactly the bug worth catching:
        /// a mic left open has no symptom except a recording indicator that never
        /// goes out.
        func cancelTurnCapture() async {
            if Task.isCancelled { return }
            verbs.append(.cancel)
        }
    }

    /// A capture with no session able to host a detector.
    private struct RefusingCapture: VoiceTurnCapturing {
        func beginTurnCapture() async throws {}
        @discardableResult
        func attachTurnDetector(_ detector: VoiceActivityDetector?) async -> Bool { false }
        func finalizeTurnCapture() async throws -> String { "unreachable" }
        func cancelTurnCapture() async {}
    }

    // MARK: - Fixtures

    private func makeCoordinator(
        capture: any VoiceTurnCapturing,
        loop: ConversationLoopManager = ConversationLoopManager(),
        watchdog: TimeInterval = 5.0
    ) -> VoiceTurnCoordinator {
        VoiceTurnCoordinator(
            capture: capture,
            loop: loop,
            configuration: .init(watchdog: watchdog)
        )
    }

    /// A buffer whose RMS is `amplitude` — sign-alternating so it is genuine
    /// signal energy and not a DC offset the detector would measure differently.
    private func buffer(amplitude: Float, seconds: Double = 0.1) throws -> AVAudioPCMBuffer {
        let sampleRate = 16_000.0
        let frames = AVAudioFrameCount(sampleRate * seconds)
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1))
        let pcm = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        pcm.frameLength = frames
        let channel = try XCTUnwrap(pcm.floatChannelData)
        for frame in 0..<Int(frames) {
            channel[0][frame] = frame.isMultiple(of: 2) ? amplitude : -amplitude
        }
        return pcm
    }

    /// Drive a detector through a whole utterance: energy well above the 0.03
    /// threshold, then more than enough silence to cross the 0.6 s window.
    private func speakThenFallSilent(_ detector: VoiceActivityDetector) throws {
        let speech = try buffer(amplitude: 0.5)
        let silence = try buffer(amplitude: 0.0)
        for _ in 0..<5 { detector.processBuffer(speech) }
        for _ in 0..<12 { detector.processBuffer(silence) }
    }

    /// Wait for the coordinator to attach its detector, so a test never races
    /// the turn's own start-up. Returns nil if it never arrives.
    private func awaitDetector(
        from capture: CaptureDouble,
        otherThan previous: VoiceActivityDetector? = nil
    ) async -> VoiceActivityDetector? {
        for _ in 0..<200 {
            if let detector = await capture.attachedDetector, detector !== previous { return detector }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return nil
    }

    /// Run `work` with a ceiling, returning false if it did not finish. Exists so
    /// a coordinator that fails to observe cancellation fails a test instead of
    /// hanging the suite until the harness gives up.
    ///
    /// Deliberately *not* a task group: a group awaits all its children, so a
    /// hung child would hang the very call meant to detect the hang. The stray
    /// task is abandoned instead — the test has already failed by then.
    private func withDeadline(seconds: Double, _ work: @escaping @Sendable () async -> Void) async -> Bool {
        let finished = Finished()
        Task { await work(); await finished.raise() }
        for _ in 0..<Int(seconds * 100) {
            if await finished.value { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }

    private actor Finished {
        private(set) var value = false
        func raise() { value = true }
    }

    // MARK: - The finding this design exists to encode

    /// The E7 property, asserted twice over: the outcome carries the finalized
    /// text, and the loop manager was moved into `.processing` with that same
    /// text — not with whatever partial it held when the detector fired.
    func testCommitsFinalizedTextNotThePartialInFlight() async throws {
        let spoken = "send this to Sarah and copy Anne"
        let capture = CaptureDouble(finalizedText: spoken)
        let loop = ConversationLoopManager()
        let coordinator = makeCoordinator(capture: capture, loop: loop)

        let turn = Task { await coordinator.listen() }
        let attached = await awaitDetector(from: capture)
        let detector = try XCTUnwrap(attached, "detector was never attached")

        // A partial the loop would have committed had the coordinator trusted
        // in-flight state. It must not survive into the turn.
        loop.handleVADTranscriptUpdated("send this to Sarah and copy")
        try speakThenFallSilent(detector)

        let outcome = await turn.value
        XCTAssertEqual(outcome, .committed(spoken))
        XCTAssertEqual(loop.state, .processing(prompt: spoken))
    }

    /// The ordering IS the design: endpoint, then flush, then commit. Detach
    /// must land before the turn returns, so nothing downstream can speak into
    /// a microphone that still has a detector on it — that is what keeps this
    /// path half-duplex and out of needing echo cancellation.
    func testFlushHappensAfterDetachAndBeforeReturn() async throws {
        let capture = CaptureDouble()
        let coordinator = makeCoordinator(capture: capture)

        let turn = Task { await coordinator.listen() }
        let attached = await awaitDetector(from: capture)
        let detector = try XCTUnwrap(attached, "detector was never attached")
        try speakThenFallSilent(detector)
        _ = await turn.value

        let verbs = await capture.verbs
        XCTAssertEqual(verbs, [.begin, .attach, .detach, .finalize])
    }

    // MARK: - Outcomes

    /// An empty finalized transcript is silence, not a turn. Committing "" would
    /// hand an agent an empty prompt to reason about.
    func testEmptyFinalizedTranscriptIsSilent() async throws {
        let capture = CaptureDouble(finalizedText: "   \n ")
        let loop = ConversationLoopManager()
        let coordinator = makeCoordinator(capture: capture, loop: loop)

        let turn = Task { await coordinator.listen() }
        let attached = await awaitDetector(from: capture)
        let detector = try XCTUnwrap(attached, "detector was never attached")
        try speakThenFallSilent(detector)

        let outcome = await turn.value
        XCTAssertEqual(outcome, .silent)
        XCTAssertEqual(loop.state, .idle)
    }

    /// The case the detector structurally cannot report: nobody speaks, so
    /// `speechActive` is never set and `.speechEnded` can never fire. Only the
    /// watchdog ends this turn — which is exactly why it is not deleted.
    func testWatchdogEndsATurnNobodySpeaksIn() async throws {
        let capture = CaptureDouble()
        let coordinator = makeCoordinator(capture: capture, watchdog: 0.3)

        let turn = Task { await coordinator.listen() }
        let attached = await awaitDetector(from: capture)
        let detector = try XCTUnwrap(attached, "detector was never attached")
        let silence = try buffer(amplitude: 0.0)
        for _ in 0..<3 { detector.processBuffer(silence) }

        let outcome = await turn.value
        XCTAssertEqual(outcome, .timedOut)

        let verbs = await capture.verbs
        XCTAssertTrue(verbs.contains(.cancel), "a timed-out turn must release the microphone")
        XCTAssertFalse(verbs.contains(.finalize), "nothing was said; nothing should be flushed")
    }

    /// A capture that cannot host a detector must fail loudly. Proceeding would
    /// silently degrade the turn to a blind timeout that still looks like a turn.
    func testCaptureThatRefusesTheDetectorFailsTheTurn() async {
        let coordinator = makeCoordinator(capture: RefusingCapture())
        let outcome = await coordinator.listen()
        guard case .failed = outcome else {
            return XCTFail("a refused detector must fail the turn, not proceed without one")
        }
    }

    /// `microphoneMuted` is a refusal at the engine and must stay a refusal here.
    func testBeginFailurePropagatesAndNothingIsFlushed() async {
        let capture = CaptureDouble(beginError: SpeakError.microphoneMuted)
        let coordinator = makeCoordinator(capture: capture)

        let outcome = await coordinator.listen()
        guard case .failed = outcome else {
            return XCTFail("a capture that cannot start must fail the turn")
        }
        let verbs = await capture.verbs
        XCTAssertFalse(verbs.contains(.finalize))
    }

    /// If the flush fails there is no complete transcript, so there is nothing
    /// safe to commit — a partial must not be substituted for one.
    func testFinalizeFailureDoesNotCommitAPartial() async throws {
        let capture = CaptureDouble(finalizeError: SpeakError.unknown("flush failed"))
        let loop = ConversationLoopManager()
        let coordinator = makeCoordinator(capture: capture, loop: loop)

        let turn = Task { await coordinator.listen() }
        let attached = await awaitDetector(from: capture)
        let detector = try XCTUnwrap(attached, "detector was never attached")
        loop.handleVADTranscriptUpdated("half an instruction")
        try speakThenFallSilent(detector)

        let outcome = await turn.value
        guard case .failed = outcome else {
            return XCTFail("a failed flush must fail the turn")
        }
        XCTAssertEqual(loop.state, .idle, "a failed flush must not leave a partial committed")
    }

    // MARK: - Serialization

    /// Two turns would contend for one microphone and one state machine. The
    /// second is refused rather than queued: a queued turn would capture audio
    /// the caller has stopped expecting to be captured.
    func testSecondListenIsRefusedWhileATurnIsInFlight() async throws {
        let capture = CaptureDouble()
        let coordinator = makeCoordinator(capture: capture)

        let first = Task { await coordinator.listen() }
        let attached = await awaitDetector(from: capture)
        let detector = try XCTUnwrap(attached, "detector was never attached")

        let refused = await coordinator.listen()
        guard case .failed = refused else {
            return XCTFail("a concurrent listen() must be refused")
        }

        try speakThenFallSilent(detector)
        _ = await first.value
        XCTAssertFalse(coordinator.isListening)

        let verbs = await capture.verbs
        XCTAssertEqual(verbs.filter { $0 == .begin }.count, 1, "the refused turn must not have opened the mic")
    }

    // MARK: - Cancellation — the hotkey's escape hatch

    /// `cancel()` is how the §8 rule "the hotkey always outranks and interrupts
    /// agent TTS" is actually implemented, so it gets the same scrutiny as the
    /// commit path. Three things must hold, and each has failed in some design:
    /// the call must *return* (the turn's event loop has to notice cancellation
    /// at all), the microphone must be released (from outside the cancelled task
    /// — see `CaptureDouble.cancelTurnCapture`), and nothing may be flushed or
    /// committed, because a cancelled turn has no transcript anyone asked for.
    func testCancelReleasesTheMicrophoneAndCommitsNothing() async throws {
        let capture = CaptureDouble()
        let loop = ConversationLoopManager()
        let coordinator = makeCoordinator(capture: capture, loop: loop)

        let turn = Task { await coordinator.listen() }
        let attached = await awaitDetector(from: capture)
        let detector = try XCTUnwrap(attached, "detector was never attached")

        // Mid-utterance: the human is speaking and has not endpointed.
        let speech = try buffer(amplitude: 0.5)
        for _ in 0..<5 { detector.processBuffer(speech) }
        loop.handleVADTranscriptUpdated("wait no I meant")

        // If cancellation does not propagate into the event loop this never
        // returns, so bound it rather than hanging the whole suite.
        let returned = await withDeadline(seconds: 2) { await coordinator.cancel() }
        XCTAssertTrue(returned, "cancel() did not return — the turn never observed cancellation")

        XCTAssertFalse(coordinator.isListening, "a cancelled turn must not stay in flight")

        let outcome = await turn.value
        XCTAssertEqual(outcome, .failed("cancelled"))

        let verbs = await capture.verbs
        XCTAssertEqual(verbs, [.begin, .attach, .detach, .cancel])
        XCTAssertEqual(loop.state, .idle, "a cancelled turn must not leave a partial committed")
    }

    /// After a cancel the coordinator has to be usable again — otherwise one
    /// hotkey press permanently disables agent turns until relaunch.
    func testANewTurnCanStartAfterACancel() async throws {
        let capture = CaptureDouble(finalizedText: "second turn")
        let coordinator = makeCoordinator(capture: capture)

        let first = Task { await coordinator.listen() }
        let firstDetector = await awaitDetector(from: capture)
        _ = await withDeadline(seconds: 2) { await coordinator.cancel() }
        _ = await first.value

        let second = Task { await coordinator.listen() }
        // The double keeps the first turn's detector (detach passes nil and is not
        // recorded as a new attachment), so wait for a *different* instance.
        let attached = await awaitDetector(from: capture, otherThan: firstDetector)
        let detector = try XCTUnwrap(attached, "a second turn never attached a detector")
        try speakThenFallSilent(detector)

        let outcome = await second.value
        XCTAssertEqual(outcome, .committed("second turn"))
    }

    // MARK: - Configuration invariant

    /// The watchdog is a backstop for "the detector said nothing", not a second
    /// endpointer. Tuned near the silence window it becomes one, and re-creates
    /// the race this design removed.
    func testWatchdogClearsTheDetectorWindowByAWideMargin() {
        XCTAssertTrue(VoiceTurnCoordinator.Configuration().watchdogClearsDetector)

        let tooTight = VoiceTurnCoordinator.Configuration(
            detector: .init(silenceThresholdDuration: 0.6),
            watchdog: 0.8
        )
        XCTAssertFalse(
            tooTight.watchdogClearsDetector,
            "a watchdog inside 2x the silence window must not read as safe"
        )
    }
}
