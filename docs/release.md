# Release — sign, notarize, package

This document describes the one-time manual setup required before `make release`
can produce a Gatekeeper-clean `.dmg`. The `make release` target is fully
implemented and automated; only the credentials are manual.

---

## Prerequisites

- macOS 26 (Tahoe) with Xcode 26+ installed and selected (`xcode-select -p`).
- An Apple Developer account enrolled in the Apple Developer Program ($99/yr).
- An App Store Connect API key *or* an Apple ID with an app-specific password
  (for notarization credentials; see §2 below).

---

## §1 — Install a Developer ID Application certificate (one-time)

A "Developer ID Application" certificate is required for Gatekeeper-compliant
distribution outside the App Store.

1. Open Xcode → Settings → Accounts → select your Apple ID → Manage Certificates.
2. Click the "+" and choose "Developer ID Application".
3. Xcode creates the key pair and installs the certificate in your login keychain.

Alternatively, request the cert from the Apple Developer portal, download the
`.cer`, and install it by double-clicking.

Verify it is present:
```
security find-identity -v -p codesigning | grep "Developer ID Application"
```

The output looks like:
```
  1) ABCDEF1234... "Developer ID Application: Jane Smith (TEAMID)"
```

That quoted string is your `DEV_ID`. You will pass it to `make release` below.

---

## §2 — Store notarization credentials (one-time)

`xcrun notarytool` reads credentials from the macOS keychain under a named
profile so your password never appears on the command line or in CI logs.

**Option A — App-specific password (simpler):**
```
xcrun notarytool store-credentials speak-notary \
  --apple-id you@example.com \
  --team-id YOUR10CHARTEAMID
```
You will be prompted for an app-specific password
(generate one at appleid.apple.com → App-Specific Passwords).

**Option B — App Store Connect API key (preferred for automation):**
```
xcrun notarytool store-credentials speak-notary \
  --key /path/to/AuthKey_KEYID.p8 \
  --key-id KEYID \
  --issuer ISSUER-UUID
```
Download the `.p8` from App Store Connect → Users and Access → Integrations → Keys.

The profile name `speak-notary` becomes your `NOTARY_PROFILE` variable.
Use any name you like — just be consistent.

---

## §3 — Run `make release`

```
DEV_ID="Developer ID Application: Jane Smith (TEAMID)" \
NOTARY_PROFILE="speak-notary" \
make release
```

What it does, step by step:

| Step | Tool | Notes |
|------|------|-------|
| XcodeGen | `xcodegen generate` | Regenerates `Speak.xcodeproj` |
| Archive | `xcodebuild archive -configuration Release` | Produces `build/release/Speak.xcarchive` |
| Export | `xcodebuild -exportArchive` + `scripts/export-options.plist` | Developer ID signing applied by `exportArchive` — signs `SpeakCore.framework` inside-out correctly; hardened runtime + timestamp are set via the archive/export path `[inferred]` — verify with `codesign -dvvv` if issues arise |
| Verify sig | `codesign --verify --deep --strict` | Fails fast if signing is incomplete |
| Package | `hdiutil create -format UDZO` | Creates `build/release/Speak.dmg` |
| Notarize | `xcrun notarytool submit --wait` | Submits to Apple; waits for a ticket |
| Staple | `xcrun stapler staple` | Attaches the notarization ticket to the `.dmg` |
| Gate check | `spctl --assess` | Verifies Gatekeeper accepts the result |

---

## §4 — Update the Homebrew cask formula

After a successful `make release`, compute the sha256 of the `.dmg`:

```
shasum -a 256 build/release/Speak.dmg
```

Update `dist/speak.cask.rb`:
- Replace `PLACEHOLDER_SHA256_REPLACE_AFTER_MAKE_RELEASE` with the actual sha256.
- Replace `yourusername` in the `url` with the actual GitHub org/user.
- Update `version` if this is not `0.1.0`.

To test the cask locally:
```
brew install --cask dist/speak.cask.rb
```

---

## §5 — Troubleshooting

**"No identity found"** — the Developer ID cert is not in the login keychain.
Run `security find-identity -v -p codesigning`. Re-run §1.

**"Notarization failed"** — Apple rejected the submission. Run:
```
xcrun notarytool log <submission-id> --keychain-profile speak-notary
```
Common causes: hardened runtime not enabled, unsigned nested code.
Check `codesign -dvvv Speak.app` for each embedded binary/framework.

**"spctl: rejected"** — Gatekeeper did not accept the `.dmg`. Either the
notarization ticket is missing (re-run `xcrun stapler staple`) or the signing
cert is not a Developer ID cert.

**"exportArchive fails"** — check that `scripts/export-options.plist` exists and
that the `method` key is `developer-id` (not `app-store-connect`).

---

## §6 — What is NOT automated (intentionally)

- Certificate creation — requires an interactive Xcode/browser session.
- Keychain credential storage — passwords must never be in source control.
- GitHub release creation — the orchestrator does this after verifying the `.dmg`.
- Homebrew tap PR — submit `dist/speak.cask.rb` to the tap repo manually.
