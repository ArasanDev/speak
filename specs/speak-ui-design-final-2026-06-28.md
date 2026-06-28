# speak — UI Design Specification (Final, Locked v0)

**Date**: 2026-06-28  
**Version**: v0 (ship-ready)  
**Status**: Locked design — implementation can now proceed  
**Source**: Strategic UI/UX research (2026-06-28) + architect decision synthesis

---

## Executive Summary

**speak** is a **sidebar-navigation macOS application** with five integrated surfaces:

1. **Menubar icon** — idle/listening/processing/done status, no menu (hotkey is core)
2. **Overlay HUD** — floating panel during capture, read-only, streams partial text
3. **Main Dashboard window** — persistent sidebar with 5 panes (Dashboard, History, Settings, Privacy, About)
4. **Settings modal** — 6 tabs (General, Transcription, AI Cleanup, Hotkey, Privacy, About)
5. **Privacy pane** — dedicated sidebar section showcasing trust architecture

**Why this design?**
- Matches proven pattern (Wispr Flow, Slack) — discoverable, scales to v0.1/v1
- Emphasizes privacy (BEAT row #4: "searchable local history") — trust-building
- Simple defaults (hotkey works immediately) — zero friction for 95% of users
- Power users can discover transforms, per-app context, custom engines — progressive disclosure
- Monaco theme + semantic colors — calm clarity, not feature-rich clutter

**Unique elements**:
- **Privacy pane** (not buried in settings) — speak's structural moat (local-only, no account, no cloud)
- **Searchable history** (moat #4) — only voice app with full transcript archive
- **Transparent engine choice** — users see which model cleaned their text (Foundation Models, Ollama, etc.)
- **Overlay is read-only** — zero friction during capture, all interactions post-capture

**Design philosophy**: *Calm through clarity, privacy is visible, overlay is non-blocking, consistency serves learning, depth without overwhelm.*

---

## Part 1: Locked Design Decisions (v0)

### Navigation & Application Structure

**Main window structure:**
- **Single, persistent application window** (not modal, not floating)
- **Sidebar navigation** (persistent, 5 panes)
- **Content pane** (changes per sidebar selection)
- **Menubar icon** (status only, no menu)
- **Overlay HUD** (appears during dictation, auto-hides)

**Window geometry:**
- Minimum: 760×520 (sidebar + single pane)
- Default: 920×600 (comfortable for history + settings)
- Maximum: no limit (scales to user's display)
- Resizable, remembers last size
- Sidebar width: 180pt (fixed)

**Sidebar navigation (5 items):**
```
🏠 Dashboard      ← Home, today's stats, recent dictations
📋 History        ← Searchable, exportable transcript archive
⚙️ Settings       ← 6 tabs: hotkey, language, cleanup, privacy, about
🔐 Privacy        ← Trust architecture, verify button, compliance
ℹ️ About          ← Version, links, license, credits
```

**Menubar icon (no menu):**
- Single icon in system menu bar (upper right)
- **States & colors**:
  - Idle: gray waveform (🔘)
  - Listening: red filled circle (🔴 pulsing)
  - Processing: yellow gear spinner (⚙️ animated yellow)
  - Done: green checkmark (✅)
  - Error: red X (❌)
- Single-click **does not open settings** (user double-taps Fn hotkey instead)
- Click shows contextual menu: [Quit], [About], [Open Dashboard] (v0.1+)

---

### Settings Organization (6 Tabs)

Organized by **frequency of change** (top) to **rare/advanced** (bottom):

| Tab | Purpose | Audience | Progressive Disclosure |
|-----|---------|----------|---|
| **General** | Language, theme, notifications, paste mode | Everyone | Language picker + paste toggle top; paste modes below divider |
| **Transcription** | STT engine, microphone selection, vocabulary | Power users | SpeechAnalyzer (default) visible; WhiskerKit (v0.1+) below divider |
| **AI Cleanup** | Engine, mode, tone slider, samples | Everyone | On/off toggle + mode picker top; tone slider + samples below divider |
| **Hotkey & Input** | Rebind hotkey, streaming mode, auto-paste | Power users | Current binding visible; advanced bindings (v0.1+) below divider |
| **Privacy & Data** | Local status, export, reset, verify moat | Trust-conscious | 4-guarantee badges top; export/reset/verify below divider |
| **About** | Version, links, license, credits | Reference | GitHub link, issues, CONTRIBUTING, MIT license, version |

**Tab design notes:**
- Each tab scrolls independently (tabs don't scroll together)
- Divider pattern: `Divider()` separates day-to-day from advanced
- Common controls flush-left; advanced controls indented or below divider
- No empty tabs; every tab has content in v0

---

### Privacy Pane (Dedicated Sidebar)

**Why separate from settings?**
- Privacy is speak's structural moat (100% local, free, open, no account)
- Users should see it immediately (not buried in Settings › Privacy tab)
- Trust-building centerpiece — emphasizes what makes speak different

**Layout:**

```
┌──────────────────────────────────┐
│ 🔐 Nothing Leaves Your Device    │
├──────────────────────────────────┤
│                                  │
│ ✅ Microphone: Local             │
│    Deleted immediately           │
│    No cloud upload, ever          │
│                                  │
│ ✅ Transcripts: Stored Locally   │
│    Searchable, exportable         │
│    Your Mac, your control         │
│                                  │
│ ✅ Cleanup: On-Device Only       │
│    Foundation Models run locally  │
│    No API calls, ever             │
│                                  │
│ ✅ Hotkey: Global, Not Tracked   │
│    No analytics, no telemetry     │
│    Just listening for Fn          │
│                                  │
│ ✅ Offline: Works 100%           │
│    Zero internet required         │
│    Tested & verified              │
│                                  │
├──────────────────────────────────┤
│ [Verify Moat] button             │ ← runs `make verify-moat`, shows results
├──────────────────────────────────┤
│                                  │
│ 📖 Read the source code          │ → GitHub link
│ 📋 License (MIT)                 │ → License text
│ 🐛 Report a privacy concern      │ → Issues link
│ 💬 Join the discussion            │ → Discussions link
│                                  │
├──────────────────────────────────┤
│ Comparison (why speak?)           │
├──────────────────────────────────┤
│                                  │
│ Wispr Flow:                      │
│  ❌ Cloud upload                 │
│  ❌ Login required               │
│  ❌ Word limit on free           │
│                                  │
│ speak:                           │
│  ✅ Local only                   │
│  ✅ No account                   │
│  ✅ Unlimited free               │
│                                  │
└──────────────────────────────────┘
```

**Design details:**
- Headline: "Nothing Leaves Your Device" (bold, 17pt, system font)
- 5 guarantee rows (each: icon + title + explanation)
- Icons: SF Symbols (mic.fill, doc.fill, gear, lock.fill, checkmark.circle.fill)
- Colors: green badges + system colors (no custom)
- [Verify Moat] button (primary blue, prominent)
- Verification results shown inline (pass/fail per BEAT row)
- Comparison table (Wispr vs. speak) — factual, not marketing

---

### Dashboard Home Pane

**First thing users see when they open the app.**

**Layout:**

```
┌──────────────────────────────────┐
│ Hotkey Status                    │
├──────────────────────────────────┤
│ 🟢 Ready to Dictate              │
│ Double-tap Fn to start           │
│ (or adjust in ⚙️ Settings)        │
│                                  │
│ [Start Dictation] button (CTA)   │ ← blue, large, tappable (optional for mouse users)
│                                  │
├──────────────────────────────────┤
│ Today's Quick Stats              │
├──────────────────────────────────┤
│                                  │
│ 🔤 Words dictated today: 247     │
│ 📝 Sessions: 5                    │
│ 🔥 Streak: 7 days (if v1)        │
│                                  │
│ Active cleanup: Foundation Models │ ← engine badge
│                                  │
├──────────────────────────────────┤
│ Recent Dictations (last 5)       │
├──────────────────────────────────┤
│                                  │
│ 14:23 | "speaking into the..." │  ← time, raw preview, cleaned preview, engine
│        | "speaking into the..." │
│                                  │
│ 13:45 | "document generator..." │
│        | "document generator..." │
│                                  │
│ 10:12 | "api keys management..." │
│        | "api keys management..." │
│                                  │
│ [View All] link → History pane   │
│                                  │
└──────────────────────────────────┘
```

**Design notes:**
- **Hotkey status** (top, always visible) — answers "am I ready?"
- **[Start Dictation]** button — optional (users can hotkey instead)
- **Quick stats** — word count, session count, engine name
- **Recent dictations** — last 5 entries (time, 1-line raw, 1-line cleaned, engine badge)
- Click on entry → expands in History pane (not inline)
- All text in Monaco 13pt (body), headers in system 15pt (semibold)
- Monochrome color scheme (no gradients)

---

### History Pane

**First-class transcript archive. Users can search, filter, export, review, and retry.**

**Layout:**

```
┌──────────────────────────────────┐
│ Search bar (text + filters)      │
├──────────────────────────────────┤
│ Filter: [All engines] [All dates] │
├──────────────────────────────────┤
│ TODAY (3 entries)                │
├──────────────────────────────────┤
│                                  │
│ ▶ 14:23 | "speaking into..." |  │ ← collapsible entry
│         | "speaking into..."  │
│                                  │
│ ▶ 13:45 | "document gener..." |  │
│         | "document gener..."  │
│                                  │
│ ▶ 10:12 | "api keys manag..." |  │
│         | "api keys manag..."  │
│                                  │
├──────────────────────────────────┤
│ THIS WEEK (12 entries)           │
├──────────────────────────────────┤
│ [expand all] [collapse all]      │
│                                  │
│ ▶ Jun 27, 16:30 | "..." | "..."  │
│                                  │
│ ... (other week entries)         │
│                                  │
├──────────────────────────────────┤
│ EARLIER (487 entries)            │
├──────────────────────────────────┤
│ [Load more] or paginate          │
│                                  │
└──────────────────────────────────┘
```

**Expanded entry (click ▶ to expand):**

```
┌──────────────────────────────────────────────────────┐
│ 14:23 — Foundation Models                            │
├──────────────────────────────────────────────────────┤
│                                                      │
│ Raw transcript:                                      │
│ ┌────────────────────────────────────────────────┐   │
│ │ speaking into the api document generator code │   │
│ │ with keyboard shortcuts context               │   │
│ └────────────────────────────────────────────────┘   │
│                                                      │
│ Cleaned transcript:                                  │
│ ┌────────────────────────────────────────────────┐   │
│ │ Speaking into the API document generator code │   │
│ │ with keyboard shortcuts context.               │   │
│ └────────────────────────────────────────────────┘   │
│                                                      │
│ [Copy Raw] [Copy Cleaned] [Export] [Retry] [Delete]  │
│                                                      │
└──────────────────────────────────────────────────────┘
```

**Features:**
- **Search bar** (top) — fulltext search, matches raw + cleaned
- **Date filters** — today, this week, date range picker
- **Engine filter** — show all, or filter by STT + cleanup engine
- **List sections** — grouped by TODAY / THIS WEEK / EARLIER
- **Collapsible entries** — each entry shows time, 1-line raw, 1-line cleaned, engine
- **Expanded view** — full raw vs. cleaned side-by-side (Monaco 11pt)
- **Hover actions** — [Copy Raw], [Copy Cleaned], [Export], [Retry], [Delete]
- **Batch actions** — [Export All], [Clear Before Date], [Clear All] with undo
- **Metadata** — time, duration, engine (STT + cleanup), source app (v0.1+)

---

### About Pane

**Reference and links.**

```
┌──────────────────────────────────┐
│ speak v0.0.1                     │
│ Local Voice Dictation            │
│                                  │
│ Speech → text → clean writing    │
│ 100% on your device              │
│                                  │
├──────────────────────────────────┤
│ Version: 0.0.1 (build 1)         │
│ macOS: 26.0+ (Apple Silicon)    │
│ Swift: 5.9+                      │
├──────────────────────────────────┤
│ Links:                           │
│ [GitHub] → repo link             │
│ [Issues] → GitHub Issues         │
│ [Contributing] → CONTRIBUTING.md │
│ [Changelog] → CHANGELOG.md       │
│ [MIT License] → LICENSE text     │
│                                  │
├──────────────────────────────────┤
│ Credits:                         │
│ Built with Apple Frameworks:     │
│ • SpeechAnalyzer (STT)           │
│ • Foundation Models (cleanup)    │
│ • AVAudioEngine (audio)          │
│ • CGEventTap (hotkey)            │
│ • SQLite (history)               │
│                                  │
│ Open source libraries:           │
│ (none in v0)                     │
│                                  │
│ Contributors:                    │
│ [Open contributors.txt]          │
│                                  │
└──────────────────────────────────┘
```

---

### Overlay HUD (During Recording)

**Floating panel that appears when user speaks. Read-only, streams partial text, auto-hides.**

**Idle → Listening:**

```
┌────────────────────────────────────┐
│ 🎤 Listening (red pulsing border)  │
│                                    │
│ speaking into the api document     │ ← partial text (Monaco 13pt)
│ generator code with keyboard       │
│ shortcuts                          │
│                                    │
│ 🇺🇸 EN-US | ⏱ 3.2s (v0.1+)        │ ← language badge + timer
│                                    │
│ [⚙️ Settings] (optional v0.1)      │ ← hidden in v0, popover in v0.1
│                                    │
└────────────────────────────────────┘
```

**Processing → Cleanup:**

```
┌────────────────────────────────────┐
│ ⏳ Processing (yellow glow)        │
│                                    │
│ speaking into the api document     │ ← frozen partial (user sees where cleanup started)
│ ⟳ Cleaning... (Foundation Models)  │ ← spinner + engine name
│                                    │
└────────────────────────────────────┘
```

**Done:**

```
┌────────────────────────────────────┐
│ ✅ Done (green, fades out)         │
│                                    │
│ Speaking into the API document     │ ← cleaned text (Monaco 13pt)
│ generator code with keyboard       │
│ shortcuts.                         │
│                                    │
│ Pasted to your cursor ✓             │
│                                    │
└────────────────────────────────────┘
(Auto-closes after 600ms)
```

**Error:**

```
┌────────────────────────────────────┐
│ ❌ Error (red border)              │
│                                    │
│ Microphone permission not granted  │
│                                    │
│ Open Settings › Privacy & Data     │
│                                    │
└────────────────────────────────────┘
```

**Design notes:**
- **Floating window** — positioned near cursor (not centered)
- **Minimal chrome** — no title bar, no buttons (except optional gear in v0.1)
- **Read-only content** — user cannot interact during capture
- **Color-coded border** — red (listening), yellow (processing), green (done), red (error)
- **Partial text** — streams word-by-word (< 200ms latency)
- **Monospace font** — Monaco 13pt, left-aligned, 40-60 char per line
- **Auto-hide** — on done (600ms fade), on error (3s then close), or on user stop-hotkey
- **Gear icon** (v0.1 only) — taps open small popover: streaming toggle + language picker (not in v0)

---

## Part 2: Visual Language & Design Tokens

### Color Scheme (Semantic, System-Aligned)

All colors use **system semantic colors** (no custom palette). Supports light + dark mode automatically.

| State | Color Token | Usage | Hex (Light) | Hex (Dark) |
|-------|---|---|---|---|
| **Idle** | systemGray | Waiting, inactive | #8E8E93 | #8E8E93 |
| **Listening** | systemRed | Active recording, alert | #FF3B30 | #FF453A |
| **Processing** | systemYellow | Working, LLM inference | #FFCC00 | #FFD60A |
| **Done** | systemGreen | Success, pasted | #34C759 | #32AE4A |
| **Error** | systemRed | Failure, problem | #FF3B30 | #FF453A |
| **Local/Safe** | systemGreen + 🔐 | Privacy badge | #34C759 | #32AE4A |
| **Offline** | systemGreen + ✅ | Offline status | #34C759 | #32AE4A |
| **Raw text** | systemBlue | Unmodified transcript | #007AFF | #0A84FF |
| **Cleaned text** | systemGray | Modified transcript | #8E8E93 | #A3A3A7 |
| **Warning** | systemOrange | Retry available, secondary | #FF9500 | #FF9F0A |

**Accent color**: Warm amber (#FF9500 or systemOrange) for:
- Active tab highlight in Settings
- Primary buttons ([Verify Moat], [Start Dictation])
- Toggle on-state
- Links (system blue also acceptable)

**No gradients, no drop shadows** — semantic color + 1pt borders only.

---

### Typography

**Font stack:**
- **Content text**: Monaco (user locked, 2026-06-21) — monospace, calm, readable
- **UI labels/buttons**: System font (SF Pro or .SF NS Display)
- **Code/keycaps**: Monaco 11pt

**Sizes:**

| Usage | Font | Size | Weight | Line-height |
|-------|------|------|--------|---|
| Body text (History, Dashboard) | Monaco | 13pt | Regular | 1.5 |
| Caption (timestamp, metadata) | Monaco | 11pt | Regular | 1.4 |
| Label (button, toggle label) | System | 13pt | Regular | 1.2 |
| Heading 2 (section titles) | System | 15pt | Semibold | 1.2 |
| Heading 1 (pane titles) | System | 17pt | Semibold | 1.2 |
| Overlay partial text | Monaco | 13pt | Regular | 1.5 |
| Keycap (Fn, Cmd) | Monaco | 11pt | Medium | 1.2 |

**No bold except for headings.** Emphasis via size, not weight.

---

### Spacing Grid (4pt Baseline)

| Name | Value | Usage |
|------|---|---|
| **xs** | 4pt | Padding inside small controls |
| **sm** | 8pt | Gap between list items, inline spacing |
| **md** | 12pt | Gap between groups, padding in cells |
| **lg** | 16pt | Gap between sections, standard padding |
| **xl** | 20pt | Page margin, section top/bottom spacing |
| **xxl** | 24pt | Large section gap, window margin |
| **xxxl** | 32pt | Major section separation |

**Sidebar width**: 180pt (fixed)  
**Minimum window margin**: 20pt (all sides)  
**List item height**: 40pt (minimum, for touch-friendly hit targets)

---

### Icons (SF Symbols Only)

Every icon is a **SF Symbol** (system, semantic, always available).

| Icon | Symbol | Usage |
|------|---|---|
| Home | `house.fill` | Dashboard pane, sidebar |
| History | `clock.fill` | History pane, sidebar |
| Settings | `gear` | Settings pane, HUD gear button (v0.1) |
| Privacy | `lock.fill` | Privacy pane, sidebar |
| About | `info.circle` | About pane, sidebar |
| Microphone | `mic.fill` | Listening state, permission grant |
| Start | `mic.fill` + circle | CTA button, dashboard |
| Stop | `stop.fill` | HUD stop button (if present, v0.1+) |
| Processing | `gear` (animated) | Processing state overlay |
| Success | `checkmark.circle.fill` | Done state, paste success |
| Error | `xmark.circle.fill` | Error state, failure |
| Copy | `doc.on.doc` | Copy button, history actions |
| Export | `arrow.up.doc` | Export button, history |
| Delete | `trash` | Delete action, history |
| Search | `magnifyingglass` | Search bar, history |
| Retry | `arrow.clockwise` | Retry cleanup, history |
| Expand | `chevron.right` | Collapsible list, history |
| Collapse | `chevron.down` | Collapsible list, history |

**Icon sizing**:
- Sidebar icons: 18pt (visible at normal viewing distance)
- Button icons: 16pt (standard)
- Status icons: 12pt (small badges)
- Overlay icons: 14pt (floating panel)

---

## Part 3: Component Specifications

### Buttons

**Primary Button** (blue, calls main action):
- Text: 13pt system semibold, white
- Background: systemBlue (#007AFF light, #0A84FF dark)
- Padding: 8pt (v) × 12pt (h)
- Corner radius: 6pt
- Border: none
- Min width: 100pt
- Examples: [Start Dictation], [Verify Moat], [Export History]

**Secondary Button** (gray, alternative action):
- Text: 13pt system semibold, system label color
- Background: systemGray6 (light) / systemGray5 (dark)
- Padding: 8pt (v) × 12pt (h)
- Corner radius: 6pt
- Border: 1pt systemGray3
- Examples: [Cancel], [Close], [Learn More]

**Danger Button** (red, destructive action):
- Text: 13pt system semibold, white
- Background: systemRed (#FF3B30)
- Padding: 8pt (v) × 12pt (h)
- Corner radius: 6pt
- Border: none
- Examples: [Clear History], [Reset Settings]

**Icon Button** (symbol only, no text):
- Background: transparent (no fill)
- Icon: 16pt system symbol, systemLabel color
- Padding: 6pt (all sides)
- Corner radius: 4pt (hover state: systemGray6 background)
- Examples: copy, delete, expand/collapse, search

**Toggle Switch**:
- Off: gray circle on gray background
- On: blue circle on blue background (systemBlue)
- Padding: 2pt (margin inside track)
- Size: 50pt wide × 30pt tall
- Animation: smooth slide (200ms)

---

### Lists & Tables

**History list entry** (collapsed state):
```
┌─────────────────────────────────────────────────────────┐
│ ▶ 14:23 | "speaking into..." | "Speaking into..." | FM   │
│         (40pt tall, padding 12pt)                       │
└─────────────────────────────────────────────────────────┘
```

- **Collapsed**: time | raw preview (40 chars) | cleaned preview (40 chars) | engine badge
- **Height**: 40pt (sufficient for hit target)
- **Padding**: 12pt (all sides)
- **Dividers**: 1pt systemGray5 between entries
- **Font**: Monaco 13pt (regular) for text, system 11pt (caption) for time
- **Hover state**: systemGray6 background

**History list entry** (expanded state):
- Full-width pane with raw vs. cleaned side-by-side
- Action buttons below: [Copy Raw], [Copy Cleaned], [Export], [Retry], [Delete]
- Metadata: time, duration, engine, source app (v0.1+)

**Settings section**:
```
┌─────────────────────────────────────────────────────────┐
│ General Language                                        │
├─────────────────────────────────────────────────────────┤
│ [English (US)] ← picker                                 │
│                                                        │
│ Auto-paste after cleanup: [Toggle On]                  │
│                                                        │
│ Paste mode: [Cmd+V] ← dropdown (standard, paste special) │
│                                                        │
├─────────────────────────────────────────────────────────┤
│ Advanced (divider above)                                │
├─────────────────────────────────────────────────────────┤
│ Paste delay: [0ms] ← number input                       │
│                                                        │
│ Raw transcript copy: [Toggle Off]                      │
│                                                        │
└─────────────────────────────────────────────────────────┘
```

- **Control alignment**: all controls flush-left (no right-align)
- **Row height**: 40pt (minimum)
- **Grouping**: sections separated by 16pt gap + optional Divider()
- **Labels**: system 13pt, above or to the left of control
- **Advanced section**: divider, then indented or prefixed with "(Advanced)"

---

### Modals & Popovers

**Settings window** (modal sheet):
- Size: 680×520pt minimum (settings content fits)
- Corner radius: 12pt
- Title: "Settings" (system 17pt semibold)
- Tabs: 7 tabs across the top (TabView)
- Each tab scrolls if content exceeds visible height
- Close button: standard × (top-right)

**Gear popover** (v0.1 only, optional quick-access):
- Triggered by: gear icon in overlay HUD (bottom-right)
- Content:
  - Streaming mode toggle
  - Language picker (if auto-detect enabled)
- Size: 200pt wide × 100pt tall (approximate)
- Position: anchored to gear icon, above or beside
- Close on click elsewhere (standard popover)
- Font: system 13pt

**Error sheet** (macOS-standard):
- Title: "Error" (system 17pt semibold)
- Message: clear, actionable error text
- Buttons: [OK], [Help], [Retry] (context-dependent)
- Example: "Microphone permission not granted. Open Settings › Privacy › Microphone to grant access."

---

## Part 4: User Flows

### Flow 1: First Run (Onboarding)

**Step 1: App launches**
```
Speak.app opens
  ↓
Menubar icon appears (gray)
Main window opens → Dashboard Home pane
  ↓
Hotkey status shows: "⏸️ Microphone permission needed"
```

**Step 2: Grant microphone**
```
User clicks "Grant Microphone Permission" button
  ↓
System prompt appears ("speak wants to use your microphone")
  ↓
User clicks "Allow"
  ↓
Hotkey status updates: "⏸️ Accessibility permission needed"
```

**Step 3: Grant accessibility**
```
User clicks "Grant Accessibility Permission" button
  ↓
System opens System Settings › Privacy & Security › Accessibility
  ↓
User finds "speak" in the list, clicks checkbox
  ↓
Returns to speak
  ↓
Hotkey status updates: "🟢 Ready to dictate — Double-tap Fn"
```

**Step 4: First dictation (optional walkthrough, v0.1+)**
```
User double-taps Fn
  ↓
Overlay appears: 🎤 Listening (red)
  ↓
User speaks: "hello world"
  ↓
Partial text appears: "hello world"
  ↓
User taps Fn again (or silence timeout)
  ↓
Overlay: ⏳ Processing (yellow spinner, "Cleaning with Foundation Models...")
  ↓
After 1–2 seconds: ✅ Done (green, shows "Hello world.")
  ↓
Text pasted to cursor (or last focused app)
  ↓
Overlay fades out
  ↓
Success! 🎉
```

---

### Flow 2: Daily Use (Core Dictation Loop)

**Hotkey → Dictate → Paste (3 seconds, no UI interaction)**

```
User working in Terminal, Slack, email, code editor...
  ↓
Double-tap Fn (anywhere, no focus required)
  ↓
Overlay appears (near cursor): 🎤 Listening (red border)
Raw partials stream in Monaco 13pt
  ↓
User speaks (hands-free)
  ↓
Partial updates live: "speaking into the", "speaking into the api", ...
  ↓
User stops speaking (or single-tap Fn to manually stop)
  ↓
Overlay: ⏳ Processing (yellow, "Cleaning...")
  ↓
1–2 seconds (cleanup runs on Neural Engine)
  ↓
Overlay: ✅ Done (green, shows cleaned text)
"Speaking into the API."
  ↓
Text pasted to cursor
  ↓
Overlay fades out after 600ms
  ↓
User continues typing/working
```

**Zero friction**: No buttons to tap, no confirmations, no manual paste (Cmd+V handled by app).

---

### Flow 3: Review History

**User reviews past dictations, searches, retries.**

```
User clicks "History" in sidebar
  ↓
History pane opens
  ↓
Default view: Today's entries (last 10)
  ↓
User searches: types "API keys" in search box
  ↓
List updates: 2 matches shown (from today, this week)
  ↓
User clicks first match: entry expands
  ↓
Shows:
  - Time: 14:23
  - Raw: "api keys management in production system"
  - Cleaned: "API keys management in production system."
  - Buttons: [Copy Raw], [Copy Cleaned], [Export], [Retry], [Delete]
  ↓
User clicks [Retry] (v1+)
  ↓
Cleanup runs again with current settings (different engine or mode)
  ↓
Shows diff overlay: "Original vs. New"
  ↓
User clicks [Accept] or [Revert]
  ↓
Done
```

---

### Flow 4: Adjust Settings

**User customizes hotkey, language, cleanup mode.**

```
User clicks "Settings" in sidebar
  ↓
Settings modal opens, "General" tab visible (default)
  ↓
User sees: Language picker ([English (US)])
Auto-paste toggle (on), Paste mode (Cmd+V)
  ↓
User clicks "Hotkey & Input" tab
  ↓
Shows: "Current hotkey: Double-tap Fn" + [Change] button (v0.1+)
Streaming mode: [Toggle Off]
Auto-paste: [Toggle On]
  ↓
User clicks "AI Cleanup" tab
  ↓
Shows: Cleanup: [Toggle On], Mode: [Normal] ← dropdown
Tone: [———●———] (slider, center=neutral)
  ↓
User adjusts tone slider to "Formal"
  ↓
Applies immediately (no save button)
  ↓
User closes Settings (click × or press Escape)
  ↓
Next dictation uses new settings
```

**Autosave**: All settings save immediately (toggle, slider, picker). No [Save] button.

---

### Flow 5: View Privacy & Verify Moat

**User checks local-only claims and runs verification.**

```
User clicks "Privacy" in sidebar
  ↓
Privacy pane opens
  ↓
Shows: "🔐 Nothing Leaves Your Device"
  ↓
5 guarantee rows:
  ✅ Microphone: Local
  ✅ Transcripts: Stored Locally
  ✅ Cleanup: On-Device Only
  ✅ Hotkey: Global, Not Tracked
  ✅ Offline: Works 100%
  ↓
User scrolls down
  ↓
[Verify Moat] button (prominent blue)
  ↓
User clicks it
  ↓
Moat audit runs: `make verify-moat`
  ↓
Results appear inline:
  ✅ No cloud egress detected
  ✅ No API keys in binary
  ✅ No telemetry endpoints
  ✅ Local history confirmed (SQLite in ~/Library/Application Support)
  ✅ MIT license verified
  ✅ No third-party closures
  ✅ Offline works (tested with WiFi off)
  ↓
User scrolls to comparison section
  ↓
Wispr Flow (❌ cloud, ❌ login, ❌ word limit) vs. speak (✅ local, ✅ no account, ✅ unlimited)
  ↓
User clicks [GitHub] link
  ↓
Opens repo in browser (source code visible)
  ↓
Trusts speak ✅
```

---

## Part 5: Design Principles (Locked from Research)

### Principle 1: Calm Through Clarity
**Statement**: speak's UI prioritizes calm over flash. Monaco monospace font, ample whitespace, semantic colors, no gradients or animations-for-their-own-sake.

**Applied to**:
- Dashboard and History use Monaco for all content
- Semantic colors only (green=safe, red=alert, yellow=working)
- No animations except state transitions (color fade, panel slide)
- 4pt spacing grid ensures alignment and rhythm

### Principle 2: Privacy is Visible Architecture
**Statement**: Every part of speak's UI shows how data stays local. Privacy pane is first-class, not supplemental.

**Applied to**:
- Dedicated Privacy pane (not buried in Settings)
- 4-guarantee badges with explanations
- Engine attribution in History (shows which model ran)
- No cloud toggles or "sync" buttons
- Offline mode is the only mode

### Principle 3: The Overlay is Read-Only
**Statement**: During dictation, the user should not be forced to make decisions. Overlay streams partial text; all interactions (retry, cleanup, export) happen after, in History or Settings.

**Applied to**:
- Overlay shows: partial text (streaming), state color, elapsed time
- No buttons during capture (except optional gear in v0.1)
- All retries and re-cleaning happen post-capture
- Language quick-switch passive (v0.1+)

### Principle 4: Consistency Serves Learning
**Statement**: Every UI element appears in exactly one way across the app. If cleanup is toggled in Settings, it's toggled the same way in Dashboard.

**Applied to**:
- Design tokens: semantic colors, spacing, icon set (SF Symbols only)
- State colors: red (error), yellow (processing), green (done), blue (raw)
- Toggle appearance: never mix checkboxes and switches
- Terminology: always "cleanup" (not "cleaning," "editing," "enhancing")

### Principle 5: Power Users Get Depth Without Overwhelm
**Statement**: Core hotkey → overlay → paste works on day one with zero configuration. Power users discover transforms, per-app context, custom engines without those features blocking casual use.

**Applied to**:
- Day-one: hotkey start/stop, raw transcript, paste
- Week-one: cleanup toggle, history search, language
- Month-one: per-app context, style samples, custom engine (v0.1+)
- Season-one: transforms, code mode, quiet mode (v1+)

---

## Part 6: Implementation Sequencing

**Critical path** (what to build first, in order):

### Phase 1: Foundation (App Shell)
1. **NavigationState** (@Observable enum: dashboard, history, settings, privacy, about)
2. **SidebarView** (persistent sidebar with 5 pane buttons)
3. **AppShell** (main window with sidebar + content pane)

### Phase 2: Panes (Can Parallelize)
4. **DashboardView** (home pane: hotkey status, stats, recent dictations)
5. **HistoryView** (searchable list, expandable entries, metadata)
6. **SettingsView** (6-tab TabView with all controls)
7. **PrivacyPaneView** (4-guarantee badges, verify button, comparison)
8. **AboutView** (version, links, license)

### Phase 3: Overlay & Integration
9. **OverlayHUD** (floating panel, state colors, partial text streaming)
10. **Wire to SpeakEngine** (listening/processing/done states)
11. **Wire to SettingsStore** (language, streaming, cleanup mode)

### Phase 4: Testing & Verification
12. **Integration tests** (pane switching, settings persistence)
13. **Live verification** (visual appearance, hotkey responsiveness, paste to 3+ apps)

**Dependencies**:
- Phase 1 has no dependencies (greenfield)
- Phase 2 depends on Phase 1 only
- Phase 3 depends on Phases 1–2
- Phase 4 depends on all above

**Parallelization**:
- Phase 2 panes can be built in parallel (assign to different builders)
- Phase 3 can start once DashboardView is stable (wiring to engine)

---

## Part 7: File Structure

**New files to create** (or modify if exist):

```
App/
  Navigation/
    NavigationState.swift          ← @Observable enum: Pane selection
    SidebarView.swift              ← Persistent sidebar (5 buttons)
  AppShell/
    MainWindowView.swift           ← Window with sidebar + content pane
  Dashboard/
    DashboardView.swift            ← Pane container
    Panes/
      DashboardHomeView.swift      ← Stats, hotkey status, recent dictations
      HistoryView.swift            ← Searchable history list + expand
      SettingsView.swift           ← 6-tab settings
      PrivacyPaneView.swift        ← 4-guarantee badges + verify button
      AboutView.swift              ← Version, links, license
  Overlay/
    OverlayHUD.swift               ← Floating panel (colors, partial text, states)
  Theme/
    Colors.swift                   ← Semantic color tokens (update if needed)
    Typography.swift               ← Monaco font sizes (already exists, verify)
    Spacing.swift                  ← 4pt grid tokens (new if needed)
    Icons.swift                    ← SF Symbol definitions (optional enum)
```

**Integration points** (wire to existing code):
- `NavigationState` → `DictationController` (state machine)
- `OverlayHUD` → `SpeakEngine` (audio, STT, cleanup states)
- `SettingsView` → `SettingsStore` (persistence)
- `HistoryView` → `HistoryStore` (search, export, metadata)

---

## Part 8: Evolution Path (v0.1 & v1, No Redesign Needed)

### v0.1 (Pluggable, Language, Agent Mode)
- **Overlay**: add language pill + engine attribution badge
- **Settings**: add STT engine picker (WhisperKit v0.1)
- **Settings**: add Cleanup engine selector (Ollama)
- **Dashboard**: add Insights tab (word count chart, WPM)
- **Privacy**: add compliance export button (v3+)

**Design remains unchanged**: Same sidebar, same tabs, same colors, same layout.

### v1 (Polish, Transforms, Per-app Context)
- **Sidebar**: add Transforms pane (Rewrite, Summarize, Polish)
- **Settings**: add Style tab (writing samples, v1+)
- **Settings**: add Per-app Context section (code editor mode, email mode)
- **Dashboard**: add [Retry] button in history (re-run cleanup)
- **History**: add daily/weekly view toggle

**Design remains stable**: No sidebar reorganization, no color changes, no navigation overhaul. Additive features only.

### v2 (Platform Expansion)
- **iOS app**: gesture-driven UI, Dynamic Island activity
- **Privacy tab**: add iCloud sync toggle (opt-in, clearly labeled)

---

## Part 9: Design Review Checkpoints

Before shipping each phase, verify:

### Consistency Audit
- [ ] Every state color (red/yellow/green) appears the same in menubar, overlay, dashboard, settings
- [ ] Font sizes match spec (Monaco 13pt for body, system 15pt for headings)
- [ ] Spacing follows 4pt grid (no random padding)
- [ ] Icons are SF Symbols only (no custom graphics)

### Progressive Disclosure Audit
- [ ] Each Settings tab has common controls first, advanced below divider
- [ ] Dashboard Home shows only top-5 recent dictations (link to full History)
- [ ] Power user features (engine picker, custom hotkey) in Settings, not Dashboard
- [ ] Overlay is zero-interactive during capture (all interactions post-capture)

### Privacy Audit
- [ ] No account creation, login, or API key input (except optional Ollama in v0.1+)
- [ ] No cloud toggles or "sync" buttons
- [ ] Privacy pane is visually prominent (first click after Dashboard)
- [ ] Verify button works, shows moat pass/fail

### Accessibility Audit
- [ ] Keyboard navigation: Tab through all controls
- [ ] VoiceOver: semantic labeling on buttons, toggles, lists
- [ ] Color contrast: all text ≥ 4.5:1 (WCAG AA)
- [ ] Font size: body text 13pt+ (readable)
- [ ] No motion sickness: animations smooth, optional

### Live Dogfood
- [ ] Real user test: can first-time user dictate without changing settings?
- [ ] Success rate: ≥ 95% of users get working dictation on first try
- [ ] Hotkey reliability: < 1 false trigger per 30 minutes
- [ ] Paste compatibility: tested in ≥ 3 app categories (Terminal, Slack, email, code editor)
- [ ] Latency: stop → paste < 2.0s (with cleanup)

---

## Part 10: Design Decisions Log

| Decision | Rationale | Trade-off |
|----------|-----------|-----------|
| Sidebar nav (not tabs) | Proven UX (Wispr, Slack), scales to v0.1/v1, discoverable | Wider min-width (760pt) |
| 5 panes (not 8 in sidebar) | v0 is core only; Dashboard, History, Settings, Privacy, About | Insight/Dictionary/Snippets/Style/Transforms deferred to v0.1+ |
| 6 settings tabs (not sections) | Clearer organization, easier to find | More modal surface area |
| Dedicated Privacy pane | speak's moat, builds trust, visible immediately | Adds to sidebar navigation |
| Monaco font (not system) | User locked decision, calm clarity, monospace is readable | Monospace is compact, less traditional |
| Semantic colors (not custom) | System-aligned, accessible, consistent, automatic dark mode | Limited aesthetic customization |
| Overlay is read-only | Non-intrusive, zero friction during capture | Limited visual feedback during recording |
| Menubar icon no menu | Hotkey is core; menu is secondary (use Dashboard for discovery) | Less discoverable than menubar menu |
| No "advanced mode" toggle | Progressive disclosure in Settings tabs (dividers) is clearer | Requires explaining divider to users |

---

## Conclusion: Design Philosophy in Action

**speak is built on these locked truths:**

1. **Privacy is architecture, not marketing** — The moat (100% local, free, open, no account) is coded into every system boundary. The UI should make this obvious (Privacy pane, badges, verify button).

2. **Voice dictation is ambient** — The best UX is one where the user speaks, the app listens silently, and the text appears where needed. The app fades out; it doesn't demand attention.

3. **Defaults matter more than options** — speak ships with uncontroversial defaults (hotkey, language, cleanup on, paste mode). Most users never change them. Options exist for power users, but they're secondary.

4. **Clarity beats polish** — Monaco fonts, semantic colors, ample whitespace matter more than gradients and animations. The user should understand what speak is doing, not feel dazzled.

5. **Consistency is a feature** — Every part of the app (menubar, overlay, dashboard, settings) behaves the same way. This makes the app predictable and trustworthy.

**When any design decision is needed, return to these 5 truths. They're the why; the design principles and component specs above are the how.**

---

## Appendix: Quick Reference

### Color States at a Glance
- 🔘 **Idle**: systemGray (waiting)
- 🔴 **Listening**: systemRed (active, pulsing)
- 🟡 **Processing**: systemYellow (working, spinner)
- 🟢 **Done**: systemGreen (success, pasting)
- ❌ **Error**: systemRed (problem, explanation text)

### Sidebar Panes
1. 🏠 Dashboard (home, stats, recent)
2. 📋 History (searchable archive)
3. ⚙️ Settings (6 tabs: General, Transcription, AI Cleanup, Hotkey, Privacy, About)
4. 🔐 Privacy (trust architecture, verify button)
5. ℹ️ About (version, links, license)

### Key Interactions
- **Dictate**: Double-tap Fn → speak → single-tap Fn (or silence) → paste
- **Review**: Click History → search → expand entry → see raw vs. cleaned
- **Configure**: Click Settings → pick tab → adjust controls (autosave) → close
- **Verify**: Click Privacy → click [Verify Moat] → see pass/fail results

### Files Changed
- `App/Navigation/NavigationState.swift` (new)
- `App/SidebarView.swift` (new)
- `App/Dashboard/*.swift` (panes, new)
- `App/Overlay/OverlayHUD.swift` (refine colors/states)
- `App/Theme/Colors.swift` (verify tokens)

---

**Design complete and locked. Ready for implementation.**

**Last updated**: 2026-06-28 by Orchestrator  
**Next phase**: P13 Dogfood (live verification)  
**Ship gate**: MATCH + BEAT + quality.md §9 all pass
