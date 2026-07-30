# speak — Future Surfaces (v1/v2/v3+)

> **Purpose**: v1/v2/v3+ UI design exploration (snippet editor, dictionary editor, etc). · **Audience**: contributor, AI agent (low-priority reference) · **Status**: living design exploration — do not implement until the v0 ship gate passes · **Last reviewed**: 2026-06-30 (git log)

> v1/v2/v3+ design exploration. Low-priority reference. Do not implement until the v0 ship gate passes.

---

## v1 Surfaces

### 2.8 Snippet editor [planned: v1]

**Goal:** Define voice commands — trigger phrase → expansion text.
Examples: "new line" → `\n`, "period" → `.`, "my email" → `tamil@example.com`.

Snippets run **before** LLM cleanup. Cleanup is configured to skip punctuation when a snippet already inserted it.

```
┌─────────────────────────────────────────────────────────┐
│ speak — Snippets                                ⊕ ⊗     │
├─────────────────────────────────────────────────────────┤
│  🔍 Search snippets                                     │
│  ─────────────────────────────────────────────────      │
│  ┌───────────────────────────────────────────────────┐  │
│  │ "new line"        →  \n                            │  │
│  │ "new paragraph"   →  \n\n                          │  │
│  │ "period"          →  .                             │  │
│  │ "comma"           →  ,                             │  │
│  │ "question mark"   →  ?                             │  │
│  │ ─── my custom ───                                  │  │
│  │ "my email"        →  tamil@example.com             │  │
│  │ "lgtm"            →  Looks good to me.             │  │
│  └───────────────────────────────────────────────────┘  │
│  [+ Add Snippet]  [Import…]  [Export…]                  │
└─────────────────────────────────────────────────────────┘
                                                  520×480
```

Built-in snippets (v1): top 10 voice punctuation commands (period, comma, question mark, exclamation, new line, new paragraph, colon, semicolon, open/close paren).

Storage: JSON in `~/Library/Application Support/speak/snippets.json`. Importable/exportable.

Open question: snippets before LLM cleanup vs. as part of it? Proposal: before cleanup; cleanup prompt gets "skip punctuation" mode flag.

### 2.9 Custom vocabulary editor (Dictionary) [planned: v1]

**Goal:** Add words the STT engine should recognize. Names, jargon, technical terms.

Apple `SpeechAnalyzer` supports custom vocabulary via `SFSpeechLanguageModel`.

```
┌─────────────────────────────────────────────────────────┐
│ speak — Dictionary                              ⊕ ⊗     │
├─────────────────────────────────────────────────────────┤
│  Words the speech engine should listen for.             │
│  ─────────────────────────────────────────────────      │
│  ┌───────────────────────────────────────────────────┐  │
│  │ Word           Pronunciation?   Source             │  │
│  │ Tamil          (auto)           Manual             │  │
│  │ SpeechAnalyzer (speech-AN-)     Manual             │  │
│  │ Cgeventtap     (cg-EVENT-tap)   Manual             │  │
│  └───────────────────────────────────────────────────┘  │
│  [+ Add Word]  [Import from contacts]  [Clear]          │
└─────────────────────────────────────────────────────────┘
```

Source column: Manual / Contacts / Auto-learned.
"Import from contacts" → Contacts picker, adds first/last/org names. Requires `NSContactsUsageDescription` [planned: v1.1].

Open question: per-engine vocabulary? Proposal: one vocabulary, transformed per-engine at use time.

### 2.10 Modes editor (Style) [planned: v1]

**Goal:** Named presets — language, cleanup prompt, snippets, hotkey, optional per-app binding.

**This is the single most-requested feature across all competitor reviews.**

