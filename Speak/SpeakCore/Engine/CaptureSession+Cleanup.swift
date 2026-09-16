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

    /// Result of `runCleanup` — a named struct rather than a 4-member tuple
    /// (SwiftLint `large_tuple` is an error in this project).
    /// See `runCleanup`'s doc comment for the `cleanupSeconds` sentinel and
    /// `status` contract.
    struct CleanupPassResult: Sendable {
        let cleanedText: String?
        let engineId: String
        let cleanupSeconds: Double
        let status: CleanupStatus
    }

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
    /// Returns `(cleanedText, engineId, cleanupSeconds, status)` where:
    /// - `cleanupSeconds == 0.0` (exact) when cleanup did NOT run (cleaner nil or
    ///   forced-Raw override). This is a **sentinel** — not a clock measurement —
    ///   so `LatencyStats` can test `cleanupSeconds == 0` for "cleanup skipped".
    /// - `cleanupSeconds > 0` when a cleanup pass was attempted — success, error,
    ///   empty output, unavailable, or timeout. The value is the wall-clock time
    ///   spent inside the availability check + timeout race, converted to seconds.
    ///   [decision P13: timed-out/failed runs keep their real elapsed time — it is
    ///   the user-experienced latency; the `status` field, not `cleanupSeconds`,
    ///   now discriminates success from fallback.]
    /// - `status` is the honest outcome: `.skipped` (never ran — cleanupSeconds==0),
    ///   `.cleaned`, or `.fallbackRaw(reason)` for every raw-fallback path.
    ///   `LatencyStats` partitions on `status` (falling back to `cleanupSeconds`
    ///   for legacy rows) so failed/timed-out passes no longer pollute the
    ///   "cleanup succeeded" median. [fix: audit — cleanup latency honesty]
    ///
    /// [decision P13: timing goes inside runCleanup so the sentinel `0.0` can never be produced
    ///  by a live clock read between two DispatchTime.now() calls on the no-cleanup paths.
    ///  This is the discriminator for LatencyStats population partitioning.]
    func runCleanup(rawText: String) async -> CleanupPassResult {
        if forcedRaw {
            // PE-3: the user picked Raw in the live panel for THIS dictation — skip cleanup
            // and paste the raw transcript (the base-core bypass), exactly like cleaner-nil.
            // cleanupSeconds = 0.0 (sentinel: cleanup did not run).
            SpeakLog.engine.info("CaptureSession: live-panel Raw override — skipping cleanup for this dictation.")
            return CleanupPassResult(cleanedText: nil, engineId: transcriber.id, cleanupSeconds: 0.0, status: .skipped)
        }
        guard let cleaner = cleaner else {
            // Cleanup off — raw transcript, STT engine id only.
            // cleanupSeconds = 0.0 (sentinel: cleanup did not run).
            return CleanupPassResult(cleanedText: nil, engineId: transcriber.id, cleanupSeconds: 0.0, status: .skipped)
        }

        // t_cleanupStart: monotonic instant before the availability check. Any path
        // that reaches here *intended* to run cleanup — including the
        // unavailable-fallback — so all of them report cleanupSeconds > 0 and a
        // non-.skipped status. (Unavailable was previously a 0.0 sentinel; it is
        // now an explicit `.fallbackRaw(.cleanerUnavailable)` so LatencyStats no
        // longer folds "the engine was off" into the raw population.)
        let tCleanupStart = DispatchTime.now().uptimeNanoseconds

        let available = await cleaner.isAvailable
        if !available {
            // Engine unavailable — graceful fallback, NOT an error.
            let elapsedNs = max(DispatchTime.now().uptimeNanoseconds - tCleanupStart, 1)
            SpeakLog.engine.info(
                "CaptureSession: cleaner '\(cleaner.id, privacy: .public)' unavailable; falling back to raw transcript."
            )
            return CleanupPassResult(cleanedText: nil, engineId: transcriber.id, cleanupSeconds: Double(elapsedNs) / 1_000_000_000, status: .fallbackRaw(.cleanerUnavailable))
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
        // PE-3: read the effective mode (live-panel override if set, else the latched
        // mode) so a chip tap during listening reshapes THIS dictation's output.
        let mode = effectiveCleanupMode
        let sttId = transcriber.id

        enum CleanupOutcome {
            case success(String)
            case failure(String)   // logged reason; caller falls back to raw
            case timedOut
        }

        let coordinator = self.streamingCoordinator
        let expandedFinalized = expander?.expand(self.finalizedText) ?? self.finalizedText
        let matchesFinalized = (rawText == self.finalizedText || rawText == expandedFinalized)

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

            // Unstructured task: runs the actual clean() call. Priority .userInitiated
            // schedules on high-performance P-cores and prioritizes Neural Engine (ANE) queues.
            let cleanTask = Task(priority: .userInitiated) {
                do {
                    let cleaned: String
                    if let coordinator, matchesFinalized, await coordinator.chunkCount > 0 {
                        let count = await coordinator.chunkCount
                        SpeakLog.cleanup.info(
                            "CaptureSession: using progressive streaming coordinator with \(count, privacy: .public) chunks."
                        )
                        cleaned = try await coordinator.finalizeAndStitch(trailingRawText: nil)
                    } else {
                        cleaned = try await cleaner.clean(rawText, mode: mode)
                    }
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

        self.streamingCoordinator = nil

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
            // [SM-3] Guard against empty output: if the cleaner returns "" the paste
            // path would deliver an empty string (cleanedText ?? rawText picks "").
            // Treat empty output the same as a failure — fall back to raw transcript.
            guard !cleaned.isEmpty else {
                SpeakLog.engine.warning(
                    "CaptureSession: cleaner returned empty string — falling back to raw transcript."
                )
                return CleanupPassResult(cleanedText: nil, engineId: sttId, cleanupSeconds: cleanupSeconds, status: .fallbackRaw(.emptyOutput))
            }
            SpeakLog.engine.info("""
                CaptureSession: cleanup produced \(cleaned.count, privacy: .public) chars \
                from \(rawText.count, privacy: .public) raw chars
                """)
            return CleanupPassResult(cleanedText: cleaned, engineId: "\(sttId)+\(cleanerId)", cleanupSeconds: cleanupSeconds, status: .cleaned)

        case .failure(let detail):
            // [decision: cleanup error → graceful fallback to raw transcript, NOT .error.
            //  See runCleanup() doc comment above for the full rationale.]
            SpeakLog.engine.error(
                "CaptureSession: cleanup failed — falling back to raw transcript. Detail: \(detail, privacy: .public)"
            )
            return CleanupPassResult(cleanedText: nil, engineId: sttId, cleanupSeconds: cleanupSeconds, status: .fallbackRaw(.cleanerError))

        case .timedOut:
            // [decision: cleanup timeout → graceful fallback to raw transcript.
            //  The cleanup task was cancelled (best-effort). The overlay must hide.]
            SpeakLog.engine.error(
                "CaptureSession: cleanup timed out after T_cleanup — falling back to raw transcript."
            )
            return CleanupPassResult(cleanedText: nil, engineId: sttId, cleanupSeconds: cleanupSeconds, status: .fallbackRaw(.timedOut))
        }
    }
}
