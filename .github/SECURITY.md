# Security policy

## Threat model

`speak` is a 100% local, offline-by-default macOS app — there is no server
component to compromise, no account database, no telemetry pipeline. The
threat surface that matters here is **local, not remote**:

- **Microphone access** — speak captures audio only while dictating, and never
  while hardware-muted (`SpeakEngineMuteTests` pins this in CI).
- **Accessibility / `CGEventTap`** — used for the global hotkey and to simulate
  Cmd+V for pasting. A bug here could mean a stray synthetic keystroke, or a
  hotkey that fires when it shouldn't.
- **Pasteboard writes** — speak writes the cleaned/raw transcript to the
  system pasteboard and simulates a paste. It never *reads* the pasteboard
  (`make verify-moat` enforces this structurally, not just as a claim).
- **Local SQLite history** (`~/Library/Application Support/speak/`) — stores
  past dictations on disk, unencrypted, readable by anything with local
  filesystem access to that user account.
- **`SpeakLLM` (opt-in cloud cleanup)** — the one deliberate exception to
  "no networking." If enabled, transcript text is sent to whatever
  OpenAI-compatible endpoint the user configures, using a key stored in
  Keychain. This is opt-in and isolated to its own build target precisely so
  the rest of the app can be structurally audited as having zero networking
  code.
- **`speak-mcp` / Agent Bridge** — a local stdio MCP server that lets an
  agent (e.g. Claude Code, Codex) request structured input, speak
  notifications, or poll durable "agent calls" through the running app. It
  has no access to ambient microphone audio, dictation history, pasteboard,
  files, or screen — only the narrow tool surface in
  `specs/agent-voice-bridge.md`.

If you find a way to defeat any of these boundaries — e.g. capture audio
while muted, read the pasteboard, get `speak-mcp` to reach outside its
documented tool surface, or leak data off-device from a target that isn't
`SpeakLLM` — that's a security bug, not a feature request.

## Reporting a vulnerability

Please **do not** open a public GitHub issue for a security vulnerability.

<!-- TODO: maintainer to fill in a real disclosure contact (email or GitHub
     Security Advisories link) before this policy is considered complete. -->
Report privately via **TODO: maintainer contact (email or GitHub Security
Advisory) not yet configured** — until this is filled in, please open a
[GitHub Security Advisory](https://github.com/ArasanDev/speak/security/advisories/new)
on this repository, which is private by default between you and the
maintainer.

Please include:
- macOS version, chip, and `speak` version/commit
- Steps to reproduce
- What boundary you believe was crossed (see threat model above) and why

## Scope

In scope: anything in this repository (`SpeakCore`, `Speak.app`, `SpeakLLM`,
`speak`/`speak-mcp` CLIs). Out of scope: vulnerabilities in Apple frameworks
themselves (report those to Apple), or issues requiring physical access to an
already-unlocked, already-compromised Mac.
