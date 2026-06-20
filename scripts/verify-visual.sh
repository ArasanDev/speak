#!/usr/bin/env bash
#
# scripts/verify-visual.sh — Agent-drivable visual verification harness for `speak`.
#
# PURPOSE:
#   v0 is code-complete; the only remaining v0 gate is docs/human-verification.md
#   (live behaviour). External AX/System-Events UI-scripting is BLOCKED without an
#   Accessibility grant, but `screencapture` works without one. So this harness
#   drives the app's own DEBUG launch surface (`--debug-open <target>`, gated to
#   #if DEBUG) — the app opens its own windows / runs its own pipeline — and
#   captures a screenshot per state. The orchestrating agent then Reads each PNG
#   and records a "rendered" verdict (NOT a "behaves-live" verdict — see the
#   integrity rule in docs/human-verification.md §4).
#
# USAGE:
#   scripts/verify-visual.sh            # capture every target
#   scripts/verify-visual.sh settings   # capture one target
#
# OUTPUT: PNGs in $OUTDIR (default /tmp/speak-verify). The agent Reads them.
#
# REQUIRES: a DEBUG build of Speak.app (make build). No TCC permissions needed
#   for the window-render targets. simulate-dictation pastes into the frontmost
#   app, so this harness brings TextEdit frontmost first for that target.
set -euo pipefail

APP="${SPEAK_APP:-build/DerivedData/Build/Products/Debug/Speak.app}"
OUTDIR="${SPEAK_VERIFY_OUT:-/tmp/speak-verify}"
SETTLE="${SPEAK_SETTLE:-2.5}"          # window draw settle time (s)
SIM_WAIT="${SPEAK_SIM_WAIT:-9}"        # simulate-dictation: > app's 2.5s arm delay + STT + cleanup + paste

# Window-render targets (no permissions, no focus stealing into a target app).
WINDOW_TARGETS=(
  onboarding-welcome onboarding-microphone onboarding-accessibility
  onboarding-inputmonitoring onboarding-hotkey onboarding-done
  settings history overlay-demo
)

die() { echo "ERROR: $*" >&2; exit 1; }
[ -d "$APP" ] || die "Speak.app not found at '$APP' — run 'make build' first."
mkdir -p "$OUTDIR"

quit_speak() { pkill -x Speak 2>/dev/null || true; osascript -e 'delay 0.4' >/dev/null 2>&1 || true; }

capture_window_target() {
  local target="$1"
  local out="$OUTDIR/$target.png"
  quit_speak
  open "$APP" --args --debug-open "$target"
  osascript -e "delay $SETTLE" >/dev/null 2>&1 || true
  screencapture -x "$out"
  echo "captured: $out"
  quit_speak
}

capture_simulate_dictation() {
  local out="$OUTDIR/simulate-dictation.png"
  quit_speak
  # Fresh TextEdit doc as the paste target, brought frontmost.
  osascript >/dev/null 2>&1 <<'OSA' || true
tell application "TextEdit"
  activate
  make new document
end tell
OSA
  osascript -e 'delay 1' >/dev/null 2>&1 || true
  # Speak waits ~2.5s before running the pipeline, so TextEdit stays frontmost
  # and the synthetic Cmd+V lands there. Speak (LSUIElement) must NOT activate.
  open -g "$APP" --args --debug-open simulate-dictation
  osascript -e "delay $SIM_WAIT" >/dev/null 2>&1 || true
  screencapture -x "$out"
  echo "captured: $out (inspect for pasted fixture text in TextEdit)"
  quit_speak
}

run_one() {
  case "$1" in
    simulate-dictation) capture_simulate_dictation ;;
    *) capture_window_target "$1" ;;
  esac
}

if [ "$#" -ge 1 ]; then
  run_one "$1"
else
  for t in "${WINDOW_TARGETS[@]}"; do run_one "$t"; done
  capture_simulate_dictation
fi

echo
echo "Done. Screenshots in $OUTDIR — the agent now Reads each PNG and records a"
echo "'rendered' verdict in docs/human-verification.md (rendered != behaves-live)."
