#!/bin/bash
# check-compat.sh — does this Mac run speak?
#
# speak is an alpha-stage, local-first project with a deliberately narrow
# support matrix: Apple Silicon M5 (primary) / M4 (supported), macOS 26+
# (Tahoe). Everything is Apple frameworks — no third-party runtime deps —
# so compatibility is a property of the hardware + OS, which this script
# checks in one shot. Safe for end users: read-only, no sudo, no installs.
#
# Usage:  make compat        (from the repo)
#         bash scripts/check-compat.sh
#
# Exit: 0 = supported · 1 = unsupported · 2 = supported-with-warnings

set -u

warn=0
fail=0

ok()   { printf '  ✓ %s\n' "$1"; }
warnf() { printf '  ⚠ %s\n' "$1"; warn=1; }
bad()  { printf '  ✗ %s\n' "$1"; fail=1; }

echo "== speak compatibility check =="

# --- architecture -------------------------------------------------------
arch="$(uname -m)"
if [ "$arch" = "arm64" ]; then
    ok "Architecture: arm64 (Apple Silicon)"
else
    bad "Architecture: $arch — speak is Apple Silicon only (no Intel)"
fi

# --- chip ---------------------------------------------------------------
chip="$(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo unknown)"
case "$chip" in
    *M5*) ok "Chip: $chip (primary target)" ;;
    *M4*) ok "Chip: $chip (supported)" ;;
    *M3*|*M2*|*M1*)
        warnf "Chip: $chip — likely works (macOS 26 supports it) but is not in the supported matrix; alpha support is M5/M4 only" ;;
    *)
        warnf "Chip: $chip — unrecognized; verify manually" ;;
esac

# --- macOS version ------------------------------------------------------
macos="$(sw_vers -productVersion 2>/dev/null || echo 0)"
major="${macos%%.*}"
if [ "$major" -ge 26 ] 2>/dev/null; then
    ok "macOS: $macos (≥ 26.0 Tahoe required)"
else
    bad "macOS: $macos — speak requires macOS 26.0 or later (FoundationModels / SpeechAnalyzer only exist on the 26 SDK)"
fi

# --- dev toolchain (only needed to build from source) --------------------
if command -v xcodebuild >/dev/null 2>&1; then
    xcv="$(xcodebuild -version 2>/dev/null | head -1 | awk '{print $2}')"
    xmajor="${xcv%%.*}"
    if [ "${xmajor:-0}" -ge 26 ] 2>/dev/null; then
        ok "Xcode: $xcv"
    else
        warnf "Xcode: $xcv — building from source needs Xcode 26+"
    fi
else
    warnf "xcodebuild not found — needed only if building from source (DMG/cask installs don't need it)"
fi

for tool in xcodegen swiftlint; do
    if command -v "$tool" >/dev/null 2>&1; then
        ok "$tool: $(command -v "$tool")"
    else
        warnf "$tool not found — brew install $tool (dev builds only)"
    fi
done

# --- Apple Intelligence --------------------------------------------------
# No supported headless probe exists for Apple Intelligence availability.
# speak degrades gracefully (raw transcript) when it's off, so this is
# informational, not a gate.
echo "  · Apple Intelligence: check System Settings → Apple Intelligence & Siri —"
echo "    OFF means raw transcripts instead of AI neat-writing (still fully works)"

# --- verdict -------------------------------------------------------------
echo
if [ "$fail" -eq 1 ]; then
    echo "COMPATIBILITY: UNSUPPORTED — speak will not run correctly on this machine."
    exit 1
elif [ "$warn" -eq 1 ]; then
    echo "COMPATIBILITY: SUPPORTED WITH WARNINGS — see ⚠ items above."
    exit 2
else
    echo "COMPATIBILITY: SUPPORTED"
    exit 0
fi