```
┌─────────────────────────────────────────────────────────┐
│ speak — Style                                  ⊕ ⊗      │
├─────────────────────────────────────────────────────────┤
│  ┌───────────────────────────────────────────────────┐  │
│  │  ●  Default                                       │  │  ← active (radio)
│  │     Casual, friendly, with filler removal         │  │
│  │  ○  Professional                                  │  │
│  │     Formal, no contractions, terse                │  │
│  │  ○  Casual                                        │  │
│  │     Relaxed, keeps "yeah" and "gonna"             │  │
│  │  ○  Code                                          │  │
│  │     Code-aware, preserves variable names          │  │
│  │  ○  Email                                         │  │
│  │     Greeting/sign-off aware, formal               │  │
│  └───────────────────────────────────────────────────┘  │
│  [Edit cleanup prompt…]   [Reset to default]            │
│  [Apply to all apps]      [Per-app overrides →]         │
└─────────────────────────────────────────────────────────┘
```

Built-in modes (v1): Default, Professional, Casual, Code, Email.
Per-app overrides: auto-switch when frontmost app changes [planned: v1.1].
"Edit cleanup prompt…" opens a sheet with the `LLMCleaning` system prompt. `Save` writes back; `Reset to default` restores shipped prompt.

### 2.12 CLI shim [planned: v1]

**Goal:** `speak --start`, `speak --stop`, `speak --status`, `speak --config`, `speak --export`.

```
$ speak --help
speak — local-first voice dictation
  speak --start                  Start dictation
  speak --stop                   Stop and paste
  speak --cancel                 Cancel in-flight dictation
  speak --status                 Print state (idle|listening|...)
  speak --toggle                 Toggle (start if idle, stop if listening)
  speak --config <key>=<value>   Set a config value
  speak --export <file>          Export history to JSON
  speak --mute / --unmute        Mute / unmute
  speak --version
```

CLI cannot grant permissions. User must run the GUI once. For power users and dogfood team only.

### 2.13 Status popover (menubar click) [planned: v1]

**Goal:** Richer alternative to the dropdown menu. A 360×400 popover with live status, recent dictations, and quick actions.

Use when modes + snippets + language = 6+ items in the dropdown. A popover with sections is more scannable than a 20+ item dropdown.

```
┌──────────────────────────────────────────────┐
│  speak  ⏺                                    │
│  ──────────────────────────────────          │
│  Status: Listening  (0:04)                   │
│  Mode: Default  |  Language: en-US           │
│  Engine: Apple Speech  +  Foundation Models  │
│  ──────────────────────────────────          │
│  [▶ Start Dictation]      ⌥⌘Space            │
│  [🔇 Mute Microphone]                        │
│  ──────────────────────────────────          │
│  Recent dictations:                          │
│  • Hello world, this is a test.   10:32 AM   │
│  • This is a longer dictation…    10:30 AM   │
│  [See all history →]                         │
│  ──────────────────────────────────          │
│  [Settings…]  [About speak…]                 │
└──────────────────────────────────────────────┘
                                       360×400
```

Decision: v0 = dropdown (built); v1 = evaluate migration. If modes + snippets are 6+ items, popover wins.

---

## v2+ Aspirational surfaces

### 2.11 Voice commands / AI Transforms [planned: v2]

**Goal:** Select text in any app, invoke a voice command, and the local LLM applies a rewrite.

Requires text-selection detection (`AXUIElement` focused range) and per-app integration. Engineering risk is high.

```
Built-in transforms:
  ⌥⌘R  Rephrase          ⌥⌘S  Make shorter
  ⌥⌘L  Make longer       ⌥⌘F  Fix grammar
  ⌥⌘T  Translate         ⌥⌘B  Bullet list
  ⌥⌘N  Numbered list     ⌥⌘E  Explain (for code)
  ⌥⌘P  Proofread         ⌥⌘H  Humanize
```

Interaction flow: user selects text → presses transform hotkey → popover appears near selection with "Rewriting…" spinner → result + Apply/Undo. `Esc` to cancel.

### Conversation view (v2)

Rename "History" to "Conversations." Add per-app grouping, per-day grouping, "today" quick-filter pill. For users who dictate 50+ times/day.

### Live confidence overlay (v1 → ship it)

