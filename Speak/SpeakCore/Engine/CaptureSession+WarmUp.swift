// Speak/SpeakCore/Engine/CaptureSession+WarmUp.swift
//
// [V01-W] Warm-cleanup machinery (specs/voicestudio-inspiration-plan.md W01).
// Lives in an extension so the actor's own body stays under the type-body lint
// cap; only the optional stored state (`warmUp`) lives in CaptureSession.swift.

extension CaptureSession {

    /// Optional cleanup-engine warm-up trigger, fired once at `start()`
    /// concurrently with listening so the first `clean()` after stop skips
    /// model cold-start. Assembled in `SpeakEngine.newSession()` (it captures
    /// the active cleaner) following the same inject-a-closure pattern as
    /// `voiceCommandPreprocessor` / `voiceActionsHandler`.
    ///
    /// `nil` (default, and whenever cleanup will not run) means no warm-up task
    /// is ever created and the session path is byte-identical to pre-V01-W.
    public typealias WarmUpHandler = @Sendable () async -> Void

    /// [V01-W] Warm-up state: the handler plus the in-flight task. Both live
    /// here so the actor body stays lean — only the optional itself is stored.
    struct WarmUpState {
        let handler: WarmUpHandler
        var task: Task<Void, Never>?
    }

    /// `true` when a warm-up handler was injected (cleanup will run), `false`
    /// when warm-up is disabled. Internal so unit tests can assert the wiring
    /// without comparing closures. A `false` session provably spawns no warm-up
    /// task — the delivery path is byte-identical to pre-V01-W.
    var isWarmUpArmed: Bool { warmUp != nil }

    /// Fire the cleanup warm-up concurrently with listening. Returns immediately
    /// — never blocks `start()`. At most one is ever in flight (`start()` runs
    /// once from `.idle`; a stale handle is defensively cancelled first). The
    /// handler is non-throwing by type, so a failed warm-up is a logged no-op
    /// inside the handler, never an error here.
    func fireWarmUp() {
        guard var warmUp = warmUp else { return }
        warmUp.task?.cancel()
        warmUp.task = Task { await warmUp.handler() }
        self.warmUp = warmUp
    }

    /// Cancel the in-flight warm-up task without awaiting it. Safe to call when
    /// no warm-up is armed or already finished (nil / completed handles are
    /// no-ops under `Task.cancel()`).
    func cancelWarmUp() {
        warmUp?.task?.cancel()
        warmUp = nil
    }
}