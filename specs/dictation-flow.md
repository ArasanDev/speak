# Spec — End-to-end dictation flow (hotkey → record → process → paste)

> **Owner:** orchestrator (principal engineer). **Status:** active build contract.
> **Grounded in** three research reports (OSS: VoiceInk, Hex, Handy, Whispering;
> lifecycle: AltTab, Loop) — all claims carry file:line / SDK citations in the
> session record. **Supersedes** ad-hoc hotkey behavior; does not change the moat.

## 0. The flow (user's words, normalized)

Cursor sits in *any* app that accepts keyboard input (Terminal, editor, chat) →
user triggers the hotkey → a small **recording HUD** appears (never steals focus)
→ user speaks → user ends the trigger → STT + cleanup run → finished text is
inserted **at the cursor**. Two trigger gestures on one key:
- **Double-tap = toggle** (tap-tap to start hands-free, single tap to stop).
- **Press-and-hold = push-to-talk** (hold to record, release to stop).

## 1. Diagnosis (what was actually wrong) — [verified, this session]

1. **Signing** — Xcode (Cmd+R) built **ad-hoc**, so every run's cdhash changed and
   TCC grants broke. *Fixed* (Signing.xcconfig → both Xcode + make cert-sign;
   cert-anchored DR proven stable across builds).
2. **Tap never re-arms** — `DictationController.startMonitoring()` calls
   `monitor.start()` once at launch; on permission-denied it returns and never
   retries. So a grant made *after* launch does nothing until relaunch. (`App/
   DictationController.swift:169-208`, log: `CGEvent.tapCreate failed: Accessibility
   not granted`.) **← the "input monitoring isn't working" symptom.**
3. **`HotkeyMonitor.init` blocks the main thread** (semaphore wait → priority-inversion
   backtrace). Violates the no-main-thread-block rule.
4. **No single-instance guard** — multiple launches coexist and contend.
5. Benign: `com.apple.linkd.autoShortcut` App-Intents registration noise.

## 2. Permission model — [verified research]

- **The Fn `.flagsChanged` tap is gated by Accessibility OR Input Monitoring;
  Accessibility alone is sufficient** (AltTab/Hex create their keyboard tap under
  AX only). We need Accessibility regardless for the synthetic Cmd+V paste.
- **Decision:** gate the tap on **Accessibility**; request **Input Monitoring**
  (`CGRequestListenEventAccess()` registers + prompts) but **do NOT hard-block
  onboarding on it** — treat it as the "expected/correct" grant, not a gate.
- **Re-arm signal:** no distributed notification exists for Input Monitoring; poll
  `AXIsProcessTrustedWithOptions([prompt:false])` + `IOHIDCheckAccess(.listenEvent)`
  at ~100 ms while ungranted, back off once granted. AX also has the (undocumented)
  `com.apple.accessibility.api` notification (250 ms settle) as an optional fast path.
- Escape hatch for stale entries: `make reset-permissions` (tccutil reset). [done]

## 3. Hotkey architecture — adopt Hex's model

Keep the existing seam (live `HotkeyMonitor` + pure testable detector + `AsyncStream`)
— it already matches Hex, the cleanest OSS design. Replace the 2-state
`DoubleTapDetector` with a **pure 3-state processor**: `idle → pressAndHold(start) →
doubleTapLock`. One Fn key yields **both** gestures, auto-distinguished:
- Press → `.startRecording` (enter `pressAndHold`).
- Release after `< doubleTapWindow` and a quick second tap → `doubleTapLock` (stay
  recording hands-free); next press → `.stopRecording`.
- Release after a real hold (≥ min-hold) → `.stopRecording` (push-to-talk).
- Fn **release edge** must be processed (currently ignored).

**Constants (each traces to a shipping app — no magic numbers; record in benchmark.md §7):**
| Constant | Value | Source |
|---|---|---|
| double-tap window | 0.3 s | Hex `doubleTapWindow` |
| min-hold (modifier-only) guard | 0.3 s | Hex `modifierOnlyMinimumDuration` |
| re-trigger cooldown | 0.5 s | VoiceInk `shortcutPressCooldown` |
| debounce (key-repeat) | 30 ms | Handy `DEBOUNCE` |

(speak's current 0.4 s double-tap window → move to 0.3 s, or keep 0.4 s with a
`benchmark.md` note; tune in dogfood.)

