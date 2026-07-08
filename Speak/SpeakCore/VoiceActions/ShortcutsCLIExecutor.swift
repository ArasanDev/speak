// SpeakCore/VoiceActions/ShortcutsCLIExecutor.swift
//
// H-1 (specs/horizon-voice-os.md, Pillar 1): the live `ActionExecuting` conformer.
// Wraps `/usr/bin/shortcuts` (`list` / `run`) via `Process`. No third-party deps,
// no network — a local subprocess of an Apple-provided CLI, consistent with the
// 100%-local constraint (this is not egress; nothing leaves the machine).
//
// `[unverified — dogfood H-4]` (spec line 32-33): headless `shortcuts run`
// behavior for input-requesting shortcuts is not verified in this slice — such
// a shortcut may block waiting for input that will never arrive over a
// non-interactive subprocess. The `timeout` watchdog below exists specifically
// for that risk: a hang degrades (via termination) rather than blocking the
// caller — never silently — forever.
//
// WATCHDOG ESCALATION `[hardened H-4]`: a single SIGTERM (`Process.terminate()`)
// is not guaranteed to end the child — a process showing a modal dialog can be
// in a state that ignores or defers SIGTERM. If the child doesn't actually
// exit, its stdout/stderr pipes never reach EOF and `drainGroup.wait()` /
// `waitUntilExit()` below hang forever, defeating the whole point of the
// watchdog. So the watchdog is two-stage: SIGTERM at `timeout`, then SIGKILL
// (which cannot be caught or ignored) at `timeout + killGrace` if the process
// is still alive. `[deferred — human verification]`: whether a real
// input-requesting Shortcut's dialog-holding process actually resists SIGTERM
// this way is still unverified — this hardens the code path against that
// possibility rather than confirming it occurs.
//
// CONCURRENCY: `Process.run()`/`waitUntilExit()` are synchronous/blocking APIs.
// Per AGENTS.md (never block the main thread), all Process interaction happens
// on a background dispatch queue; the `async` functions here bridge it back to
// the caller via `withCheckedContinuation`.
//
// PIPE-READ SAFETY: stdout and stderr are drained CONCURRENTLY, before
// `waitUntilExit()`. Reading one pipe to EOF while the other's kernel buffer
// fills (and the child blocks trying to write to it) is a classic `Process`
// deadlock; draining both at once avoids it regardless of output size.

import Foundation

// MARK: - ShortcutsCLIExecutor

/// `ActionExecuting` conformer backed by the system `shortcuts` CLI.
public struct ShortcutsCLIExecutor: ActionExecuting, Sendable {

    /// Path to the `shortcuts` binary. Overridable for tests (point at a fixture
    /// script instead of the real CLI).
    private let executablePath: String

    /// How long to wait for a `shortcuts` invocation before terminating it.
    /// [decision H-1] 10s: generous for a local Shortcuts run (no network round
    /// trip expected), but short enough that a hang — e.g. an input-requesting
    /// shortcut per the H-4 unverified item above — resolves to "the action
    /// didn't work" (degrade to dictation) rather than blocking indefinitely.
    private let timeout: TimeInterval

    /// Grace period after the SIGTERM watchdog before escalating to SIGKILL.
    /// [decision H-4] short: SIGKILL only fires if the process ignored/ate the
    /// SIGTERM entirely, so there's nothing worth waiting for.
    private let killGrace: TimeInterval

    public init(executablePath: String = "/usr/bin/shortcuts", timeout: TimeInterval = 10.0, killGrace: TimeInterval = 1.0) {
        self.executablePath = executablePath
        self.timeout = timeout
        self.killGrace = killGrace
    }

