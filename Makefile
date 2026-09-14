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
PRODUCTS := $(DERIVED)/Build/Products/$(CONFIG)
MCP_USER_DIR ?= $$HOME/Library/Application Support/speak/mcp

# -destination pins the run to this Mac's arm64 slice — without it xcodebuild
# sees "multiple matching destinations" (My Mac arm64 + x86_64 + Any Mac) and
# races parallel LaunchServices test-host launches, which fail with error 20
# and emit `** TEST FAILED **` even when every test passes.
# -parallel-testing-enabled NO serializes the test-host launches — the parallel
# LaunchServices launcher attempts race and fail (IDELaunchErrorDomain 20) even
# on a single destination. [fix: audit — gate-manufacturing flake]
XCB := xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG) -derivedDataPath $(DERIVED) -destination 'platform=macOS,arch=arm64' -parallel-testing-enabled NO

# Recipes run under bash with pipefail so `xcodebuild | pretty-output` and the
# `gates` summary pipelines propagate the LEFT command's exit status — without
# this, a red build/test run exits 0 (the pipeline reports the filter's status)
# and the gates can never fail. [fix: audit item — gates manufactured green]
SHELL      := /bin/bash
.SHELLFLAGS := -o pipefail -c

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
RELEASE_APP    := $(DERIVED)/Build/Products/Release/Speak.app

# Stable local code-signing identity. When present, build re-signs the app with it
# so macOS TCC permission grants (Accessibility, Input Monitoring) survive rebuilds.
# Absent (fresh clone / CI) → the app stays ad-hoc and grants won't persist — run
# `make dev-cert` once to create it. See scripts/dev-codesign-setup.sh for the why.
DEV_CERT  := speak-local-codesign
BUNDLE_ID := com.speak.app
VERSION   := $(shell grep 'CFBundleShortVersionString' project.yml | awk -F'"' '{print $$2}')

# The running app binary, used to find/kill the live process (a menubar LSUIElement
# app is NOT relaunched by `open` if an instance is already running — see `run`/`kill`).
APP_BIN   := Speak.app/Contents/MacOS/Speak
# Local history store (P9). `make history` dumps recent dictations (raw vs cleaned).
HISTORY_DB := $$HOME/Library/Application Support/speak/history.sqlite

.PHONY: all help generate generate-force build test test-fast eval study lint fmt run kill relaunch restart logs logs-show history history-eval doctor gates lsp clean install clean-install uninstall install-mcp-user register-mcp register-mcp-apply github-release release verify-moat dev-cert reset-permissions release-preflight

all: build

## help: list the common targets (grouped: dev loop, gates, release)
help:
	@echo "speak — make targets"
	@echo ""
	@grep -E '^## ' $(MAKEFILE_LIST) | sed -e 's/^## /  /'

## generate: (re)create Speak.xcodeproj from project.yml (incremental: only if project.yml changed)
generate:
	@if [ ! -d "$(PROJECT)" ] || [ project.yml -nt "$(PROJECT)" ]; then \
		echo "⚙️  project.yml changed or project missing — running xcodegen generate..."; \
		xcodegen generate; \
	fi

## generate-force: unconditionally recreate Speak.xcodeproj
generate-force:
	xcodegen generate

## build: produce a runnable Speak.app (signed per Signing.xcconfig — cert if
##        `make dev-cert` has been run, else ad-hoc)
build: generate
	@$(XCB) build 2>&1 | bash scripts/pretty-output.sh build

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

## test: run the full unit test suite (SpeakTests, all ~80 test suites).
##       Kills any running Speak first: the suite's TEST_HOST launches
##       Speak.app and a live instance's single-instance guard fights the
##       test-host spawn — the first launch fails (LaunchServices error,
##       `** TEST FAILED **`) and xcodebuild has to retry. Deterministic
##       beats retry-lucky.
test: generate kill
	@$(XCB) test 2>&1 | bash scripts/pretty-output.sh test

## test-fast: run only prompt & cleanup unit tests (~3s iteration loop)
test-fast: generate kill
	@$(XCB) test -only-testing:SpeakTests/DeveloperAcronymBiasingTests -only-testing:SpeakTests/FoundationModelPromptBuilderTests -only-testing:SpeakTests/FoundationModelsCleanerTests 2>&1 | bash scripts/pretty-output.sh test

