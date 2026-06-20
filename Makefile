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

.PHONY: all generate build test lint run clean release

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

## clean: remove generated project + build artifacts
clean:
	rm -rf $(DERIVED) $(PROJECT)

## release: Developer ID sign + notarize + .dmg + Homebrew cask (implemented at P11)
release:
	@echo "make release is implemented at roadmap P11 (sign + notarize + dmg + cask)."
	@exit 1
