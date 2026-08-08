// SpeakCore/Conversation/TurnMetrics.swift
//
// Latency instrumentation for one conversational turn.
//
// The conversation loop is a latency product: the only thing that decides
// whether it feels alive is how long the human waits between finishing their
// sentence and hearing a reply. Before this file, nothing in the app measured
// that. Every latency figure in `specs/voice-agent-design.md` §5 was
// `[unverified]` for exactly that reason.
//
// Stage vocabulary follows the decomposition real-time voice stacks converged
// on (LiveKit Agents names these EOU delay / TTFT / TTFB): the composite
// numbers are what predict felt quality, and per-stage marks exist only to
// explain a bad composite. [decision: measure the loop, not the parts.]
//
// Marks arrive from three different execution contexts — the CoreAudio tap
// thread (VAD), `@MainActor` (overlay/UI), and actors (TTS, inference) — so
// the recorder is lock-protected rather than actor-isolated: `mark()` must
// never suspend, because suspending on the audio thread would distort the very
// measurement being taken.

import Foundation
import os

/// A single observable instant in a conversational turn.
///
/// Ordering here is the nominal happy path; a real turn may skip stages
/// (no tool call) or repeat them (barge-in), so nothing depends on the order.
public enum TurnStage: String, Sendable, CaseIterable, Codable {
    /// VAD saw speech energy rise — the human started talking.
    case userSpeechStarted
    /// VAD saw speech energy fall — the human stopped making sound.
    case userSpeechEnded
    /// The loop decided the turn is over and the agent may answer.
    /// Distinct from `userSpeechEnded`: that is acoustic, this is a decision.
    case endpointDeclared
    /// STT delivered its final (non-partial) transcript.
    case transcriptFinalized
    /// The prompt was handed to the language model.
    case agentRequested
    /// First token of the model's reply came back.
    case agentFirstToken
    /// The model invoked a tool.
    case toolCallStarted
    /// The tool returned.
    case toolCallFinished
    /// Last token of the model's reply.
    case agentLastToken
    /// Text was handed to the synthesizer.
    case ttsRequested
    /// The first genuinely audible sample reached the output — the human hears
    /// something.
    ///
    /// **Mark this from the render path, never from
    /// `AVSpeechSynthesizerDelegate.didStart`.** `make measure-latency` shows
    /// `didStart` firing 1–2 ms after the request when warm, which is below the
    /// floor for CoreAudio output start: it reports *enqueue*. The measured
    /// audible figure on the same machine is ~267 ms, so marking from the
    /// delegate understates `synthesisMs` — and therefore the headline
    /// `responseLatencyMs` — by roughly a quarter second. [verified: E1]
    case ttsFirstAudio
    /// The utterance completed on its own.
    case ttsFinished
    /// The human started talking over the agent.
    case bargeInDetected
    /// Agent audio actually went quiet after a barge-in.
    case bargeInSilenced
}

/// One timestamped stage observation.
public struct TurnMark: Sendable {
    public let stage: TurnStage
    public let instant: ContinuousClock.Instant
    public let detail: String?

    public init(stage: TurnStage, instant: ContinuousClock.Instant, detail: String? = nil) {
        self.stage = stage
        self.instant = instant
        self.detail = detail
    }
}

/// Derived latency figures for a completed (or partial) turn.
///
/// Every field is optional because a turn that errored, was cancelled, or was
/// barged in simply does not have the corresponding pair of marks. Reporting
/// `nil` is honest; reporting `0` would silently pollute any aggregate.
public struct TurnReport: Sendable {
    public let turnID: UUID
    public let marks: [TurnMark]

    /// `userSpeechEnded` → `endpointDeclared`.
    ///
    /// The cost of deciding the human is finished. With silence-threshold VAD
    /// this is roughly the configured silence window plus detection lag, and it
    /// is pure dead air — the dominant, and most reducible, component of felt
    /// latency.
    public let endpointDelayMs: Double?

    /// `endpointDeclared` → `agentFirstToken` (time to first token).
    public let thinkingMs: Double?

    /// `toolCallStarted` → `toolCallFinished`.
    public let toolMs: Double?

    /// `ttsRequested` → `ttsFirstAudio` (time to first byte of audio).
    public let synthesisMs: Double?

    /// **The headline number.** `userSpeechEnded` → `ttsFirstAudio`: the human
    /// stops talking, and this is how long until they hear anything back.
    /// Composes endpoint delay + thinking + synthesis. This is the figure the
    /// product lives or dies by; everything else exists to explain it.
    public let responseLatencyMs: Double?

    /// `bargeInDetected` → `bargeInSilenced`. How long the agent keeps talking
    /// after being interrupted. Above roughly 200 ms this reads as the agent
    /// ignoring you, which is worse than it being slow.
    public let bargeInLatencyMs: Double?

