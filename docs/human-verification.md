# `speak` — Human-Verification Checklist (the live gates)

> **Why this file exists.** The build runs autonomously, but several v0 ship-gate
> criteria are **physically impossible to verify headlessly** — they need a human
> on a real Mac to grant OS permissions, enable Apple Intelligence, and observe
> paste behavior in real apps. The autonomous loop builds the code and unit-tests
> every *pure* path; each criterion below is the remaining *live* half, marked in
> `roadmap.md`/`progress.md` as `[deferred — needs human verification]`.
>
> **Discipline (hard rule):** the loop must NEVER mark these passed without a real
> run. "Done = verified, not assumed." This file is the single place to track them.
> When you (the human) complete a row, record the result here and the loop will
> reconcile `roadmap.md` + the ship gate.
>
> **Updated**: 2026-06-20 (after P6). Living doc — appended as more seams land.

---

## 0. One-time setup (do this first)

These unblock every live test below.

- [ ] **Build & launch**: `make run` (builds `Speak.app`, launches the menubar app).
- [ ] **Grant Microphone** when first prompted (P2 — needed for capture).
- [ ] **Grant Accessibility**: System Settings → Privacy & Security → Accessibility
      → enable `Speak`. *(Required for the global hotkey CGEventTap **and** the
      synthetic Cmd+V paste.)*
- [ ] **Grant Input Monitoring**: System Settings → Privacy & Security → Input
      Monitoring → enable `Speak`. *(Required for the global Fn hotkey tap.)*
