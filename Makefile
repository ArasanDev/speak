# Makefile for `speak` — common build tasks.
#
# The canonical build system is the Xcode project (architecture.md §5), which is
# GENERATED from project.yml by XcodeGen (build-time tooling only — never linked
# into the app). Speak.xcodeproj is git-ignored; `generate` recreates it, so the
# whole flow works from a clean clone.
#
# Tooling: Xcode 26+, XcodeGen (`brew install xcodegen`), SwiftLint
# (`brew install swiftlint`).

PROJECT  := Speak.xcodeproj
SCHEME   := Speak
CONFIG   := Debug
DERIVED  := build/DerivedData
APP      := $(DERIVED)/Build/Products/$(CONFIG)/Speak.app

XCB := xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG) -derivedDataPath $(DERIVED)

# ── Release variables ─────────────────────────────────────────────────────────
# These must be set in your environment (or on the make command line) before
# running `make release`. They are intentionally NOT committed — no secrets
# ever touch source control.
#
#   DEV_ID          – Your Developer ID Application cert name.
#                     Example: "Developer ID Application: Jane Smith (TEAMID)"
#                     Find it: security find-identity -v -p codesigning
#
#   NOTARY_PROFILE  – The profile name you created with:
#                     xcrun notarytool store-credentials <profile-name>
#                     See docs/release.md for the one-time setup procedure.
#
# Invocation:
#   DEV_ID="Developer ID Application: Jane Smith (TEAMID)" \
#   NOTARY_PROFILE="speak-notary" \
#   make release
DEV_ID         ?=
NOTARY_PROFILE ?=

# Release-specific paths (kept out of DERIVED to avoid `make clean` deleting them)
RELEASE_DIR    := build/release
ARCHIVE        := $(RELEASE_DIR)/Speak.xcarchive
EXPORT_DIR     := $(RELEASE_DIR)/export
APP_EXPORT     := $(EXPORT_DIR)/Speak.app
DMG            := $(RELEASE_DIR)/Speak.dmg
EXPORT_PLIST   := scripts/export-options.plist

# Stable local code-signing identity. When present, build re-signs the app with it
# so macOS TCC permission grants (Accessibility, Input Monitoring) survive rebuilds.
# Absent (fresh clone / CI) → the app stays ad-hoc and grants won't persist — run
# `make dev-cert` once to create it. See scripts/dev-codesign-setup.sh for the why.
DEV_CERT  := speak-local-codesign
BUNDLE_ID := com.speak.app

.PHONY: all generate build test lint fmt run lsp clean release verify-moat dev-cert reset-permissions release-preflight

all: build

## generate: (re)create Speak.xcodeproj from project.yml
generate:
	xcodegen generate

## build: produce a runnable Speak.app (signed per Signing.xcconfig — cert if
##        `make dev-cert` has been run, else ad-hoc)
build: generate
	$(XCB) build

## dev-cert: ONE-TIME setup. Creates the stable self-signed signing identity AND writes
##           the git-ignored Signing.local.xcconfig that points the build at it — so BOTH
##           `make build` and Xcode Cmd+R sign with it, and TCC grants (Accessibility /
##           Input Monitoring) persist across rebuilds. Idempotent; re-run any time.
dev-cert:
	bash scripts/dev-codesign-setup.sh
	@printf 'SPEAK_SIGN_IDENTITY = %s\n' "$(DEV_CERT)" > Signing.local.xcconfig
	@echo "dev-cert: wrote Signing.local.xcconfig (SPEAK_SIGN_IDENTITY=$(DEV_CERT))."
	@echo "          Run 'make generate' (or reopen Speak.xcodeproj in Xcode) for it to take effect,"
	@echo "          then 'make reset-permissions' once and re-grant — the grant will now stick."

## reset-permissions: clear stale TCC grants for speak (run after switching signing
##                    identity, or to force a clean re-grant). Then relaunch + grant once.
reset-permissions:
	-tccutil reset Accessibility $(BUNDLE_ID)
	-tccutil reset ListenEvent $(BUNDLE_ID)
	-tccutil reset Microphone $(BUNDLE_ID)
	@echo "reset-permissions: cleared Accessibility / Input-Monitoring / Microphone for $(BUNDLE_ID)."

## test: run the unit test suite (SpeakTests)
test: generate
	$(XCB) test

## lint: SwiftLint over the source tree
lint:
	swiftlint

## fmt: Format source with swift-format (install: brew install swift-format).
## Uses .swift-format at the repo root — the same config Apple uses in the
## container project. Run before committing; CI will gate on this when wired.
fmt:
	@which swift-format > /dev/null || (echo "swift-format not installed. Run: brew install swift-format" && exit 1)
	swift-format format --recursive --configuration .swift-format --in-place App SpeakCore SpeakTests
	@echo "fmt: done."

## run: build then launch the menubar app
run: build
	open $(APP)

