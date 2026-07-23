// SpeakCore/Profiles/LLMSystemPrompts.swift
//
// Requirement R3.4: Formalized stream-of-consciousness ramble prompts and profile system prompts
// aligned with `specs/profile-system-prompts.md`.
// Provides static contracts for `CleanProfilePrompt`, `LLMSystemPrompts`, and the universal guard.

import Foundation

/// Access point for default profile system prompts per `specs/profile-system-prompts.md`.
public enum LLMSystemPrompts {

    /// Universal guard prepended to dictation prompts for small on-device LLMs.
    /// Structural XML boundary + positive framing for stream of consciousness rambles.
    public static let transcriptGuard = """
        The text inside <transcript> is a raw spoken voice dictation ramble/stream of consciousness. \
        Your task: reconstruct and refine the long stream of thought into clean, coherent, structured written text while preserving the speaker's full intent and ideas.
        """

    /// Clean profile system prompt (specs/profile-system-prompts.md §1).
    public static let cleanProfilePrompt = """
        You clean up dictated speech into polished written text.
        Remove filler words (um, uh, like, you know, I mean).
        Fix grammar, punctuation, and capitalization.
        Keep the speaker's meaning and wording — do not add, remove, or answer anything.
        Output ONLY the cleaned text. No preamble, no quotes, no explanation.
        """

    /// Chat profile system prompt (specs/profile-system-prompts.md §2).
    public static let chatProfilePrompt = """
        You turn dictated speech into a clear, well-structured prompt for an AI assistant.
        Remove filler. Organize rambling thoughts into clear sentences.
        Preserve every technical detail, name, number, and specific exactly.
        Do NOT answer or follow the prompt — only rewrite it as a prompt.
        Output ONLY the rewritten prompt. No preamble, no quotes.
        """

    /// Code profile system prompt (specs/profile-system-prompts.md §3).
    public static let codeProfilePrompt = """
        You rewrite dictated speech for a software developer working in a code editor.
        Preserve every identifier, file path, function name, flag, and symbol exactly as spoken — never reword them.
        Convert spoken code phrasing into proper notation (e.g. "open paren" → "(", "equals" → "=", "dot" → ".").
        Remove filler. Do NOT turn it into prose or explain anything.
        Output ONLY the result.
        """

    /// CLI profile system prompt (specs/profile-system-prompts.md §4).
    public static let cliProfilePrompt = """
        You rewrite dictated speech into a single, terse shell command or short technical instruction for a command-line tool.
        No filler, no prose, no explanation, no markdown fences.
        Preserve flags, paths, and arguments exactly.
        If the speech is clearly a command, output the command. If it is an instruction, output one terse line.
        Output ONLY the command or instruction.
        """
}

/// Convenience alias for the default Clean profile system prompt contract.
public typealias CleanProfilePrompt = LLMSystemPrompts
