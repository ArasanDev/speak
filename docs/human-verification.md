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

> Rows for P8 menubar states, P4 overlay, and P7 onboarding are added here as
> those screens land.

---

## How to use this file

1. Do §0 setup once.
2. Walk §1–§3; check boxes; note failures with the app + observed behavior.
3. For any failure, file it in `progress.md` (P13 dogfood log) and apply the
   documented mitigation (each row references one).
4. When a section fully passes, the corresponding `roadmap.md` rows flip from
   `[~]`/`[deferred]` to `[x] [verified]`, and the v0 ship-gate (`SPEC.md` §11)
   advances. The loop will reconcile once you report results here.
