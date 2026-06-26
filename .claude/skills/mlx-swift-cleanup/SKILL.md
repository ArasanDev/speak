---
name: mlx-swift-cleanup
description: Use when implementing MLX Swift as an in-process LLM cleanup engine (v1 task V1-1) — runs entirely in-process with no external daemon, faster than Ollama for short texts on Apple Silicon.
---

# MLX Swift Cleanup — Implementation Pointer

## Architectural Seam

Protocol: `LLMCleaning` — lives at `SpeakCore/Cleanup/Cleaner.swift`
Target file to create: `SpeakCore/Cleanup/MLXModelCleaner.swift`
Engine id: `"mlx"` `[decision]`

Plug in via `EngineFactories.swift` behind `cleanupEngine = "mlx"`. The model download and initialization happen on first use; fallback to `FoundationModelsCleaner` if init fails.

## Hard Constraints

- **Apple Silicon required** — MLX uses the Neural Engine/GPU. Gate in `EngineFactories`: `#if arch(arm64)` + macOS version check. On Intel: disable option in Settings, show "Requires Apple Silicon" tooltip.
- **Model download is large** — Qwen3-0.6B ~600MB, 1.7B ~1.7GB, 4B ~4GB. Show download progress HUD before first use. Cache in `Application Support/speak/MLX/`.
- **RAM warning**: if `ProcessInfo.processInfo.physicalMemory < 8 * 1024 * 1024 * 1024` and user selects ≥1.7B model, show advisory: "This model may impact system performance on 8GB RAM Macs." `[decision]`
- **In-process**: MLX runs in the same process as `speak`. Peak RAM during inference = model size × ~1.2. Test on 8GB M1 before enabling 1.7B as default.
- **License**: MLX Swift is Apache 2.0 `[verified from research]` — compatible with speak's MIT. Confirm the specific model weights license (Qwen3: Apache 2.0 `[inferred]`) before shipping.
- No `print`. No force-unwrap. `os.Logger` only.

## SPM Dependency `[inferred — verify exact target names from the actual package]`

MLX Swift is split across repos. The LLM inference capability is in the examples repo:

```yaml
# In project.yml packages: section [inferred]
- url: https://github.com/ml-explore/mlx-swift-examples
  branch: "main"   # or pin to a release tag — check latest tag
```

Target name inside that package for LLM inference: **verify** — it may be `MLXLLM`, `LLMEval`, or similar. Do NOT guess — read the Package.swift inside the resolved checkout.

Alternatively, the community package `https://github.com/huggingface/swift-transformers` may offer a cleaner path `[unverified]`.

## API Shape `[unverified — ALL shapes must be verified from package source before coding]`

```swift
// This is the conceptual pattern — exact types/methods are [unverified]
import MLXLLM   // [unverified — may be a different module name]

// 1. Load model (async, ~2-10s on first run)
let modelConfig = ModelConfiguration(id: "mlx-community/Qwen3-0.6B-4bit")  // [inferred]
let (model, tokenizer) = try await load(configuration: modelConfig)          // [inferred]

// 2. Generate text
let prompt = "You are a writing assistant. Clean this transcript: \(rawText)"
let result = try await generate(                                              // [inferred]
    prompt: prompt,
    model: model,
    tokenizer: tokenizer,
    parameters: GenerateParameters(maxTokens: 500, temperature: 0.1)         // [inferred]
)
// result: String (the generated text)
```

**Do not ship code based on the above** without running `swift package resolve` and reading the actual Sources.

## Recommended Models

| HuggingFace ID | Size | Speed (M4 Max) | Use for |
|----------------|------|----------------|---------|
| `mlx-community/Qwen3-0.6B-4bit` | ~350MB | ~525 tok/s | **Default speed** |
| `mlx-community/Qwen3-1.7B-4bit` | ~1.0GB | ~200 tok/s | **Default quality** |
| `mlx-community/Qwen3-4B-4bit` | ~2.5GB | ~90 tok/s | Max quality |

All model IDs `[inferred from research]` — verify against `https://huggingface.co/mlx-community` at implementation time. The `-4bit` quantized versions are fastest; `-8bit` available for higher quality.

## Verify at Implementation Time

```sh
# 1. Resolve the package and find the correct target name
cd /tmp && mkdir mlx-probe && cd mlx-probe
cat > Package.swift << 'EOF'
// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "MLXProbe", platforms: [.macOS(.v14)],
  dependencies: [.package(url: "https://github.com/ml-explore/mlx-swift-examples", branch: "main")],
  targets: [.target(name: "MLXProbe", dependencies: [])])
EOF
swift package resolve
ls .build/checkouts/mlx-swift-examples/Libraries/  # find the LLM target name
# Read: .build/checkouts/mlx-swift-examples/Libraries/<LLM-target>/Sources/

# 2. Type-check your cleaner file
swiftc -typecheck -sdk "$(xcrun --show-sdk-path)" \
  -target arm64-apple-macosx26.0 MLXModelCleaner.swift

# 3. Smoke test: run inference on a short string and measure latency
# Target: <3s for 200-word transcript cleanup on M1/M2/M3
```

## First-Use Flow

1. User selects "MLX — Fast (Qwen3 0.6B)" in Settings → AI Cleanup → Engine
2. `MLXModelCleaner.init()` runs → checks if model cache exists
3. If not: show `MLXDownloadSheet` (progress bar, estimated size, "~350 MB download")
4. Download streams to `Application Support/speak/MLX/Qwen3-0.6B-4bit/`
5. Model loads into memory (~0.5s on M3) → engine ready
6. Next cleanup request uses the loaded model (keep in memory between cleanups; release after 60s idle to free RAM)
