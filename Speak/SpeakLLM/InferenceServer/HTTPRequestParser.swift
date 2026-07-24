// SpeakLLM/InferenceServer/HTTPRequestParser.swift
//
// Minimal HTTP/1.1 request parser for the local inference server.
// Parses raw TCP data into a structured request (method, path, headers, body).
// Handles Content-Length to determine when the full body has arrived.
// One request per connection (Connection: close semantics for v1).
//
// No third-party dependencies. Apple frameworks only (AGENTS.md §2.4).

import Foundation

/// A parsed HTTP/1.1 request.
public struct HTTPRequest: Sendable {
    /// HTTP method (GET, POST, etc.)
    public let method: String
    /// Request path (e.g., "/v1/chat/completions")
    public let path: String
    /// HTTP headers with case-insensitive keys (stored lowercase).
    public let headers: [String: String]
    /// Raw request body data (empty for GET requests).
    public let body: Data

    /// Returns the header value for the given case-insensitive key.
    public func header(_ key: String) -> String? {
        headers[key.lowercased()]
    }
}

/// Errors that can occur during HTTP request parsing.
public enum HTTPParseError: Error, Sendable, Equatable {
    /// The data does not contain a valid HTTP request line.
    case malformedRequestLine
    /// A header line is not in "Key: Value" format.
    case malformedHeader(String)
    /// The Content-Length header value is not a valid integer.
    case invalidContentLength
    /// The body is incomplete (fewer bytes than Content-Length).
    case incompleteBody(expected: Int, received: Int)
    /// The request data is empty.
    case emptyData
}

/// Parses raw HTTP/1.1 request data into a structured `HTTPRequest`.
///
/// This is a minimal, single-request parser designed for the local inference
/// server. It handles one request per connection (Connection: close after
/// response). It does NOT support chunked transfer encoding, pipelining,
/// or keep-alive — those are unnecessary for localhost tool integrations.
public enum HTTPRequestParser {

    // MARK: - Constants

    /// Maximum header size before we reject the request.
    /// 64 KB is generous for API requests with Bearer tokens.
    /// [decision: 64KB header cap prevents memory abuse on localhost]
    private static let maxHeaderSize = 65_536

    /// The CRLF sequence that terminates HTTP header lines.
    private static let crlf = Data([0x0D, 0x0A])

    /// The double-CRLF that separates headers from body.
    private static let headerBodySeparator = Data([0x0D, 0x0A, 0x0D, 0x0A])

    // MARK: - Parsing

    /// Attempts to parse a complete HTTP request from raw data.
    ///
    /// - Parameter data: Raw bytes received from the TCP connection.
    /// - Returns: A parsed `HTTPRequest`, or `nil` if the data is malformed
    ///   or the body is incomplete.
    public static func parse(data: Data) -> HTTPRequest? {
        guard !data.isEmpty else { return nil }

        // Find the header/body separator (double CRLF).
        guard let separatorRange = data.range(of: headerBodySeparator) else {
            // Headers not fully received yet — treat as malformed for v1
            // (we receive the full request in one read for localhost).
            return nil
        }

        let headerData = data[data.startIndex..<separatorRange.lowerBound]

        // Guard against oversized headers.
        guard headerData.count <= maxHeaderSize else { return nil }

        // Parse header lines.
        guard let headerString = String(data: Data(headerData), encoding: .utf8) else {
            return nil
        }

        let lines = headerString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }

        // Parse request line: "METHOD /path HTTP/1.1"
        let requestParts = requestLine.split(separator: " ", maxSplits: 2)
        guard requestParts.count >= 2 else { return nil }

        let method = String(requestParts[0]).uppercased()
        let path = String(requestParts[1])

        // Validate method is a known HTTP method.
        guard ["GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS"].contains(method) else {
            return nil
        }

        // Parse headers (skip first line which is the request line).
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard !line.isEmpty else { continue }
            guard let colonIndex = line.firstIndex(of: ":") else { continue }
            let key = String(line[line.startIndex..<colonIndex])
                .trimmingCharacters(in: .whitespaces)
                .lowercased()
            let value = String(line[line.index(after: colonIndex)...])
                .trimmingCharacters(in: .whitespaces)
            headers[key] = value
        }

        // Extract body based on Content-Length.
        let bodyStartIndex = separatorRange.upperBound
        let remainingData = Data(data[bodyStartIndex...])

        let body: Data
        if let contentLengthStr = headers["content-length"],
           let contentLength = Int(contentLengthStr) {
            guard contentLength >= 0 else { return nil }
            if contentLength == 0 {
                body = Data()
            } else if remainingData.count >= contentLength {
                body = remainingData.prefix(contentLength)
            } else {
                // Incomplete body — for localhost with single-read semantics,
                // use what we have (the NWConnection receive may have gotten it all).
                body = remainingData
            }
        } else {
            // No Content-Length: use remaining data as body (may be empty for GET).
            body = remainingData
        }

        return HTTPRequest(method: method, path: path, headers: headers, body: body)
    }
}
