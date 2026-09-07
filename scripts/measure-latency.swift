// scripts/measure-latency.swift — E1, the conversational latency harness.
//
// Run with: make measure-latency
//
// WHY THIS EXISTS
// The conversation loop is a latency product. Nothing in the app measured it,
// so every figure in `specs/voice-agent-design.md` §5 was `[unverified]` and
// the design rested on a guess. This harness replaces the guess with numbers
// from *this* machine, and is re-runnable so a regression is visible.
//
// It measures the two components that are physics, not policy:
//   synthesisMs — ttsRequested   → first audio   (AVSpeechSynthesizer)
//   thinkingMs  — agentRequested → first token   (FoundationModels, on-device)
// `endpointDelayMs` is deliberately NOT measured: it is a policy number we
// choose (the VAD silence window), so it enters the composite as a parameter.
//
// Deliberately standalone rather than an XCTest: it needs no Xcode project, no
// app bundle, and no permissions, so it runs on a clean clone in seconds. It
// speaks a few short lines aloud — that is the measurement, not a side effect.
//
// MEASUREMENT NOTES (read before trusting a number)
//  - `didStart` is NOT audibility. It measured 1–2 ms warm, which is below the
//    floor for CoreAudio output start, so it is reporting enqueue. The composite
//    therefore uses `AUDIBLE first-sample`: a tap on the mixer that timestamps
//    the first buffer whose RMS clears silence. `didStart` is still printed, so
//    the gap between the two stays visible instead of being quietly assumed.
//  - Warm figures follow a cold call in the same process, so the in-process
//    `prewarm` row cannot show a gain — the model is already warm. The real
//    question (does prewarming at launch recover the first turn?) needs a fresh
//    process: `--first-turn-cold` / `--first-turn-prewarm`, run by the Makefile.

import AVFoundation
import Foundation
import FoundationModels

let clock = ContinuousClock()

func ms(_ duration: Duration) -> Double {
    let components = duration.components
    return Double(components.seconds) * 1000 + Double(components.attoseconds) / 1e15
}

/// `String(format:)` does not honour a field width for `%@` on macOS, so pad
/// label columns manually rather than emitting a ragged table.
func pad(_ text: String, _ width: Int) -> String {
    text.count >= width ? text : text + String(repeating: " ", count: width - text.count)
}

func stats(_ label: String, _ samples: [Double]) {
    guard !samples.isEmpty else {
        print("  \(pad(label, 22))  no samples")
        return
    }
    let sorted = samples.sorted()
    let mean = samples.reduce(0, +) / Double(samples.count)
    let p50 = sorted[sorted.count / 2]
    let p90 = sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.9))]
    print("  \(pad(label, 22))" + String(format: "n=%-3d p50=%6.0f  mean=%6.0f  p90=%6.0f  max=%6.0f",
                                         samples.count, p50, mean, p90, sorted[sorted.count - 1]))
}

func median(_ samples: [Double]) -> Double? {
    guard !samples.isEmpty else { return nil }
    return samples.sorted()[samples.count / 2]
}

// MARK: - TTS

/// Captures the instant the synthesizer reports first audio for an utterance.
///
/// Lock-protected for the same reason `TurnMetricsRecorder` is: delegate
/// callbacks arrive off the calling context and must never suspend.
final class FirstAudioProbe: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var requested: ContinuousClock.Instant?
    private var firstAudible: ContinuousClock.Instant?
    private var finished: ContinuousClock.Instant?
    private var continuation: CheckedContinuation<Void, Never>?

    func request() {
        lock.lock()
        requested = clock.now
        firstAudible = nil
        finished = nil
        lock.unlock()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        lock.lock()
        if firstAudible == nil { firstAudible = clock.now }
        lock.unlock()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        lock.lock()
        finished = clock.now
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume()
    }

    func waitForFinish() async {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            lock.lock()
            if finished != nil {
                lock.unlock()
                c.resume()
                return
            }
            continuation = c
            lock.unlock()
        }
    }

    var timeToFirstAudioMs: Double? {
        lock.lock()
        defer { lock.unlock() }
        guard let requested, let firstAudible, firstAudible >= requested else { return nil }
        return ms(requested.duration(to: firstAudible))
    }

    var speakingMs: Double? {
        lock.lock()
        defer { lock.unlock() }
        guard let firstAudible, let finished, finished >= firstAudible else { return nil }
        return ms(firstAudible.duration(to: finished))
    }
}

