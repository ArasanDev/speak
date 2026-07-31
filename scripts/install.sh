#!/usr/bin/env bash
# scripts/install.sh — one-line installer for speak (build-from-source, no cert needed).
#
#   curl -fsSL https://raw.githubusercontent.com/ArasanDev/speak/main/scripts/install.sh | bash
#
# What this does, and why it needs no Apple Developer credential:
#   1. Clones the repo to a temp dir (shallow, main branch).
#   2. make build CONFIG=Release  — xcodegen + xcodebuild, Apple-frameworks only.
#   3. Ad-hoc code-signs the app (codesign -s -) — free, no cert, no account.
#   4. Copies Speak.app to /Applications and clears the quarantine attribute
#      (xattr -cr) so Gatekeeper never shows the "unidentified developer" prompt
#      in the first place — the manual xattr step some projects ask users to
#      run themselves is done here automatically.
#   5. Prints the permissions speak will ask for on first launch.
#
# This mirrors `make install` exactly; it exists so a person without a local
# clone yet can go from a blank terminal to a running app in one command,
# without waiting on the Homebrew tap or a notarized release (docs/roadmap.md P11-b).
#
# Safe to re-run: idempotent, only touches /Applications/Speak.app and a
# throwaway clone under a private mktemp dir it creates and cleans up itself.

set -euo pipefail

REPO_URL="https://github.com/ArasanDev/speak.git"
APP_NAME="Speak.app"
INSTALL_DIR="/Applications/${APP_NAME}"

log() { printf '==> %s\n' "$1"; }
die() { printf 'error: %s\n' "$1" >&2; exit 1; }

# --- Preflight ---------------------------------------------------------

[[ "$(uname -s)" == "Darwin" ]] || die "speak only runs on macOS."
[[ "$(uname -m)" == "arm64" ]] || die "speak requires Apple Silicon (arm64)."

os_major="$(sw_vers -productVersion | cut -d. -f1)"
if [[ "$os_major" -lt 26 ]]; then
  die "speak requires macOS 26 (Tahoe) or later — SpeechAnalyzer/Foundation Models are macOS 26-only. Found: $(sw_vers -productVersion)"
fi

command -v xcodebuild >/dev/null 2>&1 || die "Xcode (full install, not just CLT) is required. Install from the App Store, then: sudo xcodebuild -license accept"
xcodebuild -version >/dev/null 2>&1 || die "Xcode is installed but not selected. Run: sudo xcode-select -s /Applications/Xcode.app"

for tool in git rsync; do
  command -v "$tool" >/dev/null 2>&1 || die "'$tool' is required but not found."
done

if ! command -v xcodegen >/dev/null 2>&1 || ! command -v swiftlint >/dev/null 2>&1; then
  log "Installing build dependencies (xcodegen, swiftlint) via Homebrew ..."
  command -v brew >/dev/null 2>&1 || die "Homebrew is required to install xcodegen/swiftlint. Install from https://brew.sh, then re-run this script."
  brew install xcodegen swiftlint xcbeautify
fi

# --- Clone + build -------------------------------------------------------

work_dir="$(mktemp -d /tmp/speak-install.XXXXXX)"
trap 'rm -rf "$work_dir"' EXIT

log "Cloning speak (shallow) into a temp dir ..."
git clone --depth 1 "$REPO_URL" "$work_dir/speak"

log "Building Speak.app (Release configuration) — this can take a few minutes ..."
(cd "$work_dir/speak" && make build CONFIG=Release)

built_app="$work_dir/speak/build/DerivedData/Build/Products/Release/${APP_NAME}"
[[ -d "$built_app" ]] || die "Build did not produce ${APP_NAME} at the expected path."

# --- Sign + install -------------------------------------------------------

log "Ad-hoc signing (free — no Developer ID cert required) ..."
codesign --force --deep --sign - "$built_app"

log "Stopping any running speak instance ..."
pkill -x Speak 2>/dev/null || true

log "Installing to ${INSTALL_DIR} ..."
rsync -a --delete "$built_app/" "$INSTALL_DIR/"
xattr -cr "$INSTALL_DIR"

log "Installed. Launch it:"
echo "         open ${INSTALL_DIR}"
echo ""
echo "First launch will ask for two permissions:"
echo "  • Microphone    — captures audio for on-device transcription"
echo "  • Accessibility — global hotkey (double-tap Fn) + paste at cursor"
echo ""
echo "100% on-device: no audio ever leaves this Mac. See https://github.com/ArasanDev/speak#privacy"
