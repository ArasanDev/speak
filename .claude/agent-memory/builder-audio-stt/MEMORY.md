# builder-audio-stt Memory Index

- [SpeechAnalyzer lifecycle hang fix](speechanalyzer-lifecycle.md) — analyzer.start() returns after setup; must call finalizeAndFinishThroughEndOfInput() or results loops forever
- [SpeechAnalyzer audio format](speechanalyzer-format.md) — bestAvailableAudioFormat returns 16kHz Int16 interleaved, not Float32; comparison must check commonFormat not just sampleRate
- [P3 implementation status](p3-status.md) — AppleSpeechTranscriber complete, 10/10 tests green, real transcription confirmed