    public func listActionNames() async -> [String] {
        switch await runProcess(arguments: ["list"]) {
        case .success(let output):
            guard let output else { return [] }
            return output
                .split(separator: "\n", omittingEmptySubsequences: true)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }

        case .notFound, .failed:
            return []
        }
    }

    public func run(named name: String) async -> ActionExecutionResult {
        await runProcess(arguments: ["run", name])
    }

    // MARK: - Process plumbing

    private func runProcess(arguments: [String]) async -> ActionExecutionResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executablePath)
                process.arguments = arguments
                let outPipe = Pipe()
                let errPipe = Pipe()
                process.standardOutput = outPipe
                process.standardError = errPipe

                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: .failed(error.localizedDescription))
                    return
                }

                // Drain both pipes concurrently BEFORE waiting for exit — see the
                // PIPE-READ SAFETY note above. See `drainPipesConcurrently` for
                // why `resultQueue` (not the raw vars) is the sync point.
                let (drainGroup, resultQueue, pipeResults) = Self.drainPipesConcurrently(outPipe: outPipe, errPipe: errPipe)

                // Watchdog: only ever terminates the process, never resumes the
                // continuation itself — the single `resume` below always fires
                // after `waitUntilExit()` returns, on every path (success, exit
                // failure, or a termination caused by this watchdog).
                let watchdog = DispatchWorkItem {
                    if process.isRunning { process.terminate() }
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)

                // Escalation: if SIGTERM didn't end the process (e.g. it's
                // caught/ignoring the signal — see WATCHDOG ESCALATION note
                // above), SIGKILL cannot be caught and guarantees OUR direct
                // child exits. It does NOT guarantee the pipes reach EOF — a
                // grandchild the child spawned (e.g. a shell script's `sleep`)
                // can inherit the pipe's write end and keep it open after the
                // shell itself is gone. That's why `drainGroup.wait()` below is
                // bounded rather than unconditional: past that bound we give up
                // on the read and resume with whatever was captured so far.
                let killWatchdog = DispatchWorkItem {
                    if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout + killGrace, execute: killWatchdog)

                // Bounded past `timeout + killGrace`: a straggling grandchild
                // holding the pipe open must not make this call hang forever.
                _ = drainGroup.wait(timeout: .now() + timeout + killGrace + 2.0)
                process.waitUntilExit()
                watchdog.cancel()
                killWatchdog.cancel()
                let (outData, errData) = resultQueue.sync { (pipeResults.out, pipeResults.err) }

                if process.terminationStatus == 0 {
                    let output = String(data: outData, encoding: .utf8)
                    continuation.resume(returning: .success(output: output))
                } else {
                    let errText = String(data: errData, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    let detail = errText.flatMap { $0.isEmpty ? nil : $0 }
                        ?? "exit code \(process.terminationStatus)"
                    continuation.resume(returning: .failed(detail))
                }
            }
        }
    }

    /// Reads `outPipe`/`errPipe` to EOF concurrently on background queues, so
    /// one pipe's kernel buffer filling while the other blocks on write can't
    /// deadlock `Process` (see PIPE-READ SAFETY above).
    ///
    /// Returns the `DispatchGroup` to wait on, the `DispatchQueue` that
    /// synchronizes writes to the returned result box, and the box itself.
    /// The queue matters because SIGKILL only guarantees OUR direct child
    /// exits — a grandchild it spawned (e.g. a shell script's `sleep`) can
    /// inherit a pipe's write end and keep it open past the kill, so the
    /// caller's `drainGroup.wait()` is bounded rather than unconditional; the
    /// sync queue is what makes reading the box after giving up race-free.
    private final class PipeReadResults: @unchecked Sendable {
        var out = Data()
        var err = Data()
    }

    private static func drainPipesConcurrently(
        outPipe: Pipe,
        errPipe: Pipe
    ) -> (DispatchGroup, DispatchQueue, PipeReadResults) {
        let drainGroup = DispatchGroup()
        let resultQueue = DispatchQueue(label: "ShortcutsCLIExecutor.pipeResult")
        let results = PipeReadResults()

        drainGroup.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            let data = outPipe.fileHandleForReading.readDataToEndOfFile()
            resultQueue.sync { results.out = data }
            drainGroup.leave()
        }
        drainGroup.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            let data = errPipe.fileHandleForReading.readDataToEndOfFile()
            resultQueue.sync { results.err = data }
            drainGroup.leave()
        }

        return (drainGroup, resultQueue, results)
    }
}