## eval: run the small-models eval harness (live Foundation Models scoring)
## Uses the Eval scheme which bakes SPEAK_EVAL=1 into the test-action environment
## (xcodebuild shell-prefix does not propagate to the test host on macOS 26). [decision: SM-2]
eval: generate
	xcodebuild -project $(PROJECT) -scheme Eval -configuration $(CONFIG) -derivedDataPath $(DERIVED) test -only-testing:SpeakTests/EvalHarnessTests

## history-eval: score real raw→cleaned history pairs (reference-free over-editing
##               detection). Uses the Eval scheme with SPEAK_HISTORY_EVAL=1 baked in.
history-eval: generate
	xcodebuild -project $(PROJECT) -scheme Eval -configuration $(CONFIG) -derivedDataPath $(DERIVED) test -only-testing:SpeakTests/HistoryCleaningEvalTests

## study: run the Foundation Models limits study (live; writes RAW measurements)
## Uses the Eval scheme which bakes SPEAK_STUDY=1 into the test-action
## environment (xcodebuild shell-prefix does not propagate to the test host on
## macOS 26 — the old env-prefixed invocation silently XCTSkip'd every study
## test and reported green). [decision: SM-2]
study: generate
	xcodebuild -project $(PROJECT) -scheme Eval -configuration $(CONFIG) -derivedDataPath $(DERIVED) test -only-testing:SpeakTests/FoundationModelsStudyTests

## measure-latency: E1 — conversational latency (TTS first-audio + model TTFT)
## Standalone: needs no Xcode project, no app bundle, no permissions. Speaks a
## few short lines aloud — that is the measurement. See specs/voice-agent-design.md §5.
measure-latency:
	@mkdir -p $(DERIVED)/tools
	@xcrun swiftc -O -sdk "$$(xcrun --show-sdk-path --sdk macosx)" \
	  -target arm64-apple-macos26.0 \
	  scripts/measure-latency.swift -o $(DERIVED)/tools/measure-latency
	@$(DERIVED)/tools/measure-latency
	@echo ""
	@echo "First turn after launch — fresh process per row, so prewarm() has"
	@echo "something left to save (in-process reps do not)."
	@$(DERIVED)/tools/measure-latency --first-turn-cold
	@$(DERIVED)/tools/measure-latency --first-turn-prewarm

## probe-partials: E6 — does the transcriber punctuate volatile (partial) results?
## Gates the EndpointDecider rule set. Synthesizes its own audio and installs the
## speech model itself, so it needs no microphone, no permissions, no fixtures,
## and no prior dictation — re-runnable in a clean checkout.
probe-partials:
	@mkdir -p $(DERIVED)/tools
	@xcrun swiftc -O -sdk "$$(xcrun --show-sdk-path --sdk macosx)" \
	  -target arm64-apple-macos26.0 \
	  scripts/probe-partials.swift -o $(DERIVED)/tools/probe-partials
	@$(DERIVED)/tools/probe-partials

## probe-latency: E7 — how long after speech stops does the volatile carrying the
## last words arrive? Gates whether EndpointDecider can drive the VAD's silence
## window at all. Feeds real silence at real time instead of finalizing early,
## which is the difference between measuring the live pipeline and measuring a
## forced flush. No microphone, no permissions, no fixtures.
probe-latency:
	@mkdir -p $(DERIVED)/tools
	@xcrun swiftc -O -sdk "$$(xcrun --show-sdk-path --sdk macosx)" \
	  -target arm64-apple-macos26.0 \
	  scripts/probe-partial-latency.swift -o $(DERIVED)/tools/probe-partial-latency
	@$(DERIVED)/tools/probe-partial-latency

## lint: SwiftLint over the source tree
lint:
	swiftlint

## fmt: Format source with swift-format (install: brew install swift-format).
## Uses .swift-format at the repo root — the same config Apple uses in the
## container project. Run before committing; CI will gate on this when wired.
fmt:
	@which swift-format > /dev/null || (echo "swift-format not installed. Run: brew install swift-format" && exit 1)
	swift-format format --recursive --configuration .swift-format --in-place Speak/App Speak/SpeakCore Speak/SpeakLLM Speak/CLI Speak/MCP Speak/Tests/SpeakTests
	@echo "fmt: done."

