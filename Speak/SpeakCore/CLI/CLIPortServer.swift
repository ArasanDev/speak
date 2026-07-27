// SpeakCore/CLI/CLIPortServer.swift
//
// Server-side CFMessagePort registration for the CLI IPC channel.
//
// Called once from `DictationController.startMonitoring()` (after the
// XCTestConfigurationFilePath early-return guard in AppDelegate) so the port is
// live only when the app is running as a real menubar instance.
//
// Threading contract:
//   - `CLIPortServer` is created and retained by `DictationController` (MainActor).
//   - The CFMessagePort callback is `@convention(c)` — cannot capture Swift context.
//     We route context through `CFMessagePortContext.info` using an unretained
//     Unmanaged reference to the `CLIPortServer` instance (the server lives for
//     the app lifetime — there is no UAF risk). [decision: W2.3]
//   - The port's run-loop source is scheduled on `CFRunLoopGetMain()` in
//     `.commonModes` so the callback fires on the main thread even during modal /
//     event-tracking run-loop modes (onboarding, settings sheet, menu tracking).
//   - `--status` reads the live state synchronously inside the callback using
//     `MainActor.assumeIsolated` (we are already on the main thread). [decision: W2.3]
//   - `--start`/`--stop` dispatch a `Task { @MainActor in ... }` and return an
//     accept-ack immediately. The dictation transition may not have completed
//     when the reply is delivered. [decision: W2.3]
//
// Idempotency:
//   The handler gates on `DictationController.icon` before dispatching:
//     start: no-op if icon != .idle  (already recording or processing)
//     stop:  no-op if icon != .listening  (already idle or processing)
//   This matches the Escape-handler guard at DictationController:307 and reuses
//   the same private beginDictation/endDictation path. [decision: W2.3]

@preconcurrency import CoreFoundation
import Foundation
import os

// MARK: - CLICommandHandler protocol

/// The subset of `DictationController` that `CLIPortServer` needs.
/// Keeping this narrow avoids a circular import and makes the server
/// independently testable via a stub. [decision: W2.3]
@MainActor
public protocol CLICommandHandler: AnyObject {
    /// The current app icon state — used to gate idempotent commands.
    var icon: MenubarIcon { get }
    /// The current hotkey binding display string (e.g. "⌘ Right Command ×2").
    var currentHotkeyDisplayString: String { get }
    /// Start a dictation session. No-op if already listening/processing.
    func cliBeginDictation()
    /// End the current dictation session. No-op if not listening.
    func cliEndDictation()

    // MARK: - H-3 (specs/horizon-voice-os.md Pillar 3)

    /// Speak `text` aloud. Fire-and-forget from the port server's point of view —
    /// the port replies with an accept-ack before speech finishes, mirroring
    /// start/stop. [decision: H-3]
    func cliSay(text: String, interrupt: Bool)

    /// Speak `question`, then run a full dictation round-trip (reusing the same
    /// `beginDictation()`/`endDictation()` session the hotkey uses) and return the
    /// transcript. Returns `.timedOut` if no answer arrives within `timeoutSeconds`.
    /// [decision: H-3]
    func cliAsk(question: String, timeoutSeconds: TimeInterval) async -> CLIAskOutcome

    /// Speak `question`, then run a full dictation round-trip and extract a
    /// deterministic yes/no/cancel/unclear from the answer via `YesNoCancelExtractor`.
    /// Returns `.timedOut` if no answer arrives within `timeoutSeconds`. [decision: H-3]
    func cliConfirm(question: String, timeoutSeconds: TimeInterval) async -> CLIConfirmOutcome

    // MARK: - AVB-5 (specs/agent-voice-bridge.md §6)

    /// `speak_request_input`: speak `prompt` (or `spokenSummary` when given), then
    /// run one full dictation round-trip on the same session path as `cliAsk`/
    /// `cliConfirm`, and return exactly one of the five canonical
    /// `HumanResponseOutcome` outcomes. Returns `.busy` immediately (without ever
    /// opening the mic) when another agent-initiated capture is already in flight
    /// — never queues. [decision: AVB-5]
    func cliRequestInput(
        requestId: String,
        idempotencyKey: String?,
        prompt: String,
        mode: RequestInputMode,
        choices: [String],
        timeoutSeconds: TimeInterval,
        consequence: String?,
        spokenSummary: String?
    ) async -> HumanResponseOutcome