/// Short conversational replies — the real workload, not a paragraph.
let replyLines = [
    "Sure, I can do that.",
    "You have three meetings today.",
    "Done. Anything else?"
]

func measureSpeak(reps: Int) async -> (firstAudio: [Double], speaking: [Double]) {
    let synthesizer = AVSpeechSynthesizer()
    let probe = FirstAudioProbe()
    synthesizer.delegate = probe
    var firstAudio: [Double] = []
    var speaking: [Double] = []

    for index in 0..<reps {
        let utterance = AVSpeechUtterance(string: replyLines[index % replyLines.count])
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        probe.request()
        synthesizer.speak(utterance)
        await probe.waitForFinish()
        if let value = probe.timeToFirstAudioMs { firstAudio.append(value) }
        if let value = probe.speakingMs { speaking.append(value) }
    }
    return (firstAudio, speaking)
}

/// Offline render: time until the first buffer exists. The conservative bound
/// on synthesis compute, independent of playback scheduling.
func measureWriteFirstBuffer(reps: Int) async -> [Double] {
    var out: [Double] = []
    for _ in 0..<reps {
        let synthesizer = AVSpeechSynthesizer()
        let utterance = AVSpeechUtterance(string: replyLines[0])
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        let start = clock.now
        let elapsed: Double? = await withCheckedContinuation { (c: CheckedContinuation<Double?, Never>) in
            let guardLock = NSLock()
            var resumed = false
            synthesizer.write(utterance) { (_: AVAudioBuffer) in
                guardLock.lock()
                if resumed {
                    guardLock.unlock()
                    return
                }
                resumed = true
                guardLock.unlock()
                c.resume(returning: ms(start.duration(to: clock.now)))
            }
        }
        if let elapsed { out.append(elapsed) }
    }
    return out
}

// MARK: - TTS, audibility-verified

/// Watches rendered output and records when the first genuinely non-silent
/// sample appears.
///
/// This exists because `didStart` is the synthesizer reporting it *began* an
/// utterance, which measured 1–2 ms warm — below the floor for CoreAudio output
/// start on any hardware. That figure is almost certainly enqueue, not
/// audibility, so it cannot be trusted as the `ttsFirstAudio` mark. This probe
/// timestamps actual audio instead.
final class FirstAudibleSampleProbe: @unchecked Sendable {
    /// Comfortably above digital silence and dither, below any real speech.
    private static let audibleRMS: Float = 0.001

    private let lock = NSLock()
    private var start: ContinuousClock.Instant?
    private var audibleMs: Double?

    func arm() {
        lock.lock()
        start = clock.now
        audibleMs = nil
        lock.unlock()
    }

    /// Called from the render thread — must not allocate or suspend.
    func consider(_ buffer: AVAudioPCMBuffer) {
        guard let channels = buffer.floatChannelData else { return }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return }
        var sumOfSquares: Float = 0
        let samples = channels[0]
        for index in 0..<frames {
            sumOfSquares += samples[index] * samples[index]
        }
        guard (sumOfSquares / Float(frames)).squareRoot() > Self.audibleRMS else { return }

        lock.lock()
        if audibleMs == nil, let start {
            audibleMs = ms(start.duration(to: clock.now))
        }
        lock.unlock()
    }

    /// Synchronous so the polling loop below never holds a lock across a
    /// suspension point — `NSLock.lock()` is unavailable from async contexts.
    private func recorded() -> Double? {
        lock.lock()
        defer { lock.unlock() }
        return audibleMs
    }

    /// Polled rather than continuation-based: a missed resume would hang the
    /// harness, and 2 ms of polling error is irrelevant when discriminating
    /// 1 ms from ~150 ms.
    func waitForAudible(timeoutMs: Int) async -> Double? {
        let deadline = clock.now.advanced(by: .milliseconds(timeoutMs))
        while clock.now < deadline {
            if let value = recorded() { return value }
            try? await Task.sleep(for: .milliseconds(2))
        }
        return nil
    }
}

/// Holds the first rendered buffer's format across the render callback and the
/// polling loop that waits for it.
final class RenderFormatBox: @unchecked Sendable {
    private let lock = NSLock()
    private var format: AVAudioFormat?

    func store(_ candidate: AVAudioFormat) {
        lock.lock()
        if format == nil { format = candidate }
        lock.unlock()
    }

    func value() -> AVAudioFormat? {
        lock.lock()
        defer { lock.unlock() }
        return format
    }
}