# ── Dev loop (agent-friendly) ───────────────────────────────────────────────
# speak is a menubar (LSUIElement) app: `open` will NOT relaunch it if an instance
# is already running, so a plain `open` after a rebuild silently keeps the STALE
# binary in memory (this cost a multi-hour debugging detour). `run`/`relaunch`
# always kill the live process first so you are guaranteed to test fresh code.

## run: rebuild, kill any running instance, then launch the FRESH binary
run: build
	@$(MAKE) --no-print-directory kill
	@echo "==> run: launching fresh Speak.app ..."
	@open "$(APP)"
	@sleep 1
	@pid=$$(pgrep -n -f "$(APP_BIN)"); \
	 echo "run: launched PID $${pid:-?}  (started $$(ps -o lstart= -p $$pid 2>/dev/null | xargs))"

## kill: terminate any running Speak.app instance (the menubar app won't relaunch otherwise)
kill:
	@pkill -f "$(APP_BIN)" 2>/dev/null && echo "kill: stopped running instance." || echo "kill: nothing running."
	@sleep 1

## relaunch: kill + open the already-built binary (NO rebuild — fast UI iteration)
relaunch:
	@$(MAKE) --no-print-directory kill
	@open "$(APP)"
	@echo "relaunch: opened $(APP) (no rebuild)."

## restart: stop any running instance and launch the installed /Applications/Speak.app
restart:
	@pkill -f "Speak.app/Contents/MacOS/Speak" 2>/dev/null || true
	@pkill -x Speak 2>/dev/null || true
	@sleep 1
	@open /Applications/Speak.app
	@sleep 1
	@pid=$$(pgrep -n -f "Speak.app/Contents/MacOS/Speak"); \
	 echo "restart: launched PID $${pid:-?} from /Applications/Speak.app"

## logs: stream speak's LIVE os.Logger output (info+). Ctrl-C to stop. Use this to
##       watch a dictation in real time — .info/.debug are NOT persisted to `log show`.
logs:
	@echo "==> streaming subsystem=$(BUNDLE_ID) (info+). Dictate now; Ctrl-C to stop."
	@log stream --predicate 'subsystem == "$(BUNDLE_ID)"' --level info --style compact

## logs-show: dump speak's recent log history (last 10m). Best-effort — macOS may not
##            persist .info/.debug; prefer `make logs` (live) for the dictation flow.
logs-show:
	@log show --predicate 'subsystem == "$(BUNDLE_ID)"' --last 10m --info --debug --style compact

## history: show the last 10 dictations (raw vs cleaned + cleanup time) from the local DB.
##          The fastest way to verify cleanup ran and a profile reshaped the output.
history:
	@sqlite3 -header -column "$(HISTORY_DB)" \
	  "SELECT datetime(createdAt,'unixepoch','localtime') AS at, substr(rawText,1,38) AS raw, substr(cleanedText,1,38) AS cleaned, round(cleanupSeconds,2) AS clean_s FROM history ORDER BY createdAt DESC LIMIT 10;" \
	  2>/dev/null || echo "history: no DB yet at $(HISTORY_DB) (dictate once first)."

## doctor: diagnose the dev environment — running instance vs built binary (STALE?),
##         signing identity, perms hint. Run this the moment a rebuild seems ignored.
doctor:
	@echo "== speak doctor =="
	@printf -- "-- built binary --\n"
	@ls -l "$(APP)/Contents/MacOS/Speak" 2>/dev/null | awk '{print "  mtime:",$$6,$$7,$$8}' || echo "  (not built — run: make build)"
	@printf -- "-- running instance --\n"
	@pid=$$(pgrep -n -f "$(APP_BIN)"); \
	 if [ -n "$$pid" ]; then \
	   echo "  PID $$pid  started $$(ps -o lstart= -p $$pid | xargs)"; \
	   echo "  NOTE: if 'started' predates the binary mtime above, you are running STALE code → make run"; \
	 else echo "  (not running)"; fi
	@printf -- "-- signing identity --\n"
	@codesign -dvv "$(APP)" 2>&1 | grep -E "Authority=|Signature" | sed 's/^/  /' || echo "  (unsigned / not built)"
	@printf -- "-- permissions --\n"
	@echo "  TCC grant state isn't queryable; if hotkey/paste fail after a re-sign: make reset-permissions"

