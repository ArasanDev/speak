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
    private func makeFixtureScript(in dir: URL) throws -> String {
        let script = """
        #!/bin/sh
        case "$1" in
          list)
            echo "Good Morning"
            echo "Wind Down"
            ;;
          run)
            case "$2" in
              "Good Morning")
                echo "ran good morning"
                exit 0
                ;;
              "Broken Shortcut")
                echo "something went wrong" 1>&2
                exit 1
                ;;
              "Slow Shortcut")
                sleep 5
                exit 0
                ;;
              *)
                echo "no shortcut named $2" 1>&2
                exit 1
                ;;
            esac
            ;;
          *)
            exit 2
            ;;
        esac
        """
        let url = dir.appendingPathComponent("fixture-shortcuts.sh")
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url.path
    }

    // MARK: - listActionNames

    func testListActionNames_parsesStdoutLines() async throws {
        try await TestStorage.withTempDir { dir in
            let path = try self.makeFixtureScript(in: dir)
            let executor = ShortcutsCLIExecutor(executablePath: path)

            let names = await executor.listActionNames()

            XCTAssertEqual(names, ["Good Morning", "Wind Down"])
        }
    }

    // MARK: - run(named:) — success

    func testRun_success_returnsOutput() async throws {
        try await TestStorage.withTempDir { dir in
            let path = try self.makeFixtureScript(in: dir)
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
            let path = try self.makeFixtureScript(in: dir)
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
            let path = try self.makeFixtureScript(in: dir)
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
            let path = try self.makeFixtureScript(in: dir)
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
}
