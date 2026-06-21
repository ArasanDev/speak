// SpeakCore/Cleanup/FoundationModelsCleaner.swift
//
// v0 default implementation of `LLMCleaning` using Apple's Foundation Models
// framework (macOS 26, Apple Silicon + Neural Engine). This is an Apple
// framework — it does NOT violate the no-third-party-deps rule (AGENTS.md §2.9).
//
// API verified [verified] against arm64e-apple-macos.swiftinterface in
// FoundationModels.framework (macOS 26 SDK, Xcode) on 2026-06-20:
//   - SystemLanguageModel.default: static var, non-optional [verified]
//   - SystemLanguageModel.availability: enum { .available, .unavailable(UnavailableReason) } [verified]
//   - SystemLanguageModel.isAvailable: Bool (direct property) [verified]
//   - UnavailableReason cases: deviceNotEligible, appleIntelligenceNotEnabled, modelNotReady [verified]
//   - LanguageModelSession.init(model:guardrails:instructions:) [verified]
//   - LanguageModelSession.respond(to:String, options:) async throws -> Response<String> [verified]
//   - Response<String>.content: String [verified]
//   - LanguageModelSession.GenerationError: exhaustive enum of API errors [verified]
//
// Session lifecycle: a fresh LanguageModelSession is created per clean() call
// so that (a) mode-specific instructions can be injected at init (the idiomatic
// system-prompt slot), and (b) dictation history from earlier sessions cannot
// bias later ones or push the context window past `exceededContextWindowSize`.
// Architecture §10a.2 says "reuse across dictations" — this deviates from that
// guidance deliberately: for a stateless transform, per-call sessions are more
// correct. Reuse is appropriate for multi-turn conversations, not cleanup.
// [decision] Revisit in P13 dogfood if per-call latency budgets are not met.
//
// Guardrails: `.permissiveContentTransformations` is used instead of the default
// guardrails so that ordinary dictation about sensitive topics (code, security,
// medicine, legal) is not spuriously refused during cleanup. Cleanup is a content
// transformation, not content generation. [decision] — see architecture §10a.2.

import Foundation
import FoundationModels
import os

@available(macOS 26.0, *)
public final class FoundationModelsCleaner: LLMCleaning, Sendable {

    // MARK: - LLMCleaning conformance

    /// The stable identifier for this engine, written to `TranscriptionResult.engineId`
    /// when cleanup runs.
    public let id = "foundation-models"

    /// Returns `true` when the on-device Foundation Models engine is ready to accept
    /// requests. Uses `SystemLanguageModel.default.availability` (enum form) rather
    /// than `.isAvailable` (Bool) so we can log the `UnavailableReason` for diagnostics.
    ///
    /// Checked once per `CaptureSession` processing pass; **not** cached across sessions.
    /// `isAvailable == false` is never an error — the caller falls back to raw transcript.
    public var isAvailable: Bool {
        get async {
            let availability = SystemLanguageModel.default.availability
            switch availability {
            case .available:
                SpeakLog.cleanup.info("FoundationModelsCleaner: model available")
                return true
            case .unavailable(let reason):
                let reasonDescription = String(describing: reason)
                SpeakLog.cleanup.warning(
                    "FoundationModelsCleaner: model unavailable — reason: \(reasonDescription, privacy: .public)"
                )
                return false
            }
        }
    }

