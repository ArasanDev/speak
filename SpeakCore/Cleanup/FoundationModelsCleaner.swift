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
//   - SystemLanguageModel(useCase:guardrails:) two-step pattern with guardrails on the model [verified]
//   - UnavailableReason cases: deviceNotEligible, appleIntelligenceNotEnabled, modelNotReady [verified]
//   - LanguageModelSession.init(model:instructions:Instructions?) — typed API [verified]
//   - LanguageModelSession.respond(to:Prompt) async throws -> Response<String> — typed API [verified]
//   - Response<String>.content: String [verified]
//   - LanguageModelSession.GenerationError: non-@frozen enum, exhaustive switches need @unknown default [verified]
//   - UnavailableReason: non-@frozen enum [verified]
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

    // [Cleanup-H1] Single shared model instance — ensures `isAvailable` and `clean()`
    // check the same `SystemLanguageModel`. If availability is gated per-guardrail
    // config, using separate instances risks a false-available: `isAvailable` → true,
    // `clean()` → throws `assetsUnavailable`.
    private let model = SystemLanguageModel(
        useCase: .general,
        guardrails: .permissiveContentTransformations
    )

    /// Returns `true` when the on-device Foundation Models engine is ready to accept
    /// requests. Uses the shared `model`'s `.availability` (enum form) rather than
    /// `.isAvailable` (Bool) so we can log the `UnavailableReason` for diagnostics.
    ///
    /// Checked once per `CaptureSession` processing pass; **not** cached across sessions.
    /// `isAvailable == false` is never an error — the caller falls back to raw transcript.
    public var isAvailable: Bool {
        get async {
            let availability = model.availability
            switch availability {
            case .available:
                SpeakLog.cleanup.debug("FoundationModelsCleaner: model available")
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
        // permissiveContentTransformations applied via `model` ivar. [Cleanup-H1]
        // [Cleanup-M2] Use typed Instructions / Prompt APIs to avoid the
        // @_disfavoredOverload String-based paths. String conforms to
        // InstructionsRepresentable + PromptRepresentable, so the values are identical.
        // [verified: SDK String conformances, arm64e-apple-macos.swiftinterface, 2026-06-26]
        let session = LanguageModelSession(
            model: model,
            instructions: Instructions(systemInstructions)
        )

        let modeDescription = String(describing: mode)
        let charCount = text.count
        SpeakLog.cleanup.debug("FoundationModelsCleaner: cleaning \(charCount, privacy: .public) chars")
        SpeakLog.cleanup.debug("FoundationModelsCleaner: mode=\(modeDescription, privacy: .public)")

        // Wrap in XML tags so the model treats the content as data to edit,
        // not as a conversational turn. Structural signal beats negative instructions
        // ("do NOT answer") for small on-device LLMs. [decision 2026-06-27]
        let wrappedText = Self.wrapTranscript(text)
        do {
            let response = try await session.respond(to: Prompt(wrappedText))  // [Cleanup-M2]
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

    /// Universal guard prepended to every mode's system instructions.
    ///
    /// Small on-device LLMs are RLHF-trained to be conversational — negative
    /// instructions ("do NOT answer") are consistently the weakest instruction type
    /// and get overridden by the model's training reflex to respond to questions.
    /// Fix: positive-only framing ("your output is ONLY the edited text") + XML
    /// wrapping of the input so the model treats it as data, not a conversational turn.
    /// [decision: positive framing + structural XML boundary beats negative instructions
    ///  for small on-device models; see research finding 2026-06-27]
    private static let transcriptGuard = """
        You are a transcript editing function. \
        You receive raw spoken words inside <transcript> tags. \
        Your output is ALWAYS and ONLY the edited version of those spoken words — \
        plain text, nothing else. \
        One task only: clean and format the text per the instructions below. \
        Output format: the edited transcript text, no tags, no explanation, no preamble.
        """

    /// Wraps the raw transcript in XML tags so the model treats it as data,
    /// not as a conversational turn directed at itself.
    /// [decision: XML boundary is a structural signal that outperforms negative
    ///  instructions ("do not answer") for small on-device models]
    static func wrapTranscript(_ text: String) -> String {
        "<transcript>\(text)</transcript>"
    }

    /// Returns the system instructions string for the given cleanup mode.
    /// Inlined here (not in `SpeakLLM/`) because `SpeakLLM/` targets the
    /// Ollama v0.1 engine and is a separate module not available in SpeakCore.
    /// `internal` (not `private`) so the prompt mapping is unit-testable without a
    /// live Foundation Models pass (StyleModeTests). [decision Wave B]
    static func instructions(for mode: CleanupMode) -> String {
        return transcriptGuard + "\n\n" + modeInstructions(for: mode)
    }

    /// Mode-specific instructions without the universal guard. Separated so
    /// unit tests can assert mode-specific prompt content in isolation.
    static func modeInstructions(for mode: CleanupMode) -> String {
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

        case .styled(let style, let level, let customVocabulary):
            // Wave B / Wave 2.2: compose a writing voice (style), a polish intensity
            // (level), and an optional "preserve these spellings" clause derived from
            // the user's custom-dictionary terms. Kept as composed strings (not a
            // fixed table) so a new style, level, or vocabulary is one clause.
            return Self.styledInstructions(style: style, level: level, customVocabulary: customVocabulary)

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

    /// Compose the system instructions for a `.styled(style, level, customVocabulary:)` mode.
    /// `style` selects the voice clause; `level` selects how aggressively to rewrite;
    /// `customVocabulary` (default `[]`) injects a "preserve these spellings" clause so the
    /// model does not mangle proper nouns, technical terms, or non-standard spellings the user
    /// has registered. When the list is empty the clause is omitted entirely, producing a
    /// byte-identical prompt to the pre-Wave-2.2 baseline — no regression for existing tests
    /// or users without vocabulary entries. [decision Wave 2.2]
    /// `internal` for unit-test access (StyleModeTests, CustomVocabularyPromptTests). [decision Wave B]
    static func styledInstructions(style: CleanupStyle, level: CleanupLevel,
                                   customVocabulary: [String] = []) -> String {
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

        // W4.1 — 4-level intensity ladder. Each clause is named here for traceability
        // (test assertions target the quoted phrases). [decision W4.1: distinct named
        // clauses, not interpolated, so each level is independently unit-testable]
        let intensity: String
        switch level {
        case .none:
            // .none means "no model call" — SpeakEngine.newSession() never passes the
            // cleaner when level==.none, so this branch is unreachable in production.
            // It is included for exhaustive switch coverage and defensive safety: if
            // somehow called, return a no-op instruction rather than crashing. [decision]
            // [Cleanup-L3] Log the regression rather than assertionFail: tests legitimately
            // exercise allCases including .none (StyleModeTests). assertionFailure would
            // crash the test process rather than produce a meaningful failure message.
            SpeakLog.cleanup.warning("styledInstructions called with .none — SpeakEngine should short-circuit before reaching the cleaner")
            intensity = "Return the text exactly as provided, with no changes whatsoever."
        case .light:
            // Light: filler-word removal + punctuation only. Minimal rewriting.
            // [decision W4.1: "light touch" is the distinguishing phrase tested in
            //  CleanupIntensityTests.testLightLevelIsLightTouch()]
            intensity = "Apply a light touch: add punctuation and fix capitalization, and " +
                        "remove only obvious filler sounds (um, uh, hmm). Otherwise leave the " +
                        "speaker's words and structure intact."
        case .medium:
            // Medium: filler removal + punctuation + sentence tightening.
            // [decision W4.1: "sentence tightening" is the distinguishing phrase tested]
            intensity = "Apply standard cleanup: correct punctuation, capitalization, and " +
                        "grammar, remove filler words (um, uh, like, you know, kind of, sort of), " +
                        "and tighten run-on sentences. Do not paraphrase or change the speaker's meaning."
        case .high:
            // High: full restructuring including paragraph breaks. The most aggressive level.
            // [decision W4.1: "paragraph" and "restructure" are the distinguishing phrases tested]
            intensity = "Apply a thorough polish: in addition to punctuation, capitalization, " +
                        "grammar, and filler removal, tighten rambling phrasing and redundancy " +
                        "into concise, well-structured prose, and restructure the text into logical " +
                        "paragraphs where appropriate — while preserving the speaker's meaning and " +
                        "key vocabulary."
        }

        // Wave 2.2 — custom vocabulary clause. Injected only when non-empty so the
        // prompt for users with no vocabulary entries is byte-identical to the pre-2.2
        // baseline. The clause instructs the model to preserve exact spellings and
        // capitalisation for the listed terms, complementing the STT-side biasing already
        // applied via AnalysisContext.contextualStrings. [decision Wave 2.2]
        let vocabularyClause: String
        if customVocabulary.isEmpty {
            vocabularyClause = ""
        } else {
            // Format terms as a comma-separated list enclosed in double quotes for
            // maximum model clarity. Limiting to the first 50 terms avoids an
            // excessively long system prompt on large dictionaries. [decision: 50-term
            // cap — all 50 fit comfortably in the system-prompt context window; users
            // with >50 terms need the highest-priority ones first (UI responsibility).]
            // [Cleanup-L2] Log when vocabulary is truncated so the user-facing symptom
            // (unlisted terms not preserved) is diagnosable without guessing.
            if customVocabulary.count > 50 {
                SpeakLog.cleanup.debug(
                    "FoundationModelsCleaner: vocabulary truncated \(customVocabulary.count, privacy: .public) → 50 terms (system-prompt cap)."
                )
            }
            let terms = customVocabulary.prefix(50)
                .map { "\"\($0)\"" }
                .joined(separator: ", ")
            vocabularyClause = " The following terms must be preserved exactly as spelled, " +
                               "including their capitalisation: \(terms)."
        }

        return """
            You are a transcript editor. \(voice) \(intensity)\(vocabularyClause) Return only \
            the edited text with no commentary, no quotes, and no introduction.
            """
    }

    // MARK: - Init

    /// Creates a new `FoundationModelsCleaner`. Lightweight — no model is loaded
    /// at init time. The on-device engine is invoked only when `clean()` is called.
    public init() {}
}
