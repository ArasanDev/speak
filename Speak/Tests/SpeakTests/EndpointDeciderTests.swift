// SpeakTests/EndpointDeciderTests.swift
//
// Unit tests for EndpointDecider — the endpoint silence-window policy.
//
// The decider's value is a ~400 ms latency win; its RISK is truncating someone
// mid-sentence. So these tests weight the safety property heavily: the largest
// group below pins that unreadable, ambiguous, and mid-thought transcripts
// never shorten the window. A test suite that only proved the fast path works
// would be measuring the wrong thing.
//
// Pure input → output, no audio and no model, which is exactly why the policy
// was factored out of the VAD in the first place.

import Foundation
@testable import SpeakCore
import XCTest

final class EndpointDeciderTests: XCTestCase {

    private let decider = EndpointDecider()
    private let config = EndpointDecider.Configuration()

    // MARK: The safety property — never shorten when unsure

    /// The floor guarantee: anything the decider cannot read confidently must
    /// produce exactly the window that shipped before it existed. This is what
    /// makes the change safe to enable by default.
    func testUnreadableTranscriptsFallBackToTodaysBehaviour() {
        let cases: [(String, Bool)] = [
            ("", true),
            ("   ", true),
            ("\n\t ", false),
            ("42", true),
            ("...", true),
            ("— ", true)
        ]
        for (text, volatile) in cases {
            let decision = decider.decide(transcript: text, isVolatile: volatile)
            XCTAssertEqual(
                decision.window, config.neutralWindow, accuracy: 0.0001,
                "\"\(text)\" must not change the window"
            )
        }
    }

    /// A sentence ending in an ordinary word is not evidence of completion.
    func testPlainTailIsNeutral() {
        let decision = decider.decide(transcript: "send the report", isVolatile: true)
        XCTAssertEqual(decision.reason, .neutral)
        XCTAssertEqual(decision.window, config.neutralWindow, accuracy: 0.0001)
    }

    // MARK: Lengthening — the case today's fixed window gets wrong

    /// Stopping on a conjunction means thinking, not finishing. E6 caught the
    /// real cost of getting this wrong: "…quarterly numbers and" finalized as
    /// "…quarterly numbers, Anne." — the tail was lost and a word invented.
    func testDanglingConjunctionLengthensWindow() {
        for tail in ["and", "but", "so", "because", "or"] {
            let decision = decider.decide(transcript: "I need to send this \(tail)", isVolatile: true)
            XCTAssertEqual(decision.reason, .trailing, "tail '\(tail)'")
            XCTAssertGreaterThan(decision.window, config.neutralWindow, "tail '\(tail)'")
        }
    }

    func testDanglingPrepositionArticleAndAuxiliaryLengthenWindow() {
        for tail in ["to", "of", "with", "the", "a", "my", "is", "would", "should"] {
            let decision = decider.decide(transcript: "put it \(tail)", isVolatile: true)
            XCTAssertEqual(decision.reason, .trailing, "tail '\(tail)'")
        }
    }

    /// Hesitation is the clearest "still composing" signal there is.
    func testHesitationLengthensWindow() {
        for tail in ["um", "uh", "hmm", "like"] {
            let decision = decider.decide(transcript: "I want to, \(tail)", isVolatile: true)
            XCTAssertEqual(decision.reason, .trailing, "tail '\(tail)'")
            XCTAssertEqual(decision.window, config.trailingWindow, accuracy: 0.0001)
        }
    }

    /// Dangling detection must survive the comma that E6 showed the transcriber
    /// inserting before a trailing word.
    func testDanglingTailDetectedThroughTrailingComma() {
        let decision = decider.decide(transcript: "the quarterly numbers, and", isVolatile: true)
        XCTAssertEqual(decision.reason, .trailing)
    }

    func testTailMatchingIsCaseInsensitive() {
        XCTAssertEqual(decider.decide(transcript: "wait AND", isVolatile: true).reason, .trailing)
        XCTAssertEqual(decider.decide(transcript: "wait And", isVolatile: true).reason, .trailing)
    }

    // MARK: Shortening — the ~400 ms win

    /// The measured signal: E6 observed `"The meeting is at 3."` arriving as a
    /// volatile, terminal period included, 174 ms before its final.
    func testTerminalPunctuationOnVolatileShortensWindow() {
        for text in ["The meeting is at 3.", "Can you remind me?", "Stop that!"] {
            let decision = decider.decide(transcript: text, isVolatile: true)
            XCTAssertEqual(decision.reason, .complete, text)
            XCTAssertLessThan(decision.window, config.neutralWindow, text)
        }
    }

    /// The headline number this whole file exists to move.
    func testCompleteWindowIsTheAdvertisedSaving() {
        let decision = decider.decide(transcript: "That's all.", isVolatile: true)
        XCTAssertEqual(decision.window, 0.20, accuracy: 0.0001)
        XCTAssertEqual(config.neutralWindow - decision.window, 0.40, accuracy: 0.0001)
    }

    // MARK: The volatile/final asymmetry

    /// E6's sharpest finding: finalization appends terminal punctuation
    /// unconditionally, so a final ending in "." says nothing about whether the
    /// human is done. Trusting it here would shorten the window on exactly the
    /// unfinished utterances that most need lengthening.
    func testTerminalPunctuationOnFinalIsNotTrusted() {
        let decision = decider.decide(transcript: "The meeting is at 3.", isVolatile: false)
        XCTAssertNotEqual(decision.reason, .complete)
        XCTAssertEqual(decision.window, config.neutralWindow, accuracy: 0.0001)
    }

