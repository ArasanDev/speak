// SpeakCore/AgentBridge/AgentBridgeTools.swift
//
// The Pillar-3 tool catalog (specs/horizon-voice-os.md — tool contract
// [decision 2026-07-06]). `inputSchema` values are hand-written JSON Schema
// (2020-12, the MCP tools spec's default when no `$schema` is present) — no
// schema-generation library, per the no-third-party-deps rule.

import Foundation

public enum AgentBridgeTools {
    /// Reused by every tool below so `sessionId` documents the same contract
    /// everywhere. [decision: AVB-6]
    private static let sessionIdDescription: String =
        "Optional. The sessionId returned by speak_register_session. If present and recognized, this call " +
        "is attributed to that session. If present but unrecognized, the call still proceeds and the " +
        "result notes the session is unregistered. If omitted, behavior is unchanged from before session " +
        "registration existed."

    private static let sessionIdProperty: JSONValue = [
        "type": "string",
        "description": .string(sessionIdDescription)
    ]

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
            ],
            "sessionId": sessionIdProperty
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
            ],
            "sessionId": sessionIdProperty
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
            "timeout": ["type": "number", "description": "Seconds to wait for a spoken answer before giving up."],
            "sessionId": sessionIdProperty
        ],
        "required": ["question"]
    ]

    public static let confirmInputSchema: JSONValue = [
        "type": "object",
        "properties": [
            "question": [
                "type": "string",
                "description": "A yes/no question to speak and listen for a deterministic yes/no/cancel answer."
            ],
            "sessionId": sessionIdProperty
        ],
        "required": ["question"]
    ]

    private static let capabilitiesRequestDescription: String =
        "Optional. Capabilities this session wants to use. The response's 'capabilities' is the subset " +
        "speak actually supports right now — anything else is silently dropped, not rejected."

    private static let reRegisterSessionIdDescription: String =
        "Optional. Re-register an existing sessionId (updates its fields and lastSeen) instead of " +
        "minting a new one."

    /// AVB-6 (specs/agent-voice-bridge.md §7.1). `capabilities` is the caller's
    /// requested set; the response is the intersection with what speak actually
    /// supports this slice — unknown requested capabilities are dropped
    /// silently, never an error (that IS the negotiation).
    public static let registerSessionInputSchema: JSONValue = [
        "type": "object",
        "properties": [
            "provider": [
                "type": "string",
                "description": "The agent client/provider identifier, e.g. 'codex' or 'claude-code'."
            ],
            "label": [
                "type": "string",
                "description": "A short human-readable label for this session, shown to the user."
            ],
            "cwd": [
                "type": "string",
                "description": "Optional. The agent's working directory or repository path."
            ],
            "capabilities": [
                "type": "array",
                "items": ["type": "string"],
                "description": .string(capabilitiesRequestDescription)
            ],
            "sessionId": [
                "type": "string",
                "description": .string(reRegisterSessionIdDescription)
            ]
        ],
        "required": ["provider", "label"]
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
            ],
            "sessionId": sessionIdProperty
        ],
        "required": ["requestId", "prompt", "mode"]
    ]

    /// `sessionId` is the one optional property — everything else stays absent
    /// so a bare `{}` call remains valid. [decision: AVB-6]
    public static let statusInputSchema: JSONValue = [
        "type": "object",
        "properties": [
            "sessionId": sessionIdProperty
        ],
        "additionalProperties": false
    ]

    // MARK: - AVB-7 (specs/avb7-durable-calls-design.md)

    /// Unlike every other tool's `sessionId` (optional, advisory), durable calls
    /// REQUIRE a registered session — this is deliberately a different
    /// description from `sessionIdDescription` above. [decision: AVB-7]
    private static let durableCallSessionIdProperty: JSONValue = [
        "type": "string",
        "description": "Required. The sessionId returned by speak_register_session. Call speak_register_session first — unlike other tools, this one fails without a registered session."
    ]

    public static let submitCallInputSchema: JSONValue = [
        "type": "object",
        "properties": [
            "requestId": ["type": "string", "description": "Caller-supplied identifier for this request."],
            "idempotencyKey": [
                "type": "string",
                "description": .string(
                    "Optional. A duplicate submission with the same key while the original is still " +
                    "non-terminal returns the ORIGINAL call instead of creating a second one ('duplicate': true)."
                )
            ],
            "prompt": ["type": "string", "description": "The question or statement to present in the inbox."],
            "mode": [
                "type": "string",
                "enum": ["freeform", "choice", "approval"],
                "description": "freeform: any answer. choice: match one of 'choices'. approval: yes/no."
            ],
            "choices": [
                "type": "array",
                "items": ["type": "string"],
                "description": "Required, non-empty, when mode is 'choice'."
            ],
            "consequence": ["type": "string", "description": "Optional human-readable statement of what answering implies."],
            "spokenSummary": ["type": "string", "description": "Reserved for a future spoken-announcement policy. Not currently spoken — this tool never opens the mic."],
            "urgency": [
                "type": "string",
                "enum": ["low", "normal", "high"],
                "description": "A hint only — never overrides the human's local attention policy or ordering."
            ],
            "expiresInSeconds": [
                "type": "number",
                "description": "Seconds until this call expires if the human never engages it. Defaults to 24 hours when omitted."
            ],
            "sessionId": durableCallSessionIdProperty
        ],
        "required": ["requestId", "prompt", "mode", "sessionId"]
    ]

    public static let getCallInputSchema: JSONValue = [
        "type": "object",
        "properties": [
            "callId": ["type": "string", "description": "The callId returned by speak_submit_call."],
            "sessionId": durableCallSessionIdProperty
        ],
        "required": ["callId", "sessionId"]
    ]

    // MARK: - Layer 4 (specs/agent-voice-bridge.md Layer 4)

    public static let askUserInputSchema: JSONValue = [
        "type": "object",
        "properties": [
            "prompt": [
                "type": "string",
                "description": "The question or prompt to speak and present in the Magenta floating overlay UI."
            ],
            "mode": [
                "type": "string",
                "enum": ["fullDuplex", "pushToTalk", "gatedTurn"],
                "description": "Optional conversation mode for turn-taking (defaults to fullDuplex)."
            ],
            "sessionId": sessionIdProperty
        ],
        "required": ["prompt"]
    ]

    public static let streamSpeechInputSchema: JSONValue = [
        "type": "object",
        "properties": [
            "text": [
                "type": "string",
                "description": "Text content to speak via TTS and render in the streaming overlay UI."
            ],
            "isFinal": [
                "type": "boolean",
                "description": "Whether this speech chunk completes the agent response turn. Defaults to true."
            ],
            "sessionId": sessionIdProperty
        ],
        "required": ["text"]
    ]


    public static let all: [MCPTool] = [
        MCPTool(
            name: "speak_register_session",
            description: "Register this agent session with speak so other tool calls can be attributed " +
                "to it, and negotiate which capabilities are available. Registration identifies a " +
                "routable destination and grants NO access to files, screen contents, dictation history, " +
                "or the microphone. Returns a sessionId to pass as 'sessionId' on subsequent calls — " +
                "optional everywhere else; skipping it preserves today's behavior. Requires speak.app " +
                "to be running.",
            inputSchema: registerSessionInputSchema
        ),
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
        ),
        MCPTool(
            name: "speak_submit_call",
            description: "Durably submit a question to the human's local inbox — no mic opens, no HUD, " +
                "returns immediately. The human answers on their own time from the Dashboard inbox " +
                "(by voice) or declines/dismisses it. Poll speak_get_call for the result. Requires " +
                "speak_register_session first.",
            inputSchema: submitCallInputSchema
        ),
        MCPTool(
            name: "speak_get_call",
            description: "Poll the current state of a call submitted via speak_submit_call: pending, " +
                "presented, or a terminal outcome (answered/declined/cancelled/timedOut/expired). No " +
                "server-side wait — poll on your own interval. Requires speak_register_session first.",
            inputSchema: getCallInputSchema
        ),
        MCPTool(
            name: "speak_ask_user",
            description: "Ask the user a question via speech readback and the Magenta overlay UI. " +
                "Listens for the user's spoken or typed answer and returns it directly to the agent via async continuation (bypassing pasteboard). " +
                "Requires speak.app to be running.",
            inputSchema: askUserInputSchema
        ),
        MCPTool(
            name: "speak_stream_speech",
            description: "Stream agent text response to the TTS engine and update the overlay UI text display. " +
                "Renders readback in real-time and updates conversation loop state.",
            inputSchema: streamSpeechInputSchema
        )
    ]
}
