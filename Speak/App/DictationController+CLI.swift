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

    // MARK: - AVB-5 (specs/agent-voice-bridge.md §6) requestInput

    /// `speak_request_input`: the single workflow behind `.freeform`/`.choice`/
    /// `.approval` — `cliAsk`/`cliConfirm` below are now thin adapters over this.
    ///
    /// Busy check is the very first thing this does, before speaking a word or
    /// touching the mic: another agent-initiated capture already in flight means
    /// this request is refused as `.busy`, never queued. [decision: AVB-5]
    ///
    /// Empty-transcript outcomes: `.timedOut` when the request's own deadline was
    /// reached while still listening (this function then stops the capture itself);
    /// `.cancelled` when the human stopped the capture (Escape/hotkey/user stop)
    /// before the deadline without saying anything. A non-empty transcript is
    /// mode-extracted via `RequestInputExtractor` into `.answered`/`.declined`.
    func cliRequestInput(
        requestId: String,
        idempotencyKey: String?,
        prompt: String,
        mode: RequestInputMode,
        choices: [String],
        timeoutSeconds: TimeInterval,
        consequence: String?,
        spokenSummary: String?
    ) async -> HumanResponseOutcome {
        guard !RequestInputExtractor.isBusy(icon: icon) else {
            SpeakLog.engine.info(
                "DictationController: cliRequestInput(\(requestId, privacy: .public)) refused — busy."
            )
            return .busy
        }

        await agentSpeechQueue.cancelAll()
        await voiceOut.speak(spokenSummary ?? prompt, locale: settingsStore.language)

        // A hotkey dictation may have started while we were speaking — refuse
        // rather than stomp on it.
        guard !RequestInputExtractor.isBusy(icon: icon) else {
            SpeakLog.engine.info(
                "DictationController: cliRequestInput(\(requestId, privacy: .public)) refused — busy after speaking."
            )
            return .busy
        }

        let previousTranscript = lastTranscript
        lastTranscript = ""
        // [decision: AVB-5 follow-up — fixes a check-then-act race] Check the
        // return value of beginDictation(), not `icon` afterward: SpeakEngine's
        // [A3] guard can silently no-op if another capture (hotkey or a second
        // agent call) won the race during this `await`. Trusting `icon` here
        // would let the losing caller believe it owns a session it doesn't, and
        // later read the WINNING caller's `lastTranscript` — exactly the bug this
        // closes. `.requestInputRefusal` distinguishes `.collided` (self-resolving
        // → `.busy`) from `.failed` (mute/permission/other error — NOT
        // self-resolving → `.timedOut`), so a misleading "retry me" signal is
        // never sent for a persistent failure.
        if let refusal = await beginDictation().requestInputRefusal {
            SpeakLog.engine.info(
                "DictationController: cliRequestInput(\(requestId, privacy: .public)) — beginDictation did not start (\(String(describing: refusal), privacy: .public))."
            )
            lastTranscript = previousTranscript
            return refusal
        }

        // The answer belongs to the requesting MCP client, never the focused app.
        await engine.suppressPasteForAgentResponse()

        let deadline = Date().addingTimeInterval(max(0, timeoutSeconds))
        let pollNanoseconds: UInt64 = 100_000_000
        while Date() < deadline, [.listening, .processing].contains(icon) {
            try? await Task.sleep(nanoseconds: pollNanoseconds)
        }
        let reachedDeadline = Date() >= deadline

        if icon == .listening {
            await endDictation()
        } else {
            // An out-of-band stop may already be running endDictation(). Do not
            // inspect shared transcript state until that request-owned stop settles
            // — this is what makes a failed/aborted capture never return a stale
            // earlier dictation (stale-answer isolation).
            while icon == .processing {
                try? await Task.sleep(nanoseconds: pollNanoseconds)
            }
        }

        guard !lastTranscript.isEmpty else {
            lastTranscript = previousTranscript
            return RequestInputExtractor.outcomeForEmptyTranscript(reachedDeadline: reachedDeadline)
        }

        return RequestInputExtractor.extract(transcript: lastTranscript, mode: mode, choices: choices)
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
    /// [decision: AVB-5] Rebased as a thin compatibility adapter over
    /// `cliRequestInput(mode: .freeform)` — same HUD capture, same paste
    /// suppression, same stale-answer isolation, now with one shared
    /// implementation instead of a parallel round-trip. The wire contract and
    /// observable behavior are unchanged: any non-`.answered` outcome (`.declined`
    /// is unreachable in freeform mode, but `.cancelled`/`.timedOut`/`.busy` all
    /// arise from "no answer arrived") maps to `.timedOut`, exactly like the
    /// original implementation collapsed every "no transcript" cause into one case.
    func cliAsk(question: String, timeoutSeconds: TimeInterval) async -> CLIAskOutcome {
        let outcome = await cliRequestInput(
            requestId: UUID().uuidString,
            idempotencyKey: nil,
            prompt: question,
            mode: .freeform,
            choices: [],
            timeoutSeconds: timeoutSeconds,
            consequence: nil,
            spokenSummary: question
        )
        switch outcome {
        case .answered(let text, _):
            return .answered(text ?? "")
        case .declined, .cancelled, .timedOut, .busy:
            return .timedOut
        }
    }

    /// [decision: AVB-5] Rebased as a thin compatibility adapter over
    /// `cliRequestInput(mode: .approval)`. `speak_confirm`'s original fine-grained
    /// distinction between a spoken "cancel" phrase (`.cancelled`) and genuinely
    /// unrecognized speech (`.unclear`) lived entirely in the raw transcript text,
    /// which `.approval` mode's ambiguous case (`.answered(text:, choice: nil)`)
    /// still carries — so it's recovered here via the same `YesNoCancelExtractor`
    /// the original implementation used, preserving byte-for-byte identical
    /// behavior for existing `speak_confirm` clients.
    func cliConfirm(question: String, timeoutSeconds: TimeInterval) async -> CLIConfirmOutcome {
        let outcome = await cliRequestInput(
            requestId: UUID().uuidString,
            idempotencyKey: nil,
            prompt: question,
            mode: .approval,
            choices: [],
            timeoutSeconds: timeoutSeconds,
            consequence: nil,
            spokenSummary: question
        )
        switch outcome {
        case .answered(let text, let choice):
            guard choice == "approved" else {
                // Ambiguous: recover the old fine-grained cancel/unclear split
                // from the raw transcript text (never nil here — `.approval`
                // mode's ambiguous branch always carries the transcript).
                switch YesNoCancelExtractor.extract(text ?? "") {
                case .cancel:            return .cancelled
                case .yes, .no, .unclear: return .unclear
                }
            }
            return .yes
        case .declined:
            return .no
        case .cancelled, .timedOut, .busy:
            return .timedOut
        }
    }
}
