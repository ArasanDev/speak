#!/usr/bin/env bash
#
# register-mcp.sh — register the installed speak-mcp bridge with every MCP-capable
# agent CLI found on this machine, idempotently.
#
# `install-mcp-user` places the relocatable binary + frameworks under
# ~/Library/Application Support/speak/mcp/. Until now it stopped there and printed a
# JSON blob for the human to hand-paste into each agent's config. This script closes
# that gap.
#
# Blast radius: this WRITES OUTSIDE THE REPO, into user-level agent configuration
# (~/.claude.json for Claude Code, ~/.codex/config.toml for Codex). It only touches
# the single server entry named by SERVER_NAME. Re-running is safe: an existing entry
# of that name is removed and re-added, so there is never a duplicate.
#
# Usage:
#   scripts/register-mcp.sh            # show what would change, write nothing
#   scripts/register-mcp.sh --apply    # actually register
#
set -euo pipefail

MCP_USER_DIR="${MCP_USER_DIR:-$HOME/Library/Application Support/speak/mcp}"
BRIDGE="$MCP_USER_DIR/bin/speak-mcp"
SERVER_NAME="${SERVER_NAME:-speak-app}"

APPLY=0
[ "${1:-}" = "--apply" ] && APPLY=1

if [ ! -x "$BRIDGE" ]; then
  echo "register-mcp: no bridge at $BRIDGE" >&2
  echo "register-mcp: run 'make install-mcp-user' first." >&2
  exit 1
fi

# The install path contains a space ("Application Support"), and agent CLIs store the
# command as an argv[0] string. Launching through 'zsh -lc exec' keeps the quoting
# correct in every client rather than relying on each one to handle the space.
LAUNCH_CMD='/bin/zsh'
LAUNCH_ARGS=(-lc "exec \"\$HOME/Library/Application Support/speak/mcp/bin/speak-mcp\"")

echo "==> register-mcp: bridge     $BRIDGE"
echo "==> register-mcp: server name '$SERVER_NAME'"
if [ "$APPLY" -eq 0 ]; then
  echo "==> register-mcp: DRY RUN — nothing will be written. Re-run with --apply."
fi
echo

found_any=0

register_claude() {
  command -v claude >/dev/null 2>&1 || return 0
  found_any=1
  echo "--> Claude Code detected ($(command -v claude))"
  if [ "$APPLY" -eq 0 ]; then
    echo "    would run: claude mcp remove $SERVER_NAME   (ignore-if-absent)"
    echo "    would run: claude mcp add $SERVER_NAME -- $LAUNCH_CMD ${LAUNCH_ARGS[*]}"
    return 0
  fi
  # Remove-then-add is how we stay idempotent; a missing entry is not an error here.
  claude mcp remove "$SERVER_NAME" >/dev/null 2>&1 || true
  claude mcp add "$SERVER_NAME" -- "$LAUNCH_CMD" "${LAUNCH_ARGS[@]}"
  echo "    registered with Claude Code."
}

register_codex() {
  command -v codex >/dev/null 2>&1 || return 0
  found_any=1
  echo "--> Codex detected ($(command -v codex))"
  if [ "$APPLY" -eq 0 ]; then
    echo "    would run: codex mcp remove $SERVER_NAME   (ignore-if-absent)"
    echo "    would run: codex mcp add $SERVER_NAME -- $LAUNCH_CMD ${LAUNCH_ARGS[*]}"
    return 0
  fi
  codex mcp remove "$SERVER_NAME" >/dev/null 2>&1 || true
  codex mcp add "$SERVER_NAME" -- "$LAUNCH_CMD" "${LAUNCH_ARGS[@]}"
  echo "    registered with Codex."
}

register_claude
register_codex

echo
if [ "$found_any" -eq 0 ]; then
  echo "register-mcp: no supported agent CLI found (looked for: claude, codex)."
  echo "register-mcp: for any other MCP client, add this stdio server manually:"
  echo "  {\"command\":\"$BRIDGE\"}"
  exit 0
fi

if [ "$APPLY" -eq 1 ]; then
  echo "register-mcp: done. The menubar app must be running to own the mic and TTS."
  echo "register-mcp: verify with 'claude mcp list' (expect '$SERVER_NAME ... Connected')."
else
  echo "register-mcp: dry run complete. Re-run with --apply to write."
fi
