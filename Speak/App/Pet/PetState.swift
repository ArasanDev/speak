// App/Pet/PetState.swift
//
// FE-1 (specs/frontend-identity.md §5): Voice Desktop Pet's state machine. Pure, value-type
// logic — no AppKit/SwiftUI — so it is unit-testable independent of the panel
// or rendering, matching the `SpeakCore`-style pattern used elsewhere (e.g.
// `LevelMath.swift`, `AuroraMath.swift`) even though this type lives app-side
// (Voice Desktop Pet is an App-target concept, not an engine concept).
//
// STATE MAPPING (locked, orchestrator brief):
//   dormant      = petEnabled but engine unavailable / mic permission missing
//   idle         = engine idle
//   listening    = capturing (tally onAir)
//   processing   = cleanup running
//   speaking     = agent TTS active
//   agentWorking = reserved, reachable via the provider seam; stub keeps it off
//   attention    = provider count > 0
//
// PRIORITY (locked, spec §8 — "human always outranks agents"):
//   listening > speaking > attention > agentWorking > processing > idle > dormant
//   Exactly one state is ever active at a time.

import Foundation

/// Voice Desktop Pet's visual/behavioral state (spec §5 table).
public enum PetState: String, CaseIterable, Equatable, Sendable {
    case dormant
    case idle
    case listening
    case processing
    case agentWorking
    case attention
    case speaking
}

extension PetState {

    /// The EXPECTED-transitions map — ADVISORY ONLY (review fix, 2026-07-11).
    ///
    /// `PetState.resolve(from:)` is the single source of truth for what Voice Desktop Pet
    /// displays; `PetPanelController.tick()` applies its output UNCONDITIONALLY
    /// every tick. This map exists solely to flag unexpected edges (a signal
    /// source skipping a beat between two polls, e.g. `.listening → .idle`
    /// when a fast cleanup finished inside one 200ms tick) via a log line —
    /// it must NEVER gate state application. A gate that rejects resolve()'s
    /// output can only ever suppress truth (worst case: a frozen "Listening"
    /// + onAir tally after the mic closed, violating the spec §2 hard rule).
    ///
    /// Built from the state diagram implied by the dictation lifecycle
    /// (idle ⇄ listening ⇄ processing ⇄ idle), the agent signals, and dormant
    /// as the universal off-ramp/on-ramp.
    private static let expectedTransitions: [PetState: Set<PetState>] = [
        .dormant: [.idle],
        .idle: [.dormant, .listening, .agentWorking, .attention, .speaking],
        .listening: [.dormant, .processing],
        .processing: [.dormant, .idle, .attention],
        .agentWorking: [.dormant, .idle, .listening, .attention, .speaking],
        .attention: [.dormant, .idle, .listening, .speaking, .agentWorking],
        .speaking: [.dormant, .idle, .listening, .attention, .agentWorking]
    ]

    /// Whether `self → next` is an EXPECTED transition per the advisory map
    /// above. `false` does NOT mean the transition is forbidden — the display
    /// still converges to `resolve()`'s output regardless — only that the edge
    /// is worth a log line. A state transitioning to itself is always expected
    /// (a no-op refresh, e.g. `listening` while the level updates).
    public func canTransition(to next: PetState) -> Bool {
        if next == self { return true }
        return Self.expectedTransitions[self]?.contains(next) ?? false
    }
}

// MARK: - State-priority resolution

/// The inputs that determine Voice Desktop Pet's current state, mirroring the STATE MAPPING
/// table above one-to-one. Resolved by `PetState.resolve(from:)` into exactly
/// one `PetState` per the locked priority order.
public struct PetStateInputs: Equatable, Sendable {
    /// `false` when the engine is unavailable or mic permission is missing —
    /// forces `.dormant` regardless of every other input.
    public var engineAvailable: Bool
    /// The dictation engine's own idle/listening/processing signal (mirrors
    /// `MenubarIcon`/`CaptureSession.State`, collapsed to the three that matter
    /// to Voice Desktop Pet — `.done`/`.error` are transient and read as `.idle` here).
    public var isListening: Bool
    public var isProcessing: Bool
    /// Agent TTS active (`AgentSpeechQueue`-backed).
    public var isSpeaking: Bool
    /// Reserved seam (`PetAttentionProviding`); stub always reports `false`.
    public var isAgentWorking: Bool
    /// `true` when the AVB-7 inbox has ≥1 pending/presented item.
    public var hasAttention: Bool

    public init(
        engineAvailable: Bool,
        isListening: Bool,
        isProcessing: Bool,
        isSpeaking: Bool,
        isAgentWorking: Bool,
        hasAttention: Bool
    ) {
        self.engineAvailable = engineAvailable
        self.isListening = isListening
        self.isProcessing = isProcessing
        self.isSpeaking = isSpeaking
        self.isAgentWorking = isAgentWorking
        self.hasAttention = hasAttention
    }
}

extension PetState {

    /// Resolve the single active `PetState` from every simultaneous input,
    /// per the locked priority order: listening > speaking > attention >
    /// agentWorking > processing > idle > dormant. "Human always outranks
    /// agents" (spec §8) — `isListening` wins over every agent-originated
    /// signal even if they are simultaneously true.
    public static func resolve(from inputs: PetStateInputs) -> PetState {
        guard inputs.engineAvailable else { return .dormant }
        if inputs.isListening { return .listening }
        if inputs.isSpeaking { return .speaking }
        if inputs.hasAttention { return .attention }
        if inputs.isAgentWorking { return .agentWorking }
        if inputs.isProcessing { return .processing }
        return .idle
    }
}
