// SpeakCore/AgentBridge/AgentBridgeTools.swift
//
// The Pillar-3 tool catalog (specs/horizon-voice-os.md — tool contract
// [decision 2026-07-06]). `inputSchema` values are hand-written JSON Schema
// (2020-12, the MCP tools spec's default when no `$schema` is present) — no
// schema-generation library, per the no-third-party-deps rule.

import Foundation

public enum AgentBridgeTools {
    public static let notifyInputSchema: JSONValue = [
        "type": "object",
        "properties": [
            "summary": [
                "type": "string",
                "description": "A short, self-contained outcome to speak. Use one to three sentences."
            ],
            "kind": [
                "type": "string",
                "enum": ["completion", "blocked", "warning", "requested"],
                "description": "Why this deserves the developer's attention. Defaults to completion."
            ],
            "detail": [
                "type": "string",
                "description": "Reserved for the future visual inbox. Currently ignored and never spoken."
            ],
            "interrupt": [
                "type": "boolean",
                "description": "Replace speech already in progress. Defaults to false."
            ]
        ],
        "required": ["summary"]
    ]

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

    /// AVB-5 (specs/agent-voice-bridge.md §6). `choices` is required (and must be
    /// non-empty) iff `mode == "choice"` — JSON Schema 2020-12 has no clean way to
    /// express that conditional without `if`/`then`, so it's documented in
    /// `choices`' description and enforced in code (`AgentBridgeServer.runTool`).
    public static let requestInputInputSchema: JSONValue = [
        "type": "object",
        "properties": [
            "requestId": [
                "type": "string",
                "description": "Caller-supplied identifier for this request (for correlating with logs)."
            ],
            "idempotencyKey": [
                "type": "string",
                "description": "Optional. A duplicate call with the same key while this request is still in flight returns 'busy' instead of opening a second capture."
            ],
            "prompt": [
                "type": "string",
                "description": "The question or statement to present to the human and listen for an answer to."
            ],
            "mode": [
                "type": "string",
                "enum": ["freeform", "choice", "approval"],
                "description": "freeform: any spoken answer. choice: match one of 'choices'. approval: yes/no."
            ],
            "choices": [
                "type": "array",
                "items": ["type": "string"],
                "description": "Required, non-empty, when mode is 'choice' — the options to match the spoken answer against. Ignored otherwise."
            ],
            "timeout": ["type": "number", "description": "Seconds to wait for a spoken answer before giving up."],
            "consequence": [
                "type": "string",
                "description": "Optional human-readable statement of what answering implies. Reserved for future presentation; not currently spoken."
            ],
            "spokenSummary": [
                "type": "string",
                "description": "What to actually speak aloud. Defaults to 'prompt' when omitted."
            ]
        ],
        "required": ["requestId", "prompt", "mode"]
    ]

    /// No parameters. `additionalProperties: false` is the MCP-recommended
    /// shape for a zero-argument tool (explicitly accepts only empty objects).
    public static let statusInputSchema: JSONValue = [
        "type": "object",
        "additionalProperties": false
    ]

    public static let all: [MCPTool] = [
        MCPTool(
            name: "speak_notify",
            description: "Notify the developer with a concise local spoken summary. Use only for a final " +
                "task outcome, a blocker, a high-severity warning, or readback the user explicitly requested. " +
                "Do not narrate routine progress, logs, diffs, stack traces, or full agent responses. " +
                "Requires speak.app to be running.",
            inputSchema: notifyInputSchema
        ),
        MCPTool(
            name: "speak_say",
            description: "Speak text aloud on the human's Mac (fire-and-forget status channel). " +
                "Requires speak.app to be running.",
            inputSchema: sayInputSchema
        ),
        MCPTool(
            name: "speak_ask",
            description: "Speak a question, then listen for the human's spoken answer and return it as " +
                "text. Opens the mic and shows the HUD (same as a hotkey dictation) — the human sees " +
                "and can cancel it. Requires speak.app to be running.",
            inputSchema: askInputSchema
        ),
        MCPTool(
            name: "speak_confirm",
            description: "Speak a yes/no question and return the human's deterministic yes/no answer as " +
                "a boolean. Fails with a clear error if the spoken answer is unclear or the human cancels, " +
                "rather than guessing. Requires speak.app to be running.",
            inputSchema: confirmInputSchema
        ),
        MCPTool(
            name: "speak_request_input",
            description: "Ask the human a freeform question, a multiple-choice question, or a yes/no " +
                "approval, and get back a typed result: answered, declined, cancelled, timedOut, or busy. " +
                "Opens the mic and shows the HUD (same as a hotkey dictation) — the human sees and can " +
                "cancel every capture. Returns 'busy' immediately (never queues) if another agent-initiated " +
                "capture is already in flight. Prefer this over speak_ask/speak_confirm for new integrations " +
                "— they remain as compatibility wrappers. Requires speak.app to be running.",
            inputSchema: requestInputInputSchema
        ),
        MCPTool(
            name: "speak_status",
            description: "Report whether speak.app is running and its current mic/engine state, so an " +
                "agent can degrade gracefully.",
            inputSchema: statusInputSchema
        )
    ]
}
