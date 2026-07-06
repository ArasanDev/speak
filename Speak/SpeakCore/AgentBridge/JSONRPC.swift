// SpeakCore/AgentBridge/JSONRPC.swift
//
// JSON-RPC 2.0 message envelope — the wire format MCP rides on
// (https://www.jsonrpc.org/specification). Pure Foundation Codable types, no
// I/O and no transport assumptions: together with MCPTypes.swift this is the
// "protocol layer" H-3 calls for — fully unit-testable via in-memory `Data`,
// no stdin/stdout here. The stdio read/write loop lives in
// `Speak/MCP/main.swift`.

import Foundation

/// A JSON-RPC request/notification `id`: string or number. JSON-RPC 2.0 §4
/// also permits `null`, but that usage is discouraged and MCP never emits it
/// for a request; we treat "id key absent" (not "id present but null") as the
/// notification signal — see `JSONRPCInbound.isNotification`.
public enum JSONRPCID: Sendable, Equatable, Codable {
    case string(String)
    case number(Int)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let s = try? container.decode(String.self) {
            self = .string(s)
        } else if let n = try? container.decode(Int.self) {
            self = .number(n)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "JSON-RPC id must be a string or a number")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let s): try container.encode(s)
        case .number(let n): try container.encode(n)
        }
    }
}

/// Standard JSON-RPC 2.0 error codes (spec §5.1). The MCP tools spec also
/// uses `invalidParams` for "unknown tool" — see `AgentBridgeServer`.
public enum JSONRPCErrorCode {
    public static let parseError = -32700
    public static let invalidRequest = -32600
    public static let methodNotFound = -32601
    public static let invalidParams = -32602
    public static let internalError = -32603
}

public struct JSONRPCErrorObject: Codable, Sendable, Equatable {
    public let code: Int
    public let message: String
    public let data: JSONValue?

    public init(code: Int, message: String, data: JSONValue? = nil) {
        self.code = code
        self.message = message
        self.data = data
    }
}

/// An inbound message from the client: either a request (`id` present) or a
/// notification (`id` absent). A server in this slice only ever receives
/// these two shapes — `speak-mcp` makes no outbound requests to the client,
/// so it never has to decode a response.
public struct JSONRPCInbound: Sendable, Equatable {
    public let jsonrpc: String
    public let id: JSONRPCID?
    public let method: String
    public let params: JSONValue?

    public var isNotification: Bool { id == nil }

    public init(jsonrpc: String = "2.0", id: JSONRPCID?, method: String, params: JSONValue?) {
        self.jsonrpc = jsonrpc
        self.id = id
        self.method = method
        self.params = params
    }
}

extension JSONRPCInbound: Codable {
    private enum CodingKeys: String, CodingKey { case jsonrpc, id, method, params }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        jsonrpc = try container.decodeIfPresent(String.self, forKey: .jsonrpc) ?? "2.0"
        id = try container.decodeIfPresent(JSONRPCID.self, forKey: .id)
        method = try container.decode(String.self, forKey: .method)
        params = try container.decodeIfPresent(JSONValue.self, forKey: .params)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(jsonrpc, forKey: .jsonrpc)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encode(method, forKey: .method)
        try container.encodeIfPresent(params, forKey: .params)
    }
}

/// An outbound response to a request. Exactly one of `result` / `error` is
/// set — enforced by the two factory methods below (plain-Codable-struct
/// style, matching `CLIReply` elsewhere in SpeakCore, rather than a Swift
/// `enum` with associated payloads, so `Codable` conformance stays simple).
public struct JSONRPCOutbound: Sendable, Equatable {
    public let jsonrpc: String
    public let id: JSONRPCID?
    public let result: JSONValue?
    public let error: JSONRPCErrorObject?

    /// A successful reply. `id` matches the request being answered.
    public static func success(id: JSONRPCID, result: JSONValue) -> JSONRPCOutbound {
        JSONRPCOutbound(jsonrpc: "2.0", id: id, result: result, error: nil)
    }

    /// An error reply. `id` is `nil` only when the request could not be
    /// parsed well enough to recover an id (JSON-RPC 2.0 §5.1 — "if there was
    /// an error in detecting the id ... it MUST be Null").
    public static func failure(id: JSONRPCID?, error: JSONRPCErrorObject) -> JSONRPCOutbound {
        JSONRPCOutbound(jsonrpc: "2.0", id: id, result: nil, error: error)
    }

    public init(jsonrpc: String, id: JSONRPCID?, result: JSONValue?, error: JSONRPCErrorObject?) {
        self.jsonrpc = jsonrpc
        self.id = id
        self.result = result
        self.error = error
    }
}

extension JSONRPCOutbound: Codable {
    private enum CodingKeys: String, CodingKey { case jsonrpc, id, result, error }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        jsonrpc = try container.decodeIfPresent(String.self, forKey: .jsonrpc) ?? "2.0"
        id = try container.decodeIfPresent(JSONRPCID.self, forKey: .id)
        result = try container.decodeIfPresent(JSONValue.self, forKey: .result)
        error = try container.decodeIfPresent(JSONRPCErrorObject.self, forKey: .error)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(jsonrpc, forKey: .jsonrpc)
        // JSON-RPC 2.0 §5: id is REQUIRED in a response, but MAY be `null`
        // when the request's own id could not be recovered (parse error).
        if let id {
            try container.encode(id, forKey: .id)
        } else {
            try container.encodeNil(forKey: .id)
        }
        try container.encodeIfPresent(result, forKey: .result)
        try container.encodeIfPresent(error, forKey: .error)
    }
}

// MARK: - Wire codec (Data <-> message)

/// Pure encode/decode helpers — no I/O. `Speak/MCP/main.swift` owns reading
/// stdin lines / writing stdout lines; this type only turns one line's raw
/// bytes into a message and back.
public enum JSONRPCCodec {
    public static func decodeInbound(_ data: Data) throws -> JSONRPCInbound {
        try JSONDecoder().decode(JSONRPCInbound.self, from: data)
    }

    public static func encodeOutbound(_ message: JSONRPCOutbound) throws -> Data {
        try JSONEncoder().encode(message)
    }
}
