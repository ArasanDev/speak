// E7 — how long after the human stops speaking does the volatile carrying their
// last words actually arrive?
//
// WHY THIS GATES THE WHOLE ENDPOINTING DESIGN
// `EndpointDecider` chooses a silence window from the live transcript, and the
// plan is to apply it by retuning `VoiceActivityDetector.silenceThresholdDuration`
// as partials arrive. The VAD counts silence against whatever the config says at
// the moment each buffer is processed, so the timeline is:
//
//   t=0    human stops on "…numbers and"; the VAD starts accumulating silence
//   t=L    the volatile containing "and" arrives; we widen 0.60 -> 0.90
//   t=0.60 the VAD fires .speechEnded IF nobody widened the window first
//
// The lengthening half of the decider therefore only works when L < 0.60 s, and
// lengthening is the half that carries the safety argument — it is the reason
// the feature was called safe to enable by default. Shortening degrades
// gracefully (a late 0.20 s window just trips immediately, which is the intent
// anyway); lengthening does not degrade, it silently does nothing, and the
// utterance gets truncated exactly as it does today.
//
// E6 measured volatile->final (174 ms) and drained-input->final (40-80 ms).
// Neither is this number. Nothing measured has been audio->volatile.
//
// WHAT MAKES THIS DIFFERENT FROM E6, AND WHY A SEPARATE SCRIPT
// E6 calls `finalizeAndFinishThroughEndOfInput()` the instant the audio runs
// out. That is correct for E6's question and fatal for this one: forcing a
// flush manufactures a fast arrival that the live pipeline would never produce.
// A real microphone does not stop when the human does — it keeps delivering
// silence. So this probe feeds REAL SILENCE at real time after the utterance
// and watches the clock, and only finalizes once that window has elapsed.
//
// Reading the verdict:
//   L < 250 ms  — the retune-the-VAD design is sound with margin.
//   250-600 ms  — it works, but the margin is thin enough to be worth pinning.
//   L >= 600 ms — the design is INVALID. The VAD has already fired by the time
//                 the text that would have widened the window exists, and
//                 endpointing has to key off transcript arrival instead of
//                 audio silence. That is a different object, not a tweak.

import AVFoundation
import Foundation
import Speech

let clock = ContinuousClock()

func ms(_ duration: Duration) -> Double {
    let components = duration.components
    return Double(components.seconds) * 1000 + Double(components.attoseconds) / 1e15
}

/// How long to keep feeding silence after the utterance, mimicking a live mic.
/// Comfortably past the 600 ms the VAD would fire at, so the interesting region
/// is fully observed rather than clipped.
let tailSilenceSeconds = 2.0

// ------------------------------------------------------------- synthesis ----

/// Renders `text` to PCM via `AVSpeechSynthesizer.write`. Mirrors E6.
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

// --------------------------------------------------------------- silence ----

/// A zero-filled buffer in `format`, holding `seconds` of audio.
///
/// The point of the experiment is that the analyzer keeps receiving input after
/// the speech ends, exactly as `AudioCapture` keeps tapping the mic. Zeroed
/// explicitly rather than trusting the allocator: garbage here would read as
/// noise and could hold the recognizer open.
func silenceBuffer(format: AVAudioFormat, seconds: Double) -> AVAudioPCMBuffer? {
    let frames = AVAudioFrameCount(format.sampleRate * seconds)
    guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else {
        return nil
    }
    buffer.frameLength = frames
    let channels = Int(format.channelCount)
    if let floats = buffer.floatChannelData {
        for channel in 0..<channels {
            memset(floats[channel], 0, Int(frames) * MemoryLayout<Float>.size)
        }
    } else if let int16s = buffer.int16ChannelData {
        for channel in 0..<channels {
            memset(int16s[channel], 0, Int(frames) * MemoryLayout<Int16>.size)
        }
    } else if let int32s = buffer.int32ChannelData {
        for channel in 0..<channels {
            memset(int32s[channel], 0, Int(frames) * MemoryLayout<Int32>.size)
        }
    } else {
        return nil
    }
    return buffer
}

