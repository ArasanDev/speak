---
name: dev-codesigning-for-tcc
description: speak dev builds must be cert-signed (Signing.xcconfig) or macOS TCC permission grants break on every rebuild; Xcode AND make must both use it
metadata: 
  node_type: memory
  type: project
  originSessionId: a5c0ce3e-f540-4a41-8c36-c46462a9457c
---

The biggest live blocker (2026-06-21): macOS TCC binds Accessibility / Input-Monitoring grants to the app's **code-signing designated requirement (DR)**. Ad-hoc signing pins the DR to the binary's **cdhash**, which changes every build → a grant made against one build is rejected by the next → the classic *"enabled in System Settings but `AXIsProcessTrusted()` is false."* Proven empirically on macOS 26.5.

**Fix (committed):** signing lives in `Signing.xcconfig`, applied to every config via `project.yml` `configFiles` — so **both `make build` and Xcode Cmd+R** cert-sign with a stable self-signed identity `speak-local-codesign`. The DR becomes `identifier "com.speak.app" and certificate leaf = H"…"` — **identical across rebuilds** (verified by diffing `codesign -d -r-` of two clean builds). `make dev-cert` creates the cert (idempotent; no `add-trusted-cert`/password needed — codesign signs by name even when the cert is untrusted) and writes the git-ignored `Signing.local.xcconfig`. Default without the cert = ad-hoc, so clean clones / CI still build.

**Gotcha that cost real time:** Xcode builds to `~/Library/Developer/Xcode/DerivedData/Speak-…`, NOT `./build/DerivedData`. A Makefile-only post-sign therefore fixes the `make` build while the **Xcode build the user actually runs stays ad-hoc.** Always put dev signing in the build itself (xcconfig), never a post-build step. Diagnose divergence with two running instances: `ps -o command -p <pids>` + `codesign -dv` each.

**Escape hatch for stale TCC entries:** `make reset-permissions` → `tccutil reset Accessibility|ListenEvent|Microphone com.speak.app`. Then re-grant once against the stable identity.

**Adjacent verified facts (this session):**
- The Fn `.flagsChanged` listen tap is gated by **Accessibility alone**; Input Monitoring is the "expected" grant but does NOT gate the tap (confirmed in AltTab/Hex). Don't hard-block onboarding on Input Monitoring.
- A CGEventTap created while untrusted stays **dead until re-armed** — poll `AXIsProcessTrustedWithOptions`/`IOHIDCheckAccess` ~100ms and rebuild the tap on the grant edge (Hex pattern); there is NO distributed notification for Input Monitoring (AX has `com.apple.accessibility.api`, 250ms settle). See `specs/dictation-flow.md`.
- FM cleanup needs Apple Intelligence enabled (`SystemLanguageModel.default.availability` returned `appleIntelligenceNotEnabled`) — a human toggle.

**Agent-drivable verification:** the `make`-signed app + `scripts/verify-visual.sh` + `#if DEBUG --debug-open <target>` opens any window for `screencapture` with no AX grant (external AX UI-scripting IS blocked; screencapture is not). Relates to [[agent-first-acceleration-model]].

**Dogfood-failure diagnostic checklist (cost real time again 2026-06-29 — "detecting but not pasting"):** when paste/hotkey silently fails live, check IN THIS ORDER before touching code:
1. **STALE BINARY TRAP** — a long-running `Speak` process can predate your last `make build`; you're testing OLD code. `pgrep -lf "Speak.app/Contents/MacOS/Speak"` then compare its start time to the build time. `make build` overwrites the on-disk app but the running PID keeps old code. Quit (`osascript -e 'quit app "Speak"'`) and relaunch.
2. **SIGNATURE IS AD-HOC** — `codesign -dvvv <app> 2>&1 | grep Authority` must show `Authority=speak-local-codesign`. If absent/`TeamIdentifier=not set` → ad-hoc → AX grant won't survive rebuild. NB: `security find-identity -v -p codesigning` reports **"0 valid identities"** even when `speak-local-codesign` exists (self-signed = not "valid"); use `find-identity -p codesigning` WITHOUT `-v`, or just trust the `codesign` Authority line.
3. **LIVE LOGS** — the shell aliases `log`; use the absolute path: `/usr/bin/log stream --predicate 'subsystem == "com.speak.app"' --level info --style compact` (run in background, then reproduce). The exact failing gate prints: `streaming enabled — skipping final paste` (the pre-#29 bug), `AX not trusted — skipping Cmd+V`, `focused element is a secure field`, `empty transcript`, or success `Cmd+V sequence posted to .cghidEventTap`.
The 2026-06-29 incident was BOTH (1) stale pre-#29 binary AND (2) ad-hoc signature. Recovery sequence that works: `make dev-cert` → `make build` (verify Authority) → `make reset-permissions` → relaunch → re-grant AX once. v0 base verified working after this; tagged `git v0-base`. Relates to [[profile-engine-north-star]].