/// Learn the synthesizer's native render format via a throwaway render, so the
/// player graph can be built and started *before* the measured run — matching
/// the app, where the engine is already running when a reply arrives.
func firstWrittenBufferFormat(timeoutMs: Int = 5000) async -> AVAudioFormat? {
    let synthesizer = AVSpeechSynthesizer()
    let utterance = AVSpeechUtterance(string: "format probe")
    utterance.voice = AVSpeechSynthesisVoice(language: "en-US")

    let box = RenderFormatBox()
    synthesizer.write(utterance) { (buffer: AVAudioBuffer) in
        guard let pcm = buffer as? AVAudioPCMBuffer, pcm.frameLength > 0 else { return }
        box.store(pcm.format)
    }

    let deadline = clock.now.advanced(by: .milliseconds(timeoutMs))
    while clock.now < deadline {
        if let found = box.value() { return found }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return nil
}

/// End-to-end first-audio for the architecture we would actually ship: render
/// streaming out of `write()`, scheduled onto a player node as buffers arrive,
/// with the first audible sample detected at the mixer.
///
/// This is the honest `synthesisMs`. It is also the path barge-in requires —
/// silencing mid-utterance needs sample-level control that `speak()` does not give.
func measureStreamedPlaybackFirstAudio(reps: Int) async -> [Double] {
    guard let renderFormat = await firstWrittenBufferFormat() else { return [] }

    let engine = AVAudioEngine()
    let player = AVAudioPlayerNode()
    engine.attach(player)
    engine.connect(player, to: engine.mainMixerNode, format: renderFormat)

    let probe = FirstAudibleSampleProbe()
    engine.mainMixerNode.installTap(onBus: 0, bufferSize: 512, format: nil) { buffer, _ in
        probe.consider(buffer)
    }

    do {
        try engine.start()
    } catch {
        FileHandle.standardError.write(Data("  engine start failed: \(error)\n".utf8))
        return []
    }
    player.play()

    var out: [Double] = []
    for index in 0..<reps {
        let synthesizer = AVSpeechSynthesizer()
        let utterance = AVSpeechUtterance(string: replyLines[index % replyLines.count])
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")

        probe.arm()
        synthesizer.write(utterance) { (buffer: AVAudioBuffer) in
            guard let pcm = buffer as? AVAudioPCMBuffer, pcm.frameLength > 0 else { return }
            player.scheduleBuffer(pcm, completionHandler: nil)
        }
        if let audible = await probe.waitForAudible(timeoutMs: 5000) { out.append(audible) }
        // Let the utterance drain so the next arm() does not catch its tail.
        try? await Task.sleep(for: .milliseconds(2200))
    }

    engine.mainMixerNode.removeTap(onBus: 0)
    player.stop()
    engine.stop()
    return out
}

// MARK: - FoundationModels

let promptLines = [
    "What time is it? Answer in one short sentence.",
    "Say hello back, briefly.",
    "Give me a one-sentence status."
]

struct ModelRun {
    var ttft: [Double] = []
    var total: [Double] = []
    var errors = 0
}

func measureModel(reps: Int, prewarm: Bool) async -> ModelRun {
    var ttft: [Double] = []
    var total: [Double] = []
    var errors = 0

    for index in 0..<reps {
        let session = LanguageModelSession(
            instructions: Instructions("You are a terse voice assistant. Reply in one short sentence.")
        )
        if prewarm { session.prewarm() }
        do {
            let start = clock.now
            var sawFirstToken = false
            for try await snapshot in session.streamResponse(to: promptLines[index % promptLines.count]) {
                if !sawFirstToken, !snapshot.content.isEmpty {
                    sawFirstToken = true
                    ttft.append(ms(start.duration(to: clock.now)))
                }
            }
            total.append(ms(start.duration(to: clock.now)))
        } catch {
            errors += 1
            FileHandle.standardError.write(Data("  model error: \(error)\n".utf8))
        }
    }
    return ModelRun(ttft: ttft, total: total, errors: errors)
}

// MARK: - First-turn mode

/// Measures the one thing a warm-process run structurally cannot: what the
/// *first* turn after launch costs, and whether prewarming at launch recovers
/// it. Requires a fresh process, so it is a separate invocation rather than
/// another rep — which is exactly why the in-process `prewarm` row shows no
/// gain: by then the model is already warm and there is nothing left to save.
func measureFirstTurn(prewarm: Bool) async {
    let label = prewarm ? "prewarmed at launch" : "no prewarm"
    let session = LanguageModelSession(
        instructions: Instructions("You are a terse voice assistant. Reply in one short sentence.")
    )
    if prewarm { session.prewarm() }

    // Nobody speaks the instant the app launches. Both variants hold the same
    // gap so the only difference between them is the prewarm() call.
    try? await Task.sleep(for: .milliseconds(2000))

    do {
        let start = clock.now
        var ttft: Double?
        for try await snapshot in session.streamResponse(to: promptLines[0]) {
            if ttft == nil, !snapshot.content.isEmpty {
                ttft = ms(start.duration(to: clock.now))
            }
        }
        guard let ttft else {
            print("  \(pad(label, 26))no token observed")
            return
        }
        print("  \(pad(label, 26))" + String(format: "first-turn TTFT = %6.0f", ttft))
    } catch {
        print("  \(pad(label, 26))error: \(error)")
    }
}

let mode = CommandLine.arguments.dropFirst().first
if mode == "--first-turn-prewarm" || mode == "--first-turn-cold" {
    await measureFirstTurn(prewarm: mode == "--first-turn-prewarm")
    exit(0)
}

// MARK: - Report

print("=== E1 — conversational latency on this machine ===")
print("all figures in milliseconds\n")

print("environment")
switch SystemLanguageModel.default.availability {
case .available:
    print("  FoundationModels        available")

case .unavailable(let reason):
    print("  FoundationModels        UNAVAILABLE — \(reason)")

@unknown default:
    print("  FoundationModels        unknown availability")
}

let englishVoices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("en") }
let defaultQuality = englishVoices.filter { $0.quality == .default }.count
let enhanced = englishVoices.filter { $0.quality == .enhanced }.count
let premium = englishVoices.filter { $0.quality == .premium }.count
print("  english voices          \(englishVoices.count) (default \(defaultQuality) · enhanced \(enhanced) · premium \(premium))")
if enhanced == 0 && premium == 0 {
    print("  ⚠︎ only default-quality voices installed — the agent will sound robotic.")
    print("    Enhanced/Premium are a user download: System Settings → Accessibility → Spoken Content.")
}
print("")

