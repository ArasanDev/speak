// E6 — do volatile (partial) SpeechTranscriber results carry sentence-final
// punctuation?
//
// This gates the `EndpointDecider` rule set. The strongest available signal
// that a human has finished a sentence is the transcript ending in `.`/`?`/`!`.
// But streaming recognizers frequently emit partials with no punctuation at
// all, and revise it only on finalization — in which case the decider cannot
// depend on it and must lean entirely on lexical-tail analysis instead.
// Writing the rule set before answering this is guessing.
//
// The SDK settles half of it already: `SpeechTranscriber.TranscriptionOption`
// has exactly one case (`etiquetteReplacements`) and `ReportingOption` has
// three (`volatileResults`, `alternativeTranscriptions`, `fastResults`).
// There is NO punctuation toggle — unlike the older `SFSpeechRecognizer`'s
// `addsPunctuation`. So punctuation is whatever the model emits; we cannot ask
// for it. [verified: arm64e-apple-macos.swiftinterface, MacOSX26.5.sdk]
//
// METHOD, AND ITS ONE WEAKNESS
// Audio is synthesized with `AVSpeechSynthesizer.write()` and fed to
// `SpeechAnalyzer` — no microphone, no permissions, no fixtures, so this is
// re-runnable in any checkout. The evidence is asymmetric and should be read
// that way:
//   - punctuation OBSERVED in a volatile  => conclusive. The path emits it.
//   - punctuation ABSENT from all volatiles => suggestive, not conclusive.
//     Synthetic speech is unnaturally clean and prosodically flat, and
//     punctuation inference leans on prosody.
// The decider is therefore designed to treat punctuation as a bonus signal and
// never to require it.
//
// Buffers are fed at approximately real time. Dumping the whole utterance at
// once would let the analyzer finalize in one shot and manufacture the very
// answer being tested.

import AVFoundation
import Foundation
import Speech

let clock = ContinuousClock()

func ms(_ duration: Duration) -> Double {
    let components = duration.components
    return Double(components.seconds) * 1000 + Double(components.attoseconds) / 1e15
}

/// `String(format:)` ignores field width for `%@` on macOS, so pad manually.
func pad(_ text: String, _ width: Int) -> String {
    text.count >= width ? text : text + String(repeating: " ", count: width - text.count)
}

/// Sentence-final punctuation — the signal the decider would like to use.
func terminalPunctuation(_ text: String) -> Character? {
    guard let last = text.trimmingCharacters(in: .whitespacesAndNewlines).last else { return nil }
    return ".?!".contains(last) ? last : nil
}

func anyPunctuation(_ text: String) -> Bool {
    text.contains { ".?!,;:".contains($0) }
}

// ------------------------------------------------------------- synthesis ----

/// Renders `text` to PCM buffers via the offline synthesis path.
///
/// Deliberately multi-sentence: the interesting case is whether punctuation
/// shows up mid-utterance, at the boundary between two spoken sentences, while
/// the result is still volatile.
func synthesize(_ text: String) async -> [AVAudioPCMBuffer] {
    final class Collector: @unchecked Sendable {
        private let lock = NSLock()
        private var buffers: [AVAudioPCMBuffer] = []
        private var continuation: CheckedContinuation<[AVAudioPCMBuffer], Never>?
        private var finished = false

        func append(_ buffer: AVAudioPCMBuffer) {
            lock.lock()
            buffers.append(buffer)
            lock.unlock()
        }

        /// `write()` signals completion with a zero-length buffer.
        func finish() {
            lock.lock()
            guard !finished else { lock.unlock(); return }
            finished = true
            let pending = continuation
            continuation = nil
            let result = buffers
            lock.unlock()
            pending?.resume(returning: result)
        }

        func wait() async -> [AVAudioPCMBuffer] {
            await withCheckedContinuation { (cont: CheckedContinuation<[AVAudioPCMBuffer], Never>) in
                lock.lock()
                if finished {
                    let result = buffers
                    lock.unlock()
                    cont.resume(returning: result)
                    return
                }
                continuation = cont
                lock.unlock()
            }
        }
    }

    let synthesizer = AVSpeechSynthesizer()
    let utterance = AVSpeechUtterance(string: text)
    utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
    let collector = Collector()

    synthesizer.write(utterance) { (buffer: AVAudioBuffer) in
        guard let pcm = buffer as? AVAudioPCMBuffer else { return }
        if pcm.frameLength == 0 {
            collector.finish()
        } else {
            collector.append(pcm)
        }
    }
    return await collector.wait()
}

// ------------------------------------------------------------ conversion ----

/// One-shot format conversion, mirroring `AppleSpeechTranscriber.convert`.
func convert(
    _ buffer: AVAudioPCMBuffer,
    using converter: AVAudioConverter,
    to targetFormat: AVAudioFormat
) -> AVAudioPCMBuffer? {
    let ratio = targetFormat.sampleRate / buffer.format.sampleRate
    let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
    guard capacity > 0,
          let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity)
    else { return nil }

    final class InputBox: @unchecked Sendable {
        var supplied = false
        let buffer: AVAudioPCMBuffer
        init(buffer: AVAudioPCMBuffer) { self.buffer = buffer }
    }

    let box = InputBox(buffer: buffer)
    var conversionError: NSError?
    let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
        if box.supplied {
            inputStatus.pointee = .noDataNow
            return nil
        }
        box.supplied = true
        inputStatus.pointee = .haveData
        return box.buffer
    }
    guard status != .error, output.frameLength > 0 else { return nil }
    return output
}

// ------------------------------------------------------------------ probe ---

