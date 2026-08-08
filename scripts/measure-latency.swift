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
// MEASUREMENT CAVEATS (read before trusting a number)
//  - `didStart` is the synthesizer reporting the utterance began, which is a
//    proxy for "the human hears something", not a microphone-verified
//    observation. The `write()` first-buffer figure is reported alongside it as
//    the conservative bound on pure synthesis compute.
//  - Warm figures follow a cold call in the same process. Real cold-start on a
//    freshly launched app may be worse; the cold row is a single sample.

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
if let think = median(warmModel.ttft), let synth = median(warmSpeak.firstAudio) {
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
