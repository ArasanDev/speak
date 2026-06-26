---
name: foundation-models-provider-api
description: Use when implementing WWDC26 Foundation Models provider API (v1 task V1-13) — the macOS 26 API that lets Anthropic, Google, and MLX models work behind the same LanguageModelSession interface as the on-device model.
---

# Foundation Models Provider API (WWDC26) — Implementation Pointer

## Confirmed at WWDC26 `[inferred from official sources]`

The **`LanguageModel` protocol** is the public Swift integration point. Third-party providers
implement this protocol; `LanguageModelSession` accepts them behind the same call site.
Zero changes to `FoundationModelsCleaner.swift` are needed to adopt future providers.

Source: WWDC26 session "What's new in Foundation Models" —
https://developer.apple.com/videos/play/wwdc2026/241/

Still verify the exact protocol shape via `apple-docs` MCP at implementation time — the
above confirms the pattern but NOT the exact method signatures or initializer parameters.

---

## ⚠️ WARNING: Exact API shapes are `[inferred from official sources]` — verify before coding

This API was introduced at WWDC26. Do NOT write a single line of code based on this skill
alone. Verify every symbol against the **local macOS 26 SDK** before coding.

## What We Know

Apple added a **provider API** to `FoundationModels` at WWDC26, allowing third-party model providers to work behind the same `LanguageModelSession` interface. `[inferred from official sources]`

Key insight: **`FoundationModelsCleaner.swift` likely needs zero code changes** to adopt future providers — if the provider API is purely additive (new factory methods on `LanguageModelSession` or a new session init). The existing cleanup code already uses `LanguageModelSession` correctly. `[inferred from official sources]`

Providers confirmed at WWDC26: `[inferred from official sources]`
- Anthropic (cloud, requires API key)
- Google (cloud, requires API key)
- MLX (local in-process — most relevant for `speak`)

## Architectural Seam

Existing file: `SpeakCore/Cleanup/FoundationModelsCleaner.swift`
New file (if needed): `SpeakCore/Cleanup/ProviderSessionFactory.swift`

The goal: a `cleanupEngine = "foundation-models-provider"` setting that lets power users specify which provider to route through, while the `FoundationModelsCleaner` code itself stays the same.

## Hypothetical API Shape `[unverified — DO NOT USE WITHOUT SDK VERIFICATION]`

These are educated guesses based on WWDC26 session titles and Apple's typical API patterns:

```swift
import FoundationModels

// Hypothesis A: new factory method on LanguageModelSession [unverified]
// let session = LanguageModelSession(provider: .anthropic(apiKey: "..."), instructions: "...")
// let session = LanguageModelSession(provider: .mlx(modelPath: "..."), instructions: "...")

// Hypothesis B: new LanguageModelConfiguration type [unverified]
// let config = LanguageModelConfiguration(provider: .mlx(...))
// let session = LanguageModelSession(configuration: config, instructions: "...")

// The existing pattern (already in FoundationModelsCleaner — known [verified]):
let session = LanguageModelSession(instructions: systemPrompt)
let response = try await session.respond(to: userPrompt)
```

**Do not assume either hypothesis is correct.** The actual API may look completely different.

## Verify at Implementation Time — This Is Not Optional

```sh
# Step 1: Check what FoundationModels exports in the local macOS 26 SDK
xcrun swift-stdlib-tool --list -bundle "$(xcrun --show-sdk-path)/System/Library/Frameworks/FoundationModels.framework"

# Step 2: Probe the type-checker with your hypothesis
cat > /tmp/fm_provider_probe.swift << 'EOF'
import FoundationModels
// Try your hypothesized API here
// e.g.: let _ = LanguageModelSession.Provider.self  // does this type exist?
EOF
swiftc -typecheck \
  -sdk "$(xcrun --show-sdk-path)" \
  -target arm64-apple-macosx26.0 \
  /tmp/fm_provider_probe.swift
# If it exits 0 with no error → the symbol exists [verified]
# If it errors → wrong hypothesis, try another shape

# Step 3: Use apple-docs MCP
# Query: "LanguageModelSession provider" in FoundationModels framework
# Look for any type named Provider, LanguageModelProvider, SessionConfiguration
```

## What To Do If the API Doesn't Exist Yet

macOS 26.0 shipped with the on-device model only. The provider API may have been announced at WWDC26 but ship in a later point release (26.1, 26.2). Check:

```sh
xcrun swift package describe --type json 2>/dev/null | grep FoundationModels
# Or: check macOS version gating in SDK headers
```

If the API isn't in the local SDK: **log it as `[unverified — not in local SDK <version>]`** in progress.md and defer V1-13 until the SDK update lands. Do not stub a fake implementation.

## Hard Constraint

This is the only skill where `[unverified]` is the expected state before implementation. Do not convert any claim to `[verified]` until you have run the `swiftc -typecheck` probe above and it exits 0 with no errors on that specific symbol.
