#!/usr/bin/env bash
#
# scripts/verify-moat.sh — Standalone structural-moat audit for `speak`
#
# PURPOSE:
#   A fast, dependency-free shell audit that can run in CI without Xcode.
#   It duplicates the intent of MoatAuditTests.swift at the bash level so:
#     1. It can be wired into CI as a pre-build step (no test runner needed).
#     2. It's human-readable and trivially re-runnable: `make verify-moat`.
#     3. It's a belt-and-suspenders guard alongside the XCTest suite.
#
# BEAT ROWS AUDITED (benchmark.md §3):
#   #1  100% local + offline (no networking symbols)
#   #2  Free & unlimited     (no paywall/subscription symbols)
#   #3  Open source (MIT)    (LICENSE exists and contains "MIT License")
#   #4  No account / no auth (no identity-auth symbols)
#   #7  Privacy              (same as #1 — no network egress)
#   Plus: no third-party imports, no print(), no pasteboard reads.
#
# WHAT THIS SCRIPT DOES NOT CHECK:
#   • Live runtime behaviour (paste, hotkey, FM cleanup) — deferred to human.
#   • Latency or accuracy — deferred to LatencyAndAccuracyTests.swift.
#
# EXIT CODE: 0 = all audits pass; 1 = one or more violations found.
#
# USAGE:
#   bash scripts/verify-moat.sh            # from repo root
#   make verify-moat                       # via Makefile alias

set -euo pipefail

# ── Repo root discovery ──────────────────────────────────────────────────────
# Anchor on project.yml so this works from any CWD.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ ! -f "$REPO_ROOT/project.yml" ]]; then
    echo "ERROR: project.yml not found at $REPO_ROOT. Run from the repo root." >&2
    exit 1
fi

SOURCE_DIRS=("$REPO_ROOT/SpeakCore" "$REPO_ROOT/App")
PASS_COUNT=0
FAIL_COUNT=0

