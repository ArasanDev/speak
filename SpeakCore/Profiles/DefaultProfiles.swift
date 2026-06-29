// SpeakCore/Profiles/DefaultProfiles.swift
//
// The shipped built-in profiles (PT-1 profile taxonomy: specs/profile-taxonomy.md).
// Four destinations (Agent, Write, Note, Raw) replace the flat 7-set. Each system
// prompt is written for a very small (~3B) on-device model and obeys the small-model
// rules (profile-engine.md §6). These are DEFAULTS, not law — AI Studio will let users
// edit them with a "Reset to default" that restores exactly these values.
//
// STABLE IDENTITY: built-ins use fixed UUIDs so "reset to default" and persisted
// per-profile overrides can find a built-in across launches. `stableID(_:)` parses
// a constant UUID string; the `?? allZero` fallback (the non-failable
// `UUID(uuid:)` initializer) keeps us lint-clean (no force-unwrap) while the valid
// literals below always parse, so the fallback never actually triggers.

import Foundation

// MARK: - DefaultProfiles

public enum DefaultProfiles {

    /// All built-ins in overlay/AI-Studio display order: Raw (base-core bypass),
    /// then the three destinations: Agent, Write, Note.
    public static var all: [Profile] {
        [raw, agent, write, note]
    }

    /// The global default profile (ships as `Write`; profile-taxonomy.md §1).
    public static var defaultProfile: Profile { write }

    // MARK: - 0. Raw (base core — not a prompt)

    /// The immutable base-core bypass: empty prompt, `.raw` model → the raw
    /// transcript passes through untouched. Always present, cannot be deleted.
    public static var raw: Profile {
        Profile(
            id: stableID("00000000-0000-0000-0000-0000000000A0"),
            name: "Raw",
            icon: "waveform",
            isBuiltIn: true,
            systemPrompt: "",
            examples: [],
            model: .raw
        )
    }

    // MARK: - 1. Agent (coding agents / dev tools)

    /// Agent destination: for instructions to coding agents, dev tools, and
    /// AI assistants. The base prompt applies before category fragments are appended.
    public static var agent: Profile {
        Profile(
            id: stableID("00000000-0000-0000-0000-0000000000A1"),
            name: "Agent",
            icon: "list.bullet.rectangle",
            isBuiltIn: true,
            systemPrompt: """
            You turn dictated speech into a clear instruction for a coding agent.
            Preserve every technical detail, file name, identifier, and number exactly.
            Remove filler and conversational phrasing; organize rambling thoughts into clear sentences.
            Do NOT perform the task — only rewrite it as a well-formed instruction.
            Output ONLY the structured instruction.
            """,
            examples: [
                Example(
                    spoken: "okay so i need you to first add a login button and then uh wire it to the auth service and also write a test for it",
                    written: """
                    Add a login flow:
                    1. Add a login button.
                    2. Wire it to the auth service.
                    3. Write a test for it.
                    """
                ),
                Example(
                    spoken: "um add type checking for the config loader module",
                    written: "Add type checking for the config loader module."
                )
            ],
            targetApps: [
                "com.anthropic.claudecode",  // Claude Code
                "com.todesktop.230313mzl4w4u92",  // Cursor
                "com.microsoft.VSCode",
                "com.apple.dt.Xcode",
                "dev.zed.zed",
                "com.apple.Terminal",
                "com.googlecode.iterm2",
                "com.gitpod.gitpod",
                "com.anthropic.ai"
            ],
            model: .foundationModels
        )
    }

    // MARK: - 2. Write (prose for humans)

    /// Write destination: for email, Slack, Messages, docs, and other prose
    /// written for human readers. The global default.
    public static var write: Profile {
        Profile(
            id: stableID("00000000-0000-0000-0000-0000000000A2"),
            name: "Write",
            icon: "sparkles",
            isBuiltIn: true,
            systemPrompt: """
            You clean up dictated speech into polished written text.
            Remove filler words (um, uh, like, you know, I mean).
            Fix grammar, punctuation, and capitalization.
            Keep the speaker's meaning and wording — do not add, remove, or answer anything.
            Output ONLY the cleaned text. No preamble, no quotes, no explanation.
            """,
            examples: [
                Example(
                    spoken: "um so i think we should uh meet on tuesday maybe to go over the the budget",
                    written: "I think we should meet on Tuesday to go over the budget."
                ),
                Example(
                    spoken: "yeah send her the file and like let her know it's done",
                    written: "Send her the file and let her know it's done."
                )
            ],
            targetApps: [
                "com.apple.mail",
                "com.tinyspeck.slackmacgap",
                "com.apple.iChat",
                "com.discordapp.Discord",
                "com.google.Chrome",
                "org.mozilla.firefox",
                "com.apple.Safari"
            ],
            model: .foundationModels
        )
    }

    // MARK: - 3. Note (capture for myself)

    /// Note destination: for lists, todos, quick thoughts, and personal notes.
    /// Tidy and concise, without expansion or explanation.
    public static var note: Profile {
        Profile(
            id: stableID("00000000-0000-0000-0000-0000000000A3"),
            name: "Note",
            icon: "note.text",
            isBuiltIn: true,
            systemPrompt: """
            You tidy dictated speech into a concise note, list, or quick-capture format.
            Remove filler words and conversational phrasing.
            Keep entries short and punchy — bullets, one-liners, or minimal prose.
            Do not expand, explain, or answer anything — only tidy the spoken words.
            Output ONLY the tidied note.
            """,
            examples: [
                Example(
                    spoken: "um i need to remember to um call mom tomorrow and also uh pick up the dry cleaning",
                    written: "• Call mom tomorrow\n• Pick up dry cleaning"
                ),
                Example(
                    spoken: "the project deadline is uh friday next week and we need to have the code review done by wednesday",
                    written: "• Project deadline: Friday next week\n• Code review: Wednesday"
                )
            ],
            targetApps: [
                "com.apple.Notes",
                "com.obsproject.obsidian",
                "notion.so",
                "net.shinyfrog.bear"
            ],
            model: .foundationModels
        )
    }

    // MARK: - Stable id helper

    /// Parse a constant UUID string into a stable id. The `?? allZero` fallback uses
    /// the non-failable `UUID(uuid:)` initializer so we stay lint-clean (no force-unwrap);
    /// the literals above are all valid, so the fallback is never reached in practice.
    private static func stableID(_ string: String) -> UUID {
        UUID(uuidString: string) ?? UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
    }
}