- [ ] **Enable Apple Intelligence**: System Settings → Apple Intelligence & Siri
      → turn on. *(Required for the Foundation Models cleanup path; it is gated
      OFF on the dev Mac, which is why P3.5's live quality is deferred.)*

---

## 1. P3.5 — AI cleanup (Foundation Models), live

The engine logic + graceful-fallback are unit-verified; the **live model** is not
(Apple Intelligence is gated off on the dev Mac).

- [ ] With Apple Intelligence ON, `FoundationModelsCleaner.isAvailable` returns
      `true` (not the fallback path).
- [ ] A real dictation with cleanup ON produces **cleaned** text (fillers removed,
      punctuation + capitalization correct) — not the raw transcript.
- [ ] Cleanup quality is acceptable vs the raw transcript (subjective; log notes
      in `progress.md` for P13).
- [ ] With Apple Intelligence OFF, the session still reaches `done` and pastes the
      **raw** transcript (graceful fallback — should already hold; confirm live).

## 2. P5 — Global hotkey (CGEventTap double-tap Fn), live

The `DoubleTapDetector` logic + `HotkeyBinding` Codable are unit-verified; the
**live OS tap** is not.

- [ ] **First-run prompts**: launching triggers the Accessibility + Input
      Monitoring permission prompts (if not already granted).
- [ ] **Double-tap Fn starts capture while another app has focus** (e.g. focus
      TextEdit, double-tap Fn → menubar goes red / overlay appears).
- [ ] **Single-tap Fn stops** capture (→ processing → paste).
- [ ] **Fn-key event model holds**: the physical Fn/Globe key actually fires the
      tap (the implementation assumes `flagsChanged` + `.maskSecondaryFn`; this is
      `[inferred]` and needs live confirmation — esp. on external keyboards).
- [ ] **False-trigger rate < 1 per 30 min** of normal typing in Notes
      (`benchmark.md` §7 `F_rate`). Tune the 0.4 s double-tap window here if needed.

## 3. P6 — Paste (write-never-read + Cmd+V), live  ← **highest-risk**

The text-selection logic (`cleanedText ?? rawText`) + error mapping are
unit-verified; the **live paste** is not. **This is the project's #1 `[unverified]`.**

- [ ] **TextEdit** (plain text field): dictate → finished text pastes at cursor.
- [ ] **Slack** (rich text): finished text pastes correctly.
- [ ] **Terminal / iTerm** — ⚠️ **THE #1 UNKNOWN**: macOS 26.4 added a
      paste-provenance / pastejacking check (`_sourceSigningIdentifier`, ~74-app
      allowlist). Confirm our `NSPasteboard.write` + synthetic Cmd+V **pastes
      without triggering a prompt or being blocked**. If it IS blocked, the
      mitigation (architecture §11 / risk #3) is per-app AX paste for Terminal.
- [ ] **No macOS 26.4 paste-protection prompt** appears in any tested app (we
      write, never read — the read-prompt should never fire; confirm).
- [ ] **Password field**: synthetic Cmd+V is silently rejected by secure fields;
      the session reaches `done` **without crashing** (graceful no-op).

## 4. UI screens (visual verification — built, not yet seen)

UI built after the user authorized it (2026-06-21). Logic/persistence is
unit-tested; the **rendered, interactive behavior** needs a human running the app.

### 4.1 Settings window (P10)
- [ ] "Settings…" menu item opens a window.
- [ ] AI cleanup toggle flips `cleanupEnabled`; turning it off → the **next**
      dictation pastes raw text (the toggle is read per-dictation).
- [ ] Language picker shows en-US + en-GB; STT picker shows Apple Speech
      (others disabled v0.1/v1 placeholders); cleanup-engine picker shows
      Foundation Models (Ollama disabled placeholder); paste-mode picker present.
- [ ] Settings persist after quitting + relaunching.

### 4.2 Menubar states (P8)
- [ ] The menubar icon visibly changes through idle → listening → processing →
      done → idle across a real dictation (symbol changes are wired + tested;
      confirm they actually render on each transition).
- [ ] The "done" indication shows ~600ms then returns to idle.
- [ ] (Polish) Consider distinct colors (red/yellow/green) — currently
      monochrome SF Symbols; cosmetic.

### 4.3 Partial-transcript overlay (P4)

The text-accumulation logic (`OverlayTextAccumulator`) is unit-verified (11 tests,
all green). The overlay's **live behavior** is `[deferred — needs human verification]`:

- [ ] **Overlay appears on listening**: double-tap Fn → the translucent card appears
      near the top-center of the screen (below the menubar) while the menubar icon
      changes to "listening".
- [ ] **Panel does NOT steal focus**: while the overlay is visible, keyboard focus
      remains in the app you were dictating into (TextEdit, Slack, etc.). Typing in
      that app still works normally while the overlay is shown.
- [ ] **Partials update in real time**: spoken words appear in the overlay as the
      transcriber produces partial chunks. The perceived lag between speech and
      overlay update should meet the `L_partial` < 200 ms budget (`benchmark.md` §7).
      `[deferred — benchmark.md §7 L_partial; measured at build time as 42 ms p50
       on a file-fed proxy — live lag includes mic buffer and SpeechAnalyzer overhead]`
- [ ] **"Listening…" placeholder shown before first partial**: between the moment
      the overlay appears and when the first non-empty chunk arrives, the card shows
      "Listening…" (empty-state placeholder), not a blank card.
- [ ] **Empty chunks do not blank the overlay**: if the transcriber momentarily
      emits an empty string between hypotheses, the previous text stays displayed
      (newest-non-empty rule — verified in unit tests; confirm live behavior matches).
- [ ] **Overlay hides on done**: after endDictation() (single-tap Fn), the overlay
      disappears before the menubar switches to "processing". The text is already
      pasted at the cursor.
- [ ] **Overlay hides on error**: if the dictation fails (e.g. STT unavailable),
      the overlay also hides and does not linger.
- [ ] **Multi-space / full-screen**: the overlay appears when the focused app is in
      a full-screen space (panel `collectionBehavior` includes `.fullScreenAuxiliary`
      and `.canJoinAllSpaces`).

### 4.4 Onboarding flow (P7)

The `OnboardingStateMachine` step logic and `SettingsStore.hasCompletedOnboarding`
persistence are unit-verified (`OnboardingFlowTests` — 14 tests, all green). The
`IOHIDCheckAccess` input-monitoring status read typechecks against the macOS 26 SDK
([verified: swiftc -typecheck, 2026-06-21]). The **live, rendered behavior** is
`[deferred — needs human verification]`.

- [ ] **Onboarding appears on first launch**: `make run` on a fresh install (or after
      `defaults delete com.speak.app`) → the onboarding window opens before or alongside
      the menubar icon appearing.
- [ ] **Welcome screen displays correctly**: title card with the waveform icon and
      "Get Started" button renders; "Skip for now" is in the footer.
- [ ] **Microphone step — first-run dialog fires**: tapping "Grant Microphone Access"
      triggers the macOS microphone permission dialog. After granting, the step shows a
      green checkmark and a "Continue" button.
- [ ] **Microphone denied — Settings deep-link**: if microphone is denied (test by
      pre-denying in System Settings), the "Open System Settings instead" link appears
      and opens `Privacy & Security → Microphone` in System Settings.
- [ ] **Accessibility step — deep-link opens correct pane**: "Open System Settings"
      opens `Privacy & Security → Accessibility` (the
      `?Privacy_Accessibility` anchor). After toggling the app on, the status indicator
      flips to ✓ within ~2 s (the 1.5 s poll interval + processing time).
      `[deep-link anchor correctness: deferred — verify on macOS 26 Tahoe]`
- [ ] **Input Monitoring step — deep-link opens correct pane**: "Open System Settings"
      opens `Privacy & Security → Input Monitoring` (the `?Privacy_ListenEvent` anchor).
      After toggling on, the checkmark appears. `[anchor correctness: deferred — macOS 26]`
- [ ] **IOHIDCheckAccess returns correct state**: after granting Input Monitoring in
      System Settings and returning to the app, `PermissionManager.status(.inputMonitoring)`
      returns `.granted`. After denying, returns `.denied`. Confirms IOKit live correctness.
      `[deferred — environment-dependent, confirmed only with real TCC grant]`
- [ ] **Hotkey step renders correctly**: "Double-tap Fn" explanation, the Fn icon, and
      "Finish Setup" button.
- [ ] **Done step + auto-close**: "You're all set." screen appears, then the window
      closes automatically after ~1.5 s.
- [ ] **hasCompletedOnboarding persists**: after finishing, quit and relaunch the app —
      the onboarding window does NOT appear again.
- [ ] **Skip path works**: clicking "Skip for now" closes the onboarding window and does
      not re-show on next launch (flag is set). Permissions can be granted later via the
      `Grant Accessibility + Input Monitoring` menu item.
- [ ] **Revocation → re-shows onboarding**: revoke Accessibility in System Settings while
      the app is running; quit and relaunch — the onboarding window re-appears on the
      Accessibility step (`showOnboardingIfNeeded` fires because `status(.accessibility)`
      returns `.denied` even though `hasCompletedOnboarding == true`).
- [ ] **Window comes to front**: the onboarding window is frontmost after launch without
      the app appearing in the Dock (LSUIElement). `NSApp.activate(ignoringOtherApps:true)`
      is wired; confirm it actually brings the window to front on macOS 26.
- [ ] **Step progress dots**: five dots appear in the footer; the filled dot tracks the
      current step (welcome=1, microphone=2, accessibility=3, inputMonitoring=4, hotkey=5).

---

## 5. P12 — README demo GIF and screenshots

> **Added**: 2026-06-21, P12 public docs.

The README placeholder reserves space for a demo GIF showing the full dictation
flow (double-tap Fn → overlay streams → paste). This requires a live, working
app with all permissions granted — it cannot be fabricated or captured headlessly.

- [ ] **Demo GIF**: record a ~10 s screen capture of the full flow (hotkey →
      overlay appears + streams → text pastes at cursor in a visible app) using
      QuickTime or another recorder; export as an optimised GIF or short MP4;
      embed in `README.md` in the "How it works" section (replace the TODO
      placeholder once this item is checked off).
      *Unblock condition*: §0 setup complete + §2 and §3 pass (hotkey fires;
      paste works in at least one target app).
- [ ] **Screenshots (optional, v0.1)**: a Settings window screenshot and an
      overlay screenshot to accompany the install instructions. Same unblock
      condition as the GIF.

When both items above pass, update `README.md`'s Status section to remove the
"Demo GIF — deferred" note and embed the media.

---

## How to use this file

1. Do §0 setup once.
2. Walk §1–§3; check boxes; note failures with the app + observed behavior.
3. For any failure, file it in `progress.md` (P13 dogfood log) and apply the
   documented mitigation (each row references one).
4. When a section fully passes, the corresponding `roadmap.md` rows flip from
   `[~]`/`[deferred]` to `[x] [verified]`, and the v0 ship-gate (`SPEC.md` §11)
   advances. The loop will reconcile once you report results here.
