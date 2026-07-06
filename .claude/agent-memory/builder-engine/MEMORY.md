# Memory index — builder-engine (SpeakCore Engine)

One line per memory; loaded each session.

- [SpeechAnalyzer segment semantics](project-speechanalyzer-segment-semantics.md) — isFinal is per speech WINDOW not per utterance; CaptureSession must accumulate finalizedText across windows
- [Voice Actions H-1 skeleton](project-voice-actions-h1-skeleton.md) — standalone SpeakCore/VoiceActions/ module, NOT wired into the live pipeline yet; read before touching H-2/H-3/H-4
- [Moat catches real force-unwraps](feedback-moat-catches-real-forceunwraps.md) — make test (MoatAuditTests) is a second, independent force-unwrap gate beyond SwiftLint; run full gate sequence, don't assume lint alone covers it
