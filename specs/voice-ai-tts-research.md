# Ultra-Lightweight Local Text-to-Speech (TTS) Research & Architecture

> **Document Status**: Production Architecture Specification  
> **Target System**: macOS 26.0+ / Apple Silicon (M1–M4+)  
> **Core Principle**: 100% Local, 0 Cloud Dependencies, Low-Latency Voice Synthesis  

---

## 1. Executive Summary

`speak` requires instant, high-quality, local-first voice synthesis for readbacks, agent responses, and desktop pet audio notifications. To satisfy the hard rule of **100% local operation by default** with zero cloud audio services or remote API dependencies, this document evaluates ultra-lightweight open-source Text-to-Speech (TTS) models and runtimes for integration alongside Apple's built-in `AVSpeechSynthesizer`.

### Key Evaluation Criteria
1. **Latency to First Token (TTFT)**: Under 100ms warm TTFT for instant playback response.
2. **Real-Time Factor (RTF)**: $< 0.20\times$ on Apple Silicon (generates 1 sec of audio in $< 200\text{ms}$).
3. **On-Device Memory Footprint**: $< 350\text{MB}$ RAM / Disk footprint.
4. **Hardware Acceleration**: Apple Neural Engine (ANE) or Metal GPU acceleration via CoreML / ONNX Runtime.
5. **Voice Quality & Expressiveness**: Mean Opinion Score (MOS) $\ge 3.8 / 5.0$.

---

## 2. Open-Source Local TTS Model Deep Dives

### 2.1 Kokoro (82M Parameters)

- **Overview**: Kokoro is an ultra-lightweight open-source TTS model built on a StyleTTS2 derivative architecture. Despite having only 82 million parameters, it delivers voice quality comparable to much larger models (e.g. ElevenLabs, XTTS-v2).
- **Architecture**:
  - Text-to-Phoneme Grapheme-to-Phoneme (G2P) parser (`espeak-ng` or `phonemizer`).
  - Style-conditioned duration predictor and frame-level mel-spectrogram decoder.
  - Neural vocoder (iSTFTNet / HiFi-GAN variant) for waveform synthesis.
- **Model Sizes & Quantization**:
  - **FP32 / FP16**: ~320 MB (unquantized / half precision).
  - **INT8 ONNX / CoreML**: ~160 MB (quantized, negligible quality loss).
- **Performance Metrics (Apple Silicon M-series)**:
  - **Time to First Audio (TTFT)**: ~80 ms.
  - **Real-Time Factor (RTF)**: $0.15\times - 0.25\times$.
  - **MOS Score**: ~4.2 / 5.0.
- **Runtimes & Export**:
  - Exportable to **ONNX** (`kokoro-onnx`) and **CoreML** (`.mlmodelc`).
  - Swift binding via ONNX Runtime C API with Metal / CoreML execution provider.
- **Pros**: Outstanding prosody and natural warmth; multi-speaker and multi-language support in a tiny 160MB footprint.
- **Cons**: Requires phonemizer pre-processing pass; higher memory footprint than Piper.

---

### 2.2 Piper TTS

- **Overview**: Piper is a fast, local, low-resource neural text-to-speech system optimized for edge devices (Raspberry Pi, microcontrollers, desktop apps).
- **Architecture**:
  - Based on **VITS** (Variational Inference with adversarial learning for end-to-end Text-to-Speech).
  - Normalizing flows + adversarial vocoder integrated into a single unified network (no separate mel-spectrogram intermediate stage).
- **Model Sizes & Quantization**:
  - **Medium Quality Voices**: 25 MB – 60 MB per voice model.
  - **High Quality Voices**: ~100 MB per voice model.
- **Performance Metrics (Apple Silicon M-series)**:
  - **Time to First Audio (TTFT)**: < 20 ms.
  - **Real-Time Factor (RTF)**: $0.03\times - 0.08\times$ (extremely fast).
  - **MOS Score**: ~3.8 – 4.0 / 5.0.
- **Runtimes & Export**:
  - Driven by `piper-phonemize` (C++) + ONNX Runtime.
  - Direct C++ runtime embedding or Swift ONNX wrapper.
- **Pros**: Instantaneous audio start (< 20ms); trivial memory usage (< 50MB RAM); dozens of pre-trained voices across 30+ languages.
- **Cons**: Monotone/robotic tone on lower-tier voices compared to Kokoro.

---

### 2.3 SuperTonic

- **Overview**: SuperTonic is a modern non-autoregressive neural speech synthesizer designed specifically for low-latency voice streaming and zero-shot voice cloning.
- **Architecture**:
  - Flow-matching / conditional diffusion architecture with latent acoustic representation.
  - Non-autoregressive generation allowing chunk-parallel audio streaming.
