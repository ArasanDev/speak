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
    /// `precomputedCallId`: when non-nil, `CLIPortServer` already submitted +
    /// presented this call's durable row synchronously (via `bridgeToStore`)
    /// before this method even started, and is polling `getCall` for the
    /// terminal state — this method must resolve exactly that row rather than
    /// creating a second one. [decision: AVB-7-ask-confirm-pump-fix]
    func cliRequestInput(
        requestId: String,
        idempotencyKey: String?,
        prompt: String,
        mode: RequestInputMode,
        choices: [String],
        timeoutSeconds: TimeInterval,
        consequence: String?,
        spokenSummary: String?,
        precomputedCallId: UUID? = nil
    ) async -> HumanResponseOutcome {
        guard !RequestInputExtractor.isBusy(icon: icon) else {
            SpeakLog.engine.info(
                "DictationController: cliRequestInput(\(requestId, privacy: .public)) refused — busy."
            )
            await resolveDurableCall(precomputedCallId, outcome: .busy)
            return .busy
        }

        // AVB-7 (specs/avb7-durable-calls-design.md): thin adapter side effect —
        // durably record + immediately present this call so it's visible in the
        // inbox while the round-trip is in flight, without changing latency or
        // observable behavior. `sessionId: nil`, `expiresAt: nil` (this call
        // resolves within its own call stack below — never lingers). Best-effort:
        // any failure here is logged and swallowed, never surfaces to the caller
        // or changes the returned outcome — existing AVB-5 behavior is unchanged.
        // When `precomputedCallId` is supplied, the row already exists (submitted
        // synchronously by `CLIPortServer`) — reuse it instead of submitting again.
        let durableCallId: UUID?
        if let precomputedCallId {
            durableCallId = precomputedCallId
        } else {
            durableCallId = await recordDurableCallSubmission(
                requestId: requestId, idempotencyKey: idempotencyKey, prompt: prompt, mode: mode,
                choices: choices, consequence: consequence, spokenSummary: spokenSummary
            )
        }

        let spoken = spokenSummary ?? prompt
        // Clear before attach so a typed Send during TTS cannot be wiped by a
        // late `lastTranscript = ""` after speak. [fix: presenter wipe race]
        let previousTranscript = lastTranscript
        lastTranscript = ""

        let (presenter, interruptFlag) = attachRequestInputPresentation(
            prompt: spoken,
            timeoutSeconds: timeoutSeconds
        )

        await agentSpeechQueue.cancelAll()
        await voiceOut.speak(spoken, locale: settingsStore.language)
        presenter.markListening()

        if interruptFlag.value {
            lastTranscript = previousTranscript
            presenter.detach()
            await resolveDurableCall(durableCallId, outcome: .cancelled)
            return .cancelled
        }

        // A hotkey dictation may have started while we were speaking — refuse
        // rather than stomp on it.
        guard !RequestInputExtractor.isBusy(icon: icon) else {
            SpeakLog.engine.info(
                "DictationController: cliRequestInput(\(requestId, privacy: .public)) refused — busy after speaking."
            )
            lastTranscript = previousTranscript
            presenter.detach()
            await resolveDurableCall(durableCallId, outcome: .busy)
            return .busy
        }

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
            presenter.detach()
            await resolveDurableCall(durableCallId, outcome: refusal)
            return refusal
        }

        await engine.suppressPasteForAgentResponse()
        let reachedDeadline = await pollRequestInputUntilSettled(
            timeoutSeconds: timeoutSeconds,
            presenter: presenter
        )
        presenter.detach()

        if interruptFlag.value {
            lastTranscript = previousTranscript
            await resolveDurableCall(durableCallId, outcome: .cancelled)
            return .cancelled
        }

        guard !lastTranscript.isEmpty else {
            lastTranscript = previousTranscript
            let outcome = RequestInputExtractor.outcomeForEmptyTranscript(reachedDeadline: reachedDeadline)
            await resolveDurableCall(durableCallId, outcome: outcome)
            return outcome
        }

        let outcome = RequestInputExtractor.extract(transcript: lastTranscript, mode: mode, choices: choices)
        await resolveDurableCall(durableCallId, outcome: outcome)
        return outcome
    }

    /// Magenta conversation presentation for request_input — not an MCP mode.
    /// Uses `.gatedTurn` so silence VAD cannot race the AVB-5 poll loop.
    private func attachRequestInputPresentation(
        prompt: String,
        timeoutSeconds: TimeInterval
    ) -> (ConversationInputPresenter, RequestInputInterruptFlag) {
        let presenter = ConversationInputPresenter()
        let interruptFlag = RequestInputInterruptFlag()
        do {
            try presenter.attach(
                overlayController: overlayController,
                prompt: prompt,
                maxListeningDuration: timeoutSeconds,
                onUserCommitted: { [weak self] text in
                    guard let self else { return }
                    self.lastTranscript = text
                    Task { await self.endDictation() }
                },
                onInterrupted: { [weak self] in
                    interruptFlag.value = true
                    guard let self else { return }
                    Task {
                        await self.agentSpeechQueue.cancelAll()
                        await self.endDictation()
                    }
                }
            )
        } catch {
            SpeakLog.engine.error(
                "DictationController: conversation presentation attach failed — \(error.localizedDescription, privacy: .public)"
            )
        }
        return (presenter, interruptFlag)
    }

    /// Poll until the request-owned capture leaves listening/processing or the
    /// deadline elapses. Returns whether the deadline was reached.
    private func pollRequestInputUntilSettled(
        timeoutSeconds: TimeInterval,
        presenter: ConversationInputPresenter
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(max(0, timeoutSeconds))
        let pollNanoseconds: UInt64 = 100_000_000  // 100 ms — [decision: AVB-5 poll cadence]
        while Date() < deadline, [.listening, .processing].contains(icon) {
            guard !Task.isCancelled else { break }
            if !lastTranscript.isEmpty {
                presenter.updateUserTranscript(lastTranscript)
            }
            do {
                try await Task.sleep(nanoseconds: pollNanoseconds)
            } catch {
                break
            }
        }
        let reachedDeadline = Date() >= deadline

        if icon == .listening {
            await endDictation()
        } else {
            while icon == .processing {
                guard !Task.isCancelled else { break }
                do {
                    try await Task.sleep(nanoseconds: pollNanoseconds)
                } catch {
                    break
                }
            }
        }
        return reachedDeadline
    }

    // MARK: - AVB-7 request_input durable side effect

    /// Submit + immediately present the durable `AgentCall` backing this
    /// `speak_request_input` round-trip. Best-effort: failures are logged and
    /// swallowed — `cliRequestInput`'s returned `HumanResponseOutcome` is never
    /// affected. Returns `nil` when the write failed (or a race produced a
    /// duplicate with no usable id), in which case `resolveDurableCall` below
    /// is also a no-op. [decision: AVB-7]
    private func recordDurableCallSubmission(
        requestId: String, idempotencyKey: String?, prompt: String, mode: RequestInputMode,
        choices: [String], consequence: String?, spokenSummary: String?
    ) async -> UUID? {
        do {
            let result = try await agentCallStore.submit(AgentCallSubmission(
                sessionId: nil, requestId: requestId, idempotencyKey: idempotencyKey, prompt: prompt,
                mode: mode, choices: choices, consequence: consequence, spokenSummary: spokenSummary,
                urgency: .normal, expiresAt: nil
            ))
            let callId: UUID
            switch result {
            case .created(let call):
                callId = call.id
            case .duplicateSubmission(let existingCallId):
                // Rare: two request_input calls in-flight with the same
                // (nil-session, idempotencyKey) pair. AVB-5's busy check
                // already governs the actual capture; this only affects
                // inbox bookkeeping, so recording against the existing row
                // is fine — it does not get a second `markPresented`/`resolve`
                // from THIS call stack (that would race the other one's), so
                // skip presenting/resolving here and let the original caller
                // own its own lifecycle.
                SpeakLog.storage.info(
                    "DictationController: durable requestInput submission was a duplicate of \(existingCallId.uuidString, privacy: .private) — skipping presentation."
                )
                return nil
            }
            try await agentCallStore.markPresented(id: callId)
            return callId
        } catch {
            SpeakLog.storage.error(
                "DictationController: durable requestInput submission failed — \(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
    }

    /// Resolve the durable `AgentCall` (if one was successfully recorded) with
    /// the round-trip's outcome. Best-effort: failures are logged, never thrown.
    private func resolveDurableCall(_ callId: UUID?, outcome: HumanResponseOutcome) async {
        guard let callId else { return }
        do {
            try await agentCallStore.resolve(id: callId, outcome: outcome)
        } catch {
            SpeakLog.storage.error(
                "DictationController: durable requestInput resolve failed — \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    // MARK: - AVB-6 (specs/agent-voice-bridge.md §7.1) session registration

    /// `speak_register_session`: register (or re-register, when `sessionId` is
    /// already known) an `AgentSession` and negotiate capabilities. Fast/
    /// in-memory — no mic, no HUD, no speech. [decision: AVB-6]
    func cliRegisterSession(
        sessionId: String?,
        provider: String,
        label: String,
        workingDirectory: String?,
        requestedCapabilities: [String]
    ) -> (sessionId: String, capabilities: [String]) {
        let session = agentSessionRegistry.register(
            sessionId: sessionId,
            provider: provider,
            label: label,
            workingDirectory: workingDirectory,
            requestedCapabilities: requestedCapabilities
        )
        SpeakLog.cli.info(
            "DictationController: cliRegisterSession(\(session.sessionId, privacy: .public)) — provider=\(provider, privacy: .public)."
        )
        return (sessionId: session.sessionId, capabilities: session.capabilities)
    }

    /// Update `lastSeen` for `sessionId` and report whether it was already
    /// known. Every agent-bridge tool that carries an optional `sessionId`
    /// routes through this so a call for an unrecognized session still
    /// proceeds — the note is attached one layer up (`CLIPortServer`).
    /// [decision: AVB-6]
    func cliTouchSession(_ sessionId: String) -> Bool {
        agentSessionRegistry.touch(sessionId: sessionId)
    }

    // MARK: - AVB-7 (specs/avb7-durable-calls-design.md) durable calls

    /// Synchronous session-registration check backing `speak_submit_call`/
    /// `speak_get_call` — split out so `CLIPortServer` can validate inline
    /// (no Task, no pump) and touch `agentCallStore` directly for the actual
    /// I/O. [decision: AVB-7-pump-fix]
    func cliIsSessionKnown(_ sessionId: String) -> Bool {
        agentSessionRegistry.isKnown(sessionId: sessionId)
    }

    /// AVB-7 inbox UI "Answer by voice" row action. Routes through the SAME
    /// capture path `cliRequestInput` uses (`beginDictation()`/`endDictation()`,
    /// `RequestInputExtractor`) — never a second, parallel mic path. Unlike
    /// `cliRequestInput`, this does NOT submit a new `AgentCall` (the row's call
    /// already exists, already `.presented`) — it only runs the round-trip and
    /// resolves the SAME call id. A `.collided` start surfaces as `.busy` here
    /// (never a silent no-op) so the inbox can show "capture busy" rather than
    /// nothing happening. [decision: AVB-7]
    ///
    /// [decision: AVB-7 — accepted duplication] This mirrors the round-trip body
    /// of `cliRequestInput` below rather than sharing a private helper; the two
    /// differ only in which durable-store calls bracket the round-trip
    /// (submit+present+resolve vs. resolve-only), and factoring that out is left
    /// to a follow-up rather than risking `cliRequestInput`'s already-reviewed
    /// AVB-5 behavior in this slice.
    func answerAgentCallByVoice(_ call: AgentCall) async -> HumanResponseOutcome {
        guard !RequestInputExtractor.isBusy(icon: icon) else {
            SpeakLog.engine.info("DictationController: answerAgentCallByVoice(\(call.id.uuidString, privacy: .private)) refused — busy.")
            return .busy
        }

        await agentSpeechQueue.cancelAll()
        await voiceOut.speak(call.spokenSummary ?? call.prompt, locale: settingsStore.language)

        guard !RequestInputExtractor.isBusy(icon: icon) else {
            await resolveDurableCall(call.id, outcome: .busy)
            return .busy
        }

        let previousTranscript = lastTranscript
        lastTranscript = ""
        if let refusal = await beginDictation().requestInputRefusal {
            lastTranscript = previousTranscript
            await resolveDurableCall(call.id, outcome: refusal)
            return refusal
        }

        await engine.suppressPasteForAgentResponse()

        let defaultAnswerTimeout: TimeInterval = 60
        let deadline = Date().addingTimeInterval(defaultAnswerTimeout)
        let pollNanoseconds: UInt64 = 100_000_000  // 100 ms — [decision: AVB-5 poll cadence]
        while Date() < deadline, [.listening, .processing].contains(icon) {
            try? await Task.sleep(nanoseconds: pollNanoseconds)
        }
        let reachedDeadline = Date() >= deadline

        if icon == .listening {
            await endDictation()
        } else {
            while icon == .processing {
                try? await Task.sleep(nanoseconds: pollNanoseconds)
            }
        }

        let outcome: HumanResponseOutcome
        if lastTranscript.isEmpty {
            lastTranscript = previousTranscript
            outcome = RequestInputExtractor.outcomeForEmptyTranscript(reachedDeadline: reachedDeadline)
        } else {
            outcome = RequestInputExtractor.extract(transcript: lastTranscript, mode: call.mode, choices: call.choices)
        }
        await resolveDurableCall(call.id, outcome: outcome)
        return outcome
    }

    /// AVB-7 inbox UI "Decline"/"Dismiss" row actions — no mic. `decline` maps to
    /// `HumanResponseOutcome.declined`; `dismiss` maps to `.cancelled` (the
    /// human explicitly chose not to engage, same terminal bucket as an
    /// Escape-cancelled capture). [decision: AVB-7]
    func declineAgentCall(_ callId: UUID) async {
        await resolveDurableCall(callId, outcome: .declined)
    }

    func dismissAgentCall(_ callId: UUID) async {
        await resolveDurableCall(callId, outcome: .cancelled)
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
    func cliAsk(question: String, timeoutSeconds: TimeInterval, precomputedCallId: UUID? = nil) async -> CLIAskOutcome {
        let outcome = await cliRequestInput(
            requestId: UUID().uuidString,
            idempotencyKey: nil,
            prompt: question,
            mode: .freeform,
            choices: [],
            timeoutSeconds: timeoutSeconds,
            consequence: nil,
            spokenSummary: question,
            precomputedCallId: precomputedCallId
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
    func cliConfirm(question: String, timeoutSeconds: TimeInterval, precomputedCallId: UUID? = nil) async -> CLIConfirmOutcome {
        let outcome = await cliRequestInput(
            requestId: UUID().uuidString,
            idempotencyKey: nil,
            prompt: question,
            mode: .approval,
            choices: [],
            timeoutSeconds: timeoutSeconds,
            consequence: nil,
            spokenSummary: question,
            precomputedCallId: precomputedCallId
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