Render partial transcript words with confidence coloring: low (0.0–0.6) = `.secondary`, mid (0.6–0.85) = `.primary`, high (0.85+) = primary with subtle underline. Data is already in `TranscriptionResult`. This is the single biggest HUD UX tell Wispr users love.

### Code mode (v2)

Auto-activate when frontmost app is Xcode, VS Code, Cursor, JetBrains. No filler removal, no capitalization fix. Snippets: "open paren" → `(`, "new line" → `\n`, "tab" → `  `.

### Multi-dictation batch (v2)

Dictate N separate thoughts separated by Fn taps. Long-press Fn to paste all at once.

### Live translation (v2/v3)

Speak in language A; LLM translates to language B before paste. Runs before paste, not as cleanup.

**Anti-feature — do NOT ship:** audio-reactive desktop wallpaper or menubar glow. Stay subtle. The HUD is the attention surface.

---

## Wispr Flow reorientation (2026-06-21) [design-exploration]

> **Added after studying the Wispr Flow Home dashboard screenshot.** This section reorients three load-bearing assumptions. It is a **[decision] for the human** — it changes the v0.1 build order.

### Three assumptions that changed

**1. Full-window Home dashboard, not just menubar.**

Wispr Flow's Home dashboard is the always-primary surface. The conversation log is the landing page. It makes the app feel like a *product* rather than a *tool*. This is a large architectural shift.

**2. Sidebar = navigation.**

Wispr uses a 2-pane layout (sidebar + content) with 7 feature areas. The sidebar model is more discoverable than Settings-as-window and scales to v1+ features (Snippets, Dictionary, Style, Transforms, Scratchpad). Standard Mac idiom: System Settings, Mail, Music.

**3. Feature names updated.**

| Original | Wispr-aligned | Why |
|---|---|---|
| Custom Vocabulary | **Dictionary** | Friendlier, matches Wispr + MacWhisper |
| Modes | **Style** | "Formatting presets" is clearer |
| AI Commands | **Transforms** | "Transform" is the user-facing verb |
| (new) | **Scratchpad** | Quick-notes surface; strong power-user feature |
| (new) | **Insights** | Gamification: WPM, streak, total words |

### Menubar-only vs. full-window dashboard

| | Menubar-only (current) | Full-window Dashboard |
|---|---|---|
| Vibe | Tool, daemon | Product, voice journal |
| Discoverability | Low | High (sidebar IS the IA) |
| v1 feature scale | Modal windows stack up | Sidebar grows cleanly |
| Mac idiom | Pushover-style | Mail / System Settings-style |
| Engineering cost | Lower | Higher |
| Risk | "Just a tool" perception | Drift from minimal identity |

**Proposed decision:** ship menubar-only for v0, add dashboard in v0.1 alongside a popover option. User picks default in Settings.

### Home dashboard layout [planned: v0.1]

```
┌────────────────────────────────────────────────────────────────────────┐
│ ⬛ 🟡 🟢  [tile]                                            [help] [⌘W]│
├──────────────┬─────────────────────────────────────────────────────────┤
│  ⏶ speak     │  Welcome back. Press [fn] to start.                    │ ← hero
│              │  ─────────────────────────────────                      │
│  ▦ Home      │  TODAY                                                  │
│  📖 History  │  ┌──────────────────────────────────────────────────┐  │
│  ⚙  Settings │  │ 02:52 am   Amen.                                  │  │
│  ?  Help     │  │ 02:51 am   Can you hear me?                       │  │
│              │  └──────────────────────────────────────────────────┘  │
│  ─── v1+ ─── │  YESTERDAY                                              │
│  📖 Dictionary│  ┌──────────────────────────────────────────────────┐  │
│  ✂ Snippets   │  │ 10:32 am  Hello world, this is a test.            │  │
│  Tt Style     │  │ 10:30 am  This is a longer dictation…             │  │
│  ✨ Transforms│  └──────────────────────────────────────────────────┘  │
│  📄 Scratchpad│                                                          │
│              │  [Show older →]                                          │
└──────────────┴─────────────────────────────────────────────────────────┘
                                                  880×640 (min)
```