## gates: run the full merge gate in order — build, test, lint, moat. The loop's done-check.
## pipefail (.SHELLFLAGS) makes each `make <gate> | tail` pipeline fail when the
## sub-make fails, so `gates` exits non-zero on the FIRST red gate instead of
## always reaching "done". The tail keeps the failing gate's summary visible.
gates:
	@echo "==> [1/4] build ..."       && $(MAKE) --no-print-directory build >/dev/null && echo "    build: OK"
	@echo "==> [2/4] test ..."        && $(MAKE) --no-print-directory test  2>&1 | tail -8
	@echo "==> [3/4] lint ..."        && $(MAKE) --no-print-directory lint  2>&1 | tail -3
	@echo "==> [4/4] verify-moat ..." && $(MAKE) --no-print-directory verify-moat 2>&1 | tail -4
	@echo "==> gates: all four gates green."

## install: build Speak.app and install it to /Applications/ (dev/test path, no signing needed).
##
## Kills any running instance first, copies via rsync, then clears quarantine.
## For TCC permission grants (Accessibility, Microphone) to survive future
## rebuilds, run `make dev-cert` once beforehand.
install: build
	@echo "==> install: stopping any running Speak instance ..."
	@pkill -f "Speak.app/Contents/MacOS/Speak" 2>/dev/null || true
	@pkill -x Speak 2>/dev/null || true
	@echo "==> install: syncing Speak.app to /Applications/ ..."
	@rsync -a --delete "$(APP)/" /Applications/Speak.app/
	@xattr -cr /Applications/Speak.app
	@/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister -f -R -trusted /Applications/Speak.app 2>/dev/null || true
	@echo "install: Speak.app → /Applications/ (v$(VERSION)). Launch from Spotlight or:"
	@echo "         open /Applications/Speak.app"

## clean-install: purge stale caches, kill old background processes, build Release, and install fresh to /Applications/
clean-install:
	@echo "==> clean-install: stopping any running Speak processes ..."
	@pkill -f "Speak.app/Contents/MacOS/Speak" 2>/dev/null || true
	@pkill -x Speak 2>/dev/null || true
	@sleep 1
	@echo "==> clean-install: clearing stale build cache and DerivedData ..."
	@rm -rf $(DERIVED) build/dmg_staging
	@echo "==> clean-install: building fresh Release app ..."
	@$(MAKE) --no-print-directory build CONFIG=Release
	@echo "==> clean-install: removing old /Applications/Speak.app ..."
	@rm -rf /Applications/Speak.app
	@echo "==> clean-install: installing fresh Speak.app to /Applications/ ..."
	@cp -R "$(RELEASE_APP)" /Applications/Speak.app
	@xattr -cr /Applications/Speak.app
	@/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister -f -R -trusted /Applications/Speak.app 2>/dev/null || true
	@echo "clean-install: Speak.app cleanly installed to /Applications/ (Release v$(VERSION))."
	@echo "               Launching fresh instance ..."
	@open /Applications/Speak.app
	@sleep 1
	@pid=$$(pgrep -n -f "Speak.app/Contents/MacOS/Speak"); \
	 echo "clean-install: launched PID $${pid:-?} from /Applications/Speak.app"

## uninstall: stop running instances, remove /Applications/Speak.app and LaunchServices registrations
uninstall:
	@echo "==> uninstall: stopping running instances ..."
	@pkill -f "Speak.app/Contents/MacOS/Speak" 2>/dev/null || true
	@pkill -x Speak 2>/dev/null || true
	@sleep 1
	@echo "==> uninstall: removing /Applications/Speak.app ..."
	@rm -rf /Applications/Speak.app
	@/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister -u /Applications/Speak.app 2>/dev/null || true
	@echo "uninstall: removed /Applications/Speak.app and unregistered from LaunchServices."

