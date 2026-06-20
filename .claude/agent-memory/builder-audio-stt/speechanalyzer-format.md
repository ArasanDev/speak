---
name: speechanalyzer-format
description: SpeechAnalyzer bestAvailableAudioFormat returns 16kHz Int16 interleaved on macOS 26; comparing only sampleRate/channelCount misses the commonFormat difference
metadata:
  type: feedback
---

`SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith:)` returns **16kHz mono Int16 interleaved** on macOS 26.5 with the en-US model installed.

P2's `AudioCapture` outputs **16kHz mono Float32 non-interleaved**.

**Why this matters:** If you compare formats by `sampleRate` and `channelCount` only, they appear equal (both 16kHz mono) and no converter is built → feeding Float32 buffers to the analyzer crashes with "Audio sample data must be 16-bit signed integers".

**How to apply:** Always compare `commonFormat` AND `isInterleaved` in addition to `sampleRate` and `channelCount` when checking if formats match. Build `AVAudioConverter(from: p2Format, to: analyzerFormat)` whenever any dimension differs.

The converter from P2 Float32 non-interleaved → Int16 interleaved works correctly via AVAudioConverter.

Note: P2 could be improved to output native mic format and let P3 do a single conversion. Currently P2→16kHz conversion + P3→Int16 conversion is two steps. Not a bug, but a latency optimization opportunity for P13.

Related: [[speechanalyzer-lifecycle]]