    /// `ttsFirstAudio` → `ttsFinished`. Not latency — duration of speech.
    /// Recorded because verbosity is a tunable and long replies are a defect.
    public let speakingMs: Double?
}

/// Collects stage marks for one turn and derives a `TurnReport`.
///
/// Deliberately an injected instance, not a shared singleton: `AGENTS.md` §3
/// forbids global mutable state, and per-turn instances also make concurrent
/// turns (agent-initiated call while dictation runs) measurable independently.
///
/// `@unchecked Sendable` with an `NSLock` follows the established idiom in this
/// module (`AudioCapture.ConverterBox` / `VADBox`) — mutation is confined to
/// the lock and the type exposes no shared references.
public final class TurnMetricsRecorder: @unchecked Sendable {

    private let lock = NSLock()
    private var marks: [TurnMark] = []
    private var turnID: UUID
    private let clock = ContinuousClock()
    private let signposter: OSSignposter
    private let signpostID: OSSignpostID

    public init(turnID: UUID = UUID()) {
        self.turnID = turnID
        let signposter = OSSignposter(logger: SpeakLog.conversation)
        self.signposter = signposter
        self.signpostID = signposter.makeSignpostID()
    }

    /// Current turn identifier.
    public var currentTurnID: UUID {
        lock.lock()
        defer { lock.unlock() }
        return turnID
    }

    /// Record that `stage` happened now.
    ///
    /// Safe to call from the audio thread: takes an uncontended lock and does
    /// no allocation beyond appending. Never suspends.
    public func mark(_ stage: TurnStage, detail: String? = nil) {
        let instant = clock.now
        lock.lock()
        marks.append(TurnMark(stage: stage, instant: instant, detail: detail))
        lock.unlock()

        signposter.emitEvent("turn-stage", id: signpostID, "\(stage.rawValue, privacy: .public)")
    }

    /// Discard all marks and begin a new turn.
    public func reset(turnID newTurnID: UUID = UUID()) {
        lock.lock()
        marks.removeAll(keepingCapacity: true)
        turnID = newTurnID
        lock.unlock()
    }

    /// Snapshot of the marks recorded so far.
    public func snapshot() -> [TurnMark] {
        lock.lock()
        defer { lock.unlock() }
        return marks
    }

    /// Derive the latency figures for the turn recorded so far.
    public func report() -> TurnReport {
        lock.lock()
        let marks = self.marks
        let turnID = self.turnID
        lock.unlock()

        /// First occurrence wins for starts, so a repeated stage (e.g. a second
        /// tool call) does not retroactively move an earlier interval.
        func first(_ stage: TurnStage) -> ContinuousClock.Instant? {
            marks.first { $0.stage == stage }?.instant
        }
        func last(_ stage: TurnStage) -> ContinuousClock.Instant? {
            marks.last { $0.stage == stage }?.instant
        }
        func elapsed(_ from: ContinuousClock.Instant?, _ to: ContinuousClock.Instant?) -> Double? {
            guard let from, let to, to >= from else { return nil }
            return Self.milliseconds(from.duration(to: to))
        }

        let speechEnded = first(.userSpeechEnded)
        let endpoint = first(.endpointDeclared)
        let firstAudio = first(.ttsFirstAudio)

        return TurnReport(
            turnID: turnID,
            marks: marks,
            endpointDelayMs: elapsed(speechEnded, endpoint),
            thinkingMs: elapsed(endpoint, first(.agentFirstToken)),
            toolMs: elapsed(first(.toolCallStarted), last(.toolCallFinished)),
            synthesisMs: elapsed(first(.ttsRequested), firstAudio),
            responseLatencyMs: elapsed(speechEnded, firstAudio),
            bargeInLatencyMs: elapsed(first(.bargeInDetected), first(.bargeInSilenced)),
            speakingMs: elapsed(firstAudio, last(.ttsFinished))
        )
    }

    /// Emit the derived report to the `conversation` log category.
    ///
    /// Values are `.public` because they are timings, not content — no
    /// transcript text is ever logged here.
    public func logReport() {
        let report = report()
        func fmt(_ value: Double?) -> String {
            guard let value else { return "—" }
            return String(format: "%.0fms", value)
        }
        SpeakLog.conversation.info(
            """
            turn \(report.turnID.uuidString, privacy: .public) — \
            response=\(fmt(report.responseLatencyMs), privacy: .public) \
            [endpoint=\(fmt(report.endpointDelayMs), privacy: .public) \
            think=\(fmt(report.thinkingMs), privacy: .public) \
            tool=\(fmt(report.toolMs), privacy: .public) \
            tts=\(fmt(report.synthesisMs), privacy: .public)] \
            bargeIn=\(fmt(report.bargeInLatencyMs), privacy: .public) \
            speaking=\(fmt(report.speakingMs), privacy: .public)
            """
        )
    }

    private static func milliseconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) * 1_000.0
            + Double(components.attoseconds) / 1_000_000_000_000_000.0
    }
}
