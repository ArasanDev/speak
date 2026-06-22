// CLI/main.swift
//
// `speak` CLI tool — drives the running speak menubar app via CFMessagePort IPC.
//
// Usage:
//   speak --start   start a dictation session (error if app not running)
//   speak --stop    stop the current dictation session (error if app not running)
//   speak --status  print the app state + current hotkey binding
//
// Output goes to stdout (success) or stderr (error). Exit code 0 = success,
// 1 = failure (app not running, timeout, unknown flag).
//
// Output: FileHandle.standardOutput / .standardError — NOT print() — so the
// CLI tool stays consistent with the no-print rule in production code. The GUI
// app uses os.Logger; the CLI tool is a separate binary where FileHandle writes
// to the terminal. [decision: W2.3 — FileHandle.standardOutput is appropriate
// for a CLI tool; os.Logger writes to the system log which is not visible to
// shell scripts consuming `speak --status` output]
//
// Install (Homebrew, P11): the cask symlinks the binary into PATH.
// rpath: linked against SpeakCore.framework from DerivedData at build time;
//        production rpath (relative to @executable_path/../Frameworks or
//        /usr/local/lib/speak/) is deferred to the P11 release target.
//        [decision: W2.3 — standalone rpath is a P11 concern]
//
// App-not-running behaviour [decision: W2.3]:
//   --start / --stop print a clear "speak is not running" error and exit 1.
//   --status prints "not running" and exits 1.
//   Auto-launch is NOT attempted in v0 — launching an LSUIElement app from a
//   CLI tool requires NSWorkspace.openApplication which is async and adds UX
//   complexity (the user may have intentionally quit speak). A future
//   `speak --launch` subcommand can address this.

import Foundation
import SpeakCore

// MARK: - Output helpers (no print() — uses FileHandle)

/// Write a line to stdout.
private func emit(_ message: String) {
    var output = message + "\n"
    if let data = output.data(using: .utf8) {
        FileHandle.standardOutput.write(data)
    }
    // Prevent compiler warning about unused variable in the (unlikely) non-UTF8 case.
    _ = output
}

/// Write a line to stderr and exit with code 1.
private func fail(_ message: String) -> Never {
    let line = message + "\n"
    if let data = line.data(using: .utf8) {
        FileHandle.standardError.write(data)
    }
    exit(1)
}

// MARK: - Argument parsing

let args = CommandLine.arguments.dropFirst()  // drop the binary path

guard let flag = args.first, args.count == 1 else {
    fail("""
        speak CLI — drives the running speak menubar app.

        Usage:
          speak --start    start dictation
          speak --stop     stop dictation
          speak --status   print state + hotkey binding

        Requires: speak.app must already be running.
        """)
}

let command: CLICommand
switch flag {
case "--start":  command = .start
case "--stop":   command = .stop
case "--status": command = .status
default:
    fail("Unknown flag: \(flag). Valid flags: --start, --stop, --status")
}

// MARK: - Send the command

let transport = CFMessagePortTransport()

let reply: CLIReply
do {
    reply = try transport.send(CLIRequest(cmd: command))
} catch CLITransportError.portNotFound {
    // App is not running — give the user a clear, actionable message.
    // [decision: W2.3 — error + exit 1; no auto-launch in v0]
    fail("speak is not running. Open speak.app first.")
} catch CLITransportError.timeout {
    fail("speak did not respond in time. Try again.")
} catch let err as CLITransportError {
    fail("IPC error: \(err.description)")
} catch {
    fail("Unexpected error: \(error.localizedDescription)")
}

// MARK: - Format and print the reply

if !reply.ok {
    let reason = reply.error ?? "(no reason given)"
    fail("speak returned an error: \(reason)")
}

switch command {
case .status:
    let state   = reply.state?.rawValue ?? "unknown"
    let binding = reply.binding ?? "(none)"
    emit("state:   \(state)")
    emit("hotkey:  \(binding)")

case .start:
    emit("start command accepted by speak.")

case .stop:
    emit("stop command accepted by speak.")
}

exit(0)
