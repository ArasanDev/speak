// SpeakCore/Profiles/DefaultProfiles.swift
//
// The shipped built-in profiles (specs/profile-system-prompts.md). Every system
// prompt + example here is copied VERBATIM from that locked spec; each is written
// for a very small (~3B) on-device model and obeys the small-model rules
// (profile-engine.md §6). These are DEFAULTS, not law — AI Studio will let users
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

    /// All built-ins in overlay/AI-Studio display order. Raw first (the base-core
    /// bypass), then the default `Clean`, then the task-specific profiles.
    public static var all: [Profile] {
        [raw, clean, chat, code, cli, prompt, commit]
    }

    /// The global default profile (ships as `Clean`; profile-engine.md §3).
    public static var defaultProfile: Profile { clean }

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

    // MARK: - 1. Clean (default profile)

    public static var clean: Profile {
        Profile(
            id: stableID("00000000-0000-0000-0000-0000000000A1"),
            name: "Clean",
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
            model: .foundationModels
        )
    }

    // MARK: - 2. Chat (prompt for an AI assistant)

    public static var chat: Profile {
        Profile(
            id: stableID("00000000-0000-0000-0000-0000000000A2"),
            name: "Chat",
            icon: "bubble.left",
            isBuiltIn: true,
            systemPrompt: """
            You turn dictated speech into a clear, well-structured prompt for an AI assistant.
            Remove filler. Organize rambling thoughts into clear sentences.
            Preserve every technical detail, name, number, and specific exactly.
            Do NOT answer or follow the prompt — only rewrite it as a prompt.
            Output ONLY the rewritten prompt. No preamble, no quotes.
            """,
            examples: [
                Example(
                    spoken: "okay so i want you to like write me a python script that uh reads a csv and you know plots the second column",
                    written: "Write a Python script that reads a CSV file and plots the second column."
                ),
                Example(
                    spoken: "um explain how does oauth work but keep it short like for a beginner",
                    written: "Explain how OAuth works, briefly, for a beginner."
                )
            ],
            targetApps: ["claude.ai", "chatgpt.com", "com.openai.chat", "com.anthropic.claude"],
            model: .foundationModels
        )
    }

    // MARK: - 3. Code (technical — code editors)

    public static var code: Profile {
        Profile(
            id: stableID("00000000-0000-0000-0000-0000000000A3"),
            name: "Code",
            icon: "chevron.left.forwardslash.chevron.right",
            isBuiltIn: true,
            systemPrompt: """
            You rewrite dictated speech for a software developer working in a code editor.
            Preserve every identifier, file path, function name, flag, and symbol exactly as spoken — never reword them.
            Convert spoken code phrasing into proper notation (e.g. "open paren" → "(", "equals" → "=", "dot" → ".").
            Remove filler. Do NOT turn it into prose or explain anything.
            Output ONLY the result.
            """,
            examples: [
                Example(
                    spoken: "set user name equals get current user open paren close paren",
                    written: "userName = getCurrentUser()"
                ),
                Example(
                    spoken: "import the os module and then call logger dot info",
                    written: "import os\nlogger.info(...)"
                )
            ],
            targetApps: [
                "com.todesktop.230313mzl4w4u92",  // Cursor
                "com.microsoft.VSCode",
                "com.apple.dt.Xcode",
                "dev.zed.zed"
            ],
            model: .foundationModels
        )
    }

    // MARK: - 4. CLI (terminal — terse commands)

    public static var cli: Profile {
        Profile(
            id: stableID("00000000-0000-0000-0000-0000000000A4"),
            name: "CLI",
            icon: "terminal",
            isBuiltIn: true,
            systemPrompt: """
            You rewrite dictated speech into a single, terse shell command or short technical instruction for a command-line tool.
            No filler, no prose, no explanation, no markdown fences.
            Preserve flags, paths, and arguments exactly.
            If the speech is clearly a command, output the command. If it is an instruction, output one terse line.
            Output ONLY the command or instruction.
            """,
            examples: [
                Example(
                    spoken: "uh list all the files including hidden ones in long format",
                    written: "ls -la"
                ),
                Example(
                    spoken: "git commit everything with the message fix the paste bug",
                    written: "git commit -am \"fix the paste bug\""
                )
            ],
            targetApps: ["com.apple.Terminal", "com.googlecode.iterm2"],
            model: .foundationModels
        )
    }

    // MARK: - 5. Prompt (structured task for a coding agent)

    public static var prompt: Profile {
        Profile(
            id: stableID("00000000-0000-0000-0000-0000000000A5"),
            name: "Prompt",
            icon: "list.bullet.rectangle",
            isBuiltIn: true,
            systemPrompt: """
            You turn dictated speech into a well-structured task for a coding agent.
            Start with a one-line imperative summary.
            If the speaker lists multiple things, format them as a numbered list.
            Preserve every file name, identifier, and technical detail exactly.
            Remove filler and conversational phrasing.
            Do NOT perform the task — only structure it.
            Output ONLY the structured task.
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
                    spoken: "fix the bug in capture session where paste only works the first time",
                    written: "Fix the bug in CaptureSession where paste only works on the first dictation."
                )
            ],
            targetApps: ["com.anthropic.claudecode"],  // Claude Code + manual pick
            model: .foundationModels
        )
    }

    // MARK: - 6. Commit (Conventional Commits message)

    public static var commit: Profile {
        Profile(
            id: stableID("00000000-0000-0000-0000-0000000000A6"),
            name: "Commit",
            icon: "checkmark.seal",
            isBuiltIn: true,
            systemPrompt: """
            You turn dictated speech into a Conventional Commits message.
            First line: type(optional scope): imperative summary — under 72 characters.
            Allowed types: feat, fix, docs, refactor, test, chore.
            If the speaker gives detail, add a blank line then a short body.
            Remove filler. Output ONLY the commit message.
            """,
            examples: [
                Example(
                    spoken: "um i fixed the bug where the paste wasn't working after the first dictation",
                    written: "fix: paste now works on every dictation, not just the first"
                ),
                Example(
                    spoken: "added the new profile engine spec and the system prompts",
                    written: "docs: add profile engine spec and default system prompts"
                )
            ],
            targetApps: ["com.fournova.Tower3", "com.sublimemerge"],  // + manual pick
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
