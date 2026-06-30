# Wispr Flow desktop UI — VERIFIED (screenshot + web), 2026-06-21

> **Status**: `[verified]` evidence. Upgrades the prior `[recall]`-tagged Wispr notes
> in `ui-frontend-ideation.md §11` / `acceleration-plan.md`. Source: a real Wispr Flow
> Home-screen screenshot supplied by the user (`wisperflow.png`, gitignored/personal —
> NOT committed) + Wispr help-center & features pages (fetched 2026-06-21).
> `research/` is read-only evidence; the **direction** lives in `acceleration-plan.md`.

## App shell (full-window Mac app)
Left **sidebar IA** (verified order from screenshot):
`Home · Insights · Dictionary · Snippets · Style · Transforms · Scratchpad`
- Sidebar header: product logo + plan badge ("Basic").
- Sidebar footer block: weekly usage ("1,995 words remaining / 2,000 per week"),
  "Upgrade to Pro" (purple), then `Invite your team · Get a free month · Settings · Help`.
- Top-right of content: notification bell + account avatar.

## Home = the dictation feed + stats rail  ← KEY CORRECTION
**Home is NOT a status/hotkey page.** It is:
- A personalized greeting: *"Hey {firstName}, get back into the flow with [fn]"* —
  with an **orange `fn` keycap** inline (our `KeyCapView` accent is correct).
- The **day-grouped dictation history** as the main column: `TODAY` / `YESTERDAY`
  headers, each row = timestamp (e.g. "02:52 am") + the dictated text, full width.
- A **right-rail stats card**: `1,565 total words · 94 wpm · 2 day streak`, plus a
  "Voice Profile Unlocked! / Create report" promo.
→ So **Home = recent feed + stats rail**; a separate **History** view is the deeper
  searchable archive. (We had Home and History inverted.)

## Per-screen behavior (web-verified)
- **Dictionary**: add custom words so STT spells them; auto-learned words get a ✨
  sparkle; entries sync. (→ our `customVocabulary` seam; add ✨ for future auto-learn.)
- **Snippets**: a **trigger** (what you say) + **expansion** (what's inserted).
  (→ confirms our B.2 design: expand trigger→expansion before LLM cleanup.)
- **Style**: adapts tone (formal / casual / enthusiastic) by context.
  (→ our `CleanupStyle` Default/Professional/Casual/Code/Email aligns.)
- **Transforms**: highlight any text + press a shortcut → AI rewrites it. Built-ins:
  **Polish** (clarity/concision) and **Prompt Engineer** (restructure into an AI prompt).
- **Scratchpad**: multi-tab rich-text notes; type or dictate into it; **also the
  paste-failure safety net** (if paste fails, the transcript lands here to edit/Copy).

## Dictation flow (web-verified)
- **Double-tap Fn** → start long dictation; **Fn again** → stop → **auto-pastes
  immediately** at the cursor. (No edit-before-paste *countdown* by default.)
- LLM refinement: **Backtrack/self-correction** ("2… actually 3" → "3"), filler
  removal, auto-punctuation, numbered lists, code/camelCase preservation.
- **Command Mode** (a distinct mode): **hold `Fn`+`Ctrl`** (or `Cmd`+`Ctrl`+`Opt`),
  speak a command over **highlighted** text, release → Flow **replaces the selection**
  with the AI result. `ESC` cancels. Saying "press enter" pastes + submits. Selection
  cap ~1000 words.
- **Paste-last-transcript** fallback shortcut: `Ctrl`+`Cmd`+`V` (Mac).

## Direction corrections for `speak` (carry into the build)
1. **Home = day-grouped feed + right-rail stats** (was inverted with History).
2. Add sidebar items **Transforms** + **Scratchpad** (were missing).
3. **Wave D pivot**: replace the "edit-before-paste countdown" with **Command Mode**
   (hold-chord → AI-edit highlighted text) + **Scratchpad paste-failure fallback** +
   paste-last-transcript shortcut. (Auto-paste stays the default happy path.)
4. **WPM** needs per-dictation **duration** — `HistoryEntry` must store it (small add;
   `TranscriptionResult.duration` already exists, just not persisted).

## Stays true to our moat (do NOT copy these)
Wispr's cloud/account/paywall/usage-cap/team-sync are the exact things our
local-first/free/no-account moat rejects. We copy the **UX & IA**, never the cloud
dependency. (e.g. "1,995 words remaining" weekly cap → we show *nothing* like it.)