// ------------------------------------------------------------- rechunking ---

/// The raw base address of a mono buffer's sample storage, whatever its depth.
func rawChannelPointer(_ buffer: AVAudioPCMBuffer) -> UnsafeMutableRawPointer? {
    if let floats = buffer.floatChannelData { return UnsafeMutableRawPointer(floats[0]) }
    if let int16s = buffer.int16ChannelData { return UnsafeMutableRawPointer(int16s[0]) }
    if let int32s = buffer.int32ChannelData { return UnsafeMutableRawPointer(int32s[0]) }
    return nil
}

/// Re-slice `buffers` into uniform `chunkSeconds` buffers, preserving samples.
///
/// This is the whole point of the chunk sweep. `AVSpeechSynthesizer.write`
/// hands back ~11 ms buffers; `AudioCapture` installs its tap at 4096 frames,
/// which is ~85 ms at a 48 kHz input rate — roughly 8x coarser, and 8x fewer
/// `AnalyzerInput` yields per second. If the analyzer's partial cadence were a
/// function of how input arrives rather than of the clock, feeding it the
/// synthesizer's fine-grained buffers would understate the real latency and the
/// whole E7 verdict would be an artifact of the harness. Sweeping the chunk size
/// over the production value and past it settles that without a microphone.
///
/// Mono only, which is what both the synthesizer and the capture path produce;
/// returns nil rather than guessing at an interleaved multi-channel layout.
func rechunk(_ buffers: [AVAudioPCMBuffer], chunkSeconds: Double) -> [AVAudioPCMBuffer]? {
    guard let format = buffers.first?.format, format.channelCount == 1 else { return nil }
    let bytesPerFrame = Int(format.streamDescription.pointee.mBytesPerFrame)
    let chunkFrames = Int(format.sampleRate * chunkSeconds)
    guard bytesPerFrame > 0, chunkFrames > 0 else { return nil }

    var bytes: [UInt8] = []
    for buffer in buffers {
        guard let base = rawChannelPointer(buffer) else { return nil }
        let count = Int(buffer.frameLength) * bytesPerFrame
        bytes.append(contentsOf: UnsafeRawBufferPointer(start: base, count: count))
    }

    let totalFrames = bytes.count / bytesPerFrame
    var chunks: [AVAudioPCMBuffer] = []
    var offset = 0
    while offset < totalFrames {
        let frames = min(chunkFrames, totalFrames - offset)
        guard let chunk = AVAudioPCMBuffer(pcmFormat: format,
                                           frameCapacity: AVAudioFrameCount(frames)),
              let destination = rawChannelPointer(chunk)
        else { return nil }
        chunk.frameLength = AVAudioFrameCount(frames)
        let copied: Bool = bytes.withUnsafeBytes { source in
            guard let base = source.baseAddress else { return false }
            memcpy(destination, base.advanced(by: offset * bytesPerFrame), frames * bytesPerFrame)
            return true
        }
        guard copied else { return nil }
        chunks.append(chunk)
        offset += frames
    }
    return chunks
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

/// Collects the per-utterance L values so the verdict can speak to the worst
/// case rather than the average — one utterance whose transcript lands after
/// 600 ms is enough to break the lengthening path.
typealias Sample = (sentence: String, fast: Bool, chunkMs: Int, words: Double, punct: Double)

final class Tally: @unchecked Sendable {
    private let lock = NSLock()
    private var samples: [Sample] = []

    func record(sentence: String, fast: Bool, chunkMs: Int, words: Double, punct: Double) {
        lock.lock()
        samples.append((sentence, fast, chunkMs, words, punct))
        lock.unlock()
    }

    func all() -> [Sample] {
        lock.lock()
        defer { lock.unlock() }
        return samples
    }
}

let tally = Tally()

/// `chunkMs == 0` means "feed the synthesizer's native buffers", the original
/// E7 behaviour. Anything else re-slices to that cadence first.
func probe(_ sentence: String, fast: Bool, chunkMs: Int) async {
    let feed = chunkMs == 0 ? "native" : "\(chunkMs)ms"
    print("\n── [\(fast ? "fastResults" : "progressive ")|\(feed)] utterance: \"\(sentence)\"")

    let synthesized = await synthesize(sentence)
    guard let sourceFormat = synthesized.first?.format, !synthesized.isEmpty else {
        print("   synthesis produced no audio — skipped")
        return
    }
    var rendered = synthesized
    if chunkMs > 0 {
        guard let resliced = rechunk(synthesized, chunkSeconds: Double(chunkMs) / 1000.0) else {
            print("   could not re-chunk to \(chunkMs)ms — skipped rather than silently measuring native buffers")
            return
        }
        rendered = resliced
    }
    let totalFrames = rendered.reduce(0) { $0 + Int($1.frameLength) }
    let audioSeconds = Double(totalFrames) / sourceFormat.sampleRate
    print(String(format: "   synthesized %.2fs of audio (%d buffers @ %.0f Hz, ~%.0f ms each)",
                 audioSeconds, rendered.count, sourceFormat.sampleRate,
                 audioSeconds / Double(rendered.count) * 1000))

    guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "en-US")) else {
        print("   en-US unsupported — skipped")
        return
    }

    // `.progressiveTranscription` is what the app ships. `fastResults` is the
    // documented lever for lower-latency partials, and whether it moves the ~1 s
    // partial cadence is the single question that decides if any transcript-based
    // endpointing is possible at all.
    let transcriber = fast
        ? SpeechTranscriber(locale: locale,
                            transcriptionOptions: [],
                            reportingOptions: [.volatileResults, .fastResults],
                            attributeOptions: [])
        : SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
    let status = await AssetInventory.status(forModules: [transcriber])
    if status != .installed {
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

    // ---- feed the utterance at approximately real time ----
    for buffer in rendered {
        guard let converted = convert(buffer, using: converter, to: analyzerFormat) else { continue }
        inputContinuation.yield(AnalyzerInput(buffer: converted))
        let seconds = Double(buffer.frameLength) / sourceFormat.sampleRate
        try? await Task.sleep(for: .milliseconds(Int(seconds * 1000)))
    }

    // t=0 for the measurement: the last frame of speech has been handed over.
    // This is the instant a real VAD would start counting silence.
    let audioDoneMs = ms(start.duration(to: clock.now))

    // ---- keep the mic open: real silence, real time, no finalize ----
    let chunkSeconds = 0.1
    if let silence = silenceBuffer(format: sourceFormat, seconds: chunkSeconds) {
        var elapsed = 0.0
        while elapsed < tailSilenceSeconds {
            if let converted = convert(silence, using: converter, to: analyzerFormat) {
                inputContinuation.yield(AnalyzerInput(buffer: converted))
            }
            try? await Task.sleep(for: .milliseconds(Int(chunkSeconds * 1000)))
            elapsed += chunkSeconds
        }
    } else {
        print("   could not build a silence buffer — L would be measured against a forced flush, skipping")
        inputContinuation.finish()
        return
    }
    let silenceDoneMs = ms(start.duration(to: clock.now))

    inputContinuation.finish()
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

    print(String(format: "   speech ends at %.0f ms; silence fed until %.0f ms", audioDoneMs, silenceDoneMs))
    for observation in observations {
        let kind = observation.isFinal ? "FINAL" : "vol  "
        let delta = observation.atMs - audioDoneMs
        // Anything after the silence window only exists because finalization
        // forced it, so it cannot count toward a number about natural arrival.
        let zone = observation.atMs > silenceDoneMs ? "  (post-finalize)" : ""
        print(String(format: "   %8.1f ms  %@ %+7.0f ms  %@%@",
                     observation.atMs, kind, delta, pad(observation.text, 0), zone))
    }

    // TWO latencies, not one, because EndpointDecider's two halves depend on
    // two different signals that do not arrive together:
    //
    //   L_words — when the last WORD of the utterance appears. This is what the
    //             dangling-tail rule needs: it can only see "…and" once "and"
    //             is in the transcript. Drives the LENGTHENING half.
    //   L_punct — when terminal punctuation appears on a volatile. Drives the
    //             SHORTENING half, i.e. the entire advertised 400 ms win.
    //
    // Collapsing them into "the last volatile" hides the fact that one may be
    // usable while the other is not.
    let naturalVolatiles = observations.filter { !$0.isFinal && $0.atMs <= silenceDoneMs }
    guard let richest = naturalVolatiles.max(by: { wordCount($0.text) < wordCount($1.text) }) else {
        print("   NO volatile arrived during the silence window — the decider would")
        print("   have had nothing newer than the pre-silence transcript to act on.")
        tally.record(sentence: sentence, fast: fast, chunkMs: chunkMs, words: .infinity, punct: .infinity)
        return
    }
    // The first volatile that reaches the full word count — later volatiles with
    // the same count only add punctuation or rewrite, and the tail rule could
    // already have fired on this one.
    let target = wordCount(richest.text)
    let firstComplete = naturalVolatiles.first { wordCount($0.text) >= target } ?? richest
    let wordsLatency = firstComplete.atMs - audioDoneMs

    let firstPunctuated = naturalVolatiles.first { terminalPunctuation($0.text) != nil }
    let punctLatency = firstPunctuated.map { $0.atMs - audioDoneMs } ?? .infinity

    print(String(format: "   ── L_words = %+.0f ms   \"%@\"", wordsLatency, firstComplete.text))
    if let firstPunctuated {
        print(String(format: "   ── L_punct = %+.0f ms   \"%@\"", punctLatency, firstPunctuated.text))
    } else {
        print("   ── L_punct = never (no volatile was punctuated inside the silence window)")
    }
    tally.record(sentence: sentence, fast: fast, chunkMs: chunkMs, words: wordsLatency, punct: punctLatency)
}

