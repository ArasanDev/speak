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

# Stable local code-signing identity. When present, build re-signs the app with it
# so macOS TCC permission grants (Accessibility, Input Monitoring) survive rebuilds.
# Absent (fresh clone / CI) → the app stays ad-hoc and grants won't persist — run
# `make dev-cert` once to create it. See scripts/dev-codesign-setup.sh for the why.
DEV_CERT  := speak-local-codesign
BUNDLE_ID := com.speak.app

.PHONY: all generate build test lint run lsp clean release verify-moat dev-cert reset-permissions

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

## release: Developer ID sign + notarize + .dmg + Homebrew cask (implemented at P11)
release:
	@echo "make release is implemented at roadmap P11 (sign + notarize + dmg + cask)."
	@exit 1