## lsp: configure sourcekit-lsp (buildServer.json) so editors/agents get SDK-correct
##      Swift semantics. Build first so xcode-build-server has fresh compile args,
##      then pin workspace + our local build_root (the tool can't emit both at once).
##      Re-run after a clean clone or a project.yml change; reload the LSP after.
lsp: build
	xcode-build-server config -project $(PROJECT) -scheme $(SCHEME)
	@python3 -c "import json,os; p='buildServer.json'; d=json.load(open(p)); d['workspace']=os.path.abspath('$(PROJECT)/project.xcworkspace'); d['build_root']=os.path.abspath('$(DERIVED)'); json.dump(d, open(p,'w'), indent=2)"
	@echo "buildServer.json configured -> $(DERIVED). Reload the LSP server (restart Claude Code / editor) to pick it up."

## clean: remove generated project + build artifacts
clean:
	rm -rf $(DERIVED) $(PROJECT)

## verify-moat: static audit of structural BEAT rows (benchmark.md §3)
## Runs without Xcode. Re-runnable in CI. Exits 1 on any violation.
## For the full XCTest audit, run `make test` (MoatAuditTests.swift).
verify-moat:
	bash scripts/verify-moat.sh

## release-preflight: check required environment variables before release
release-preflight:
	@if [ -z "$(DEV_ID)" ]; then \
	  echo ""; \
	  echo "ERROR: DEV_ID is not set."; \
	  echo ""; \
	  echo "  Set it to your Developer ID Application cert name, e.g.:"; \
	  echo "    DEV_ID=\"Developer ID Application: Jane Smith (TEAMID)\""; \
	  echo ""; \
	  echo "  Find it with:  security find-identity -v -p codesigning"; \
	  echo "  Full setup:    docs/release.md"; \
	  echo ""; \
	  exit 1; \
	fi
	@if [ -z "$(NOTARY_PROFILE)" ]; then \
	  echo ""; \
	  echo "ERROR: NOTARY_PROFILE is not set."; \
	  echo ""; \
	  echo "  Set it to the keychain profile name you created with:"; \
	  echo "    xcrun notarytool store-credentials <profile-name>"; \
	  echo ""; \
	  echo "  Full setup:    docs/release.md"; \
	  echo ""; \
	  exit 1; \
	fi
	@if [ ! -f "$(EXPORT_PLIST)" ]; then \
	  echo ""; \
	  echo "ERROR: $(EXPORT_PLIST) is missing."; \
	  echo "  Create it per docs/release.md (xcodebuild -exportArchive options)."; \
	  echo ""; \
	  exit 1; \
	fi
	@echo "release-preflight: DEV_ID and NOTARY_PROFILE set, export plist present — continuing."

## release: Developer ID sign + notarize + .dmg + Homebrew cask (roadmap P11).
##
## Prerequisites (one-time setup — see docs/release.md):
##   1. Install a "Developer ID Application" certificate in your keychain.
##   2. Store notarization credentials:
##        xcrun notarytool store-credentials speak-notary \
##          --apple-id you@example.com --team-id YOURTEAMID
##   3. Create scripts/export-options.plist (one-time, see docs/release.md).
##
## Then run:
##   DEV_ID="Developer ID Application: Jane Smith (TEAMID)" \
##   NOTARY_PROFILE="speak-notary" \
##   make release
release: generate release-preflight
	@echo "==> release: archiving (Release configuration)..."
	@mkdir -p $(RELEASE_DIR)
	xcodebuild archive \
	  -project $(PROJECT) \
	  -scheme $(SCHEME) \
	  -configuration Release \
	  -archivePath $(ARCHIVE) \
	  -derivedDataPath $(DERIVED)

	@echo "==> release: exporting with Developer ID signing..."
	xcodebuild -exportArchive \
	  -archivePath $(ARCHIVE) \
	  -exportPath $(EXPORT_DIR) \
	  -exportOptionsPlist $(EXPORT_PLIST)

	@echo "==> release: verifying code signature..."
	codesign --verify --deep --strict --verbose=2 "$(APP_EXPORT)"
	spctl --assess --type execute --verbose "$(APP_EXPORT)"

	@echo "==> release: packaging .dmg (hdiutil)..."
	@rm -f "$(DMG)"
	hdiutil create \
	  -volname "Speak" \
	  -srcfolder "$(EXPORT_DIR)" \
	  -ov \
	  -format UDZO \
	  "$(DMG)"

	@echo "==> release: submitting to Apple Notary service (this may take a few minutes)..."
	xcrun notarytool submit "$(DMG)" \
	  --keychain-profile "$(NOTARY_PROFILE)" \
	  --wait

	@echo "==> release: stapling notarization ticket to .dmg..."
	xcrun stapler staple "$(DMG)"

	@echo "==> release: verifying Gatekeeper acceptance..."
	spctl --assess --type open --context context:primary-signature --verbose "$(DMG)"

	@echo ""
	@echo "==> release: SUCCESS"
	@echo "    Artifact: $(DMG)"
	@echo ""
	@echo "    Next: update dist/speak.cask.rb with the sha256 of the .dmg:"
	@echo "      shasum -a 256 $(DMG)"
	@echo ""