**Sidebar IA (v0.1):** Home (conversation log), Settings (existing form as tab), Help (Markdown viewer → GitHub README).

**v1 sidebar additions** (disabled, "coming in v1" badge): Dictionary, Snippets, Style, Transforms, Scratchpad.

**Settings-as-tab:** clicking Settings replaces content area. No separate `SettingsWindowController` modal window.

**Menubar coexistence:** "Open Dashboard…" item in menubar dropdown (⇧⌘D).

### 30 design observations from Wispr Home dashboard

Key adopt decisions for v0.1:
- Day-grouped entries ("TODAY" / "YESTERDAY") with uppercase letter-spaced labels. Token: `.textCase(.uppercase).tracking(1.5)`.
- Full text inline — no `lineLimit(3)`. Dashboard list is the conversation.
- Empty entries preserved (when `text == ""`). Shows timestamp + hairline divider only.
- SF Mono timestamps, 13 pt secondary. "Log file" feel.
- Sidebar selection: soft warm-gray rounded rect. Token `Tokens.Color.Sidebar.selected ≈ Color(white: 0.92)`.
- All sidebar icons: line-style SF Symbols, consistent stroke weight.
- `KeyCapView` component for `[fn]` key cap in hero. Orange/rust background, black text, 14 pt SF Pro Rounded.
- 200 pt fixed sidebar width. `Tokens.Spacing.m` for item left padding.
- Destructive actions (Clear, Export) hidden in Settings — dashboard is read-only.

Skip for speak:
- "Hey {name}" personalization (no account in v0). v1: ask name in onboarding opt-in.
- "Invite your team" / "Get a free month" (speak is free/open).
- Usage limit promo card. Replace with "What's new in v0.1" tip card.
- Right-floating stats card (v1+, with Insights surface).

### v0.1 build sequence (post-reorientation)

1. `SpeakCore/UI/Tokens.swift` — design-token seam. Unblocks everything.
2. `App/UIComponents/KeyCapView.swift` — used in 4+ places.
3. `App/UIComponents/Sidebar.swift` + `SidebarItem` — unblocks dashboard.
4. `App/Dashboard/DashboardWindowController.swift` — mirror of `OnboardingWindowController`.
5. `App/Dashboard/DashboardView.swift` — 2-pane layout, Home tab first.
6. `App/Dashboard/HistoryViewModel` rewrite — day-grouping, full text, empty-row handling.
7. Settings-as-tab — refactor `SettingsView` from window scene to dashboard tab.
8. Menubar "Open Dashboard…" item wired to `DashboardWindowController.show()`.
9. Help tab — lightweight Markdown viewer → GitHub README.
10. v1 surface scaffolding — Dictionary/Snippets/Style/Transforms/Scratchpad placeholders with "coming in v1" badges.
11. Insights tab (v2).

Each step is backwards-compatible with v0. No existing code changed except the Settings-as-window → Settings-as-tab refactor in step 7.

---

## New v1 surface: Scratchpad [planned: v1]

**Goal:** Dictate without focusing an external app. A persistent, searchable, exportable note surface inside speak.

```
┌──────────────┬─────────────────────────────────────────────────────┐
│  📄 Scratch.←│  Scratchpad                                         │
│              │  ┌─────────────────────────────────────────────┐  │
│              │  │ Today                                         │  │
│              │  │ 10:32 am                                      │  │
│              │  │ "The .env file has real API keys…"            │  │
│              │  │ Yesterday                                     │  │
│              │  │ 4:36 am                                       │  │
│              │  │ "Understand the project, explore deeply."     │  │
│              │  └─────────────────────────────────────────────┘  │
│              │  [New Entry]  [Search…]  [Export…]                 │
└──────────────┴─────────────────────────────────────────────────────┘
                                                  640×600 (min)
```

HUD shows "Saving to Scratchpad" instead of "Cleaning up…" when scratchpad is the destination.