func wordCount(_ text: String) -> Int {
    text.split(whereSeparator: { $0.isWhitespace }).count
}

/// Sentence-final punctuation — the signal the shortening half depends on.
func terminalPunctuation(_ text: String) -> Character? {
    guard let last = text.trimmingCharacters(in: .whitespacesAndNewlines).last else { return nil }
    return ".?!".contains(last) ? last : nil
}

func pad(_ text: String, _ width: Int) -> String {
    text.count >= width ? text : text + String(repeating: " ", count: width - text.count)
}

// ------------------------------------------------------------------- main ---

print("=== E7: audio -> volatile arrival latency (L) ===")
print("Purpose: decide whether EndpointDecider can drive the VAD's silence window.")
print(String(format: "Method: feed speech at real time, then %.1fs of real silence, finalize last.",
             tailSilenceSeconds))

// The same mid-thought utterances E6 used, because those are precisely the ones
// whose transcripts must arrive in time to LENGTHEN the window. A complete
// sentence arriving late is harmless; "…numbers and" arriving late is the bug.
let sentences = [
    "I need to send an email to Sarah about the quarterly numbers and",
    "I want to send this to",
    "The reason is because",
    "Put it in the",
    "The meeting is at three. Can you remind me before it starts?"
]

// The sweep. `chunkMs: 85` is the production feed shape — `AudioCapture` taps at
// 4096 frames, which is ~85 ms at a 48 kHz hardware input rate. `0` is the
// synthesizer's native ~11 ms buffers, i.e. how E7 measured this the first time.
// `250` overshoots production deliberately: three points spanning a 20x range
// either move the cadence or establish that nothing about the feed controls it.
//
// `fastResults` is re-run at the production chunk size rather than at native,
// because "the lever does nothing" is only worth asserting under a realistic feed.
let configurations: [(fast: Bool, chunkMs: Int)] = [
    (false, 0),
    (false, 85),
    (false, 250),
    (true, 85)
]

