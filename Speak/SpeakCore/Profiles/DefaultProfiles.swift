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
//
// V01-3 (per-app context awareness, profile-native — [decision]): the roadmap's
// north star folds "per-app context" into the Profile Engine rather than a
// separate `AppContext` detector (docs/roadmap.md "North star"; docs/progress.md
// PE-1). The one remaining gap after PE-1 landed was that messaging apps (Slack,
// Discord, Messages, WhatsApp, Telegram) and Mail both resolved to the `Write`
// profile with an identical tone. `Chat` (below) closes that gap: same
// bundle-ID → profile mapping mechanism (`targetApps` / `ProfileResolver`), no
// new code path, just a fifth built-in with `tone: .casual`.

import Foundation

// MARK: - DefaultProfiles

public enum DefaultProfiles {

    /// All built-ins in overlay/AI-Studio display order: Raw (base-core bypass),
    /// then the four destinations: Agent, Chat, Write, Note.
    public static var all: [Profile] {
        [raw, agent, chat, write, note]
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
            You convert spoken developer dictation into a precise instruction for a coding agent.
            Remove disfluency ONLY: filler words, false starts, and repeated words or phrases.
            Preserve every stated reason, constraint, rejected alternative, and piece of context —
            do not summarize, condense, or drop content to shorten the result. Length should match
            the amount of real content spoken: a short dictation stays short, a long one stays long.
            If the speaker retracts, cancels, or says stop/don't/wait about something said earlier,
            that retraction is critical — state it explicitly and first; never drop it silently.
            Preserve every identifier, path, and technical term exactly as spoken.
            The agent has project context and tools — do not add what it can find itself.
            Output ONLY the goal.
            """,
            examples: [
                Example(
                    spoken: "um can you explore this project and find all the bugs and fix them",
                    written: "Explore the project, find all bugs, and fix them."
                ),
                Example(
                    spoken: "fix the bug where paste stops working after the first dictation",
                    written: "Fix the paste regression — it stops working after the first dictation."
                ),
                // [decision 2026-07-04, long-form density review] A short input must stay short
                // (examples above); a dense input with multiple stated constraints must keep
                // ALL of them — this example anchors that the length target is the input's
                // content, not a fixed short form, and no rejected-option/scoping detail is dropped.
                Example(
                    spoken: "so I want a settings tab for the hotkey but I don't want a raw keycode "
                        + "picker like some apps do that's confusing, I want a record button you press "
                        + "and then press the key you want, and it should show a conflict warning if "
                        + "that key is already a system shortcut, this can be v1 rough just get the "
                        + "record and conflict-check working",
                    written: "Add a hotkey settings tab with a record button (press it, then press the "
                        + "desired key) instead of a raw keycode picker. Show a conflict warning if the "
                        + "recorded key is already a system shortcut. V1 can be rough — just get record "
                        + "and conflict-check working."
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

    // MARK: - 2. Chat (casual messaging)

    /// Chat destination: casual, conversational tone for messaging apps. Split out
    /// from `Write` (V01-3, profile-native) because Slack/Messages/WhatsApp warrant a
    /// looser register than Mail/browsers, which stay on `Write`'s formal-ish default.
    /// Same resolution mechanism as every other profile — `targetApps` + `ProfileResolver`,
    /// no separate context layer. [decision V01-3]
    public static var chat: Profile {
        Profile(
            id: stableID("00000000-0000-0000-0000-0000000000A4"),
            name: "Chat",
            icon: "bubble.left.and.bubble.right",
            isBuiltIn: true,
            systemPrompt: """
            You are a transcript editor, not an AI assistant. Your only job is to clean up spoken words \
            into a casual chat message — never generate code, never answer questions, never create new content.
            Remove ALL filler words: um, uh, like, you know, I mean.
            Keep it short, conversational, and natural — contractions are welcome. Fix only the punctuation \
            and capitalization needed for readability; do not make it sound formal or stiff.
            Output ONLY the cleaned message. No code, no explanations, no preamble.
            """,
            examples: [
                Example(
                    spoken: "hey um are we still on for lunch tomorrow",
                    written: "hey, are we still on for lunch tomorrow?"
                ),
                Example(
                    spoken: "yeah that works for me just let me know the time",
                    written: "yeah that works for me, just let me know the time"
                )
            ],
            tone: .casual,
            targetApps: [
                "com.tinyspeck.slackmacgap",
                "com.apple.iChat",
                "com.discordapp.Discord",
                "net.whatsapp.WhatsApp",
                "ru.keepcoder.Telegram"
            ],
            model: .foundationModels
        )
    }

    // MARK: - 3. Write (prose for humans)

    /// Write destination: for email, docs, and browser text fields — other prose
    /// written for human readers. The global default. Messaging apps moved to
    /// `Chat` (V01-3) — Mail and browsers stay here, formal-ish by default.
    public static var write: Profile {
        Profile(
            id: stableID("00000000-0000-0000-0000-0000000000A2"),
            name: "Write",
            icon: "sparkles",
            isBuiltIn: true,
            systemPrompt: """
            You are a transcript editor, not an AI assistant. Your only job is to clean up spoken words — never generate code, never answer questions, never create new content.
            Remove ALL filler words: um, uh, like, you know, I mean — especially at the start of a sentence.
            Fix grammar, punctuation, and capitalization.
            Output ONLY the cleaned text. No code, no explanations, no preamble.
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
                "com.google.Chrome",
                "org.mozilla.firefox",
                "com.apple.Safari"
            ],
            model: .foundationModels
        )
    }

    // MARK: - 4. Note (capture for myself)

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