    // MARK: - AVB-6 (specs/agent-voice-bridge.md §7.1)

    /// Update `lastSeen` for `sessionId` in the app's `AgentSessionRegistry` and
    /// report whether it was known. Every tool that carries an optional
    /// `sessionId` (notify/say/ask/confirm/request_input/status) routes through
    /// this before replying so the wire can attach an "unregistered session"
    /// note without rejecting the call. [decision: AVB-6]
    func cliTouchSession(_ sessionId: String) async -> Bool

    /// `speak_register_session`: register (or re-register, when `sessionId` is
    /// already known) an `AgentSession` and negotiate capabilities against
    /// `AgentSessionRegistry.supportedCapabilities`. [decision: AVB-6]
    func cliRegisterSession(
        sessionId: String?,
        provider: String,
        label: String,
        workingDirectory: String?,
        requestedCapabilities: [String]
    ) async -> (sessionId: String, capabilities: [String])

    // MARK: - AVB-7 (specs/avb7-durable-calls-design.md)

    /// `speak_submit_call`: durably record a new `AgentCall` — no mic, no pump,
    /// fast return. Requires a known-registered `sessionId`; `.unregistered` when
    /// absent or not found in the registry (never a silent proceed, unlike the
    /// advisory `sessionNote` other tools attach). [decision: AVB-7]
    func cliSubmitCall(_ args: SubmitCallArguments) async -> CLISubmitCallOutcome

    /// `speak_get_call`: read-only poll of one `AgentCall`'s current state.
    /// Requires a known-registered `sessionId`; a session mismatch or unknown id
    /// reads as `.call(nil)`, never revealing existence. [decision: AVB-7]
    func cliGetCall(sessionId: String?, callId: UUID) async -> CLIGetCallOutcome

    // MARK: - Layer 4

    /// `speak_ask_user`: ask prompt in Magenta overlay UI, returning user response string.
    func cliAskUser(prompt: String, mode: String?) async -> CLIAskOutcome

    /// `speak_stream_speech`: stream agent response text to TTS and overlay UI.
    func cliStreamSpeech(text: String, isFinal: Bool) async -> String
}

// MARK: - AVB-7 durable-call outcomes

/// Outcome of `CLICommandHandler.cliSubmitCall`. `.unregistered` is distinct from
/// every `AgentCallSubmitResult` case — it never reaches the store at all.
/// [decision: AVB-7]
public enum CLISubmitCallOutcome: Sendable, Equatable {
    case unregistered
    case created(AgentCall)
    /// The existing (already-fetched) call for a duplicate (sessionId, idempotencyKey)
    /// submission — carries the full call so the wire reply needs no follow-up fetch.
    case duplicate(AgentCall)
    /// An internal store failure unrelated to registration (e.g. SQLite error, or
    /// the practically-unreachable "duplicate row vanished before lookup" case).
    /// Distinct from `.unregistered` so the reply text never wrongly tells the
    /// caller to register a session. [decision: AVB-7]
    case internalError(String)
}

/// Outcome of `CLICommandHandler.cliGetCall`. `.unregistered` (no/unknown
/// sessionId) is distinct from `.call(nil)` (registered caller, but the id
/// doesn't exist or belongs to another session — isolation, not an error).
/// [decision: AVB-7]
public enum CLIGetCallOutcome: Sendable, Equatable {
    case unregistered
    case call(AgentCall?)
}

// MARK: - H-3 async command outcomes

/// Outcome of `CLICommandHandler.cliAsk`. A distinct type (not `String?`) so
/// "no answer" (timeout) is never confused with the empty string being a valid
/// (if unusual) spoken answer. [decision: H-3]
public enum CLIAskOutcome: Sendable, Equatable {
    case answered(String)
    case timedOut
}