for configuration in configurations {
    let options = configuration.fast ? "[.volatileResults, .fastResults]" : ".progressiveTranscription preset"
    let feed = configuration.chunkMs == 0 ? "native synthesizer buffers" : "\(configuration.chunkMs) ms chunks"
    print("\n════ \(options) · feed: \(feed) ════")
    for sentence in sentences {
        await probe(sentence, fast: configuration.fast, chunkMs: configuration.chunkMs)
    }
}

let samples = tally.all()

print("\n── verdict ──────────────────────────────────────────────────────────────────")
guard !samples.isEmpty else {
    print("no utterances scored — nothing can be concluded.")
    exit(0)
}

let vadWindow = 600.0
let shortWindow = 200.0

func format(_ value: Double) -> String {
    value.isFinite ? String(format: "%+7.0f ms", value) : "   never"
}

print("   L_words    L_punct   feed        opts   utterance")
for sample in samples {
    let feed = sample.chunkMs == 0 ? "native" : "\(sample.chunkMs)ms"
    let opts = sample.fast ? "fast" : "prog"
    print("   \(format(sample.words))  \(format(sample.punct))   \(feed.padding(toLength: 10, withPad: " ", startingAt: 0))  \(opts)   \(sample.sentence)")
}

// The discriminator the whole re-run exists for: if the feed shape controlled
// the cadence, these per-feed worst cases would separate. If they do not, the
// cadence is a property of the analyzer and the native-buffer measurement was
// never a harness artifact.
print("\n── does the feed shape move it? (worst L_words per feed, progressive only) ──")
let feedSizes = Array(Set(samples.filter { !$0.fast }.map(\.chunkMs))).sorted()
for size in feedSizes {
    let group = samples.filter { !$0.fast && $0.chunkMs == size }
    let worst = group.map(\.words).max() ?? .infinity
    let best = group.map(\.words).min() ?? .infinity
    let label = size == 0 ? "native (~11 ms)" : "\(size) ms chunks"
    print("   \(label.padding(toLength: 18, withPad: " ", startingAt: 0)) best \(format(best))   worst \(format(worst))")
}

