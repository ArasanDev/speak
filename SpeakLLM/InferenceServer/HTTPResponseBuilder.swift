// SpeakLLM/InferenceServer/HTTPResponseBuilder.swift
//
// Builds HTTP/1.1 responses as raw Data for the local inference server.
// Supports JSON responses, SSE (Server-Sent Events) streams, and error responses.
//
// No third-party dependencies. Apple frameworks only (AGENTS.md §2.4).

import Foundation

/// Builds well-formed HTTP/1.1 responses for the inference server.
///
/// All responses use `Connection: close` semantics (one request per connection).
/// SSE responses use `text/event-stream` content type with proper cache headers.
public enum HTTPResponseBuilder {

    // MARK: - Constants

    /// HTTP version string used in response status lines.
    private static let httpVersion = "HTTP/1.1"

    /// Server identification header value.
    /// [decision: identifies the server for debugging without leaking version internals]
    private static let serverIdentifier = "speak-inference/0.1.0"

    /// Standard CRLF line ending for HTTP protocol.
    private static let crlf = "\r\n"

    // MARK: - JSON Responses

    /// Builds a complete HTTP/1.1 JSON response.
    ///
    /// - Parameters:
    ///   - status: HTTP status code (e.g., 200, 400, 401, 404, 500, 503).
    ///   - body: A JSON-serializable dictionary.
    /// - Returns: Raw HTTP response data ready to send over the wire.
    public static func buildJSONResponse(status: Int, body: [String: Any]) -> Data {
        let statusText = statusText(for: status)
        let jsonData = (try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]))
            ?? Data("{}".utf8)

        var response = "\(httpVersion) \(status) \(statusText)\(crlf)"
        response += "Content-Type: application/json\(crlf)"
        response += "Content-Length: \(jsonData.count)\(crlf)"
        response += "Connection: close\(crlf)"
        response += "Server: \(serverIdentifier)\(crlf)"
        response += crlf

        var data = Data(response.utf8)
        data.append(jsonData)
        return data
    }

    /// Builds a complete HTTP/1.1 JSON response from raw JSON data.
    ///
    /// - Parameters:
    ///   - status: HTTP status code.
    ///   - jsonData: Pre-serialized JSON data.
    /// - Returns: Raw HTTP response data.
    public static func buildJSONResponse(status: Int, jsonData: Data) -> Data {
        let statusText = statusText(for: status)

        var response = "\(httpVersion) \(status) \(statusText)\(crlf)"
        response += "Content-Type: application/json\(crlf)"
        response += "Content-Length: \(jsonData.count)\(crlf)"
        response += "Connection: close\(crlf)"
        response += "Server: \(serverIdentifier)\(crlf)"
        response += crlf

        var data = Data(response.utf8)
        data.append(jsonData)
        return data
    }

    // MARK: - SSE Responses

    /// Builds the HTTP headers for an SSE (Server-Sent Events) stream response.
    ///
    /// Call this first, then send individual SSE chunks via `buildSSEChunk(data:)`.
    /// The connection is kept open until the stream completes.
    ///
    /// - Returns: Raw HTTP response header data (no body yet).
    public static func buildSSEHeaders() -> Data {
        var response = "\(httpVersion) 200 OK\(crlf)"
        response += "Content-Type: text/event-stream\(crlf)"
        response += "Cache-Control: no-cache\(crlf)"
        response += "Connection: keep-alive\(crlf)"
        response += "Server: \(serverIdentifier)\(crlf)"
        response += crlf
        return Data(response.utf8)
    }

    /// Builds a single SSE data frame.
    ///
    /// - Parameter payload: The JSON string to send as the data field.
    /// - Returns: Raw SSE frame data ("data: <payload>\n\n").
    public static func buildSSEChunk(data payload: String) -> Data {
        Data("data: \(payload)\n\n".utf8)
    }

    /// Builds a single SSE event frame with a named event type.
    ///
    /// Used by the Anthropic Messages API which requires `event:` fields.
    ///
    /// - Parameters:
    ///   - event: The SSE event type (e.g., "message_start", "content_block_delta").
    ///   - payload: The JSON string to send as the data field.
    /// - Returns: Raw SSE frame data ("event: <event>\ndata: <payload>\n\n").
    public static func buildSSEEvent(event: String, data payload: String) -> Data {
        Data("event: \(event)\ndata: \(payload)\n\n".utf8)
    }

    /// Builds the SSE [DONE] terminator used by OpenAI-compatible streaming.
    ///
    /// - Returns: Raw SSE frame data ("data: [DONE]\n\n").
    public static func buildSSEDone() -> Data {
        Data("data: [DONE]\n\n".utf8)
    }

    // MARK: - Error Responses

    /// Builds an HTTP error response with a JSON error body.
    ///
    /// - Parameters:
    ///   - status: HTTP status code (4xx or 5xx).
    ///   - message: Human-readable error description.
    /// - Returns: Raw HTTP response data with JSON error body.
    public static func buildErrorResponse(status: Int, message: String) -> Data {
        let errorBody: [String: Any] = [
            "error": [
                "message": message,
                "type": errorType(for: status),
                "code": String(status),
            ],
        ]
        return buildJSONResponse(status: status, body: errorBody)
    }

    // MARK: - Helpers

    /// Maps HTTP status codes to their standard reason phrases.
    private static func statusText(for status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 413: return "Payload Too Large"
        case 429: return "Too Many Requests"
        case 500: return "Internal Server Error"
        case 503: return "Service Unavailable"
        default: return "Unknown"
        }
    }

    /// Maps HTTP status codes to OpenAI-compatible error type strings.
    private static func errorType(for status: Int) -> String {
        switch status {
        case 400: return "invalid_request_error"
        case 401: return "authentication_error"
        case 403: return "permission_error"
        case 404: return "not_found_error"
        case 429: return "rate_limit_error"
        case 500: return "server_error"
        case 503: return "service_unavailable"
        default: return "api_error"
        }
    }
}
