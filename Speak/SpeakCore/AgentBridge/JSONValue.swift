// SpeakCore/AgentBridge/JSONValue.swift
//
// A minimal, dependency-free JSON value type used to represent arbitrary
// JSON-RPC `params` / `result` / `data` payloads: MCP client capabilities,
// tool arguments, tool `inputSchema`. Pure Foundation — no third-party JSON
// library (e.g. AnyCodable), consistent with the v0 "no third-party deps"
// rule (AGENTS.md §2).
//
// Only as expressive as MCP actually needs: object / array / string / number
// / bool / null. Dictionary key order is not preserved — JSON object key
// order carries no protocol meaning in MCP, so this is not a limitation.

import Foundation

public enum JSONValue: Sendable, Equatable {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
}

extension JSONValue: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let b = try? container.decode(Bool.self) {
            self = .bool(b)
        } else if let d = try? container.decode(Double.self) {
            self = .number(d)
        } else if let s = try? container.decode(String.self) {
            self = .string(s)
        } else if let arr = try? container.decode([JSONValue].self) {
            self = .array(arr)
        } else if let obj = try? container.decode([String: JSONValue].self) {
            self = .object(obj)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .object(let obj): try container.encode(obj)
        case .array(let arr): try container.encode(arr)
        case .string(let s): try container.encode(s)
        case .number(let d): try container.encode(d)
        case .bool(let b): try container.encode(b)
        case .null: try container.encodeNil()
        }
    }
}

// MARK: - Convenience accessors (used by tool-argument extraction)

extension JSONValue {
    public var objectValue: [String: JSONValue]? {
        if case .object(let o) = self { return o }
        return nil
    }

    public var arrayValue: [JSONValue]? {
        if case .array(let a) = self { return a }
        return nil
    }

    public var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    public var boolValue: Bool? {
        if case .bool(let b) = self { return b }
        return nil
    }

    public var doubleValue: Double? {
        if case .number(let d) = self { return d }
        return nil
    }
}

// MARK: - Literal conveniences (building tool schemas / results in code)

extension JSONValue: ExpressibleByStringLiteral, ExpressibleByBooleanLiteral,
                      ExpressibleByIntegerLiteral, ExpressibleByArrayLiteral,
                      ExpressibleByDictionaryLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
    public init(booleanLiteral value: Bool) { self = .bool(value) }
    public init(integerLiteral value: Int) { self = .number(Double(value)) }
    public init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
    public init(dictionaryLiteral elements: (String, JSONValue)...) {
        self = .object(Dictionary(uniqueKeysWithValues: elements))
    }
}
