// SpeakTests/PetStateTests.swift
//
// FE-1: `PetState`'s priority resolution (the single source of truth for
// Pip's display) and the ADVISORY transition map. Pure value-type tests —
// no panel, no rendering (matches `AuroraMathTests`' convention).
//
// CONVERGENCE CONTRACT (review fix, 2026-07-11): the display ALWAYS converges
// to `resolve()`'s output, unconditionally, on every tick. The transition map
// is advisory (log-only) — an "unexpected" edge must still be applied. The
// convergence tests below drive resolve() across live signal changes and
// assert the resolved state tracks the signals with no possibility of a
// stale hold (the onAir-iff-capturing invariant, spec §2 hard rule).

@testable import Speak
import Testing

@Suite("PetState — convergence (resolve is the single source of truth)")
struct PetStateConvergenceTests {

    @Test("fast cleanup: listening → all-clear converges to .idle in one resolve call")
    func fastCleanupConvergesToIdle() {
        // Tick N: mic open.
        let listeningInputs = PetStateInputs(
            engineAvailable: true, isListening: true, isProcessing: false,
            isSpeaking: false, isAgentWorking: false, hasAttention: false
        )
        #expect(PetState.resolve(from: listeningInputs) == .listening)

        // Tick N+1: a fast cleanup finished entirely inside one tick — the
        // signals skipped `.processing` and went straight to all-clear.
        // The display MUST converge to .idle immediately; the advisory map
        // marking this edge "unexpected" must not prevent it (that would
        // freeze "Listening" + the onAir tally with the mic closed).
        let allClearInputs = PetStateInputs(
            engineAvailable: true, isListening: false, isProcessing: false,
            isSpeaking: false, isAgentWorking: false, hasAttention: false
        )
        #expect(PetState.resolve(from: allClearInputs) == .idle)
    }

    @Test("onAir-iff-capturing: NO input combination resolves to .listening once the mic-open signal is false")
    func noStaleListeningPossible() {
        // Exhaustive sweep of every boolean input combination with
        // isListening == false: resolve() must never output .listening —
        // there is no path by which the onAir tally can outlive the mic.
        for engineAvailable in [false, true] {
            for isProcessing in [false, true] {
                for isSpeaking in [false, true] {
                    for isAgentWorking in [false, true] {
                        for hasAttention in [false, true] {
                            let inputs = PetStateInputs(
                                engineAvailable: engineAvailable,
                                isListening: false,
                                isProcessing: isProcessing,
                                isSpeaking: isSpeaking,
                                isAgentWorking: isAgentWorking,
                                hasAttention: hasAttention
                            )
                            #expect(PetState.resolve(from: inputs) != .listening)
                        }
                    }
                }
            }
        }
    }

    @Test("resolve is memoryless: the same inputs always give the same state regardless of history")
    func resolveIsMemoryless() {
        // resolve() is a pure function of the inputs — there is no previous-
        // state parameter through which a stale display could persist.
        let inputs = PetStateInputs(
            engineAvailable: true, isListening: false, isProcessing: true,
            isSpeaking: false, isAgentWorking: false, hasAttention: false
        )
        #expect(PetState.resolve(from: inputs) == PetState.resolve(from: inputs))
        #expect(PetState.resolve(from: inputs) == .processing)
    }
}

@Suite("PetState — advisory transition map (log-only, never gates display)")
struct PetStateAdvisoryMapTests {

    @Test("a state transitioning to itself is always expected", arguments: PetState.allCases)
    func selfTransitionAlwaysExpected(state: PetState) {
        #expect(state.canTransition(to: state))
    }

    @Test("the normal dictation lifecycle edges are all expected")
    func dictationLifecycleExpected() {
        #expect(PetState.dormant.canTransition(to: .idle))
        #expect(PetState.idle.canTransition(to: .listening))
        #expect(PetState.listening.canTransition(to: .processing))
        #expect(PetState.processing.canTransition(to: .idle))
    }

    @Test("skipped-beat edges are flagged unexpected (advisory) — but nothing more")
    func skippedBeatEdgesFlagged() {
        // These edges CAN occur (fast cleanup inside one poll tick, etc.) and
        // MUST be applied by tick(); canTransition == false only means the
        // controller logs them. This test documents the advisory contract.
        #expect(!PetState.listening.canTransition(to: .idle))
        #expect(!PetState.dormant.canTransition(to: .listening))
    }

    @Test("every state expects a transition to dormant (permission can be revoked at any time)", arguments: PetState.allCases)
    func everyStateExpectsDormant(state: PetState) {
        #expect(state.canTransition(to: .dormant))
    }

    @Test("idle expects every agent-originated state")
    func idleExpectsAgentStates() {
        #expect(PetState.idle.canTransition(to: .agentWorking))
        #expect(PetState.idle.canTransition(to: .attention))
        #expect(PetState.idle.canTransition(to: .speaking))
    }
}

@Suite("PetState — priority resolution")
struct PetStatePriorityTests {

    private func inputs(
        engineAvailable: Bool = true,
        isListening: Bool = false,
        isProcessing: Bool = false,
        isSpeaking: Bool = false,
        isAgentWorking: Bool = false,
        hasAttention: Bool = false
    ) -> PetStateInputs {
        PetStateInputs(
            engineAvailable: engineAvailable,
            isListening: isListening,
            isProcessing: isProcessing,
            isSpeaking: isSpeaking,
            isAgentWorking: isAgentWorking,
            hasAttention: hasAttention
        )
    }

    @Test("engine unavailable forces dormant regardless of every other input")
    func dormantWinsWhenEngineUnavailable() {
        let resolved = PetState.resolve(from: inputs(
            engineAvailable: false,
            isListening: true,
            isSpeaking: true,
            isAgentWorking: true,
            hasAttention: true
        ))
        #expect(resolved == .dormant)
    }

    @Test("listening beats speaking, attention, and agentWorking simultaneously — human always outranks agents")
    func listeningBeatsEverything() {
        let resolved = PetState.resolve(from: inputs(
            isListening: true,
            isSpeaking: true,
            isAgentWorking: true,
            hasAttention: true
        ))
        #expect(resolved == .listening)
    }

    @Test("speaking beats attention and agentWorking")
    func speakingBeatsAttentionAndAgentWorking() {
        let resolved = PetState.resolve(from: inputs(
            isSpeaking: true,
            isAgentWorking: true,
            hasAttention: true
        ))
        #expect(resolved == .speaking)
    }

    @Test("attention beats agentWorking")
    func attentionBeatsAgentWorking() {
        let resolved = PetState.resolve(from: inputs(isAgentWorking: true, hasAttention: true))
        #expect(resolved == .attention)
    }

    @Test("agentWorking beats processing")
    func agentWorkingBeatsProcessing() {
        let resolved = PetState.resolve(from: inputs(isProcessing: true, isAgentWorking: true))
        #expect(resolved == .agentWorking)
    }

    @Test("processing wins when nothing else is set")
    func processingAlone() {
        #expect(PetState.resolve(from: inputs(isProcessing: true)) == .processing)
    }

    @Test("idle is the default when everything is false")
    func idleIsDefault() {
        #expect(PetState.resolve(from: inputs()) == .idle)
    }
}
