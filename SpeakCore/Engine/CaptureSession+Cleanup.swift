// SpeakCore/Engine/CaptureSession+Cleanup.swift
//
// LLM cleanup pass for CaptureSession. Extracted from CaptureSession.swift
// (pure reorganization — zero logic changes).
//
// runCleanup() is `internal` (not `private`) so stop() in CaptureSession.swift
// can call it across files within the same module.

import Foundation
import os

extension CaptureSession {

    /// Run the cleanup pass per the architecture's P3.5 contract.
    ///
    /// - `cleaner == nil` (cleanup off): `cleanedText = nil`, `engineId = STT id`.
    /// - `cleaner.isAvailable == false` (engine unavailable):
    ///   `cleanedText = nil`, **no error** — graceful fallback. The session
    ///   reaches `.done` and the caller pastes the raw transcript.
    /// - `cleaner.clean()` times out or throws:
    ///   `cleanedText = nil`, **no error** — graceful fallback with logged reason.
    ///   [decision: cleanup failure ≡ cleanup unavailability — both fall back to raw
    ///    transcript and reach `.done`. This honors the hard rule "cleanup unavailability
    ///    ≠ error" and ensures the overlay ALWAYS reaches a terminal hidden state after
    ///    stop, even when Foundation Models hangs or returns a GenerationError.
    ///    Previously, a thrown SpeakError.llmCleanupFailed was rethrown and surfaced as
    ///    an un-dismissable HUD error — that was a UX fault. Raw transcript is always
    ///    available and is the correct degradation target.]
    ///
    /// **Timeout (T_cleanup — benchmark.md §7):** `clean()` is wrapped in an
    /// unstructured `Task` raced against a deadline via a `CheckedContinuation`
    /// that resumes exactly once (double-resume guard via `didResume` flag).
    /// On timeout the cleanup task is cancelled (best-effort — if the on-device
    /// model does not honor cooperative cancellation, the task finishes in the
    /// background; the continuation has already resumed and the session proceeds
    /// without awaiting it). This guarantees the overlay always hides within
    /// `T_cleanup` of stop, regardless of the cleaner's implementation.
    ///
    /// Does NOT throw. All outcomes — off, unavailable, timeout, error — produce
    /// `(nil, transcriber.id)`. Only a successful clean produces `(cleaned, combinedId)`.
    /// Run the optional cleanup pass and measure how long it took.
    ///
    /// Returns a triple `(cleanedText, engineId, cleanupSeconds)` where:
    /// - `cleanupSeconds == 0.0` (exact) when cleanup did NOT run (cleaner nil or unavailable).
    ///   This is a **sentinel** — not a clock measurement — so `LatencyStats` can partition
    ///   entries as "raw" vs "cleanup" by testing `cleanupSeconds == 0`.
    /// - `cleanupSeconds > 0` when the cleaner's `clean()` was actually called, whether it
    ///   succeeded, failed, or timed out. The value is the wall-clock time spent inside the
    ///   timeout race, converted to seconds. [decision P13: timed-out runs fall into the
    ///   cleanup population — their longer elapsed time is the real user-experienced latency.]
    ///
    /// [decision P13: timing goes inside runCleanup so the sentinel `0.0` can never be produced
    ///  by a live clock read between two DispatchTime.now() calls on the no-cleanup paths.
    ///  This is the discriminator for LatencyStats population partitioning.]
    func runCleanup(rawText: String) async -> (cleanedText: String?, engineId: String, cleanupSeconds: Double) {
        guard let cleaner = cleaner else {
            // Cleanup off — raw transcript, STT engine id only.
            // cleanupSeconds = 0.0 (sentinel: cleanup did not run).
            return (nil, transcriber.id, 0.0)
        }
        let available = await cleaner.isAvailable
        if !available {
            // Engine unavailable — graceful fallback, NOT an error.
            // cleanupSeconds = 0.0 (sentinel: cleanup did not run).
            SpeakLog.engine.info(
                "CaptureSession: cleaner '\(cleaner.id, privacy: .public)' unavailable; falling back to raw transcript."
            )
            return (nil, transcriber.id, 0.0)
        }

        // Bounded timeout: race the cleanup call against T_cleanup.
        // We cannot guarantee Foundation Models' respond() honors cooperative
        // cancellation, so we use an unstructured Task + CheckedContinuation
        // pattern that resumes the parent without awaiting the child.
        // [decision: T_cleanup = 10 s — see benchmark.md §7. Architecture §12
        //  budgets cleanup at < 1.5 s happy-path and < 2.5 s p95; 10 s sits
        //  4× above p95 so it only fires on genuine hangs, not slow-but-valid runs.]
        let cleanupTimeoutNanoseconds: UInt64 = 10_000_000_000  // 10 s [decision T_cleanup benchmark.md §7]
        let cleanerId = cleaner.id
        let mode = cleanupMode
        let sttId = transcriber.id

        // t_cleanupStart: monotonic instant just before entering the continuation.
        // Placed AFTER the early-return guards above so it is only set when cleanup
        // actually runs; cleanupSeconds > 0 is guaranteed for this path.
        let tCleanupStart = DispatchTime.now().uptimeNanoseconds

        enum CleanupOutcome {
            case success(String)
            case failure(String)   // logged reason; caller falls back to raw
            case timedOut
        }

        let outcome: CleanupOutcome = await withCheckedContinuation { continuation in
            // `resumeOnce` guards the continuation against double-resume: both the
            // cleanup task and the timeout task race to resume it; only the first
            // wins. `OSAllocatedUnfairLock<Bool>` gives a data-race-free
            // test-and-set across the two unstructured Tasks running off-actor.
            // [verified: OSAllocatedUnfairLock is available from macOS 13+;
            //  this project targets macOS 26. `withLockIfAvailable` is the
            //  recommended tryLock alternative; `withLock` is the blocking form
            //  used here — the critical section is a single Bool flip, so
            //  contention is essentially zero.]
            let resumeOnce = OSAllocatedUnfairLock<Bool>(initialState: false)

            // Unstructured task: runs the actual clean() call. Not awaited —
            // if it times out, the continuation is already resumed and this task
            // finishes (or hangs) in the background without blocking the session.
            let cleanTask = Task {
                do {
                    let cleaned = try await cleaner.clean(rawText, mode: mode)
                    resumeOnce.withLock { alreadyResumed in
                        guard !alreadyResumed else { return }
                        alreadyResumed = true
                        continuation.resume(returning: .success(cleaned))
                    }
                } catch {
                    let detail = error.localizedDescription
                    resumeOnce.withLock { alreadyResumed in
                        guard !alreadyResumed else { return }
                        alreadyResumed = true
                        continuation.resume(returning: .failure(detail))
                    }
                }
            }

            // Timeout task: resumes the continuation with .timedOut after T_cleanup.
            Task {
                try? await Task.sleep(nanoseconds: cleanupTimeoutNanoseconds)
                resumeOnce.withLock { alreadyResumed in
                    guard !alreadyResumed else { return }
                    alreadyResumed = true
                    cleanTask.cancel()   // best-effort — non-cooperative cleaners ignore this
                    continuation.resume(returning: .timedOut)
                }
            }
        }

        // t_cleanupEnd: captured immediately after the continuation resumes (whether by
        // success, failure, or timeout). The delta is the real user-experienced latency
        // for this cleanup pass, including model cold-start and timeout wait if triggered.
        let tCleanupEnd = DispatchTime.now().uptimeNanoseconds
        // [A4] Floor: when tCleanupEnd == tCleanupStart (fast machine or mocked cleaner,
        // both reads return the same nanosecond), the computed delta would be exactly 0.0
        // — colliding with the "cleanup did not run" sentinel used by LatencyStats to
        // partition raw vs cleanup entries. Apply a 1 ns floor so any path that actually
        // called clean() produces cleanupSeconds > 0, preserving the partition invariant.
        // 1 ns is chosen because it is the smallest representable DispatchTime unit and
        // is far below any real measurement (≥ 1 µs in practice). [decision A4]
        let rawDeltaNs: UInt64 = tCleanupEnd > tCleanupStart ? tCleanupEnd - tCleanupStart : 1
        let cleanupSeconds: Double = Double(rawDeltaNs) / 1_000_000_000

        switch outcome {
        case .success(let cleaned):
            SpeakLog.engine.info("""
                CaptureSession: cleanup produced \(cleaned.count, privacy: .public) chars \
                from \(rawText.count, privacy: .public) raw chars
                """)
            return (cleaned, "\(sttId)+\(cleanerId)", cleanupSeconds)

        case .failure(let detail):
            // [decision: cleanup error → graceful fallback to raw transcript, NOT .error.
            //  See runCleanup() doc comment above for the full rationale.]
            SpeakLog.engine.error(
                "CaptureSession: cleanup failed — falling back to raw transcript. Detail: \(detail, privacy: .public)"
            )
            return (nil, sttId, cleanupSeconds)

        case .timedOut:
            // [decision: cleanup timeout → graceful fallback to raw transcript.
            //  The cleanup task was cancelled (best-effort). The overlay must hide.]
            SpeakLog.engine.error(
                "CaptureSession: cleanup timed out after T_cleanup — falling back to raw transcript."
            )
            return (nil, sttId, cleanupSeconds)
        }
    }
}