v0.1: manual destination (user clicks "New Entry" then dictates). v1: auto-route when no text field is focused (detect via `AXUIElement.focusedUIElement`).

---

## New v2 surface: Insights [planned: v2]

**Goal:** Gamification / analytics — total words, WPM, day streak, active hours, top snippets, engine usage.

```
┌──────────────┬─────────────────────────────────────────────────────┐
│  📊 Insights←│  Insights                                           │
│              │  This week                                           │
│              │  ┌─────────────────────────────────────────────┐  │
│              │  │  1,565  total words                           │  │  ← hero stats
│              │  │     94  wpm                                  │  │     40 pt sans
│              │  │      2  day streak                           │  │     (NOT serif)
│              │  └─────────────────────────────────────────────┘  │
│              │  Activity (12 weeks)                               │
│              │  ┌─────────────────────────────────────────────┐  │
│              │  │  ▁▂▅█▇▃▁▂▄▁  (bar chart)                   │  │
│              │  └─────────────────────────────────────────────┘  │
│              │  Top snippets                                       │
│              │  • period (×147)  • new line (×83)                 │
└──────────────┴─────────────────────────────────────────────────────┘
```

Hero stat font: **40 pt sans-serif** (not serif). SF Pro, bold. Gives "hero stat" feel without diverging from Mac idiom.
If the human wants serif, switch via `Tokens.Typography.StatNumber.font`.

Data sources: `HistoryEntry.cleanedText.wordCount`, `wordCount / duration.minutes`, consecutive days with ≥1 entry.

Skip "Top apps" (privacy-sensitive; requires logging frontmost app; opt-in v2, removed v3). Skip Achievements (freemium growth lever; speak is free).

---

## New component catalog additions (v1+)

### 3.13 `KeyCapView(label: String, color: Color)` [planned: v0.1]

Styled keyboard-key visual. Used in: onboarding hotkey step, dashboard hero, Settings hotkey display.

```
┌──────┐
│  fn  │  ← ~36×32 pt, rounded rect (6 pt), orange/rust background,
└──────┘    black "fn" text, 14 pt SF Pro Rounded medium, center-aligned
```

Variants: `KeyCapView(.fn)`, `.globe`, `.cmd`, `.cmdShift("Space")`.

### 3.14 `Sidebar<Content>(items:, selection:, content:)` [planned: v0.1]

Two-pane container with standard Mac sidebar. 200 pt fixed width. Item rows: icon + label, ~32 pt tall. Selection: soft warm-gray rounded rect. Divider above footer items.

```swift
struct SidebarItem: Identifiable, Hashable {
    let id: String
    let icon: String      // SF Symbol name
    let label: String
    let badge: String?    // optional "v1" pill
    let isEnabled: Bool   // false → show but disabled
}
```

### 3.15 `DayGroupedList(entries: [HistoryEntry])` [planned: v0.1]

Groups entries by day. Each group: uppercase letter-spaced day label + `Card` with entries.

```
TODAY                     ← 11 pt uppercase, tracking(1.5)
┌──────────────────────────────────────┐
│ 02:52 am  Amen.                      │
│ 02:51 am  Can you hear me?           │
└──────────────────────────────────────┘
```

### 3.16 `StatTile(value: String, label: String, font: Font)` [planned: v2]

Large-number + small-label tile for Insights hero. Used 3-up in a row.

### 3.17 `EditBeforePastePill` [planned: v1]

Expanded post-stop pill with editable `TextEditor` + countdown + Apply/Cancel. See §2.3 edit-before-paste. Tap text to pause countdown.

### 3.18 `TransformPopover` [planned: v2]

Popover near text selection when a transform hotkey fires. Shows "Rewriting…" spinner → result + Apply/Undo.

### 3.19 `ModeCard(name:, description:, isActive:, onSelect:)` [planned: v1]

Radio-style card for the Style tab. Active mode: filled radio + thin border accent.

### 3.20 `DevicePickerRow` [planned: v1]

Device name + live `LevelMeterView` (large variant) + selection radio. Used in Audio & Devices settings.

