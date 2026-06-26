---
name: per-app-context-awareness
description: Use when implementing AppContext detection for v0.1 tasks V01-0 (Agent Mode) and V01-3 (per-app context awareness) — reads frontmost app bundle ID via NSWorkspace and optionally selected text via Accessibility APIs.
---

# Per-App Context Awareness — Implementation Pointer

## Architectural Seam

New module: `SpeakCore/Context/`
- `AppContext.swift` — enum of context categories + prompt injection strings
- `AppContextDetector.swift` — NSWorkspace + AX reading; actor-isolated
- Injection point: `CleanupContext` (already exists in `SpeakCore/Cleanup/`) — add `appContext: AppContext` field

The detector runs continuously while `speak` is in the background. When dictation starts, the orchestrator snapshots the current `AppContext` and passes it into `CleanupContext`.

## AppContext Categories `[decision]`

```swift
public enum AppContext: String, CaseIterable, Sendable {
    case codeEditor    // Xcode, VS Code, Cursor, Zed
    case terminal      // Terminal.app, iTerm2, Warp, Alacritty
    case agentCLI      // Terminal running Claude Code, Codex, Open Code — subset of terminal
    case messaging     // Slack, Teams, Messages, Telegram, Discord, WhatsApp
    case email         // Mail.app, Spark, Mimestream, Gmail in browser
    case browser       // Safari, Chrome, Firefox, Arc (non-email/non-doc URL)
    case document      // Pages, Word, Notion, Obsidian, Bear, Notes
    case other         // Everything else (default)
}
```

## Cleanup Prompt Injections (appended to base cleanup prompt) `[decision]`

| AppContext | Injected clause |
|---|---|
| `.codeEditor` | "Format output as code-context prose: use camelCase for variables/functions, snake_case only if the snippet context shows it, no filler words, preserve exact technical terms and filenames." |
| `.terminal` | "Output is for a terminal. Use terse imperative sentences. Preserve exact command names, flags, paths. No punctuation at end of commands." |
| `.agentCLI` | "This is a task description for an AI coding agent. Rephrase as clear imperative instructions. Preserve exact file paths, function names, technical terms. No filler. Numbered steps if multiple actions." |
| `.messaging` | "Output is a casual chat message. Conversational tone. Short sentences. No formal punctuation." |
| `.email` | "Output is an email body. Professional tone. Proper punctuation and paragraphs." |
| `.browser` | "Output is web text input. Natural prose, proper punctuation." |
| `.document` | "Output is document prose. Full sentences, proper punctuation, paragraph-aware." |
| `.other` | (no additional clause — use base cleanup prompt only) |

## Hard Constraints

- **NEVER read `NSPasteboard`** — moat rule. AX read of selected text is allowed (it's a READ via accessibility, not a pasteboard read). `make verify-moat` checks for pasteboard reads.
- **Context detection must not block the main thread.** Run `NSWorkspace` observation on `Task { }` background and cache the result in an actor.
- AX selected text reading requires **Accessibility permission** (separate from Microphone). It is already granted for the hotkey `CGEventTap`. Confirm the same grant covers `AXUIElementCopyAttributeValue` — it does for non-sandboxed apps on macOS `[inferred]`.
- Do not retain a long-lived `AXUIElement` reference — create, read, release per query.

## NSWorkspace API `[verified — standard AppKit, pre-cutoff]`

```swift
import AppKit

// Get current frontmost app bundle ID
let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
// e.g. "com.apple.dt.Xcode", "com.microsoft.VSCode", "com.apple.Terminal"

// Observe app switches (on main thread — use Task for background work after)
let center = NSWorkspace.shared.notificationCenter
center.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                   object: nil, queue: .main) { note in
    let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
    // app.bundleIdentifier — update cached AppContext here
}
```

## AX Selected Text API `[inferred — verify with swiftc -typecheck]`

```swift
import ApplicationServices

func readSelectedText() -> String? {
    let systemElement = AXUIElementCreateSystemWide()
    var focused: AnyObject?
    guard AXUIElementCopyAttributeValue(systemElement,
        kAXFocusedUIElementAttribute as CFString, &focused) == .success,
        let focusedElement = focused else { return nil }

    var selected: AnyObject?
    guard AXUIElementCopyAttributeValue(focusedElement as! AXUIElement,
        kAXSelectedTextAttribute as CFString, &selected) == .success else { return nil }
    return selected as? String
}
```

Only call this when context awareness is enabled AND the cleanup mode would benefit from selected-text context (`.agentCLI`, `.codeEditor`). Never call on every keypress — call once when dictation stops.

## Bundle ID Reference Table `[inferred — verify at implementation, values can change]`

| App | Bundle ID |
|-----|-----------|
| Xcode | `com.apple.dt.Xcode` |
| VS Code | `com.microsoft.VSCode` |
| Cursor | `com.todesktop.230313mzl4w4u92` |
| Zed | `dev.zed.zed` |
| Terminal.app | `com.apple.Terminal` |
| iTerm2 | `com.googlecode.iterm2` |
| Warp | `dev.warp.Warp-Stable` |
| Slack | `com.tinyspeck.slackmacgap` |
| Messages | `com.apple.MobileSMS` |
| Mail | `com.apple.mail` |
| Safari | `com.apple.Safari` |
| Chrome | `com.google.Chrome` |
| Arc | `company.thebrowser.Browser` |
| Firefox | `org.mozilla.firefox` |
| Pages | `com.apple.iWork.Pages` |
| Notion | `notion.id` |
| Bear | `net.shinyfrog.bear` |
| Obsidian | `md.obsidian` |

Obtain the real bundle ID at runtime: `NSRunningApplication.runningApplications(withBundleIdentifier:)` or read `Info.plist` from `/Applications/<App>.app`.

## Verify at Implementation Time

```sh
# Verify NSWorkspace symbols (pre-cutoff, should be fine)
swiftc -typecheck -sdk "$(xcrun --show-sdk-path)" \
  -target arm64-apple-macosx26.0 \
  -e 'import AppKit; _ = NSWorkspace.shared.frontmostApplication?.bundleIdentifier'

# Verify AX symbols
swiftc -typecheck -sdk "$(xcrun --show-sdk-path)" \
  -target arm64-apple-macosx26.0 probe_ax.swift
# probe_ax.swift: import ApplicationServices; let _ = AXUIElementCreateSystemWide()

# At runtime: print running app bundle IDs to find unknowns
# NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier }.forEach { os_log(.debug, "\($0)") }
```

## Agent Mode Detection (V01-0 specific)

`.agentCLI` is detected by: bundle ID matches a terminal app **AND** process list contains `claude`, `codex`, `opencode`, or `pi` as a child of that terminal window. Use `NSWorkspace.shared.runningApplications` to scan process names `[inferred]`. This is best-effort; fall back to `.terminal` if process scan is inconclusive.
