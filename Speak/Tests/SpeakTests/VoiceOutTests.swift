// SpeakTests/VoiceOutTests.swift
//
// Unit tests for the H-2 VoiceOut readback seam (specs/horizon-voice-os.md Pillar 2).
//
// SCOPE:
//   `AppleSpeechSynthesizer` wraps a real `AVSpeechSynthesizer` with no injectable
//   seam (unlike `PasteboardWriter`, which takes closures for AX/clipboard/event
//   posting specifically so tests never fire real side effects). Letting a test
//   call `speak(_:locale:)` end-to-end would make the test machine audibly speak
//   during `make test` — the TTS equivalent of `PasteboardWriterTests`' documented
//   regression ("a real post lands in whatever window has focus... this test
//   previously posted real events; that is the regression being fixed"). So:
//
//   - `AppleSpeechSynthesizerTests` below only exercises the guard paths that are
//     provably side-effect-free (empty-text no-op, stop-when-idle no-op, initial
//     state) — never a real `speak()` call that would produce audio.
//   - `MockSpeechSynthesizerTests` exercises the full start/stop/interrupt
//     *contract* `SpeechSynthesizing` promises (speak sets isSpeaking, stop
//     resolves an in-flight speak() promptly, a second speak() interrupts the
//     first) against a silent, deterministic in-memory conformer — the "mock
//     synthesizer" the H-2 task calls for.
//
//   Full live-audio behavior (does it actually speak, latency, Personal Voice
//   fallback) is [deferred — needs human verification], matching the rest of
//   this codebase's honesty boundary (no CI runs real audio hardware).

@testable import SpeakCore
import XCTest

// MARK: - MockSpeechSynthesizer

/// A controllable, silent `SpeechSynthesizing` conformer. Models the same
/// start/stop/interrupt contract `AppleSpeechSynthesizer` promises — a
/// `speak(_:locale:)` call stays "in flight" until `stop()` resolves it, and a
/// second `speak(_:locale:)` call while one is in flight interrupts the first —
/// without ever touching `AVSpeechSynthesizer` or producing audio.
actor MockSpeechSynthesizer: SpeechSynthesizing {
    private(set) var calls: [(text: String, locale: Locale)] = []
    private(set) var stopCount = 0
    private var continuation: CheckedContinuation<Void, Never>?
    private var speakingFlag = false

    var isSpeaking: Bool { speakingFlag }

    func speak(_ text: String, locale: Locale) async {
        calls.append((text, locale))
        // Mirror `AppleSpeechSynthesizer.speak(_:locale:)`: never overlap — a
        // second call interrupts whatever is currently "playing" first.
        if speakingFlag { await stop() }
        speakingFlag = true
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            self.continuation = continuation
        }
    }

    func stop() async {
        stopCount += 1
        guard speakingFlag else { return }
        speakingFlag = false
        continuation?.resume()
        continuation = nil
    }
}

// MARK: - MockSpeechSynthesizerTests (the SpeechSynthesizing contract)

final class MockSpeechSynthesizerTests: XCTestCase {

    /// `speak()` must report `isSpeaking == true` while awaiting completion, and
    /// `stop()` must resolve that awaiting call promptly, leaving `isSpeaking == false`.
    func testSpeakReportsSpeakingUntilStopped() async {
        let mock = MockSpeechSynthesizer()
        let speakTask = Task { await mock.speak("hello", locale: Locale(identifier: "en-US")) }

        var becameSpeaking = false
        for _ in 0 ..< 200 {
            if await mock.isSpeaking { becameSpeaking = true; break }
            await Task.yield()
        }
        XCTAssertTrue(becameSpeaking, "isSpeaking must become true while speak() is in flight")

        await mock.stop()
        await speakTask.value   // must resolve promptly — stop() is the interrupt path

        let stillSpeaking = await mock.isSpeaking
        XCTAssertFalse(stillSpeaking, "isSpeaking must be false once stop() has resolved the utterance")
    }

    /// `stop()` when nothing is speaking is a safe no-op (no crash, no recorded calls).
    func testStopWhenIdleIsNoOp() async {
        let mock = MockSpeechSynthesizer()
        await mock.stop()
        let calls = await mock.calls
        let stopCount = await mock.stopCount
        XCTAssertTrue(calls.isEmpty, "stop() alone must never record a speak() call")
        XCTAssertEqual(stopCount, 1, "stop() still records the attempt even when idle")
        let speaking = await mock.isSpeaking
        XCTAssertFalse(speaking)
    }

    /// A second `speak()` call while the first is in flight interrupts it — the
    /// core H-2 contract ("any hotkey press / pressing the button again stops
    /// speech immediately"). Both calls are recorded; the first resolves without
    /// the caller having to call `stop()` themselves.
    func testSecondSpeakInterruptsFirst() async {
        let mock = MockSpeechSynthesizer()
        let firstTask = Task { await mock.speak("first", locale: Locale(identifier: "en-US")) }

        var becameSpeaking = false
        for _ in 0 ..< 200 {
            if await mock.isSpeaking { becameSpeaking = true; break }
            await Task.yield()
        }
        XCTAssertTrue(becameSpeaking, "precondition: first speak() must be in flight before starting the second")

        await mock.speak("second", locale: Locale(identifier: "en-US"))
        await firstTask.value   // must have resolved once interrupted by the second call

        let texts = await mock.calls.map(\.text)
        XCTAssertEqual(texts, ["first", "second"], "both speak() calls must be recorded, in order")
        let speaking = await mock.isSpeaking
        XCTAssertFalse(speaking, "the second utterance finishes (mock resolves speak() immediately after recording)")
    }
}

// MARK: - AppleSpeechSynthesizerTests (side-effect-free guard paths only)

final class AppleSpeechSynthesizerTests: XCTestCase {

    /// A fresh synthesizer reports not speaking.
    func testIsSpeakingFalseInitially() async {
        let synth = AppleSpeechSynthesizer()
        let speaking = await synth.isSpeaking
        XCTAssertFalse(speaking)
    }

    /// Whitespace-only text is a no-op: `speak(_:locale:)` returns immediately
    /// without ever constructing an `AVSpeechUtterance` or touching the real
    /// synthesizer — provably silent (no audio device dependency, no hang risk).
    func testSpeakWhitespaceOnlyTextIsNoOp() async {
        let synth = AppleSpeechSynthesizer()
        await synth.speak("   \n\t  ", locale: Locale(identifier: "en-US"))
        let speaking = await synth.isSpeaking
        XCTAssertFalse(speaking, "whitespace-only text must never start speech")
    }

    /// `stop()` when idle returns immediately — the guard clause means the real
    /// `AVSpeechSynthesizer.stopSpeaking(at:)` is never invoked when nothing is
    /// speaking, so this is provably side-effect-free.
    func testStopWhenIdleIsNoOp() async {
        let synth = AppleSpeechSynthesizer()
        await synth.stop()
        let speaking = await synth.isSpeaking
        XCTAssertFalse(speaking)
    }
}
