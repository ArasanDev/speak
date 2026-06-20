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

.PHONY: all generate build test lint run lsp clean release

all: build

## generate: (re)create Speak.xcodeproj from project.yml
generate:
	xcodegen generate

## build: produce a runnable Speak.app
build: generate
	$(XCB) build

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

## release: Developer ID sign + notarize + .dmg + Homebrew cask (implemented at P11)
release:
	@echo "make release is implemented at roadmap P11 (sign + notarize + dmg + cask)."
	@exit 1