struct Observation {
    let atMs: Double
    let isFinal: Bool
    let text: String
}

func probe(_ sentence: String) async {
    print("\n── utterance: \"\(sentence)\"")

    let rendered = await synthesize(sentence)
    guard let sourceFormat = rendered.first?.format, !rendered.isEmpty else {
        print("   synthesis produced no audio — skipped")
        return
    }
    let totalFrames = rendered.reduce(0) { $0 + Int($1.frameLength) }
    let audioSeconds = Double(totalFrames) / sourceFormat.sampleRate
    print(String(format: "   synthesized %.2fs of audio (%d buffers @ %.0f Hz)",
                 audioSeconds, rendered.count, sourceFormat.sampleRate))

    guard await SpeechTranscriber.supportedLocale(equivalentTo: Locale.current) != nil else {
        print("   locale unsupported — skipped")
        return
    }
    guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "en-US")) else {
        print("   en-US unsupported — skipped")
        return
    }

    let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
    let status = await AssetInventory.status(forModules: [transcriber])
    if status != .installed {
        // The app provisions this on first dictation; a standalone binary has
        // to ask for itself. Same API, same system-shared asset — not a
        // duplicate copy, and nothing app-specific is being changed.
        print("   speech model status: \(status) — requesting install…")
        do {
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try await request.downloadAndInstall()
                print("   installed.")
            } else {
                print("   install already in progress or complete.")
            }
        } catch {
            print("   install failed: \(error) — skipped")
            return
        }
    }
    guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]),
          let converter = AVAudioConverter(from: sourceFormat, to: analyzerFormat)
    else {
        print("   could not resolve analyzer format — skipped")
        return
    }

    let analyzer = SpeechAnalyzer(modules: [transcriber])
    let (inputStream, inputContinuation) = AsyncStream<AnalyzerInput>.makeStream()

    final class Log: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [Observation] = []
        func add(_ observation: Observation) { lock.lock(); items.append(observation); lock.unlock() }
        func all() -> [Observation] { lock.lock(); defer { lock.unlock() }; return items }
    }
    let log = Log()
    let start = clock.now

    let resultsTask = Task<Void, Error> {
        for try await result in transcriber.results {
            let text = String(result.text.characters)
            guard !text.isEmpty else { continue }
            log.add(Observation(atMs: ms(start.duration(to: clock.now)),
                                isFinal: result.isFinal,
                                text: text))
        }
    }

    do {
        try await analyzer.start(inputSequence: inputStream)
    } catch {
        print("   analyzer.start failed: \(error)")
        return
    }

    // Feed at approximately real time.
    for buffer in rendered {
        guard let converted = convert(buffer, using: converter, to: analyzerFormat) else { continue }
        inputContinuation.yield(AnalyzerInput(buffer: converted))
        let seconds = Double(buffer.frameLength) / sourceFormat.sampleRate
        try? await Task.sleep(for: .milliseconds(Int(seconds * 1000)))
    }
    inputContinuation.finish()
    let audioDoneMs = ms(start.duration(to: clock.now))

    do {
        try await analyzer.finalizeAndFinishThroughEndOfInput()
    } catch {
        print("   finalize failed: \(error)")
    }
    _ = try? await resultsTask.value

    // ---- report ----
    let observations = log.all()
    guard !observations.isEmpty else {
        print("   no results — the model may not have recognized synthetic speech")
        return
    }

    for observation in observations {
        let kind = observation.isFinal ? "FINAL" : "vol  "
        let mark = terminalPunctuation(observation.text).map { "  <- ends '\($0)'" } ?? ""
        print("   \(pad(String(format: "%6.0fms", observation.atMs), 9))\(kind)  "
              + "\"\(observation.text)\"\(mark)")
    }

    let volatiles = observations.filter { !$0.isFinal }
    let finals = observations.filter { $0.isFinal }
    let volatileWithTerminal = volatiles.filter { terminalPunctuation($0.text) != nil }
    let volatileWithAny = volatiles.filter { anyPunctuation($0.text) }

    print("   ── volatiles=\(volatiles.count)  finals=\(finals.count)")
    print("      volatile w/ sentence-final punctuation: \(volatileWithTerminal.count)/\(volatiles.count)")
    print("      volatile w/ any punctuation:            \(volatileWithAny.count)/\(volatiles.count)")
    if let lastFinal = finals.last {
        let delay = lastFinal.atMs - audioDoneMs
        print(String(format: "      last audio fed -> final result: %.0f ms", delay))
        print("      final text: \"\(lastFinal.text)\"")
    }
}

// ------------------------------------------------------------------- main ---

print("=== E6: punctuation in volatile SpeechTranscriber results ===")
print("Purpose: decide whether EndpointDecider may depend on transcript punctuation.")

// Two sentences, so a boundary exists mid-utterance; a question, because '?'
// is the highest-value endpoint signal; and a trailing conjunction, which is
// the case the decider must handle by WAITING LONGER rather than firing early.
let sentences = [
    "The meeting is at three. Can you remind me before it starts?",
    "I need to send an email to Sarah about the quarterly numbers and"
]

for sentence in sentences {
    await probe(sentence)
}

print("""

── how to read this ─────────────────────────────────────────────────────────
If volatiles carry sentence-final punctuation, EndpointDecider may use it as a
'looks complete' signal and shorten the silence window. If they do not, the
decider must rely on lexical-tail analysis alone. Either way it must never
REQUIRE punctuation: absence here is suggestive only (synthetic speech is
prosodically flat), and the decider's floor behaviour has to stay correct when
the signal is missing.
""")
