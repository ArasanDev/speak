---
name: speechanalyzer-lifecycle
description: SpeechAnalyzer.start(inputSequence:) returns after setup, not after all input — finalizeAndFinishThroughEndOfInput() is mandatory to close transcriber.results
metadata:
  type: feedback
---

`SpeechAnalyzer.start(inputSequence:)` returns AFTER SETUP, NOT after all input is consumed.
`transcriber.results` stays open forever until `finalizeAndFinishThroughEndOfInput()` is called.

**Why:** WWDC25 #277 confirms this. Without finalize, the `for try await result in transcriber.results` loop in the results task never exits → the session task never returns → the output stream never finishes → any `for try await` consuming the stream hangs forever.

**How to apply:** In Session.run(), the correct order is:
1. `try await analyzer.start(inputSequence: inputStream)` — setup only
2. Feed AnalyzerInput via the bridge task
3. `await bridgeTask.value` — wait for all input to be fed
4. `try await analyzer.finalizeAndFinishThroughEndOfInput()` — closes transcriber.results
5. `_ = try await resultsTask.value` — drain remaining results

Also: `stopSession()` must call `audioProducer.stop()` (not just finish the input continuation) to end the buffer stream and trigger the bridge task exit, which then allows finalize to run.

Related: [[speechanalyzer-format]]
