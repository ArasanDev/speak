// SpeakCore/Conversation/EndpointDecider.swift
//
// Decides HOW LONG to wait after speech stops before declaring the human's
// turn over.
//
// Why this file is the first thing built in VA-1: `make measure-latency`
// measured the loop at ~1117 ms from "human stops talking" to "human hears
// something", and 600 ms of that — 54% — is not compute at all. It is the
// fixed silence window in `VoiceActivityDetector.Configuration`. Dead air we
// impose on ourselves. Nothing else on the board is worth ~400 ms.
// (`specs/voice-agent-design.md` §5.)
//
// THE SAFETY PROPERTY, WHICH IS THE WHOLE DESIGN
// This returns an adaptive *window*, never a binary "fire now". It can make the
// window shorter than today's 600 ms when the transcript looks finished, and —
// just as importantly — LONGER when it looks unfinished. Truncating someone
// mid-sentence is a far worse failure than making them wait: waiting costs
// 400 ms, truncation costs the whole utterance and the user's trust in the
// feature. So every path that is uncertain returns exactly today's behaviour,
// which makes the worst case "no change" rather than "new bug".
//
// WHAT THE SIGNALS ARE WORTH — measured, not assumed (E6, `make probe-partials`)
// • Volatile results DO carry punctuation: `"The meeting is at 3."` arrived as
//   a volatile 174 ms before its matching final. So the partial stream is a
//   usable source. [verified]
// • Punctuation on a FINAL is worthless as a completeness signal: finalization
//   punctuates unconditionally. The deliberately unfinished "…numbers and" came
//   back finalized as "…numbers, Anne." — hallucinated word, appended period.
//   Only punctuation seen on a volatile means anything, because there the model
//   chose to close a sentence it could still have extended. [verified]
// That asymmetry is why `isVolatile` is a parameter and not an afterthought.
//
// Pure and synchronous on purpose: no audio, no model, no clock, no I/O. It is
// a function from (text, volatility) to a duration, which makes the entire
// policy unit-testable without a microphone.

import Foundation

/// The window to wait, plus why — the reason exists so a bad endpoint decision
/// can be explained from a log instead of guessed at.
public struct EndpointDecision: Equatable, Sendable {

    /// Why this window was chosen.
    public enum Reason: String, Sendable, CaseIterable {
        /// Transcript looks like a finished sentence — shorten.
        case complete
        /// Nothing informative either way — today's behaviour, unchanged.
        case neutral
        /// Transcript ends mid-thought — lengthen, the human is still going.
        case trailing
        /// No transcript yet. Cannot judge, so do not.
        case noTranscript
    }

    /// How long to wait after speech energy stops before declaring the turn over.
    public let window: TimeInterval
    public let reason: Reason

    public init(window: TimeInterval, reason: Reason) {
        self.window = window
        self.reason = reason
    }
}

/// Chooses an adaptive endpoint silence window from the live transcript.
public struct EndpointDecider: Sendable {

    public struct Configuration: Sendable {
        /// Used when the transcript reads as a finished sentence.
        ///
        /// 200 ms is short enough to feel immediate and long enough to survive
        /// the gap between two words in ordinary speech.
        public var completeWindow: TimeInterval

        /// The default, and deliberately equal to the VAD's current
        /// `silenceThresholdDuration`. Any transcript this decider cannot read
        /// confidently produces exactly the behaviour that shipped before it
        /// existed.
        public var neutralWindow: TimeInterval

        /// Used when the transcript ends mid-thought. Longer than today.
        public var trailingWindow: TimeInterval

        public init(
            completeWindow: TimeInterval = 0.20,
            neutralWindow: TimeInterval = 0.60,
            trailingWindow: TimeInterval = 0.90
        ) {
            self.completeWindow = completeWindow
            self.neutralWindow = neutralWindow
            self.trailingWindow = trailingWindow
        }
    }

