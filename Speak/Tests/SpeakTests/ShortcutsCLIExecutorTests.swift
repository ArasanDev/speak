// SpeakTests/ShortcutsCLIExecutorTests.swift
//
// H-1 (specs/horizon-voice-os.md, Pillar 1) — unit tests for `ShortcutsCLIExecutor`.
//
// These tests do NOT depend on the real `/usr/bin/shortcuts` binary or on any
// Shortcuts actually installed on the test machine (that would be nondeterministic
// and environment-dependent — exactly what `docs/architecture.md` testing
// conventions warn against). Instead they inject a tiny fixture shell script via
// `executablePath:` that mimics `shortcuts list` / `shortcuts run <name>`'s
// interface (stdout/stderr/exit-code shape), giving full, deterministic coverage
// of the real `Process` plumbing (pipe draining, exit-code handling, and the
// timeout watchdog) without any live-environment dependency.
//
// HONESTY BOUNDARY [deferred — human verification]: behavior of the REAL
// `shortcuts` CLI against REAL user shortcuts (especially input-requesting
// shortcuts, per specs/horizon-voice-os.md's `[unverified — dogfood H-4]` note)
// is not covered here.

@testable import SpeakCore
import XCTest

final class ShortcutsCLIExecutorTests: XCTestCase {

    /// Writes an executable fixture script that mimics the `shortcuts` CLI's
    /// argument/output/exit-code shape, and returns its path.
    private static func makeFixtureScript(in dir: URL) throws -> String {
        let script = """
        #!/usr/bin/env bash
        set -euo pipefail

        CMD="${1:-}"

        if [ "$CMD" = "list" ]; then
            echo "Good Morning"
            echo "Wind Down"
            exit 0
        fi

        if [ "$CMD" = "run" ]; then
            NAME="${2:-}"
            if [ "$NAME" = "Good Morning" ]; then
                echo "ran good morning"
                exit 0
            fi
            if [ "$NAME" = "Broken Shortcut" ]; then
                echo "something went wrong" >&2
                exit 1
            fi
            if [ "$NAME" = "Slow Shortcut" ]; then
                sleep 5
                echo "done sleeping"
                exit 0
            fi
            if [ "$NAME" = "Ignores Sigterm" ]; then
                trap '' TERM
                sleep 30
                echo "done sleeping past sigterm"
                exit 0
            fi
            if [ "$NAME" = "Huge Output" ]; then
                python3 -c "import sys; sys.stdout.write('x' * 5000000)"
                exit 0
            fi
            echo "unknown shortcut: $NAME" >&2
            exit 2
        fi

        echo "usage: script list | run <name>" >&2
        exit 1
        """
        let url = dir.appendingPathComponent("fake-shortcuts.sh")
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url.path
    }

    // MARK: - listActionNames

    func testListActionNames_parsesStdoutLines() async throws {
        try await TestStorage.withTempDir { dir in
            let path = try Self.makeFixtureScript(in: dir)
            let executor = ShortcutsCLIExecutor(executablePath: path)

            let names = await executor.listActionNames()

            XCTAssertEqual(names, ["Good Morning", "Wind Down"])
        }
    }

    // MARK: - run(named:) — success

    func testRun_success_returnsOutput() async throws {
        try await TestStorage.withTempDir { dir in
            let path = try Self.makeFixtureScript(in: dir)
            let executor = ShortcutsCLIExecutor(executablePath: path)

            let result = await executor.run(named: "Good Morning")

            guard case .success(let output) = result else {
                return XCTFail("Expected .success, got \(result)")
            }
            XCTAssertEqual(output?.trimmingCharacters(in: .whitespacesAndNewlines), "ran good morning")
        }
    }

    // MARK: - run(named:) — failure (nonzero exit)

    func testRun_nonzeroExit_returnsFailedWithStderrDetail() async throws {
        try await TestStorage.withTempDir { dir in
            let path = try Self.makeFixtureScript(in: dir)
            let executor = ShortcutsCLIExecutor(executablePath: path)

            let result = await executor.run(named: "Broken Shortcut")

            guard case .failed(let detail) = result else {
                return XCTFail("Expected .failed, got \(result)")
            }
            XCTAssertTrue(detail.contains("something went wrong"), "detail was: \(detail)")
        }
    }

    func testRun_unknownName_returnsFailed() async throws {
        try await TestStorage.withTempDir { dir in
            let path = try Self.makeFixtureScript(in: dir)
            let executor = ShortcutsCLIExecutor(executablePath: path)

            let result = await executor.run(named: "Does Not Exist")

            guard case .failed = result else {
                return XCTFail("Expected .failed, got \(result)")
            }
        }
    }

    // MARK: - Launch failure (bad executable path)

    func testRun_missingExecutable_returnsFailed() async throws {
        let executor = ShortcutsCLIExecutor(executablePath: "/nonexistent/path/to/shortcuts")

        let result = await executor.run(named: "anything")

        guard case .failed = result else {
            return XCTFail("Expected .failed, got \(result)")
        }
    }

    // MARK: - Timeout watchdog

    func testRun_hangingProcess_terminatesAfterTimeoutInsteadOfHanging() async throws {
        try await TestStorage.withTempDir { dir in
            let path = try Self.makeFixtureScript(in: dir)
            // Fixture's "Slow Shortcut" sleeps 5s; a 0.3s timeout must terminate it
            // well before that, proving the watchdog (not the sleep) resolves the call.
            let executor = ShortcutsCLIExecutor(executablePath: path, timeout: 0.3)

            let start = Date()
            let result = await executor.run(named: "Slow Shortcut")
            let elapsed = Date().timeIntervalSince(start)

            XCTAssertLessThan(elapsed, 3.0, "The timeout watchdog should terminate the process well before the fixture's 5s sleep completes.")
            guard case .failed = result else {
                return XCTFail("Expected .failed (terminated process exits nonzero), got \(result)")
            }
        }
    }

    /// H-4 hardening: a process that traps and ignores SIGTERM (as a
    /// dialog-holding child conceivably could — the unverified H-4 risk) must
    /// still resolve, via the SIGKILL escalation, rather than hanging forever.
    func testRun_processIgnoringSigterm_resolvesViaSigkillEscalation() async throws {
        try await TestStorage.withTempDir { dir in
            let path = try Self.makeFixtureScript(in: dir)
            // timeout: SIGTERM fires at 0.2s (ignored by fixture); killGrace: 0.2s
            // more before SIGKILL. Bounded well under the fixture's 30s sleep.
            let executor = ShortcutsCLIExecutor(executablePath: path, timeout: 0.2, killGrace: 0.2)

            let start = Date()
            let result = await executor.run(named: "Ignores Sigterm")
            let elapsed = Date().timeIntervalSince(start)

            XCTAssertLessThan(elapsed, 3.0, "SIGKILL escalation should resolve the call well before the fixture's 30s sleep completes.")
            guard case .failed = result else {
                return XCTFail("Expected .failed (SIGKILL-terminated process exits nonzero), got \(result)")
            }
        }
    }

    // MARK: - Large stdout

    func testRun_largeStdout_doesNotDeadlockAndCapturesFullOutput() async throws {
        try await TestStorage.withTempDir { dir in
            let path = try Self.makeFixtureScript(in: dir)
            let executor = ShortcutsCLIExecutor(executablePath: path)

            let result = await executor.run(named: "Huge Output")

            guard case .success(let output) = result else {
                return XCTFail("Expected .success, got \(result)")
            }
            XCTAssertEqual(output?.utf8.count, 5_000_000, "Full stdout should be captured without truncation or deadlock.")
        }
    }
}