    /// Cleans the raw transcript using the on-device Foundation Models engine.
    ///
    /// - Parameters:
    ///   - text: The raw transcript to clean.
    ///   - mode: Controls what kind of cleanup is applied.
    /// - Returns: The cleaned transcript as a non-optional `String`.
    /// - Throws: `SpeakError.llmCleanupFailed` on a genuine API failure.
    ///   Unavailability is **not** signalled here — the caller must check
    ///   `isAvailable` before calling this method and fall back to raw text.
    public func clean(_ text: String, mode: CleanupMode) async throws -> String {
        let systemInstructions = Self.instructions(for: mode)

        // Fresh session per call: mode-specific instructions set at init (the
        // system-prompt slot), no cross-dictation context leakage. [decision]
        // permissiveContentTransformations: avoids spurious refusals on dictation
        // about sensitive topics (security, medical, legal). [decision]
        let model = SystemLanguageModel(
            useCase: .general,
            guardrails: .permissiveContentTransformations
        )
        let session = LanguageModelSession(
            model: model,
            instructions: systemInstructions
        )

        let modeDescription = String(describing: mode)
        let charCount = text.count
        SpeakLog.cleanup.debug("FoundationModelsCleaner: cleaning \(charCount, privacy: .public) chars")
        SpeakLog.cleanup.debug("FoundationModelsCleaner: mode=\(modeDescription, privacy: .public)")

        do {
            let response = try await session.respond(to: text)
            let cleaned = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            SpeakLog.cleanup.debug(
                "FoundationModelsCleaner: cleaned to \(cleaned.count, privacy: .public) chars"
            )
            return cleaned
        } catch let genError as LanguageModelSession.GenerationError {
            let detail = genError.localizedDescription
            SpeakLog.cleanup.error(
                "FoundationModelsCleaner: GenerationError — \(detail, privacy: .public)"
            )
            throw SpeakError.llmCleanupFailed(detail)
        } catch {
            let detail = error.localizedDescription
            SpeakLog.cleanup.error(
                "FoundationModelsCleaner: unexpected error — \(detail, privacy: .public)"
            )
            throw SpeakError.llmCleanupFailed(detail)
        }
    }

    // MARK: - Prompt construction

    /// Returns the system instructions string for the given cleanup mode.
    /// Inlined here (not in `SpeakLLM/`) because `SpeakLLM/` targets the
    /// Ollama v0.1 engine and is a separate module not available in SpeakCore.
    /// `internal` (not `private`) so the prompt mapping is unit-testable without a
    /// live Foundation Models pass (StyleModeTests). [decision Wave B]
    static func instructions(for mode: CleanupMode) -> String {
        switch mode {

        case .fillersOnly:
            return """
                You are a transcript editor. Remove filler words and sounds \
                (um, uh, like, you know, kind of, sort of, right, okay when used \
                as a filler, hmm). Do not change the meaning, vocabulary, or structure \
                of the transcript in any other way. Return only the edited transcript \
                with no commentary, no quotes, and no introduction.
                """

        case .punctuation:
            return """
                You are a transcript editor. Convert the raw spoken transcript into \
                clean, grammatically correct written text. Add appropriate punctuation \
                (periods, commas, question marks, exclamation marks). Fix capitalization \
                at sentence boundaries and for proper nouns. Remove filler words \
                (um, uh, like, you know, kind of, sort of, hmm). Do not paraphrase \
                or change the speaker's meaning or vocabulary. Return only the cleaned \
                text with no commentary, no quotes, and no introduction.
                """

        case .codeAware:
            return """
                You are a transcript editor for a software developer. The transcript \
                may contain code-related terms: variable names, function names, \
                method names, technical acronyms, command-line flags, and file paths. \
                Clean the transcript by: adding punctuation, fixing capitalization at \
                sentence boundaries, removing filler words (um, uh, like, you know). \
                Preserve technical identifiers verbatim — do not autocorrect, \
                camelCase, or alter technical terms. If the speaker says "capital H" \
                or spells something out, preserve that intent. Return only the cleaned \
                text with no commentary, no quotes, and no introduction.
                """

        case .toneAdjust:
            return """
                You are a transcript editor. Convert the raw spoken transcript into \
                polished professional prose suitable for written communication. Fix \
                punctuation, capitalization, and grammar. Remove filler words \
                (um, uh, like, you know). Smooth out informal phrasing and sentence \
                fragments into complete, well-formed sentences. Preserve the speaker's \
                meaning and key vocabulary. Return only the refined text with no \
                commentary, no quotes, and no introduction.
                """

        case .translate(let locale):
            // Use the locale's language display name if available; fall back to
            // the locale identifier so the prompt is always unambiguous.
            // [inferred] The LLM can follow language instructions from the locale
            // identifier; no translation API is needed. Quality verified empirically
            // in P13 dogfood for non-English locales.
            let languageName = Locale.current.localizedString(forIdentifier: locale.identifier)
                ?? locale.identifier
            return """
                You are a professional translator and transcript editor. Translate the \
                following spoken transcript into \(languageName). Preserve the speaker's \
                meaning and tone. Apply correct punctuation and capitalization for the \
                target language. Remove filler words from the source if they do not \
                translate meaningfully. Return only the translated text with no \
                commentary, no quotes, and no introduction.
                """

        case .styled(let style, let level):
            // Wave B: compose a writing voice (style) with a polish intensity (level).
            // The base task + footer are shared; the voice and the intensity are the
            // two variable clauses. Kept as composed strings (not a fixed table) so a
            // new style or level is one clause, not a combinatorial rewrite.
            return Self.styledInstructions(style: style, level: level)

        case .command(let instruction):
            // Wave D Command Mode: apply the user's spoken instruction to their selection.
            return Self.commandInstructions(instruction: instruction)
        }
    }