    /// The same text must be read differently depending on its volatility —
    /// if this ever collapses, the asymmetry has been lost.
    func testVolatilityChangesTheDecision() {
        let text = "Done."
        XCTAssertNotEqual(
            decider.decide(transcript: text, isVolatile: true),
            decider.decide(transcript: text, isVolatile: false)
        )
    }

    // MARK: Precedence

    /// Punctuation on a volatile outranks the dangling list.
    ///
    /// This ordering was chosen against the initial safety instinct, and the
    /// first version of this suite asserted the opposite — it failed on
    /// "Stop that!", which the dangling list charged 900 ms because "that" can
    /// end a sentence. English strands prepositions and ends on auxiliaries
    /// constantly ("sit down.", "what's it for?", "Yes I am."), so ranking the
    /// list first penalises most short conversational replies. E6 also showed
    /// the two signals do not collide in practice: the model left the genuinely
    /// unfinished "…numbers and" unpunctuated while volatile.
    func testPunctuationOnVolatileOutranksDanglingTail() {
        for text in ["Stop that!", "What's it for?", "Yes I am.", "I did."] {
            let decision = decider.decide(transcript: text, isVolatile: true)
            XCTAssertEqual(decision.reason, .complete, text)
        }
    }

    /// …and the dangling list keeps full authority where it has signal: an
    /// unpunctuated tail. This is the pairing that makes the ordering safe.
    func testDanglingTailGovernsUnpunctuatedTranscripts() {
        let decision = decider.decide(transcript: "I was going to", isVolatile: true)
        XCTAssertEqual(decision.reason, .trailing)
        XCTAssertEqual(decision.window, config.trailingWindow, accuracy: 0.0001)
    }

    /// The precedence rule's evidence, pinned as a test.
    ///
    /// These are verbatim volatiles observed by `make probe-partials` across
    /// five utterances that stop mid-thought, one per class of dangling word.
    /// None of the 17 volatiles carried punctuation, so punctuation-first never
    /// competed with the dangling list — which is the entire argument for the
    /// ordering. If a future transcriber starts punctuating partial fragments,
    /// this test fails and the ordering must be revisited before shipping.
    func testObservedMidThoughtVolatilesAllLengthen() {
        let observed = [
            "I want to send this to",
            "The reason is because",
            "Put it in the",
            "I need to send an email to Sarah about the quarterly numbers and"
        ]
        for text in observed {
            let decision = decider.decide(transcript: text, isVolatile: true)
            XCTAssertEqual(decision.reason, .trailing, text)
            XCTAssertEqual(decision.window, config.trailingWindow, accuracy: 0.0001, text)
        }
    }

    /// The fifth E6 utterance, and the limit of the lexical approach.
    ///
    /// "I was going" is audibly unfinished, but its tail is a participle — an
    /// open-class word, and "I was going." is a perfectly good sentence. Adding
    /// it to `danglingTails` would trade a documented, principled rule (closed
    /// word classes only) for one lucky case and start charging real completed
    /// sentences the 900 ms penalty. It lands on neutral instead: the decider
    /// declines to judge and behaves exactly as it did before it existed, which
    /// is the intended outcome for everything outside its competence.
    func testOpenClassTailIsNotTreatedAsDangling() {
        XCTAssertEqual(decider.decide(transcript: "I was going", isVolatile: true).reason, .neutral)
    }

    /// Punctuation-only noise must not read as a finished sentence — the guard
    /// is "contains a letter", not "ends in a period".
    func testPunctuationWithoutWordsIsNotComplete() {
        XCTAssertEqual(decider.decide(transcript: "...", isVolatile: true).reason, .noTranscript)
        XCTAssertEqual(decider.decide(transcript: "?!", isVolatile: true).reason, .noTranscript)
    }

    // MARK: Configuration

    /// The ordering the whole policy depends on. If a config ever inverted it,
    /// "complete" would wait longer than "trailing" and the decider would be
    /// actively harmful.
    func testDefaultWindowsAreOrdered() {
        XCTAssertLessThan(config.completeWindow, config.neutralWindow)
        XCTAssertLessThan(config.neutralWindow, config.trailingWindow)
    }

    /// The neutral default must track the VAD's shipped silence threshold —
    /// that equality is what makes the fallback path a true no-op.
    func testNeutralWindowMatchesVADDefault() {
        XCTAssertEqual(
            config.neutralWindow,
            VoiceActivityDetector.Configuration().silenceThresholdDuration,
            accuracy: 0.0001
        )
    }

    func testCustomConfigurationIsHonoured() {
        let custom = EndpointDecider.Configuration(
            completeWindow: 0.1, neutralWindow: 0.5, trailingWindow: 1.2
        )
        let decider = EndpointDecider(configuration: custom)
        XCTAssertEqual(
            decider.decide(transcript: "Okay.", isVolatile: true).window, 0.1, accuracy: 0.0001
        )
        XCTAssertEqual(
            decider.decide(transcript: "okay and", isVolatile: true).window, 1.2, accuracy: 0.0001
        )
    }

    // MARK: Tail extraction

    func testFinalWordExtraction() {
        XCTAssertEqual(EndpointDecider.finalWord(of: "hello there"), "there")
        XCTAssertEqual(EndpointDecider.finalWord(of: "hello there."), "there")
        XCTAssertEqual(EndpointDecider.finalWord(of: "it's"), "it's")
        XCTAssertNil(EndpointDecider.finalWord(of: "1234"))
        XCTAssertNil(EndpointDecider.finalWord(of: "!!!"))
        XCTAssertNil(EndpointDecider.finalWord(of: ""))
    }
}
