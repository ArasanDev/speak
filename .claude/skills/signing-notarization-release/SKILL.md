---
name: signing-notarization-release
description: Code-sign, notarize, and package the speak app into a Gatekeeper-clean .dmg plus a Homebrew Cask, at roadmap P11. Use when building the release pipeline (make release), debugging notarization/Gatekeeper, or writing the cask formula.
---

# Release — sign, notarize, package (`speak`, roadmap P11)

The P11 distribution pipeline. macOS 26 (Tahoe) requires Gatekeeper-compliant
notarization `[verified]`. All tools below are Apple-shipped or dev tooling — no
runtime dependency added. `make release` orchestrates the whole chain.

## The chain (verify exact flags against current Apple docs at P11)

1. **Sign** with a **Developer ID Application** cert + hardened runtime:
   `codesign --sign "Developer ID Application: …" --options runtime --timestamp …`
   Sign `SpeakCore.framework` and any nested code first, then the `.app` (inside-out).
2. **Notarize** with `xcrun notarytool` (the current tool — `altool` is removed):
   `xcrun notarytool submit Speak.dmg --keychain-profile <profile> --wait`.
   Store creds once via `xcrun notarytool store-credentials`.
3. **Staple**: `xcrun stapler staple Speak.app` (and/or the `.dmg`).
4. **Package** a `.dmg` (e.g. `create-dmg` or `hdiutil`).
5. **Homebrew Cask**: `dist/speak.cask.rb` per the [Cask Cookbook](https://docs.brew.sh/Cask-Cookbook).

## Done-when (roadmap P11)

- `make release` produces a **signed + notarized** `.dmg`
- `brew install --cask <local-cask>` works on a clean machine
- Gatekeeper shows "verified" (no "unidentified developer")
- Cask formula follows the Cask Cookbook

## Unverified / open at P11 — do not assume

- **Developer ID signing cert availability** is unverified (Open Q#4) — confirm a
  valid cert + notarization credentials exist before claiming the pipeline works.
- Exact `notarytool`/`codesign` flag sets and entitlements **drift by OS/Xcode
  version** — re-check against current Apple docs at P11; tag inferred bits
  `[inferred]`, mark untested ones `[unverified]`.
- App is **not sandboxed** in v0 (intentional — needs Accessibility/Input Monitoring).
  Notarization still applies; sandbox entitlement does not.

`fastlane` is deliberately **not** used — `xcrun notarytool` + `codesign` cover
the macOS path without a Ruby dependency or its known signing-automation issues.
