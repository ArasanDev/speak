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

    public init(executablePath: String = "/usr/bin/shortcuts", timeout: TimeInterval = 10.0) {
        self.executablePath = executablePath
        self.timeout = timeout
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
                // PIPE-READ SAFETY note above.
                let drainGroup = DispatchGroup()
                var outData = Data()
                var errData = Data()
                drainGroup.enter()
                DispatchQueue.global(qos: .userInitiated).async {
                    outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                    drainGroup.leave()
                }
                drainGroup.enter()
                DispatchQueue.global(qos: .userInitiated).async {
                    errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                    drainGroup.leave()
                }

                // Watchdog: only ever terminates the process, never resumes the
                // continuation itself — the single `resume` below always fires
                // after `waitUntilExit()` returns, on every path (success, exit
                // failure, or a termination caused by this watchdog).
                let watchdog = DispatchWorkItem {
                    if process.isRunning { process.terminate() }
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)

                drainGroup.wait()
                process.waitUntilExit()
                watchdog.cancel()

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
}
