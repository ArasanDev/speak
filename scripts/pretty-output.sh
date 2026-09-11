#!/usr/bin/env bash
#
# scripts/pretty-output.sh — Stream filter for clean, structured CLI build & test outputs.
# Formats raw xcodebuild / swiftc / make noise into elegant, structured terminal output.

# ANSI Color System & Box Drawing Characters
BOLD="\033[1m"
DIM="\033[2m"
BLUE="\033[38;5;75m"
GREEN="\033[38;5;78m"
YELLOW="\033[38;5;220m"
RED="\033[38;5;203m"
CYAN="\033[38;5;86m"
GRAY="\033[38;5;242m"
RESET="\033[0m"

LINE_WIDTH=72

draw_header() {
    local title="$1"
    printf "${CYAN}┌─ %b %s${RESET}\n" "$title" "$(printf '─%.0s' $(seq 1 $((LINE_WIDTH - ${#title} - 4))))"
}

draw_footer() {
    local status="$1"
    if [ "$status" = "SUCCESS" ]; then
        printf "${GREEN}└─ ✓ %b %s${RESET}\n" "$status" "$(printf '─%.0s' $(seq 1 $((LINE_WIDTH - ${#status} - 6))))"
    else
        printf "${RED}└─ ✗ %b %s${RESET}\n" "$status" "$(printf '─%.0s' $(seq 1 $((LINE_WIDTH - ${#status} - 6))))"
    fi
}

draw_step() {
    local label="$1"
    local detail="$2"
    printf "${BLUE}│${RESET} ${BOLD}%-14s${RESET} ${GRAY}▸${RESET} %b\n" "$label" "$detail"
}

format_stream() {
    local mode="${1:-build}"
    draw_header "SPEAK BUILD SYSTEM — $(echo "$mode" | tr '[:lower:]' '[:upper:]')"
    
    local errors=0
    local warnings=0
    
    while IFS= read -r line || [ -n "$line" ]; do
        # Filter benign system logging noise
        if echo "$line" | grep -qE "ComputePackagePrebuildTargetDependencyGraph|CreateBuildRequest|CreateBuildOperation|ClangStatCache|ProcessInfoPlistFile|CopySwiftLibs|IDETestOperationsObserverDebug|autoShortcut|Process Instance Registry|linkd|AppIntents.framework"; then
            continue
        fi
        
        # Match Compiling / Building steps
        if echo "$line" | grep -q "CompileSwift normal arm64"; then
            file=$(echo "$line" | awk '{print $NF}')
            draw_step "Compiling" "$(basename "$file")"
        elif echo "$line" | grep -q "Building target"; then
            target=$(echo "$line" | grep -o "target '[^']*" | cut -d"'" -f2)
            if [ -n "$target" ]; then
                draw_step "Target" "$target"
            fi
        # Treat ALL real failure markers as errors — not just `.swift:N:N:`:
        # `error:` also matches xcodebuild/linker/codesign errors that carry no
        # file coordinate (`xcodebuild: error:`, `ld: error:`, `error: Signing`),
        # and the TEST/BUILD FAILED banners + failed Test Case lines mean the
        # run was red even when no compiler diagnostic exists. Without these,
        # a fully red test run printed "✓ SUCCESS" and exited 0 — the filter
        # manufactured green. [fix: audit item — honest gate]
        elif echo "$line" | grep -qE "(^|[[:space:]:])error:|TEST FAILED|BUILD FAILED|Test Case '-\[[^]]+\]' failed"; then
            errors=$((errors + 1))
            printf "${RED}│ ✖ %s${RESET}\n" "$line"
        elif echo "$line" | grep -qE "\.swift:[0-9]+:[0-9]+: warning:"; then
            warnings=$((warnings + 1))
            printf "${YELLOW}│ ⚠️  %s${RESET}\n" "$line"
        elif echo "$line" | grep -q "BUILD SUCCEEDED"; then
            draw_step "Status" "${GREEN}Build Succeeded Cleanly${RESET}"
        elif echo "$line" | grep -q "TEST SUCCEEDED"; then
            draw_step "Status" "${GREEN}Test Suite Passed Cleanly${RESET}"
        # Pass the XCTest summary line through (dimmed) so `make gates` and
        # humans can see the "Executed N tests, with M failures" verdict the
        # filter would otherwise swallow.
        elif echo "$line" | grep -qE "Executed [0-9]+ tests"; then
            printf "${GRAY}│ %s${RESET}\n" "$line"
        # Per-suite progress so a long `make test` run stays diagnosable instead
        # of going silent for hours (was the actual blocker debugging a slow CI
        # run — individual `Test Case` lines are too noisy to print one-by-one
        # across ~300 tests, but suite start/pass/fail with timing is not).
        elif echo "$line" | grep -qE "Test Suite '[^']+' started at"; then
            suite=$(echo "$line" | grep -o "Test Suite '[^']*" | cut -d"'" -f2)
            if [ "$suite" != "All tests" ] && [ "$suite" != "Selected tests" ]; then
                draw_step "Suite" "▶ $suite"
            fi
        elif echo "$line" | grep -qE "Test Suite '[^']+' passed at"; then
            suite=$(echo "$line" | grep -o "Test Suite '[^']*" | cut -d"'" -f2)
            if [ "$suite" != "All tests" ] && [ "$suite" != "Selected tests" ]; then
                draw_step "Suite" "${GREEN}✓ $suite${RESET}"
            fi
        elif echo "$line" | grep -qE "Test Suite '[^']+' failed at"; then
            suite=$(echo "$line" | grep -o "Test Suite '[^']*" | cut -d"'" -f2)
            draw_step "Suite" "${RED}✗ $suite${RESET}"
        fi
    done

    if [ "$errors" -eq 0 ]; then
        draw_footer "SUCCESS"
        exit 0
    else
        draw_footer "FAILED ($errors errors)"
        exit 1
    fi
}

format_stream "$@"
