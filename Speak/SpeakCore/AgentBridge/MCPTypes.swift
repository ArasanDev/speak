// SpeakCore/AgentBridge/MCPTypes.swift
//
// Model Context Protocol (MCP) message payloads layered on JSON-RPC 2.0
// (JSONRPC.swift). Protocol version implemented: **2025-11-25**
// [verified from: https://modelcontextprotocol.io/specification/2025-11-25/
// basic/lifecycle and .../server/tools — fetched 2026-07-06]. `speak-mcp`
// also accepts **2025-06-18** (the version Claude Code's MCP client sends as
// of this writing) and echoes it back verbatim — legal per the lifecycle
// spec's version-negotiation rule: "If the server supports the requested
// protocol version, it MUST respond with the same version." An unsupported
// request falls back to the latest version we implement, per "Otherwise, the
// server MUST respond with another protocol version it supports. This SHOULD
// be the latest version supported by the server."

import Foundation

public enum MCPProtocolVersion {
    /// The newest protocol version this server implements.
    public static let latest = "2025-11-25"

    /// Every version this server can speak. 2025-06-18 is Claude Code's
    /// current MCP client version as of this writing (2026-07-06).
    public static let supported: Set<String> = [latest, "2025-06-18"]

    /// Version negotiation per the lifecycle spec: echo the requested version
    /// if we support it, else fall back to `latest`.
    public static func negotiate(requested: String) -> String {
        supported.contains(requested) ? requested : latest
    }
}

/// `speak-mcp`'s own release version (distinct from the protocol version
/// above). [decision H-3] Pinned literal until a release process derives it
/// from a shared build setting.
public enum AgentBridgeVersion {
    public static let current = "0.1.0"
}

// MARK: - initialize

public struct MCPImplementationInfo: Sendable, Equatable {
    public let name: String
    public let version: String

    public init(name: String, version: String) {
        self.name = name
        self.version = version
    }

    var asJSONValue: JSONValue {
        .object(["name": .string(name), "version": .string(version)])
    }
}

public struct MCPInitializeResult: Sendable, Equatable {
    public let protocolVersion: String
    public let capabilities: JSONValue
    public let serverInfo: MCPImplementationInfo

    public init(protocolVersion: String, capabilities: JSONValue, serverInfo: MCPImplementationInfo) {
        self.protocolVersion = protocolVersion
        self.capabilities = capabilities
        self.serverInfo = serverInfo
    }

    /// `speak-mcp` declares only the `tools` capability. It offers no
    /// resources/prompts, and the tool catalog is static for this slice (no
    /// runtime add/remove), so `listChanged` is omitted rather than set —
    /// there is nothing that would ever fire a `tools/list_changed`.
    public static func speakMCP(protocolVersion: String) -> MCPInitializeResult {
        MCPInitializeResult(
            protocolVersion: protocolVersion,
            capabilities: .object(["tools": .object([:])]),
            serverInfo: MCPImplementationInfo(name: "speak-mcp", version: AgentBridgeVersion.current)
        )
    }

    var asJSONValue: JSONValue {
        .object([
            "protocolVersion": .string(protocolVersion),
            "capabilities": capabilities,
            "serverInfo": serverInfo.asJSONValue
        ])
    }
}

// MARK: - tools/list

public struct MCPTool: Sendable, Equatable {
    public let name: String
    public let description: String
    public let inputSchema: JSONValue

    public init(name: String, description: String, inputSchema: JSONValue) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
    }

    var asJSONValue: JSONValue {
        .object([
            "name": .string(name),
            "description": .string(description),
            "inputSchema": inputSchema
        ])
    }
}

// MARK: - tools/call

public struct MCPToolCallRequest: Sendable, Equatable {
    public let name: String
    public let arguments: [String: JSONValue]

    /// Parses a `tools/call` request's `params`. `nil` when `params` is
    /// missing the required `name` string — the caller treats that as a
    /// protocol-level "invalid params" error, per the MCP tools spec, which
    /// classifies malformed requests (failing the `CallToolRequest` schema)
    /// as Protocol Errors, distinct from tool-execution errors.
    public init?(params: JSONValue?) {
        guard let obj = params?.objectValue, let name = obj["name"]?.stringValue else { return nil }
        self.name = name
        self.arguments = obj["arguments"]?.objectValue ?? [:]
    }
}

public enum MCPContentBlock: Sendable, Equatable {
    case text(String)

    var asJSONValue: JSONValue {
        switch self {
        case .text(let s): return .object(["type": .string("text"), "text": .string(s)])
        }
    }
}

public struct MCPToolCallResult: Sendable, Equatable {
    public let content: [MCPContentBlock]
    public let isError: Bool

    public init(content: [MCPContentBlock], isError: Bool = false) {
        self.content = content
        self.isError = isError
    }

    /// A successful tool result carrying one text block.
    public static func text(_ s: String) -> MCPToolCallResult { MCPToolCallResult(content: [.text(s)]) }

    /// A **tool execution error** (`isError: true`) — a business-logic
    /// condition the calling agent can act on (e.g. retry, tell the human),
    /// as opposed to a JSON-RPC protocol error. Per the MCP tools spec this
    /// is still a `result`, not a top-level `error` object.
    public static func error(_ s: String) -> MCPToolCallResult { MCPToolCallResult(content: [.text(s)], isError: true) }

    var asJSONValue: JSONValue {
        .object([
            "content": .array(content.map { $0.asJSONValue }),
            "isError": .bool(isError)
        ])
    }
}