    /// System instructions for Command Mode: apply the spoken `instruction` to the
    /// highlighted text (passed as the `respond(to:)` argument). The instruction is
    /// echoed verbatim so the model edits per the user's exact request.
    static func commandInstructions(instruction: String) -> String {
        let trimmed = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        return """
            You are a text editor. The user has selected some text and given you this \
            instruction: "\(trimmed)". Apply that instruction to the text and return ONLY \
            the resulting text — no commentary, no quotes, no preamble. If the instruction \
            asks a question rather than an edit, answer concisely in place of the text.
            """
    }

    /// Compose the system instructions for a `.styled(style, level)` mode.
    /// `style` selects the voice clause; `level` selects how aggressively to rewrite.
    /// `internal` for unit-test access (StyleModeTests). [decision Wave B]
    static func styledInstructions(style: CleanupStyle, level: CleanupLevel) -> String {
        let voice: String
        switch style {
        case .default:
            voice = "Convert the raw spoken transcript into clean, natural written text, " +
                    "preserving the speaker's own wording and voice."
        case .professional:
            voice = "Convert the raw spoken transcript into polished, professional prose " +
                    "suitable for written workplace communication. Smooth informal phrasing " +
                    "and sentence fragments into complete, well-formed sentences."
        case .casual:
            voice = "Convert the raw spoken transcript into relaxed, friendly written text. " +
                    "Keep it conversational and natural — contractions are welcome — without " +
                    "sounding stiff or formal."
        case .code:
            voice = "Convert the raw spoken transcript into clean written text for a software " +
                    "developer. Preserve technical identifiers verbatim — variable, function, " +
                    "and method names, acronyms, command-line flags, and file paths. Do not " +
                    "autocorrect, camelCase, or alter technical terms. Honor spelled-out or " +
                    "\"capital H\" intent."
        case .email:
            voice = "Convert the raw spoken transcript into a clear, courteous email body. " +
                    "Organize the thoughts into coherent sentences and short paragraphs with " +
                    "a natural greeting/closing only if the speaker dictated one — do not " +
                    "invent recipients, subjects, or signatures."
        }

        let intensity: String
        switch level {
        case .basic:
            intensity = "Apply a light touch: add punctuation and fix capitalization, and " +
                        "remove only obvious filler sounds (um, uh, hmm). Otherwise leave the " +
                        "speaker's words and structure intact."
        case .balanced:
            intensity = "Apply standard cleanup: correct punctuation, capitalization, and " +
                        "grammar, and remove filler words (um, uh, like, you know, kind of, " +
                        "sort of). Do not paraphrase or change the speaker's meaning."
        case .thorough:
            intensity = "Apply a thorough polish: in addition to punctuation, capitalization, " +
                        "grammar, and filler removal, tighten rambling phrasing and redundancy " +
                        "into concise, well-structured prose — while preserving the speaker's " +
                        "meaning and key vocabulary."
        }

        return """
            You are a transcript editor. \(voice) \(intensity) Return only the edited \
            text with no commentary, no quotes, and no introduction.
            """
    }

    // MARK: - Init

    /// Creates a new `FoundationModelsCleaner`. Lightweight — no model is loaded
    /// at init time. The on-device engine is invoked only when `clean()` is called.
    public init() {}
}