# ── Helpers ──────────────────────────────────────────────────────────────────
pass() { echo "  PASS: $*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "  FAIL: $*" >&2; FAIL_COUNT=$((FAIL_COUNT + 1)); }

# Run grep across production source. Returns 0 if match found, 1 if not.
grep_source() {
    grep -rn --include="*.swift" "$@" "${SOURCE_DIRS[@]}" 2>/dev/null
}

# ── §3 #3: MIT License ───────────────────────────────────────────────────────
echo ""
echo "── §3 #3: MIT License ──────────────────────────────────────────────────"
LICENSE="$REPO_ROOT/LICENSE"
if [[ ! -f "$LICENSE" ]]; then
    fail "LICENSE file not found at $REPO_ROOT/LICENSE."
elif grep -q "MIT License" "$LICENSE"; then
    pass "LICENSE exists and contains 'MIT License'."
else
    fail "LICENSE exists but does not contain 'MIT License'."
fi

# ── Third-party import check ─────────────────────────────────────────────────
echo ""
echo "── Third-party imports (Apple-only allowlist) ──────────────────────────"
# Allowed modules (Apple-shipped). Update this list when the allowlist in
# MoatAuditTests.swift changes — keep them in sync.
ALLOWED_IMPORTS=(
    "Foundation"
    "os"
    "SwiftUI"
    "AppKit"
    "AVFoundation"
    "Speech"
    "FoundationModels"
    "CoreGraphics"
    "ApplicationServices"
    "Carbon.HIToolbox"
    "IOKit.hid"         # IOHIDCheckAccess — P7 Input Monitoring status (Apple IOKit)
    "SQLite3"
    "SpeakCore"
    "Combine"           # Apple; ObservableObject in SpeakCore
)

IMPORT_VIOLATIONS=0
while IFS= read -r line; do
    # Extract module name from `import Module` or `import Module.Sub`.
    # Skip comments.
    trimmed="${line#*:}"   # strip "file:linenum:" prefix from grep -n output
    trimmed="${trimmed#"${trimmed%%[![:space:]]*}"}"  # ltrim
    [[ "$trimmed" == //* ]] && continue
    [[ "$trimmed" == "import "* ]] || continue
    module="${trimmed#import }"
    module="${module%% *}"   # take first word
    allowed=0
    for allowed_mod in "${ALLOWED_IMPORTS[@]}"; do
        [[ "$module" == "$allowed_mod" ]] && { allowed=1; break; }
    done
    if [[ $allowed -eq 0 ]]; then
        fail "Non-allowlist import '$module' in: $line"
        IMPORT_VIOLATIONS=$((IMPORT_VIOLATIONS + 1))
    fi
done < <(grep_source -E "^[[:space:]]*import " || true)

[[ $IMPORT_VIOLATIONS -eq 0 ]] && pass "All imports are Apple-framework allowlist members."

# ── §3 #1 + #7: No network egress ────────────────────────────────────────────
echo ""
echo "── §3 #1 + #7: No network egress ───────────────────────────────────────"
NETWORK_SYMBOLS=(
    "URLSession"
    "URLRequest"
    "URLConnection"
    "dataTask("
    "uploadTask("
    "downloadTask("
    "NWConnection"
    "NWListener"
    "NWPathMonitor"
    "CFSocketCreate"
    "getaddrinfo"
    "NSURLSession"
    "NSURLConnection"
    "NSURLRequest"
    "WebSocket"
    "URLWebSocketTask"
)

NET_VIOLATIONS=0
for symbol in "${NETWORK_SYMBOLS[@]}"; do
    if results=$(grep_source --include="*.swift" -l "$symbol" 2>/dev/null); then
        while IFS= read -r match; do
            fail "Networking symbol '$symbol' found in $match"
            NET_VIOLATIONS=$((NET_VIOLATIONS + 1))
        done <<< "$results"
    fi
done
[[ $NET_VIOLATIONS -eq 0 ]] && pass "No networking symbols found — offline by construction."

# ── §3 #4: No account / no identity-auth ────────────────────────────────────
echo ""
echo "── §3 #4: No account / no auth (identity) ──────────────────────────────"
AUTH_SYMBOLS=(
    "ASAuthorizationController"
    "ASAuthorization"
    "LAContext"
    "SecItemAdd("
    "SecItemCopyMatching("
    "SecItemUpdate("
    "SecItemDelete("
    "SignInWithAppleButton"
    "import AuthenticationServices"
)

AUTH_VIOLATIONS=0
for symbol in "${AUTH_SYMBOLS[@]}"; do
    if results=$(grep_source -l "$symbol" 2>/dev/null); then
        while IFS= read -r match; do
            fail "Identity-auth symbol '$symbol' found in $match"
            AUTH_VIOLATIONS=$((AUTH_VIOLATIONS + 1))
        done <<< "$results"
    fi
done
[[ $AUTH_VIOLATIONS -eq 0 ]] && pass "No identity-auth symbols found — no account, no auth."

# ── §3 #2: Free & unlimited — no paywall ─────────────────────────────────────
echo ""
echo "── §3 #2: Free & unlimited — no paywall ────────────────────────────────"
PAYWALL_SYMBOLS=(
    "StoreKit"
    "SKProduct"
    "SKPayment"
    "InAppPurchase"
    "wordCap"
    "WordCap"
    "wordsRemaining"
    "freeLimit"
    "subscriptionActive"
    "isPremium"
    "isTrial"
    "trialDaysLeft"
    "paywall"
    "Paywall"
)

PAYWALL_VIOLATIONS=0
for symbol in "${PAYWALL_SYMBOLS[@]}"; do
    if results=$(grep_source -l "$symbol" 2>/dev/null); then
        while IFS= read -r match; do
            fail "Paywall/subscription symbol '$symbol' found in $match"
            PAYWALL_VIOLATIONS=$((PAYWALL_VIOLATIONS + 1))
        done <<< "$results"
    fi
done
[[ $PAYWALL_VIOLATIONS -eq 0 ]] && pass "No paywall/subscription symbols found — free & unlimited."

# ── Pasteboard write-only guard ───────────────────────────────────────────────
echo ""
echo "── Pasteboard write-only (AGENTS.md §2.8) ──────────────────────────────"
READ_SYMBOLS=(
    "string(forType:"
    "pasteboardItems"
    "readObjects(forClasses:"
    "data(forType:"
    "canReadObject("
)

PB_VIOLATIONS=0
for symbol in "${READ_SYMBOLS[@]}"; do
    if results=$(grep_source -l "$symbol" 2>/dev/null); then
        while IFS= read -r match; do
            fail "Pasteboard read symbol '$symbol' found in $match"
            PB_VIOLATIONS=$((PB_VIOLATIONS + 1))
        done <<< "$results"
    fi
done
[[ $PB_VIOLATIONS -eq 0 ]] && pass "No pasteboard read symbols found — write-only."

# ── No print() in production ─────────────────────────────────────────────────
echo ""
echo "── No print() in production (swift-code-review rule #1) ────────────────"
# Exclude comment lines. Use grep -v to remove comment-only lines.
PRINT_VIOLATIONS=0
while IFS= read -r line; do
    code_part="${line%%//*}"     # strip inline comment
    trimmed="${code_part#*:}"    # strip "file:linenum:" prefix
    trimmed="${trimmed#"${trimmed%%[![:space:]]*}"}"  # ltrim
    [[ "$trimmed" == //* ]] && continue
    [[ "$trimmed" == *"print("* ]] && {
        fail "print() found in production: $line"
        PRINT_VIOLATIONS=$((PRINT_VIOLATIONS + 1))
    }
done < <(grep_source -n "print(" || true)
[[ $PRINT_VIOLATIONS -eq 0 ]] && pass "No print() calls in production code."

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
TOTAL=$((PASS_COUNT + FAIL_COUNT))
echo "Moat audit: $PASS_COUNT/$TOTAL checks passed."
if [[ $FAIL_COUNT -gt 0 ]]; then
    echo ""
    echo "FAIL: $FAIL_COUNT violation(s) found. The structural moat is breached." >&2
    echo "      Fix all violations before tagging v0.0.1." >&2
    exit 1
else
    echo ""
    echo "PASS: All structural-moat checks passed."
    echo "      benchmark.md §3 BEAT rows #1–#4 #7 are verified by static analysis."
    echo ""
    echo "Deferred (not checked here — needs human / live environment):"
    echo "  §3 #5  History BEAT (P9 verified in HistoryStoreTests.swift)"
    echo "  §3 #6  Lower latency (partial — see LatencyAndAccuracyTests.swift)"
    echo "  §2 streaming-overlay BEAT (P4 UI not built)"
    echo "  §4 MATCH gate rows: accuracy WER, live paste, hotkey false-trigger rate"
    exit 0
fi