/// Outcome of `CLICommandHandler.cliConfirm`. Mirrors `YesNoCancelResult` plus a
/// `timedOut` case for "no answer arrived in time" — distinct from `.unclear`
/// ("an answer arrived but didn't match any phrase list"). [decision: H-3]
public enum CLIConfirmOutcome: Sendable, Equatable {
    case yes
    case no
    case unclear
    case cancelled
    case timedOut
}

// MARK: - CLIPortServer

/// Registers and owns a local CFMessagePort server that the `speak` CLI tool
/// connects to for `--start`, `--stop`, and `--status` commands.
///
/// Ownership: one instance per app lifetime, retained by `DictationController`.
/// `invalidate()` is called on deinit and when monitoring stops (not currently
/// used — the app terminates instead).
@MainActor
public final class CLIPortServer {

    // MARK: - Private state

    nonisolated(unsafe) private var port: CFMessagePort?
    nonisolated(unsafe) private var runLoopSource: CFRunLoopSource?

    // Unretained reference used by the C callback.
    // The server lives for the app lifetime; the weak reference is a belt-
    // and-suspenders guard for any hypothetical early teardown.
    private weak var handler: (any CLICommandHandler)?

    // MARK: - Init / teardown

    public init() {}

    deinit {
        invalidate()
    }