**Fn press/release:** `.flagsChanged` + `keyCode == kVK_Function` (0x3F) +
`flags.contains(.maskSecondaryFn)` → present = down, absent = up (Hex). Binding stays
user-configurable (external keyboards may lack Fn / repurpose Globe).

**Tap robustness (watchdog):** re-enable on `tapDisabledByTimeout/ByUserInput`
(`CGEvent.tapEnable`); cap restarts (Loop: 5 / 2 s); re-arm on
`NSWorkspace.didWakeNotification` + a 3 s second pass (AltTab); keep the callback
trivial on a dedicated thread; **emit a synthetic release if the tap dies mid-hold**
so push-to-talk never sticks "on" (VoiceInk).

## 4. Recording HUD

Keep `TranscriptOverlayPanel` (mechanics already correct: `.nonactivatingPanel`,
floating, `[.canJoinAllSpaces, .fullScreenAuxiliary]`, `canBecomeKey=false`,
`orderFrontRegardless`). Deltas:
- Add `.stationary, .ignoresCycle` to collectionBehavior.
- **Position: bottom-center** (VoiceInk/Wispr/Handy consensus; top risks menubar/notch
  collision). No caret-anchoring — *no* OSS app does it (jitter not worth it).
- **Visual states:** idle (dim bars) → recording (live mic waveform) → processing →
  done. Drive the waveform from the live `AVAudioEngine` tap RMS, linearized
  `pow(10, dB/20)` (Hex). Keep it subtle (Wispr's prominent pill is the cautionary tale).

## 5. Text insertion at cursor

Current `PasteboardWriter` = write-only pasteboard + Cmd+V, no fallback, no settle.
Deltas:
- **Add a pre-paste settle (~0.10 s)** + explicit Cmd-down / V-down / V-up / Cmd-up
  (VoiceInk/Hex post the modifier key events explicitly; we set `.maskCommand` only).
- **Fallback chain (graceful degradation — Whispering floor):** if Accessibility
  ungranted / no focused field / paste fails → leave text on the clipboard + notify;
  never silently drop. (Writing to the clipboard is allowed; only *reading* is barred.)
- **Optional** Hex AX-insert (`kAXSelectedTextAttribute`) as a Terminal/provenance-resilient
  strategy (also fails in secure fields — complement, not cure).
- **⚠️ OPEN DECISION (needs orchestrator/user sign-off):** clipboard *restore* after
  paste requires **reading** the pasteboard to snapshot it — every OSS app does this —
  which conflicts with the hard rule "never read the pasteboard." Options: (a) relax the
  rule *only* to snapshot our own restore (with the session-ownership guard so we never
  clobber a user's mid-window copy), or (b) skip restore (clobber clipboard). **Do not
  decide silently.** Until decided: no restore (option b), text left on clipboard as the
  fallback only.
- **Terminal provenance (macOS 26.4):** whether synthetic write+Cmd+V trips the prompt
  for a dev-signed app is `[unverified]` — empirical test at live verification.

## 6. Build phases (each verified before the next)

- **A — Make it fire (no relaunch):** re-arm watchdog (poll → rebuild tap on grant edge),
  non-blocking `HotkeyMonitor.init`, single-instance guard, don't hard-block onboarding on
  Input Monitoring, silence App-Intents noise. *Done-when:* grant Accessibility live → tap
  arms within ~0.2 s with no relaunch; double-tap Fn fires start/stop (verified live).
- **B — Two trigger modes:** Hex 3-state processor; push-to-talk hold + double-tap toggle;
  min-hold guard; synthetic-release safety; constants above. *Done-when:* hold-to-talk and
  double-tap-lock both work from Fn; pure-unit-tested with injected timestamps.
- **C — HUD:** states + live mic level + bottom-center. *Done-when:* HUD shows on trigger,
  streams partials + level, never steals focus, hides on done/error (screenshot-verified).
- **D — Robust paste:** settle + explicit modifier events + graceful-degradation fallback;
  resolve §5 clipboard-restore decision. *Done-when:* pastes into TextEdit/editor live;
  no-focus + failure paths leave text on clipboard, never crash.
- **E — Live end-to-end:** real spoken dictation in ≥2 apps; latency logged.

## 7. Routing
A,B → builder-input (hotkey/paste seam) + builder-engine (session). C → builder-app
(overlay). D → builder-input. QA gates throughout. Orchestrator reviews every diff,
owns commits, verifies live with the harness + the user's real grant.