let worstWords = samples.map(\.words).max() ?? .infinity
let worstPunct = samples.map(\.punct).max() ?? .infinity

print("\n── the LENGTHENING half (dangling tails, the safety property) ──")
if worstWords >= vadWindow {
    print("""
       worst L_words = \(format(worstWords).trimmingCharacters(in: .whitespaces)) >= \(Int(vadWindow)) ms  — INERT as designed.
       The tail word that would widen the window is not in the transcript when
       the VAD fires. Retuning the threshold from the transcript cannot work;
       the endpoint has to be gated on transcript arrival, not audio silence.
    """)
} else {
    print("""
       worst L_words = \(format(worstWords).trimmingCharacters(in: .whitespaces)) < \(Int(vadWindow)) ms  — usable.
       The tail is in the transcript before the VAD fires, so widening the
       window from a dangling tail is a real mechanism.
    """)
}

print("\n── the SHORTENING half (terminal punctuation, the advertised 400 ms) ──")
if worstPunct >= vadWindow {
    print("""
       worst L_punct = \(format(worstPunct).trimmingCharacters(in: .whitespaces)) >= \(Int(vadWindow)) ms  — WORTHLESS, and worse than worthless.
       Punctuation does not appear on a volatile until long after the point at
       which the \(Int(shortWindow)) ms window would have fired. Waiting for it does not save
       400 ms, it COSTS the difference. E6's 174 ms volatile->final gap was
       measured against an immediate finalize; both events sit far past the
       endpoint in a live pipeline, so that gap never implied early arrival.
    """)
} else {
    print("""
       worst L_punct = \(format(worstPunct).trimmingCharacters(in: .whitespaces))  — arrives inside the window; the signal is usable.
    """)
}

print("""

── how to read this ─────────────────────────────────────────────────────────
L is measured from the last frame of SPEECH handed to the analyzer, which is
the same instant a live VAD starts counting silence. It is not measured from
end-of-input: this probe deliberately keeps feeding silence and finalizes only
afterwards, because finalization forces a flush that a live microphone never
provides. Results printed as (post-finalize) are excluded from L for that
reason.

Synthetic speech is prosodically flat and cleanly bounded, so a real speaker
trailing off quietly may well be slower than this. Treat the measured L as a
LOWER bound on the live number, which is the conservative direction for a
result that says the design is safe.
""")