print("TTS — AVSpeechSynthesizer")
let coldSpeak = await measureSpeak(reps: 1)
stats("cold first-audio", coldSpeak.firstAudio)
let warmSpeak = await measureSpeak(reps: 8)
stats("warm first-audio", warmSpeak.firstAudio)
stats("utterance duration", warmSpeak.speaking)
let writeFirst = await measureWriteFirstBuffer(reps: 5)
stats("write first-buffer", writeFirst)
let audibleFirst = await measureStreamedPlaybackFirstAudio(reps: 5)
stats("AUDIBLE first-sample", audibleFirst)
print("  ↑ `warm first-audio` is didStart (enqueue). `AUDIBLE` is a mixer tap")
print("    detecting real signal — that is the figure the composite uses.")
print("")

print("Model — FoundationModels streamResponse → first token")
let coldModel = await measureModel(reps: 1, prewarm: false)
stats("cold TTFT", coldModel.ttft)
let warmModel = await measureModel(reps: 5, prewarm: false)
stats("warm TTFT", warmModel.ttft)
stats("warm total", warmModel.total)
let prewarmedModel = await measureModel(reps: 5, prewarm: true)
stats("prewarmed TTFT", prewarmedModel.ttft)
let modelErrors = coldModel.errors + warmModel.errors + prewarmedModel.errors
if modelErrors > 0 { print("  errors: \(modelErrors)") }
print("")

print("Composite — userSpeechEnded → ttsFirstAudio")
// Uses the mixer-verified audible figure, never didStart: didStart measures
// enqueue and would understate every total below.
if let think = median(warmModel.ttft), let synth = median(audibleFirst) {
    // The VAD silence window is policy, so show what each choice costs.
    for (label, endpoint) in [("silence VAD (0.6s, today)", 600.0), ("semantic endpointing", 200.0)] {
        print("  \(pad(label, 26))" + String(format: "endpoint %4.0f + think %4.0f + tts %3.0f  =  %5.0f",
                                             endpoint, think, synth, endpoint + think + synth))
    }
    if let cold = median(coldModel.ttft) {
        print("  \(pad("first turn after launch", 26))" + String(format: "endpoint  600 + think %4.0f + tts %3.0f  =  %5.0f   ← prewarm or pay this",
                                                                 cold, synth, 600 + cold + synth))
    }
} else {
    print("  insufficient samples for a composite")
}