## install-mcp-user: install the local agent voice bridge without requiring root.
##
## The tool binary's rpath is @executable_path/../Frameworks, so this stable
## user-scoped layout keeps SpeakCore/SpeakLLM beside it and works independently
## of DerivedData. The menubar app must still be running to own TTS and the mic.
install-mcp-user: build
	@echo "==> install-mcp-user: installing local MCP bridge ..."
	@mkdir -p "$(MCP_USER_DIR)/bin" "$(MCP_USER_DIR)/Frameworks"
	@rsync -a "$(PRODUCTS)/speak-mcp" "$(MCP_USER_DIR)/bin/speak-mcp"
	@rsync -a --delete "$(PRODUCTS)/SpeakCore.framework/" "$(MCP_USER_DIR)/Frameworks/SpeakCore.framework/"
	@rsync -a --delete "$(PRODUCTS)/SpeakLLM.framework/" "$(MCP_USER_DIR)/Frameworks/SpeakLLM.framework/"
	@chmod +x "$(MCP_USER_DIR)/bin/speak-mcp"
	@echo "install-mcp-user: installed $(MCP_USER_DIR)/bin/speak-mcp"
	@echo ""
	@echo "Next: register it with your agent CLIs in one step —"
	@echo "  make register-mcp        # preview the changes (writes nothing)"
	@echo "  make register-mcp-apply  # register with every detected agent CLI"
	@echo ""
	@echo "Or add this stdio server manually to any other MCP client:"
	@echo '  {"command":"$(MCP_USER_DIR)/bin/speak-mcp"}'

## register-mcp: preview registering the installed bridge with detected agent CLIs.
##
## Writes nothing. Shows exactly which agent CLIs were found and what would change.
register-mcp:
	@MCP_USER_DIR="$(MCP_USER_DIR)" scripts/register-mcp.sh

## register-mcp-apply: register the bridge with every detected agent CLI (idempotent).
##
## Blast radius: writes user-level agent config OUTSIDE this repo (~/.claude.json,
## ~/.codex/config.toml), touching only the single 'speak-app' server entry.
## Re-running replaces that entry rather than duplicating it.
register-mcp-apply:
	@MCP_USER_DIR="$(MCP_USER_DIR)" scripts/register-mcp.sh --apply

## github-release: build, ad-hoc sign, and zip into dist/ for a GitHub Releases artifact.
##
## No Developer ID cert is required. Produces dist/Speak-<version>.zip.
## Users must run once after download:
##   xattr -dr com.apple.quarantine Speak.app
github-release:
	$(MAKE) build
	@echo "==> github-release: ad-hoc signing ..."
	codesign --force --deep --sign - "$(APP)"
	@echo "==> github-release: packaging dist/Speak-$(VERSION).zip ..."
	@mkdir -p dist
	@rm -f "dist/Speak-$(VERSION).zip"
	ditto -c -k --sequesterRsrc --keepParent "$(APP)" "dist/Speak-$(VERSION).zip"
	@echo ""
	@echo "==> github-release: SUCCESS"
	@echo "    Artifact: dist/Speak-$(VERSION).zip"
	@shasum -a 256 "dist/Speak-$(VERSION).zip"
	@echo ""
	@echo "    Upload to GitHub Releases. Users run once after download:"
	@echo "      xattr -dr com.apple.quarantine Speak.app"
	@echo ""

## dmg: build Release Speak.app and package it into a drag-and-drop dist/Speak.dmg disk image.
dmg:
	$(MAKE) build CONFIG=Release
	@echo "==> dmg: staging Speak.app and /Applications symlink ..."
	@rm -rf build/dmg_staging
	@mkdir -p build/dmg_staging dist
	@cp -R "$(RELEASE_APP)" build/dmg_staging/
	@ln -s /Applications build/dmg_staging/Applications
	@rm -f dist/Speak.dmg "dist/Speak-$(VERSION).dmg"
	@echo "==> dmg: creating dist/Speak.dmg (UDZO compressed) ..."
	@hdiutil create -volname "Speak" -srcfolder build/dmg_staging -ov -format UDZO dist/Speak.dmg
	@cp dist/Speak.dmg "dist/Speak-$(VERSION).dmg"
	@echo ""
	@echo "==> dmg: SUCCESS"
	@echo "    Artifact: dist/Speak.dmg"
	@shasum -a 256 dist/Speak.dmg
	@echo ""
	@echo "    To test the Homebrew Cask locally:"
	@echo "      brew install --cask dist/speak.cask.rb"
	@echo ""

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
