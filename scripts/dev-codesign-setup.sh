#!/usr/bin/env bash
#
# scripts/dev-codesign-setup.sh — create a STABLE local code-signing identity so
# macOS TCC permission grants (Accessibility, Input Monitoring) survive rebuilds.
#
# WHY THIS EXISTS
#   The dev build is otherwise ad-hoc signed (`codesign -s -`). TCC binds an
#   Accessibility/Input-Monitoring grant to the app's *code-signing designated
#   requirement* (DR). For an ad-hoc app the DR is pinned to the binary's cdhash,
#   which changes on EVERY rebuild — so a grant made against one build is rejected
#   by the next (`AXIsProcessTrusted()` returns false even though System Settings
#   still shows the toggle ON). This is the #1 "I enabled it but it doesn't work"
#   macOS dev bug. (Empirically confirmed on macOS 26.5, 2026-06-21.)
#
#   Signing with a stable self-signed cert makes the DR cert-anchored instead:
#       identifier "com.speak.app" and certificate leaf = H"<cert-sha1>"
#   The cert leaf hash is identical across rebuilds, so the grant persists.
#   This is the same approach AltTab uses for its dev workflow.
#
# IDEMPOTENT: no-op if the identity already exists. No trust step is needed —
#   `codesign` signs with the identity by name even though it is self-signed and
#   not trusted for verification (we are not gatekeeping the dev build).
#
# REMOVE IT ANY TIME:  security delete-certificate -c speak-local-codesign
#
# This is build-time dev tooling only. It never ships and never links into the
# app, so it does not touch the Apple-frameworks-only runtime moat.
set -euo pipefail

CERT_CN="speak-local-codesign"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -p codesigning 2>/dev/null | grep -q "$CERT_CN"; then
  echo "dev-codesign: identity '$CERT_CN' already present — nothing to do."
  exit 0
fi

echo "dev-codesign: creating stable self-signed code-signing identity '$CERT_CN'…"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cd "$WORK"

cat > codesign.conf <<'EOF'
[ req ]
distinguished_name = req_name
prompt = no
[ req_name ]
CN = speak-local-codesign
[ extensions ]
basicConstraints=critical,CA:false
keyUsage=critical,digitalSignature
extendedKeyUsage=critical,1.3.6.1.5.5.7.3.3
1.2.840.113635.100.6.1.14=critical,DER:0500
EOF

openssl genrsa -out codesign.key 2048 2>/dev/null
openssl req -x509 -new -config codesign.conf -nodes -key codesign.key \
  -extensions extensions -sha256 -days 3650 -out codesign.crt 2>/dev/null
PASS="$(openssl rand -base64 12)"
# -legacy is required on OpenSSL 3.x for a macOS-importable PKCS#12.
openssl pkcs12 -legacy -export -inkey codesign.key -in codesign.crt \
  -out codesign.p12 -passout pass:"$PASS" 2>/dev/null

# -T /usr/bin/codesign authorizes codesign to use the private key without prompting.
security import codesign.p12 -P "$PASS" -T /usr/bin/codesign -k "$KEYCHAIN"

echo "dev-codesign: '$CERT_CN' installed in the login keychain (local-only; remove with"
echo "              security delete-certificate -c $CERT_CN)."