    public let configuration: Configuration

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    /// Words that cannot end a finished sentence.
    ///
    /// A speaker who stops on "and", "to", or "the" has not finished — they are
    /// thinking. These are the cases where the 600 ms default is too *short*,
    /// and they are the reason this type can lengthen the window at all.
    ///
    /// Kept to closed word classes (conjunctions, prepositions, articles,
    /// auxiliaries, fillers) because those are finite, language-stable, and
    /// carry no lexical meaning of their own. Open-class words are excluded
    /// deliberately: plenty of sentences legitimately end on a noun or verb.
    private static let danglingTails: Set<String> = [
        // conjunctions
        "and", "but", "or", "nor", "so", "yet", "because", "although", "though",
        "while", "whereas", "unless", "until", "since", "if", "when", "whenever",
        "where", "wherever", "whether", "that", "which", "who", "than", "as",
        // prepositions
        "to", "of", "in", "on", "at", "by", "for", "with", "about", "against",
        "between", "into", "through", "during", "before", "after", "above",
        "below", "from", "up", "down", "over", "under", "onto", "upon",
        // articles and determiners
        "a", "an", "the", "my", "your", "our", "their", "his", "her", "its",
        "this", "these", "those", "some", "any", "every", "each",
        // auxiliaries and modals
        "is", "are", "was", "were", "be", "been", "being", "am", "do", "does",
        "did", "have", "has", "had", "will", "would", "can", "could", "shall",
        "should", "may", "might", "must",
        // hesitation
        "um", "uh", "er", "erm", "hmm", "like", "well"
    ]

    private static let terminalPunctuation: Set<Character> = [".", "?", "!"]

    /// Decide the silence window for the transcript as it currently reads.
    ///
    /// - Parameters:
    ///   - transcript: The latest transcript text. May be a partial.
    ///   - isVolatile: `true` if this came from a volatile (partial) result.
    ///     Punctuation is only trusted when this is `true` — see the file
    ///     header; finalization punctuates unconditionally and so proves
    ///     nothing about completeness.
    public func decide(transcript: String, isVolatile: Bool) -> EndpointDecision {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)

        // A transcript with no letters anywhere ("...", "42", stray symbols) is
        // not something to reason about. Without this guard, "..." would end in
        // a period and be read as a finished sentence.
        guard trimmed.contains(where: { $0.isLetter }) else {
            return EndpointDecision(window: configuration.neutralWindow, reason: .noTranscript)
        }

        // Punctuation on a volatile is checked FIRST, and this ordering is the
        // one genuinely debatable decision in the file. The safety instinct says
        // resolve conflicts toward waiting, which would put the dangling check
        // first. The evidence says otherwise, and the evidence wins:
        //
        //   • E6 showed the model punctuates a volatile only where it actually
        //     closed a sentence, and pointedly did NOT punctuate the volatile
        //     for the genuinely unfinished "…quarterly numbers and".
        //   • English strands prepositions and ends on auxiliaries constantly —
        //     "sit down.", "what's it for?", "Yes I am.", "I did." Ranking the
        //     dangling list above punctuation charges every one of those the
        //     900 ms penalty, which is most short conversational replies.
        //
        // So the two signals do not in practice collide, and pre-empting a
        // collision that does not occur would cost the common case dearly.
        // The dangling list keeps full authority over UNPUNCTUATED tails, which
        // is exactly where it carries information.
        if isVolatile, let last = trimmed.last, Self.terminalPunctuation.contains(last) {
            return EndpointDecision(window: configuration.completeWindow, reason: .complete)
        }

        if let tail = Self.finalWord(of: trimmed), Self.danglingTails.contains(tail) {
            return EndpointDecision(window: configuration.trailingWindow, reason: .trailing)
        }

        return EndpointDecision(window: configuration.neutralWindow, reason: .neutral)
    }

    /// The last alphabetic word, lowercased, with trailing punctuation removed.
    ///
    /// Returns `nil` when the tail is not a word at all (digits, symbols) —
    /// unreadable rather than dangling, which routes to the neutral default.
    /// Note this reads the *last* token only: "send it to 5" ends on a number,
    /// so the dangling "to" before it is not seen. Accepted — the failure mode
    /// is a neutral window, i.e. today's behaviour.
    static func finalWord(of text: String) -> String? {
        var separators = CharacterSet.whitespacesAndNewlines
            .union(.punctuationCharacters)
            .union(.symbols)
        // Apostrophes are word-internal ("it's", "don't"), not separators —
        // splitting on them would leave a tail of "s" or "t" and misjudge it.
        separators.remove(charactersIn: "'\u{2019}")
        guard let last = text.components(separatedBy: separators).last(where: { !$0.isEmpty })
        else { return nil }
        let lowered = last.lowercased()
        return lowered.allSatisfy { $0.isLetter || $0 == "'" || $0 == "\u{2019}" } ? lowered : nil
    }
}