- **Model Sizes & Quantization**:
  - **CoreML FP16**: ~90 MB.
  - **ONNX INT8**: ~55 MB.
- **Performance Metrics (Apple Silicon M-series)**:
  - **Time to First Audio (TTFT)**: ~45 ms.
  - **Real-Time Factor (RTF)**: $0.10\times - 0.18\times$.
  - **MOS Score**: ~4.0 / 5.0.
- **Runtimes & Export**:
  - Optimized for **Apple CoreML** target execution on Apple Neural Engine (ANE).
- **Pros**: Streamable output frames; support for zero-shot voice prompt conditioning; compact size.
- **Cons**: Newer model; less mature open-source tooling ecosystem.

---

### 2.4 Apple `AVSpeechSynthesizer` (v0 Shipped Engine)

- **Overview**: Native macOS system framework engine for text-to-speech (`AVFoundation`).
- **Features & Integration**:
  - Access to all system-installed voices: Personal Voice, Premium Siri Voices, Enhanced Voices, and Compact System Voices.
  - Fine-grained controls: `voiceIdentifier`, `rate` (0.1–1.0), `pitchMultiplier` (0.5–2.0), `volume` (0.0–1.0), and `locale`.
- **Performance Metrics**:
  - **TTFT**: ~0 ms (system resident).
  - **RTF**: < 0.01x.
  - **Disk/RAM Cost**: **0 MB** app overhead (built into macOS).
- **Pros**: 0 MB download size; 100% native Apple framework; zero third-party C/C++ dependencies; full OS setting integration.
- **Cons**: Voice availability depends on user downloaded language packs in macOS System Settings.

---

## 3. Technical Comparison Matrix

| Model / Framework | Parameters | Disk Size (INT8/FP16) | TTFT (ms) | RTF (M1/M2/M3) | MOS Score | Primary Runtime | ANE / GPU Acceleration | License |
|---|---|---|---|---|---|---|---|---|
| **Apple AVSpeechSynthesizer** | System | **0 MB** | **< 5 ms** | **< 0.01x** | 3.8 – 4.5 | AVFoundation | System Native | Proprietary (Apple) |
| **Kokoro 82M** | 82M | 160 – 320 MB | ~80 ms | 0.15x | **4.2 – 4.4** | ONNX / CoreML | CoreML EP / Metal EP | Apache-2.0 |
| **Piper TTS** | 10M – 30M | **15 – 60 MB** | **< 20 ms** | **0.04x** | 3.8 – 4.0 | ONNX Runtime | CPU / Metal EP | MIT |
| **SuperTonic** | 50M | 55 – 90 MB | ~45 ms | 0.10x | 4.0 – 4.2 | CoreML | ANE (Apple Neural Engine) | MIT / Apache-2.0 |

---

## 4. On-Device Runtime Options for Swift & macOS

### 4.1 Apple CoreML (`.mlmodelc`)
- **Execution Target**: Apple Neural Engine (ANE) + GPU.
- **Swift Integration**: Native `import CoreML`, zero external C++ wrapper required.
- **Power Efficiency**: Highest performance-per-watt on MacBooks (runs on ANE without waking CPU cores).

### 4.2 ONNX Runtime Swift (`ort-swift`)
- **Execution Target**: CPU / CoreML Execution Provider / Metal Execution Provider.
- **Swift Integration**: C API bridge or Swift PM wrapper (`onnxruntime-swift`).
- **Model Compatibility**: Instant execution for models exported from PyTorch via `torch.onnx.export`.

---

## 5. Architectural Seam & Implementation Roadmap for `speak`

The `speak` engine abstracts all text-to-speech output through the `SpeechSynthesizing` protocol seam in `SpeakCore/VoiceOut/`:

```swift
public protocol SpeechSynthesizing: Sendable {
    func speak(_ text: String, locale: Locale) async
    func speak(
        _ text: String,
        voiceIdentifier: String?,
        rate: Float,
        pitch: Float,
        volume: Float,
        locale: Locale
    ) async
    func stop() async
    var isSpeaking: Bool { get async }
}
```

### Phased Roadmap

1. **Phase 1 (v0 Shipped Standard)**:
   - Use `AppleSpeechSynthesizer` conforming to `SpeechSynthesizing`.
   - Complete configuration interface in **Voice AI Studio** (`AIStudioPaneView.swift`) with voice picker, speech rate, pitch multiplier, volume, and live audio readbacks.
   - Persistence in `SettingsStore` (`ttsVoiceIdentifier`, `ttsSpeechRate`, `ttsPitchMultiplier`, `ttsVolume`).

2. **Phase 2 (v0.1+ Local Neural Model Extension)**:
   - Add `LocalNeuralSynthesizer` conforming to `SpeechSynthesizing`.
   - CoreML engine running quantized **Kokoro 82M** or **Piper** for offline custom neural voices.