    /// Register the named local port and schedule it on the main run loop.
    ///
    /// Must be called from the main thread (or main actor) after the app is live.
    /// Safe to call multiple times — no-ops if already registered.
    ///
    /// - Parameter handler: The `CLICommandHandler` that handles dispatched commands.
    public func register(handler: any CLICommandHandler) {
        guard port == nil else {
            SpeakLog.cli.warning("CLIPortServer.register: already registered — no-op.")
            return
        }

        self.handler = handler

        // Build the context with an unretained pointer to self.
        // The C callback reconstructs `CLIPortServer` from `context.info`.
        // `self` outlives the port (deinit calls invalidate()) so no UAF.
        var context = CFMessagePortContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        // Create the local named port. `shouldFreeInfo` is false — we own context.
        var shouldFreeInfo: DarwinBoolean = false
        guard let localPort = CFMessagePortCreateLocal(
            nil,                        // allocator
            CLIContract.portName,       // "com.speak.app.cli"
            CLIPortServer.portCallback, // @convention(c) callback
            &context,
            &shouldFreeInfo
        ) else {
            let portName = CLIContract.portName as String
            SpeakLog.cli.error(
                "CLIPortServer: failed to create local CFMessagePort '\(portName, privacy: .public)' — already registered?"
            )
            return
        }

        port = localPort

        // Schedule on the main run loop so the callback fires on the main thread.
        // [validation-fix C6] Use .commonModes (not .defaultMode) so the CLI callback
        // still fires while the run loop is in a modal/event-tracking mode — e.g. the
        // onboarding window, a settings sheet, or menu tracking. With .defaultMode,
        // `speak --status`/`--stop` would silently time out (3 s) during a modal.
        let source = CFMessagePortCreateRunLoopSource(nil, localPort, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        runLoopSource = source

        SpeakLog.cli.info(
            "CLIPortServer: registered on port '\(CLIContract.portName as String, privacy: .public)'."
        )
    }

    public nonisolated func invalidate() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)  // [validation-fix C6]
            runLoopSource = nil
        }
        if let existingPort = port {
            CFMessagePortInvalidate(existingPort)
            port = nil
        }
    }

    // MARK: - C callback (must be @convention(c))

    /// Called by CFRunLoop on the main thread when a CLI tool message arrives.
    ///
    /// Reconstructs `CLIPortServer` from `info` (the context pointer), decodes
    /// the JSON request, and dispatches accordingly.
    ///
    /// Return value: a `CFData` containing the JSON-encoded `CLIReply`. The reply
    /// must be non-nil for synchronous request/reply mode to work; on any error
    /// we return a failure reply rather than nil so the CLI tool always gets a
    /// response (prevents a 3-second timeout on the CLI side).
    private static let portCallback: CFMessagePortCallBack = { _, _, data, info -> Unmanaged<CFData>? in
        // Reconstruct self from the context info pointer.
        guard let info else {
            return CLIPortServer.encodeReply(.failure("internal: nil context"))
        }
        let requestData: Data? = data.map { ($0 as Data) }
        let server = Unmanaged<CLIPortServer>.fromOpaque(info).takeUnretainedValue()
        return MainActor.assumeIsolated {
            server.handle(data: requestData)
        }
    }

    // MARK: - Dispatch logic

    /// Decode the incoming request and build a reply.
    ///
    /// Called on the main thread. Reads `handler.icon` (we are already on main — see scheduling above).
    private func handle(data: Data?) -> Unmanaged<CFData>? {
        guard let data else {
            SpeakLog.cli.error("CLIPortServer: received nil data — returning failure reply.")
            return CLIPortServer.encodeReply(.failure("no request data"))
        }

        let request: CLIRequest
        do {
            request = try CLIRequest.decode(data)
        } catch {
            SpeakLog.cli.error(
                "CLIPortServer: failed to decode request — \(error.localizedDescription, privacy: .public)"
            )
            return CLIPortServer.encodeReply(.failure("bad request JSON: \(error.localizedDescription)"))
        }

        guard let cmdHandler = handler else {
            SpeakLog.cli.error("CLIPortServer: handler deallocated — returning failure reply.")
            return CLIPortServer.encodeReply(.failure("internal: handler unavailable"))
        }

        // ask/confirm need to pump a nested run loop while an async round-trip
        // completes — see `pumpUntilResult(timeoutSeconds:poll:)` below.
        if request.cmd == .ask || request.cmd == .confirm {
            return CLIPortServer.encodeReply(handleAskOrConfirm(request, handler: cmdHandler))
        }
        if request.cmd == .requestInput {
            return CLIPortServer.encodeReply(handleRequestInput(request, handler: cmdHandler))
        }
        if request.cmd == .registerSession {
            return CLIPortServer.encodeReply(handleRegisterSession(request, handler: cmdHandler))
        }
        if request.cmd == .submitCall {
            return CLIPortServer.encodeReply(handleSubmitCall(request, handler: cmdHandler))
        }
        if request.cmd == .getCall {
            return CLIPortServer.encodeReply(handleGetCall(request, handler: cmdHandler))
        }
        if request.cmd == .askUser {
            return CLIPortServer.encodeReply(handleAskUser(request, handler: cmdHandler))
        }
        if request.cmd == .streamSpeech {
            return CLIPortServer.encodeReply(handleStreamSpeech(request, handler: cmdHandler))
        }

        // AVB-6: resolve the optional sessionId note (if any) before the
        // synchronous dispatch below — `cliTouchSession` is an actor call and
        // cannot be awaited from inside a synchronous method.
        // `nil` when the request carries no sessionId, matching "absent →
        // exactly today's behavior." [decision: AVB-6]
        let sessionNote = CLIPortServer.pumpedSessionNote(sessionId: request.sessionId, handler: cmdHandler)

        // Read handler state synchronously for status; dispatch Tasks for start/stop/say.
        let reply: CLIReply
        switch request.cmd {

        case .status:
            // Synchronous: read live state and reply inline.
            let state = CLIState(from: cmdHandler.icon)
            let binding = cmdHandler.currentHotkeyDisplayString
            SpeakLog.cli.info("CLIPortServer: status — state=\(state.rawValue, privacy: .public)")
            SpeakLog.cli.info("CLIPortServer: status — binding=\(binding, privacy: .public)")
            reply = .status(state: state, binding: binding, sessionNote: sessionNote)

        case .start:
            // Idempotency gate: only dispatch if idle.
            // If already listening or processing, reply ok=true (the user's
            // desired state — recording — is already true or in flight).
            // [decision: W2.3 — accept-ack; transition is async]
            guard cmdHandler.icon == .idle else {
                let iconDescription = String(describing: cmdHandler.icon)
                SpeakLog.cli.info(
                    "CLIPortServer: --start ignored — not idle (icon=\(iconDescription, privacy: .public))"
                )
                return CLIPortServer.encodeReply(.accepted())  // already in desired or transitional state
            }
            cmdHandler.cliBeginDictation()
            SpeakLog.cli.info("CLIPortServer: --start dispatched.")
            reply = .accepted()

        case .stop:
            // Idempotency gate: only dispatch if listening.
            // If already idle/processing/done, reply ok=true — no work needed.
            // [decision: W2.3 — accept-ack; transition is async]
            guard cmdHandler.icon == .listening else {
                let iconDescription = String(describing: cmdHandler.icon)
                SpeakLog.cli.info(
                    "CLIPortServer: --stop ignored — not listening (icon=\(iconDescription, privacy: .public))"
                )
                return CLIPortServer.encodeReply(.accepted())  // already stopped or in transition
            }
            cmdHandler.cliEndDictation()
            SpeakLog.cli.info("CLIPortServer: --stop dispatched.")
            reply = .accepted()

        case .say:
            // Accept-ack, mirrors start/stop: the port replies immediately;
            // `cliSay` dispatches a Task internally and does not block this
            // callback on full speech playback. `interrupt` (handled inside
            // `cliSay`) is how the caller avoids overlap rather than the port
            // waiting for the previous utterance to finish. [decision: H-3]
            guard let text = request.text, !text.isEmpty else {
                SpeakLog.cli.error("CLIPortServer: say ignored — empty/missing text.")
                return CLIPortServer.encodeReply(.failure("say requires non-empty text"))
            }
            cmdHandler.cliSay(text: text, interrupt: request.interrupt ?? false)
            SpeakLog.cli.info("CLIPortServer: say dispatched.")
            reply = .accepted(sessionNote: sessionNote)

        case .ask, .confirm, .requestInput, .registerSession, .submitCall, .getCall, .askUser, .streamSpeech:
            // Handled above, before this switch — unreachable here.
            reply = .failure("internal: ask/confirm/requestInput/registerSession/submitCall/getCall/askUser/streamSpeech routed incorrectly")
        }

        return CLIPortServer.encodeReply(reply)
    }

    // MARK: - H-3 ask/confirm dispatch (blocking-avoidance pump)

    /// Handle `ask`/`confirm` on the main thread without literally blocking it.
    ///
    /// [decision: H-3] The CFMessagePort callback is synchronous — it must return a
    /// `CFData` reply before returning control to the run loop, but `ask`/`confirm`
    /// need to speak a question and then run a full mic+STT dictation round-trip,
    /// which can take tens of seconds and is inherently asynchronous (`beginDictation`/
    /// `endDictation` are `async` MainActor methods driven by the engine's own
    /// AsyncStream event loop). A literal `Thread.sleep`/semaphore-wait here would
    /// freeze the whole app — no HUD updates, no timers, no other run-loop sources —
    /// violating this project's "never block main thread" rule and defeating the
    /// entire point of showing the HUD during an agent-initiated mic open.
    ///
    /// Instead: kick off the async round-trip as a `Task { @MainActor in ... }` (it
    /// will actually run once we yield back to the run loop below), then repeatedly
    /// call `RunLoop.current.run(mode: .default, before:)` in short slices. Each
    /// slice pumps the main run loop — which also drains the GCD main queue that
    /// backs the `@MainActor` executor on Apple platforms — so the `Task` makes
    /// progress, timers fire, the HUD panel animates, and (critically) the engine's
    /// own event streams keep flowing, all while this call stack never returns to
    /// the CFMessagePort machinery until a result is ready. This is a *pump*, not a
    /// block: the thread is still doing real run-loop work between slices, just not
    /// returning to its caller. The tradeoff is a small poll granularity (20 ms) and
    /// a nested run-loop frame held open for the duration of the round-trip — an
    /// accepted cost for a same-user, low-frequency IPC path where a real callback-
    /// based CFMessagePort reply mechanism does not exist (only synchronous
    /// send/reply, per `CFMessagePortSendRequest`'s design).
    private func handleAskOrConfirm(_ request: CLIRequest, handler: any CLICommandHandler) -> CLIReply {
        guard let question = request.question, !question.isEmpty else {
            return .failure("\(request.cmd.rawValue) requires a non-empty question")
        }
        let timeout = request.timeout ?? CLIContract.askConfirmDefaultTimeoutSeconds
        // A small buffer beyond the caller's timeout so the handler's own internal
        // timeout (if any) has a chance to resolve and set the box before we give up.
        let pumpCeiling = timeout + 2.0
        // AVB-6: resolved up front so it's available regardless of which branch
        // below returns. [decision: AVB-6]
        let sessionNote = CLIPortServer.pumpedSessionNote(sessionId: request.sessionId, handler: handler)

        switch request.cmd {
        case .ask:
            let box = CLIPendingResultBox<CLIAskOutcome>()
            Task { @MainActor in
                let outcome = await handler.cliAsk(question: question, timeoutSeconds: timeout)
                box.set(outcome)
            }
            guard let outcome = CLIPortServer.pumpUntilResult(timeoutSeconds: pumpCeiling, poll: box.get) else {
                SpeakLog.cli.error("CLIPortServer: ask pump exhausted without a result.")
                return .failure("speak_ask timed out waiting for a spoken answer")
            }
            switch outcome {
            case .answered(let text): return .asked(text, sessionNote: sessionNote)
            case .timedOut: return .failure("speak_ask timed out waiting for a spoken answer")
            }

        case .confirm:
            let box = CLIPendingResultBox<CLIConfirmOutcome>()
            Task { @MainActor in
                let outcome = await handler.cliConfirm(question: question, timeoutSeconds: timeout)
                box.set(outcome)
            }
            guard let outcome = CLIPortServer.pumpUntilResult(timeoutSeconds: pumpCeiling, poll: box.get) else {
                SpeakLog.cli.error("CLIPortServer: confirm pump exhausted without a result.")
                return .failure("speak_confirm timed out waiting for a spoken answer")
            }
            switch outcome {
            case .yes: return .confirmed(true, sessionNote: sessionNote)
            case .no: return .confirmed(false, sessionNote: sessionNote)
            case .unclear, .cancelled: return .confirmed(nil, sessionNote: sessionNote)
            case .timedOut: return .failure("speak_confirm timed out waiting for a spoken answer")
            }

        default:
            return .failure("internal: handleAskOrConfirm called with \(request.cmd.rawValue)")
        }
    }

    // MARK: - AVB-5 requestInput dispatch

    /// Validate and dispatch a `requestInput` request, mirroring
    /// `handleAskOrConfirm`'s Task-plus-pump shape. Validation failures (missing
    /// prompt/mode, `.choice` mode with no `choices`) reply with `.failure(_:)` — a
    /// malformed-request transport error, never one of the five canonical
    /// outcomes. [decision: AVB-5]
    private func handleRequestInput(_ request: CLIRequest, handler: any CLICommandHandler) -> CLIReply {
        guard let requestId = request.requestId, !requestId.isEmpty else {
            return .failure("requestInput requires a non-empty requestId")
        }
        guard let prompt = request.prompt, !prompt.isEmpty else {
            return .failure("requestInput requires a non-empty prompt")
        }
        guard let mode = request.mode else {
            return .failure("requestInput requires a mode (freeform, choice, or approval)")
        }
        let choices = request.choices ?? []
        if mode == .choice, choices.isEmpty {
            return .failure("requestInput mode 'choice' requires a non-empty 'choices' array")
        }

        let timeout = request.timeout ?? CLIContract.askConfirmDefaultTimeoutSeconds
        let pumpCeiling = timeout + 2.0
        let sessionNote = CLIPortServer.pumpedSessionNote(sessionId: request.sessionId, handler: handler)

        let box = CLIPendingResultBox<HumanResponseOutcome>()
        Task { @MainActor in
            let outcome = await handler.cliRequestInput(
                requestId: requestId,
                idempotencyKey: request.idempotencyKey,
                prompt: prompt,
                mode: mode,
                choices: choices,
                timeoutSeconds: timeout,
                consequence: request.consequence,
                spokenSummary: request.spokenSummary
            )
            box.set(outcome)
        }
        guard let outcome = CLIPortServer.pumpUntilResult(timeoutSeconds: pumpCeiling, poll: box.get) else {
            SpeakLog.cli.error("CLIPortServer: requestInput pump exhausted without a result.")
            return .requestInputResult(.timedOut, sessionNote: sessionNote)
        }
        return .requestInputResult(outcome, sessionNote: sessionNote)
    }

    // MARK: - AVB-6 registerSession dispatch

    /// Validate and dispatch a `registerSession` request. Bridges the actor-
    /// isolated `AgentSessionRegistry` via the same Task-plus-pump mechanism
    /// `handleAskOrConfirm`/`handleRequestInput` already use — registration
    /// itself is fast/in-memory (no mic, no human round-trip, no realistic
    /// timeout risk), but the actor hop still requires an `await`, which
    /// cannot happen inside `MainActor.assumeIsolated`'s synchronous closure.
    /// Reusing the existing, already-reviewed pump primitive here is
    /// deliberate: a second bridging mechanism just for this one case would
    /// add risk without adding safety. The main thread is never blocked
    /// either way — this call simply resolves within the pump's first poll
    /// slice in practice. [decision: AVB-6]
    private func handleRegisterSession(_ request: CLIRequest, handler: any CLICommandHandler) -> CLIReply {
        guard let provider = request.provider, !provider.isEmpty else {
            return .failure("registerSession requires a non-empty provider")
        }
        guard let label = request.label, !label.isEmpty else {
            return .failure("registerSession requires a non-empty label")
        }

        let box = CLIPendingResultBox<(sessionId: String, capabilities: [String])>()
        Task { @MainActor in
            let result = await handler.cliRegisterSession(
                sessionId: request.sessionId,
                provider: provider,
                label: label,
                workingDirectory: request.workingDirectory,
                requestedCapabilities: request.requestedCapabilities ?? []
            )
            box.set(result)
        }
        guard let result = CLIPortServer.pumpUntilResult(timeoutSeconds: 5.0, poll: box.get) else {
            SpeakLog.cli.error("CLIPortServer: registerSession pump exhausted without a result.")
            return .failure("speak_register_session did not complete")
        }
        return .registered(sessionId: result.sessionId, capabilities: result.capabilities)
    }

    // MARK: - AVB-7 submitCall / getCall dispatch

    /// Validate and dispatch a `submitCall` request. Reuses the exact
    /// Task-plus-pump primitive `handleRegisterSession` already uses (5 s hard
    /// deadline) — neither this nor `handleGetCall` waits on speech, so both
    /// resolve within the pump's first poll slice in practice.
    /// [decision: AVB-7 orchestrator amendment 2]
    private func handleSubmitCall(_ request: CLIRequest, handler: any CLICommandHandler) -> CLIReply {
        guard let requestId = request.requestId, !requestId.isEmpty else {
            return .failure("submitCall requires a non-empty requestId")
        }
        guard let prompt = request.prompt, !prompt.isEmpty else {
            return .failure("submitCall requires a non-empty prompt")
        }
        guard let mode = request.mode else {
            return .failure("submitCall requires a mode (freeform, choice, or approval)")
        }
        let choices = request.choices ?? []
        if mode == .choice, choices.isEmpty {
            return .failure("submitCall mode 'choice' requires a non-empty 'choices' array")
        }
        let urgency = request.urgency ?? .normal
        // Defense in depth: never nil past this point, even if a non-standard
        // caller reaches this wire path without going through AgentBridgeServer's
        // own default-applying parse. [decision: AVB-7]
        let expiresInSeconds = request.expiresInSeconds ?? AgentCallDefaults.defaultExpirySeconds

        let args = SubmitCallArguments(
            requestId: requestId,
            idempotencyKey: request.idempotencyKey,
            prompt: prompt,
            mode: mode,
            choices: choices,
            consequence: request.consequence,
            spokenSummary: request.spokenSummary,
            urgency: urgency,
            expiresInSeconds: expiresInSeconds,
            sessionId: request.sessionId
        )
        let box = CLIPendingResultBox<CLISubmitCallOutcome>()
        Task { @MainActor in
            let outcome = await handler.cliSubmitCall(args)
            box.set(outcome)
        }
        guard let outcome = CLIPortServer.pumpUntilResult(timeoutSeconds: 5.0, poll: box.get) else {
            SpeakLog.cli.error("CLIPortServer: submitCall pump exhausted without a result.")
            return .failure("speak_submit_call did not complete")
        }
        switch outcome {
        case .unregistered:
            return .failure(
                "register a session first (speak_register_session) before using speak_submit_call.")
        case .created(let call):
            return .callSubmitted(call, duplicate: false)
        case .duplicate(let call):
            return .callSubmitted(call, duplicate: true)
        case .internalError(let message):
            return .failure("speak_submit_call failed: \(message)")
        }
    }

    /// Validate and dispatch a `getCall` request. Same pump shape as `handleSubmitCall`.
    /// [decision: AVB-7]
    private func handleGetCall(_ request: CLIRequest, handler: any CLICommandHandler) -> CLIReply {
        guard let callIdString = request.callId, let callId = UUID(uuidString: callIdString) else {
            return .failure("getCall requires a valid 'callId'")
        }

        let box = CLIPendingResultBox<CLIGetCallOutcome>()
        Task { @MainActor in
            let outcome = await handler.cliGetCall(sessionId: request.sessionId, callId: callId)
            box.set(outcome)
        }
        guard let outcome = CLIPortServer.pumpUntilResult(timeoutSeconds: 5.0, poll: box.get) else {
            SpeakLog.cli.error("CLIPortServer: getCall pump exhausted without a result.")
            return .failure("speak_get_call did not complete")
        }
        switch outcome {
        case .unregistered:
            return .failure(
                "register a session first (speak_register_session) before using speak_get_call.")
        case .call(let call):
            return .callStatus(call)
        }
    }



    /// Pump the current (main) run loop in short slices until `poll()` returns a
    /// non-nil result or `timeoutSeconds` elapses. See `handleAskOrConfirm` for the
    /// full rationale. [decision: H-3]
    static func pumpUntilResult<T>(timeoutSeconds: TimeInterval, poll: () -> T?) -> T? {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        let pollSlice: TimeInterval = 0.02  // 20 ms — short enough to stay responsive
        while Date() < deadline {
            if let result = poll() { return result }
            RunLoop.current.run(mode: RunLoop.Mode.common, before: Date().addingTimeInterval(pollSlice))
        }
        return poll()
    }

    // MARK: - Encode reply to CFData

    /// Encode a `CLIReply` to a retained `CFData` for the port callback return.
    ///
    /// On encoding failure (should never happen with a well-formed Codable type)
    /// we return a minimal ASCII fallback so the CLI still gets a response.
    static func encodeReply(_ reply: CLIReply) -> Unmanaged<CFData>? {
        let data: Data
        do {
            data = try reply.encode()
        } catch {
            SpeakLog.cli.error(
                "CLIPortServer: failed to encode reply — \(error.localizedDescription, privacy: .public)"
            )
            // Fallback: a minimal ASCII error payload so the client doesn't hang.
            let fallback = #"{"ok":false,"error":"encoding error"}"#
            data = Data(fallback.utf8)
        }
        return Unmanaged.passRetained(data as CFData)
    }
}

// MARK: - CLIPendingResultBox

/// A tiny lock-protected box used to hand a result from a `@MainActor` `Task` back
/// to the synchronous run-loop pump in `CLIPortServer.pumpUntilResult`. Both sides
/// run on the main thread (the `Task` is `@MainActor`; the pump runs inline in the
/// port callback), but the pump reads `value` from *inside* `RunLoop.current.run`
/// re-entrancy, so a lock is cheap insurance against any future caller that isn't
/// strictly main-thread-only. `@unchecked Sendable` matches this file's existing
/// pattern (`CLIPortServer` itself) for a type whose thread-safety is manually
/// reasoned about rather than compiler-enforced. [decision: H-3]
final class CLIPendingResultBox<T>: @unchecked Sendable {
    private var value: T?
    private let lock = NSLock()

    func set(_ newValue: T) {
        lock.lock()
        value = newValue
        lock.unlock()
    }

    func get() -> T? {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}
