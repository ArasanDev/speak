---
name: speechanalyzer-segment-semantics
description: SpeechAnalyzer progressiveTranscription emits one isFinal chunk per speech WINDOW (not per utterance); CaptureSession must accumulate finalizedText across windows for correct paste.
metadata:
  type: project
---

SpeechAnalyzer with `.progressiveTranscription` emits chunks in two modes:
- **volatile (isFinal=false)**: cumulative per speech window — each successive volatile for a window contains MORE of that window's hypothesis. Replace semantics work for the HUD (newest-non-empty rule via `OverlayTextAccumulator`).
- **final (isFinal=true)**: one per speech window, containing only THAT window's text. For a long utterance spanning multiple windows, there are multiple isFinal chunks — each with per-window-only text.

**Why:** The truncation P0 bug (2026-06-22) showed that `latestChunk = chunk` (replace on every chunk) meant only the last window's text landed in `rawText`. `finalizedText` was added to `CaptureSession.ingest()` to accumulate all isFinal segments space-separated.

**How to apply:** Any future change to `CaptureSession.ingest()` or `stop()` must preserve `finalizedText` accumulation. Any new STT backend must be evaluated for whether it follows this same per-window-final model or emits whole-utterance finals.

**Separator note:** `" "` chosen; Apple's segments may already carry leading whitespace (unverified). Revisit with live multi-segment corpus if double-spaces appear. [[project-overlay-hud-accumulator]]