### 3.21 `BarChart(data: [Int], labels: [String])` [planned: v2]

12-week activity bar chart for Insights.

### 3.22 `HeatmapView(data: [Date: Int], bucket: Calendar.Component)` [planned: v2]

7×24 (or 7×12) heatmap for "Active hours" in Insights.

---

## Wispr Flow deep-dive (recall-based — awaiting screenshot verification)

> **Honesty boundary.** Claims below are tagged: `[verified]` (from Home dashboard screenshot), `[recall:high]` (well-documented public UX), `[recall:med]` (known feature, UI details uncertain), `[recall:low]` (educated guess). Send screenshots from §11.13 to upgrade to `[verified]`.

### 11.1 Audio & Devices [recall:med]

Device list with per-row live level meter. Auto-fallback when Bluetooth device disconnects mid-dictation: "AirPods disconnected — using MacBook mic" toast.

### 11.2 Recording HUD (Wispr variant)

**Position:** top-center, ~80 pt from top. `speak` uses bottom-center. Explicitly rejected. [verified: we reject top-center]

**Edit-before-paste expansion `[recall:high]`:**
```
┌──────────────────────────────────────────────────────────┐
│  ┌──────────────────────────────────────────────────┐   │
│  │ "the quick brown fox jumps over the lazy dog"    │   │  ← editable TextEditor
│  └──────────────────────────────────────────────────┘   │
│  [Cancel]              Editing · paste in 1.2s          │
│  [Paste]  ⌘↩                                            │
└──────────────────────────────────────────────────────────┘
```

Key pattern: **auto-paste countdown** visible in footer. Tap text to pause. `⌘↩` to paste, `Esc` to cancel. This is the killer pattern for speak v1.

Done state: pill collapses → green ✓ for 400 ms → fade 200 ms. Fast — user should not stare at "done" for more than 500 ms.

### 11.3 Menubar dropdown (Wispr variant) [recall:high]

```
speak — ready (double-tap Fn to start)
─────────────────────────────────────
▶ Start Dictation                  ⌥⌘Space
🔇 Mute Microphone
─────────────────────────────────────
  Mode ▸       Default / Professional / Casual / Code / Email
  Language ▸   en-US / en-GB / fr-FR / de-DE / es-ES / More…
  Style ▾  Default
─────────────────────────────────────
  Open Dashboard…              ⇧⌘D
  History…                      ⌘H
  Settings…                     ⌘,
  Help                          ⌘?
─────────────────────────────────────
  About speak…
─────────────────────────────────────
  Quit speak                    ⌘Q
```

speak v0.1 plan: add "Mode ▸" submenu (5 modes), "Language ▸" submenu, "Open Dashboard…" item.

### 11.4 Voice profile setup [explicitly skipped for speak]

Apple `SpeechAnalyzer` adapts automatically. No explicit enrollment step needed. The onboarding stays at 5 steps.

"Voice Profile Unlocked" milestone concept: after ~50 dictations, show a celebration. Speculative — would need accuracy measurement.

### Screenshot wishlist (to upgrade from recall to verified)

| # | Surface | Recall tier |
|---|---|---|
| 1 | Recording HUD — active state | `[recall:high]` |
| 2 | Recording HUD — edit-before-paste expansion | `[recall:high]` |
| 3 | Audio / device picker | `[recall:med]` |
| 4 | Settings main page | `[recall:med]` |
| 5 | Voice profile setup | `[recall:med]` |
| 6 | Dictionary editor | `[recall:med]` |
| 7 | Snippets editor | `[recall:high]` |
| 8 | Style / Modes editor | `[recall:high]` |
| 9 | Transforms editor | `[recall:high]` |
| 10 | Insights page | `[recall:med]` |
| 11 | Scratchpad view | `[recall:med]` |
| 12 | Menubar dropdown | `[recall:high]` |
| 13 | Onboarding full flow | `[recall:high]` |

Even 3–4 of the most important (1, 2, 7, 8, 12) would upgrade ~80% to `[verified]`.
