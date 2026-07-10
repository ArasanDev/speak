// App/DictationController+CLI.swift
//
// CLI IPC entry points (W2.3). Bridges `speak --start` / `--stop` into the
// same begin/end path the hotkey uses. The idempotency gate lives in
// `CLIPortServer` (checks `icon` before calling); dispatch here is intentionally
// simple and trusts that gate.
//
// H-3 (specs/horizon-voice-os.md Pillar 3 — MCP Agent Bridge): `cliSay`/`cliAsk`/
// `cliConfirm` wire the `speak_say`/`speak_ask`/`speak_confirm` MCP tools to the
// same `voiceOut` TTS instance and `beginDictation()`/`endDictation()` session path
// the hotkey uses — not a second, competing engine instance. Reusing that path gives
// ask/confirm HUD visibility and mic-permission gating for free, matching the spec
// requirement that "every agent-initiated mic open is visually surfaced, never
// silent listening."

import Foundation
import SpeakCore

extension DictationController {

    // MARK: - CLICommandHandler (W2.3)

    /// Called by `CLIPortServer` when a `--start` command arrives.
    /// Dispatches `beginDictation()` on the main actor (already on main — the
    /// port callback schedules on CFRunLoopGetMain). Reuses the hotkey path exactly.
    func cliBeginDictation() {
        Task { [weak self] in
            await self?.beginDictation()
        }
    }

    /// Called by `CLIPortServer` when a `--stop` command arrives.
    /// Dispatches `endDictation()` on the main actor. Reuses the hotkey path exactly.
    func cliEndDictation() {
        Task { [weak self] in
            await self?.endDictation()
        }
    }

    // MARK: - H-3 say/ask/confirm

    /// `speak_say`: speak `text` aloud. Fire-and-forget from `CLIPortServer`'s point
    /// of view (it replies with an accept-ack immediately) — the `Task` here runs to
    /// completion independently. `SpeechSynthesizing.speak(_:locale:)` already stops
    /// any in-progress utterance before starting a new one (never overlap), so
    /// `interrupt` is honored by construction; the parameter is kept on the wire
    /// contract for API clarity / future queuing rather than because the current
    /// conformer needs it to decide. [decision: H-3]
    func cliSay(text: String, interrupt: Bool) {
        Task { [weak self] in
            guard let self else { return }
            SpeakLog.voiceOut.info(
                "DictationController: cliSay — \(text.count, privacy: .public) chars, interrupt=\(interrupt, privacy: .public)"
            )
            await self.agentSpeechQueue.submit(
                text: text,
                locale: self.settingsStore.language,
                interrupt: interrupt
            )
        }
    }

    /// `speak_ask`: speak `question`, then run one full dictation round-trip on the
    /// SAME session path `beginDictation()`/`endDictation()` (hotkey, CLI --start/
    /// --stop) uses, and return the resulting transcript.
    ///
    /// [decision: H-3 — no voice-activity-detection auto-stop in this slice] The
    /// session listens for the full `timeoutSeconds` window rather than stopping as
    /// soon as the human finishes speaking (the engine has no silence-detection
    /// seam yet). This is deliberately simple: a future task could add early-stop
    /// on trailing silence; the wire contract (`CLIRequest.timeout`) and the MCP
    /// tool schema already expose the caller-tunable knob such a feature would use.
    ///
    /// Returns `.timedOut` (never partial/garbage text) when the round-trip could
    /// not be started at all — another dictation already in flight, mic permission
    /// denied, hardware-muted, etc. — so a stuck agent request degrades to a clear
    /// failure instead of returning an empty-string "answer".
    func cliAsk(question: String, timeoutSeconds: TimeInterval) async -> CLIAskOutcome {
        // [H-2] Cut off any in-flight readback before speaking the question — mirrors
        // beginDictation()'s own "any hotkey press cuts TTS instantly" contract.
        await agentSpeechQueue.cancelAll()
        await voiceOut.speak(question, locale: settingsStore.language)

        guard icon == .idle else {
            SpeakLog.engine.info("DictationController: cliAsk refused — a dictation is already in flight.")
            return .timedOut
        }

        let previousTranscript = lastTranscript
        lastTranscript = ""
        await beginDictation()
        guard icon == .listening else {
            // beginDictation() failed (permission denied, muted, etc.) and already
            // routed itself to .error/.idle with its own HUD messaging.
            SpeakLog.engine.info("DictationController: cliAsk — beginDictation did not reach .listening; aborting.")
            lastTranscript = previousTranscript
            return .timedOut
        }

        // The answer belongs to the requesting MCP client. It must never be
        // injected into whichever editor/terminal happens to retain focus.
        await engine.suppressPasteForAgentResponse()

        let deadline = Date().addingTimeInterval(max(0, timeoutSeconds))
        // A hotkey/Escape stop should complete the request immediately instead of
        // making the agent wait out the full timeout. 100 ms is the existing
        // permission/hotkey watchdog cadence. [decision: reuse measured UI cadence]
        let pollNanoseconds: UInt64 = 100_000_000
        while Date() < deadline, [.listening, .processing].contains(icon) {
            try? await Task.sleep(nanoseconds: pollNanoseconds)
        }

        // Timeout closes a still-listening session. If the user already stopped,
        // wait above carries us through processing until lastTranscript is owned by
        // this request rather than returning stale shared state.
        if icon == .listening {
            await endDictation()
        } else {
            // An out-of-band stop may already be running endDictation(). Do not
            // inspect shared transcript state until that request-owned stop settles.
            while icon == .processing {
                try? await Task.sleep(nanoseconds: pollNanoseconds)
            }
        }
        guard !lastTranscript.isEmpty else {
            lastTranscript = previousTranscript
            return .timedOut
        }
        return .answered(lastTranscript)
    }

    /// `speak_confirm`: identical round-trip to `cliAsk`, then extracts a
    /// deterministic yes/no/cancel/unclear from the transcript via
    /// `YesNoCancelExtractor` — no LLM call. [decision: H-3]
    func cliConfirm(question: String, timeoutSeconds: TimeInterval) async -> CLIConfirmOutcome {
        switch await cliAsk(question: question, timeoutSeconds: timeoutSeconds) {
        case .timedOut:
            return .timedOut

        case .answered(let text):
            switch YesNoCancelExtractor.extract(text) {
            case .yes:     return .yes
            case .no:      return .no
            case .cancel:  return .cancelled
            case .unclear: return .unclear
            }
        }
    }
}
