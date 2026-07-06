// MCP/main.swift
//
// `speak-mcp` — the MCP agent-bridge CLI shim (specs/horizon-voice-os.md
// Pillar 3 / H-3 vertical slice). Serves the Model Context Protocol over
// stdio: reads newline-delimited JSON-RPC messages from stdin, dispatches
// them through `AgentBridgeServer` (pure protocol logic in
// SpeakCore/AgentBridge/), and writes newline-delimited JSON-RPC replies to
// stdout.
//
// This binary is a thin transport shim BY DESIGN — the JSON-RPC/MCP codec,
// handshake, and tool-call routing all live in SpeakCore, where they are unit
// tested with no I/O; this file only owns reading/writing raw bytes.
//
// Transport: stdio only, newline-delimited JSON, no sockets — per H-3 scope.
// The XPC/socket link to the running menubar app (needed for a live
// speak_say/speak_ask/speak_confirm) is a later task; this binary talks to
// `speak.app` only via the EXISTING CFMessagePort CLI IPC, reused unchanged
// inside `CLIBridgeBackend.status()`.
//
// Shutdown: per the MCP lifecycle spec, the client closes stdin to signal
// shutdown ("First, closing the input stream to the child process"); this
// loop exits cleanly on EOF.
//
// stdout carries ONLY JSON-RPC frames — an MCP client parses every stdout
// line as a message — so writing to `FileHandle.standardOutput` here is I/O,
// not logging, and does not violate the no-`print` rule (which governs
// SpeakCore's os.Logger-only logging, AGENTS.md §3). Diagnostics go through
// `SpeakLog.agentBridge`, which routes to the system log (Console.app), never
// to stdout — mixing a log line into the stdout stream would corrupt the
// client's JSON-RPC framing. [decision H-3, mirrors Speak/CLI/main.swift's
// FileHandle-not-print rationale]
//
// Top-level `await`: this file is Swift's special-cased `main.swift`, so
// top-level code runs in an implicit async context — no `@main` struct or
// manual `RunLoop`/semaphore bridging is needed to call the actor-isolated
// `AgentBridgeServer.handleLine(_:)`. [verified via swiftc -typecheck against
// the local macOS 26 SDK / Swift 5 language mode, 2026-07-06]

import Foundation
import SpeakCore

// MARK: - stdout writer

/// Write one JSON-RPC frame + trailing newline to stdout.
private func writeLine(_ data: Data) {
    var payload = data
    payload.append(UInt8(ascii: "\n"))
    FileHandle.standardOutput.write(payload)
}

// MARK: - stdin line reader

/// Buffers raw stdin bytes and yields one newline-delimited line at a time.
/// A `nil` return means EOF — the client closed stdin (the MCP shutdown
/// signal) — and the final partial line (if any, with no trailing newline)
/// is flushed as the last line before that `nil`.
private final class StdinLineReader {
    private let handle = FileHandle.standardInput
    private var buffer = Data()

    func nextLine() -> Data? {
        while true {
            if let newlineIndex = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                let line = buffer.subdata(in: buffer.startIndex..<newlineIndex)
                buffer.removeSubrange(buffer.startIndex...newlineIndex)
                return line
            }
            let chunk = handle.availableData
            if chunk.isEmpty {
                guard !buffer.isEmpty else { return nil }
                let rest = buffer
                buffer.removeAll()
                return rest
            }
            buffer.append(chunk)
        }
    }
}

// MARK: - Server loop

let server = AgentBridgeServer(backend: CLIBridgeBackend())
private let reader = StdinLineReader()

SpeakLog.agentBridge.info("speak-mcp: starting stdio MCP server, protocol \(MCPProtocolVersion.latest, privacy: .public).")

while let lineData = reader.nextLine() {
    let text = String(decoding: lineData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { continue }  // ignore blank keepalive lines
    guard let normalized = text.data(using: .utf8) else { continue }
    if let replyData = await server.handleLine(normalized) {
        writeLine(replyData)
    }
}

SpeakLog.agentBridge.info("speak-mcp: stdin closed, exiting.")
