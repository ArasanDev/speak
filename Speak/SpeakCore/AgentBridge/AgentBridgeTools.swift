// SpeakCore/AgentBridge/AgentBridgeTools.swift
//
// The Pillar-3 tool catalog (specs/horizon-voice-os.md — tool contract
// [decision 2026-07-06]). `inputSchema` values are hand-written JSON Schema
// (2020-12, the MCP tools spec's default when no `$schema` is present) — no
// schema-generation library, per the no-third-party-deps rule.

import Foundation

public enum AgentBridgeTools {
    public static let sayInputSchema: JSONValue = [
        "type": "object",
        "properties": [
            "text": ["type": "string", "description": "What speak should say aloud."],
            "interrupt": [
                "type": "boolean",
                "description": "Cut off any speech currently playing before speaking this. Defaults to false."
            ]
        ],
        "required": ["text"]
    ]

    public static let askInputSchema: JSONValue = [
        "type": "object",
        "properties": [
            "question": [
                "type": "string",
                "description": "The question to speak, then listen for the human's spoken answer."
            ],
            "timeout": ["type": "number", "description": "Seconds to wait for a spoken answer before giving up."]
        ],
        "required": ["question"]
    ]

    public static let confirmInputSchema: JSONValue = [
        "type": "object",
        "properties": [
            "question": [
                "type": "string",
                "description": "A yes/no question to speak and listen for a deterministic yes/no/cancel answer."
            ]
        ],
        "required": ["question"]
    ]

    /// No parameters. `additionalProperties: false` is the MCP-recommended
    /// shape for a zero-argument tool (explicitly accepts only empty objects).
    public static let statusInputSchema: JSONValue = [
        "type": "object",
        "additionalProperties": false
    ]

    public static let all: [MCPTool] = [
        MCPTool(
            name: "speak_say",
            description: "Speak text aloud on the human's Mac (fire-and-forget status channel). " +
                "Not yet wired to a synthesizer in this build — returns an execution error until " +
                "VoiceOut (Pillar 2) ships.",
            inputSchema: sayInputSchema
        ),
        MCPTool(
            name: "speak_ask",
            description: "Speak a question, then listen for the human's spoken answer and return it as " +
                "text. Not implemented yet — needs the menubar-app link (XPC/socket transport).",
            inputSchema: askInputSchema
        ),
        MCPTool(
            name: "speak_confirm",
            description: "Speak a yes/no question and return the human's deterministic yes/no/cancel " +
                "answer as a boolean. Not implemented yet — needs the menubar-app link.",
            inputSchema: confirmInputSchema
        ),
        MCPTool(
            name: "speak_status",
            description: "Report whether speak.app is running and its current mic/engine state, so an " +
                "agent can degrade gracefully.",
            inputSchema: statusInputSchema
        )
    ]
}
