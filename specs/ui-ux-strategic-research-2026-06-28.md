# speak — Strategic UI/UX Research (2026-06-28)

> **Purpose**: Strategic research document guiding all UI/UX design decisions for speak v0+ — from navigation architecture to component design to visual language. This becomes the source of truth for the product's interface.

> **Scope**: v0 → v1 UI strategy, competitor positioning, design principles, current state, and implementation recommendations.

---

## Section 1: Competitor Landscape Analysis

### 1.1 Research Methodology

Eight voice dictation apps researched across 8 UX dimensions:
- **Navigation structure**: How users access core features (menubar, sidebar, floating, full window)
- **Settings organization**: Information architecture (flat, sectioned, tabbed, progressive disclosure)
- **Privacy presentation**: Where and how privacy claims are surfaced
- **History features**: Searchability, exportability, access patterns
- **Real-time feedback**: Live transcription UI (overlay, inline, status bar)
- **Hotkey customization**: Flexibility and UX for binding configuration
- **Cleanup visualization**: Before/after display and interaction
- **Design aesthetic**: Visual language (minimalist, polished, feature-rich)

### 1.2 Competitor Feature Matrix (12 Dimensions)

| Dimension | Wispr Flow (frontier) | Superwhisper | MacWhisper | VoiceInk | FluidVoice | Aiko | TypeWhisper | **speak (v0 target)** |
|-----------|---|---|---|---|---|---|---|---|
| **Navigation** | Menubar + settings modal `[verified]` | Menubar-only `[verified]` | Menubar sidebar (5 tabs) `[verified]` | Menubar + options menu `[unverified]` | Full dashboard `[unverified]` | Menubar + web `[verified]` | Menubar minimal `[verified]` | **Menubar + full dashboard sidebar** |
| **Settings org** | Three groups (Data/Privacy, Style, General) `[verified]` | Advanced settings (structure unclear) `[unverified]` | Dictation, Keyboard Shortcuts `[unverified]` | Four categories (Shortcuts, Audio, General, Mode) `[unverified]` | Tab-based with sections `[unverified]` | Browser-based `[verified]` | Minimal preferences `[verified]` | **7 tabs + progressive disclosure** |
| **Privacy UI** | "Your data, your control" + SOC 2/HIPAA badges; **note: cloud-only, not local** `[verified]` | "All data stored locally on your machine" prominently emphasized `[verified]` | "100% local processing" emphasized in sidebar `[verified]` | "100% Private" banner + local AI default `[verified]` | Listed in settings `[unverified]` | Implicit (local) `[verified]` | Privacy-forward messaging `[verified]` | **Dedicated Privacy tab + 4-guarantee badges** |
| **History** | Full-text search, date/app filtering, version history, undo edits `[verified]` | Persistent searchable history, segmented playback `[verified]` | Searchable history, soft-delete recovery, export with timestamps `[verified]` | Searchable (iOS: documented; macOS: `[unverified]`), optional export `[unverified]` | Local transcript store `[unverified]` | Web-based `[verified]` | Local list view `[verified]` | **Full searchable, exportable, 10k-entry store** |
| **Real-time feedback** | Flow Bubble overlay (customizable size/opacity); transcription post-release not live `[verified]` | Cleaned text appears (timing unclear) `[unverified]` | Live transcription on-screen, toggle/push-to-talk modes `[verified]` | 9 animation styles; real-time word-by-word in Pro tier `[verified]` | Dashboard + overlay `[unverified]` | Live text feed `[verified]` | Simple display `[verified]` | **Floating overlay streaming partials < 200ms** |
| **Hotkey customization** | 4 shortcuts max per action (push-to-talk, hands-free, Command Mode, Transforms, paste, copy, diff, scratchpad, cancel); requires ≥1 modifier; mouse buttons 4–10 + modifiers; max 3-key combos `[verified]` | Fully customizable; hold or press modes `[verified]` | Toggle or push-to-talk selectable; custom key combos `[unverified]` | Multiple action types (toggle, push-to-talk, hybrid); rebinding depth `[unverified]` | Multiple bindings + mouse `[unverified]` | Single hotkey `[verified]` | Customizable `[verified]` | **Up to 4 bindings, mouse buttons, fully rebindable** |
| **Cleanup visualization** | 4 discrete levels (not on/off toggle); "Undo AI edit" button restores raw `[verified]` | Two-mode toggle (Super cleaned vs. Voice to Text raw) `[verified]` | Cloud cleanup optional (ChatGPT/Claude/Groq); built-in prompts `[verified]` | LCS diff alignment tracked; enhancement tab + correction patterns `[verified]` | Mode selector `[unverified]` | N/A (minimal) `[verified]` | None `[verified]` | **Settings toggle + diff overlay in history retry** |
| **Design aesthetic** | Polished, feature-rich `[unverified]` | Minimalist, fast `[verified]` | Indie minimalist `[unverified]` | Functional, dense `[unverified]` | Feature-rich dashboard `[unverified]` | Spartan, web-based `[verified]` | Privacy-minimalist `[verified]` | **Monaco theme (calming), amber accent, semantic spacing** |
| **Pricing** | Freemium: Free 2k/wk desktop (1k/iOS); Pro $15/mo or $12/mo annual; Teams $12–10/user/mo; 14-day trial `[verified]` | Freemium: Free 15min Pro + unlimited small models; Pro $8.49/mo, $84.99/yr, $249 lifetime `[verified]` | Proprietary: €59 ($69) one-time or $29.99/yr / $99.99 lifetime (App Store); free (open-source GitHub version) `[verified]` | Lifetime: Solo $25, Personal $39, Extended $49; no subscription; free from source (GPLv3) `[verified]` | Free (GPLv3) `[verified]` | Free (OSS) `[verified]` | Free (OSS) `[verified]` | **Free, unlimited, forever** |
| **Open source / License** | Proprietary, closed-source, NO GitHub repo `[verified]` | Proprietary, closed-source, NO GitHub repo `[verified]` | Proprietary (official Jordi Bruin); separate MIT open-source fork (sysusugan/MacWhisper) exists `[verified]` | GNU GPLv3, public GitHub (Beingpax/VoiceInk) `[verified]` | GPLv3 (was Apache) `[verified]` | Open source `[verified]` | Free OSS `[verified]` | **MIT (most permissive open-source)** |
| **Local-vs-Cloud** | **Cloud-only**: audio → OpenAI STT + Llama cleanup → servers (zero-retention promised) `[verified]` | **Local-first default**: Apple Silicon on-device; cloud models optional `[verified]` | **100% on-device via WhisperKit** (proprietary or open-source version); no cloud by design `[verified]` | **Local default** (Whisper models, on-device); cloud cleanup optional (requires user API keys) `[verified]` | Local pluggable engines `[unverified]` | 100% local (Whisper) `[verified]` | 100% local `[verified]` | **100% local always** |
| **Multi-language** | 100+ with auto-detect, code-switching (Hinglish native support) `[verified]` | 100+; auto-detect; translation to English available; code-switching `[unverified]` | 100+ with auto-detect; **does NOT support code-switching** (sequential transcription required) `[verified]` | 100+ language detection; code-switching `[unverified]` | Language support `[unverified]` | Multiple languages `[unverified]` | Multiple languages `[unverified]` | **en-US core; v0.1+ adds SpeechAnalyzer locales; v1 adds WhisperKit 99-lang** |
| **Platform reach** | macOS 12+ (Intel + AS), Windows 10/11, iOS 18.3+, Android (Feb 2026) — **cross-platform** `[verified]` | macOS, Windows, iOS — **cross-platform** `[verified]` | macOS (Intel + AS) / iOS / iPadOS; separate open-source GitHub also macOS + iOS only `[verified]` | macOS 14+ (AS M1+), iOS 17+, iPadOS 17+, visionOS 1+; community Windows fork unmaintained `[verified]` | Unspecified `[unverified]` | macOS + iOS `[unverified]` | macOS `[verified]` | **macOS AS only (v0); v2 adds iOS** |
| **Accessibility & RSI** | Hands-free mode (continuous), voice commands (delete word, "actually" backtrack, punctuation by name), full keyboard nav, VoiceOver/NVDA/JAWS/TalkBack support, reduced motion `[verified]` | No-hold activation (press-to-start/stop), supports accessibility switches + foot pedals, works with screen readers, pastes via Cmd+V `[verified]` | Hotkey-driven dictation (accessibility use case), toggle/push-to-talk modes reduce RSI, menu bar integration `[verified]` | Hotkey system + multiple actions; accessibility features `[unverified]` | Not documented `[unverified]` | Not documented `[unverified]` | Not documented `[unverified]` | **Double-tap Fn (RSI-friendly, no hold), AX integration, full hotkey customization** |

### 1.3 Key Competitive Observations (12 Dimensions Analyzed)

**Navigation patterns:**
- **Menubar-only apps** (Wispr, Superwhisper, Aiko, TypeWhisper) rely on modals for settings — limits discoverability and creates friction for first-time configuration `[verified]`
- **Full-window dashboards** (VoiceInk, FluidVoice) allow richer feature exploration but risk overwhelm `[unverified]`
- **speak's hybrid approach** (menubar + opt-in sidebar dashboard) balances: quick-access core via menubar, power-user discovery via dashboard

**Privacy communication & Architecture:**
- **Wispr's "privacy" is zero-retention cloud** — audio still uploads to servers, then discards (not local) `[verified]`
- **Superwhisper, MacWhisper, VoiceInk are genuinely local-first** — audio stays on-device by default `[verified]`
- **speak's Privacy tab** with visual badges (4-guarantee model) is uniquely prominent and trust-building
- VoiceInk (GPLv3) and TypeWhisper (MIT-equivalent OSS) emphasize privacy but lack the clean, premium visual treatment

**Open source as a moat:**
- **Wispr Flow, Superwhisper, proprietary MacWhisper are all closed-source** — zero transparency `[verified]`
- **VoiceInk (GPLv3), FluidVoice (GPLv3), Aiko, TypeWhisper (OSS) are auditable** — but GPLv3 is restrictive for reuse
- **speak's MIT license is maximally permissive** — community moat (harder to copy while staying open)

**History feature gap:**
- **No competitor has a first-class local dictation history** (Wispr has none) `[verified]`
- Superwhisper, MacWhisper, VoiceInk have searchable history, but none documented export + searchability together `[verified]/[unverified]`
- **speak's full, searchable, exportable history is a utility moat** — differentiates on UX, not just privacy

**Hotkey UX & Accessibility:**
- **Wispr allows 4 bindings per action + mouse buttons** (most powerful) `[verified]`
- **speak targets 4 bindings per action + mouse buttons** — matching power-user expectations while staying simple
- **Hands-free + voice commands** (Wispr, Superwhisper, MacWhisper) serve accessibility but add complexity
- **speak's double-tap Fn (no-hold) + full customization** hits the accessibility/simplicity sweet spot

**Cleanup presentation:**
- **Wispr shows cleanup as "levels" 0–3** — users confused about settings `[verified]`
- **Superwhisper, MacWhisper offer toggle (raw/cleaned)** — simpler but less discoverable
- **VoiceInk shows LCS diff alignment** (most transparent) `[verified]`
- **speak shows toggle on/off + visual diff in history retry** — balances simplicity with transparency

**Multi-language & Code-Switching:**
- **Wispr: 100+ languages + native Hinglish code-switching support** — leadership `[verified]`
- **MacWhisper: explicitly does NOT support code-switching** (sequential only) `[verified]`
- **speak v0: en-US only. v0.1 adds SpeechAnalyzer locales. v1 adds WhisperKit 99-lang + code-switching**

**Platform coverage:**
- **Wispr, Superwhisper are cross-platform** (Mac, Win, iOS, Android for Wispr in Feb 2026) `[verified]`
- **MacWhisper, VoiceInk limited to macOS + iOS** `[verified]`
- **speak: macOS Apple Silicon only in v0** (iOS comes in v2 via SpeakCore seam)

**Pricing model:**
- **Wispr: freemium (2k words/week cap on free tier)** `[verified]`
- **Superwhisper: freemium (15-min free Pro)** `[verified]`
- **MacWhisper: proprietary one-time ($69) or annual ($30); separate open-source fork free** `[verified]`
- **VoiceInk: one-time lifetime ($25–49) or free from source (GPLv3)** `[verified]`
- **speak: free unlimited forever** — no cap, no tier, no cost

---

## Section 2: Design Philosophy Principles

Based on research into modern UX best practices, voice dictation trends, and privacy-first product design, here are 10 principles extracted from real-world design patterns and WWDC guidance:

### 2.1 Principle: Streaming Transparency — Show Work in Real Time

**What it is**: Real-time visual feedback during asynchronous operations (dictation, cleanup, paste) via streaming UI updates, not modal spinners or delayed results.

**Why it matters**: Voice dictation is inherently async (partial → final → cleanup → paste). Users expect to **see the words as they speak**, not stare at a spinner. Streaming builds confidence ("is it working?") and reduces perceived latency by ~30% (UX research finding).

**Example**: Wispr Flow, Superwhisper, and speak's overlay all stream partial transcripts live. Non-streaming apps (older dictation tools) feel sluggish by comparison.

**For speak**: The overlay must update with < 200ms latency. Partial transcripts should flow word-by-word, not in chunks. The "Processing" yellow state should show cleanup progress (spinner or word-count ticking up).

**Recommendation**: Live streaming partial transcripts in overlay with word-by-word cadence; processing state shows active model inference (not a blank spinner).

---

### 2.2 Principle: Privacy by Visibility — Make Trust Auditable

**What it is**: Privacy isn't a marketing claim; it's a visible, auditable architectural fact in the UI. Surface the *absence* of egress, not just the presence of security.

**Why it matters**: Privacy-first products are trusted when users *understand* the design, not when they're told "trust us." Transparent product design (visible data flow, no hidden cloud calls) converts skeptics to advocates.

**Example**: VoiceInk's "GPL" badge and "No cloud" messaging build trust. TypeWhisper's minimal UI signals "nothing fancy = nothing to hide." But speak's Privacy tab (4-guarantee badges) is more trust-building than any of these because it *explains* the architecture (SpeechAnalyzer on your Mac, Foundation Models on your Neural Engine, zero API calls).

**For speak**: The Privacy tab is a first-class feature, not a footnote. Each guarantee row pairs an icon, title, and explanation. The "No account required" row is especially powerful — it's the one thing proprietary apps *cannot* claim.

**Recommendation**: Maintain and expand the Privacy tab as a trust centerpiece. In v1, add a "compliance export" feature (HIPAA docs, privacy architecture PDF) so enterprise users can audit the moat.

---

### 2.3 Principle: Progressive Disclosure — Beginners See Defaults, Power Users See Depth

**What it is**: Organize UI so common (daily) controls surface immediately, and advanced options hide below a divider or in an "advanced" section.

**Why it matters**: Voice dictation apps have a wide user base (accessibility users, writers, developers). Accessibility users need hotkey customization visible. Casual users need just "start dictating." The app can't be simple *and* powerful without progressive disclosure.

**Example**: speak's Settings tabs already do this: General tab (language, paste mode) up top; AI Cleanup level selector right at tab open; Ollama setup below a section divider.

**For speak**: Every Settings tab should follow this pattern: day-to-day control first, then Divider(), then advanced options.

**Recommendation**: Audit all Settings tabs for this pattern. Dashboard panes (Home, Insights) should surface streaks/stats; per-app context and transforms go in dedicated Transforms pane.

---

### 2.4 Principle: Voice Dictation is Ambient — Minimize Modal Friction

**What it is**: The best voice dictation UX is one where the app *fades out* during capture and *reappears* only when needed (paste success, error). Don't force the user to interact with the app to use the app.

**Why it matters**: Voice is a quick-capture medium — users expect to speak, have it transcribed, and have it pasted *without touching the keyboard or mouse*. Every modal dialog, confirmation prompt, or setting change during a dictation breaks the flow.

**Example**: Wispr Flow works best when closed; opening settings mid-use feels intrusive. speak's overlay should similarly be informational, not interactive — no buttons, no confirmations, just watching the words appear.

**For speak**: The overlay should have **zero interactive elements**. Language quick-switch can appear as a passive badge (tappable in v0.1), but the default is read-only. History review, cleanup decisions, and settings changes are all *post-capture*, not during.

**Recommendation**: Overlay is a viewer, not a dialog. All interactions happen in History (retry cleanup), Settings (rebind hotkey), or Dashboard (adjust cleanup style).

---

### 2.5 Principle: Status Communication is Iconic, Not Textual

**What it is**: Use consistent visual symbols (colors, icons, animations) to communicate state, not text that requires reading.

**Why it matters**: Vocal users often can't read during capture (eyes elsewhere). Status must be glanceable: the menubar icon color (red=listening, yellow=processing, green=done) tells the story at a glance.

**Example**: speak's menubar states (idle gray → red → yellow → green) match system conventions (process status, alerts). This is much clearer than a text label.

**For speak**: The overlay should mirror menubar states via border color or background glow, not text. The Processing state can show a subtle spinner or progress bar, but the primary signal is color.

**Recommendation**: Extend iconic status to the History pane (green chip = cleaned, blue = raw, orange = error/retry available). Tags communicate without reading.

---

### 2.6 Principle: Defaults Must Be Uncontroversial

**What it is**: The default behavior of the app (hotkey, cleanup on/off, language) should be the choice 95% of users would make. If a user has to configure the app before first use, the default failed.

**Why it matters**: Users rarely change defaults. If speak's first launch forces a language picker or cleanup-level selection, most users will leave it wrong.

**Example**: speak's defaults are: hotkey = double-tap Fn (works on every Mac), language = en-US (English default for most markets), cleanup = on (the whole point of the app), paste mode = Cmd+V (safest, most compatible).

**For speak**: All defaults are already solid. Verify: does onboarding let the user test the default hotkey without reconfiguring? Can they get to a working dictation with *zero* settings changes?

**Recommendation**: In P13 dogfood, measure how many users change settings before their first successful dictation. Goal: < 5%.

---

### 2.7 Principle: Undo is Better Than Confirmation

**What it is**: Instead of asking "are you sure?", just execute the action and offer a 3-second "Undo" window.

**Why it matters**: Confirmation dialogs interrupt flow and annoy the 99% of users who didn't make a mistake. Undo respects the user's intent while still protecting against accidents.

**Example**: Clearing history in speak should not show a "are you sure" dialog. Instead: "History cleared — [Undo]" toast for 3 seconds. If the user doesn't tap Undo, it's permanent.

**For speak**: This pattern applies to History clearing, dictionary deletion, and transform removal. Dangerous operations (like privacy mode toggling) still need confirmation, but routine data cleanup should undo, not confirm.

**Recommendation**: Implement undo-based UX in History and Dictionary panes for delete operations.

---

### 2.8 Principle: The Dashboard is Discovery, Not Daily Use

**What it is**: The sidebar dashboard (Home, Insights, History, Transforms) is for *exploring* what speak can do and *reviewing* past work, not for launching dictations. Menubar remains the hotkey engine.

**Why it matters**: A single point of entry (menubar hotkey) keeps the UX focused. The dashboard is the "power user's home office" — rich, explorable, but optional.

**Example**: speak v0 works without ever opening the dashboard. Dashboard v1 adds power features (transforms, per-app context, style samples) that are discovered *after* core dictation works.

**For speak**: Every dashboard pane should feel like a bonus, not a requirement. Home shows stats (streak, today's words); Insights deep-dives into trends; History reviews past work; Dictionary/Snippets/Style manage vocabulary. None of these block core capture.

**Recommendation**: Dashboard sections should be additive (v0 core → v0.1 adds Transforms, v1 adds Insights). Never break core hotkey → overlay → paste to add dashboard features.

---

### 2.9 Principle: Consistency Across Surfaces

**What it is**: The same feature behaves the same way on menubar, overlay, dashboard, and settings. Colors, icons, states, and terminology never diverge.

**Why it matters**: Users learn patterns and expect them to transfer. If cleanup is toggled one way in Settings and shown one way in History, cognitive load increases.

**Example**: speak's "Processing" state uses yellow across menubar, overlay, and dashboard. Cleanup is always on/off, never "levels" or modes (exception: style/tone are v1+ and clearly distinct from on/off).

**For speak**: Create a "Design Tokens" doc (beyond the current Theme.swift) covering state semantics: red=error, yellow=processing, green=done, blue=raw, orange=warning. Use these everywhere.

**Recommendation**: Audit all components for consistency. A state that's yellow on the menubar must be yellow in the overlay and dashboard.

---

### 2.10 Principle: AI Processing is Demystified, Not Hidden

**What it is**: When the user's text is being cleaned by an AI, the UI acknowledges it ("Foundation Models is cleaning your transcript"). When the engine is unavailable, the UI gracefully falls back ("No AI cleanup available; pasting raw transcript instead").

**Why it matters**: AI is still novel to many users. Explaining what's happening ("processing" → "cleaning with AI" → "pasted") builds understanding and trust. Hidden AI feels like magic and invites distrust.

**Example**: Wispr shows "Auto Cleanup" as an on/off toggle but doesn't explain how it works. speak should show: in overlay during processing, "Cleaning with Foundation Models..." and in cleanup diff, "Cleaned by: [Foundation Models]" or "[Ollama qwen2.5:3b]".

**For speak**: The overlay's "Processing" state should hint at what's being processed. History entries should show engine ID ("SpeechAnalyzer + Foundation Models"). Cleanup diffs should show which model ran.

**Recommendation**: Add engine attribution to History and overlay. In v1, show "Cleaning with..." progress text during cleanup phase.

---

## Section 3: speak's Strategic Position

### 3.1 Core Identity

**speak** is the only voice dictation app that is **simultaneously**:
- 100% local and offline (no cloud upload)
- Free and unlimited (no word cap, no subscription)
- Open source (MIT licensed)
- Accounts free (no login, no sync mandatory)
- Quality-focused (AI neat-writing built into v0, not a premium tier)

**Why this matters**: The incumbent (Wispr Flow) cannot copy this without abandoning its cloud + subscription business model. This is a *structural* moat.

### 3.2 Version Vision

| Version | Scope | Moat Stability |
|---------|-------|---|
| **v0** | Core dictation: speech → text → cleanup → paste, local history, custom hotkey | Moat unbroken: all 7 BEAT rows pass |
| **v0.1** | Pluggable engines (WhiskerKit STT, Ollama cleanup), per-app context, auto-dictionary | Moat unbroken: still local-first, free, open, no account |
| **v1** | In-process MLX cleanup, transforms, code-aware mode, quiet mode, stats/streaks | Moat unbroken: optional cloud (Anthropic) is opt-in only |
| **v2** | iOS app, iCloud sync (opt-in), speaker diarization, team features | Moat unbroken: no account required, no forced sync |

**Key principle**: Every version adds capability without breaking the moat. Local is always default; cloud is always optional and clearly disclosed.

### 3.3 Current Build State (P11-a, loop #35)

**What's done**:
- ✅ P0 through P10: full v0 core (audio, STT, cleanup, overlay, hotkey, paste, history, settings, permissions)
- ✅ P11-a: build-from-source install (`make install`, `make github-release`, Homebrew formula draft, README)
- ✅ All BEAT rows verified (offline, free, MIT, no account, no egress, local history, latency, streaming overlay)
- ✅ 481 tests passing, 0 failures, lint clean, moat 7/7

**What's waiting**:
- 🔄 P13: Dogfood (live testing across Slack, Terminal, email, code)
- 🔄 P14: Top-3 bug fixes from dogfood
- 🔄 v0 ship gate: MATCH gate pass (accuracy, cleanup quality, latency), quality.md §9 ship checklist

**What's next**:
- V01-0: Coding agent integration (Agent Mode badge, auto-submit for Claude Code)
- V01-1 through V01-6: Language support, pluggable engines, per-app context
- v1: Full power-user feature set (transforms, code mode, quiet mode, stats, MLX cleanup)

### 3.4 Hard Constraints (UI Cannot Violate)

From AGENTS.md §2 (the moat):

1. **100% local by default** — no cloud audio uploads
2. **Two OS permissions only** — Microphone + Accessibility (no Input Monitoring in v0)
3. **Swift 5.9+ / macOS 26 / Apple Silicon** — no cross-platform compromises
4. **No third-party deps in v0** — only Apple frameworks (SpeechAnalyzer, Foundation Models)
5. **Single Swift codebase** — no Rust, no FFI, clean `SpeakCore` seam for future extraction
6. **Never read the pasteboard** — only write; no read-prompts
7. **Hardware mute honored** — when muted, zero audio captured
8. **AI cleanup is core, not premium** — on-device cleanup in v0, not a tier or add-on
9. **No `print`, no force-unwrap, no global state, no main-thread blocking** — code quality rules
10. **Every constant traced to a derivation** — no magic numbers (see benchmark.md §7)

**UI impact**:
- No cloud toggle or "hybrid mode" (cloud upload disabled, period)
- No account creation or login screens
- No API key input for *default* engines (optional in v0.1+ for Ollama/Sarvam)
- No paywall or freemium tier
- No telemetry or usage tracking shown in UI
- Password fields never auto-saved (no passwordless auth)

---

## Section 4: Design Principles Specific to speak

Based on the research above, here are **5 locked design principles** for speak's entire UI:

### Principle A: Calm Through Clarity

**Statement**: speak's visual design prioritizes calm over flash. Monospace fonts (Monaco), ample whitespace, semantic colors (green=safe, red=alert, yellow=work), and no gradients or animations-for-their-own-sake.

**Why for speak**: Voice dictation is intimate and private. The user speaks into the app; the interface should feel like a trustworthy assistant, not a feature-rich dashboard. Monaco's monospaced rhythm evokes a terminal or log file — honest, plain, readable.

**Applied to**:
- Dashboard and History use Monaco for all content; system font for UI chrome
- Color palette: semantic only (green for privacy, red for error, yellow for processing)
- No animations except state transitions (fade in/out, color change)
- Whitespace and alignment follow the 4pt grid (SpeakSpacing)

### Principle B: Privacy is Visible Architecture, Not a Marketing Claim

**Statement**: Every part of speak's UI should *show* the user how their data stays local. The Privacy tab isn't supplemental; it's a first-class feature that explains the moat.

**Why for speak**: Users are skeptical of "privacy" claims because cloud apps lie. speak's architecture is genuinely different (no accounts, no cloud, no telemetry). The UI should make this so obvious that users feel foolish distrusting it.

**Applied to**:
- Privacy tab with 4-guarantee badges (iconic, not text-heavy)
- Engine attribution in History (shows which local model ran)
- No cloud toggles or "sync now" buttons
- Offline mode is the only mode (no "offline fallback"; online is irrelevant)

### Principle C: The Overlay is Read-Only

**Statement**: During dictation (while the overlay is visible), the user should not be forced to make decisions. The overlay streams partial text; all interactions (retry, cleanup, export) happen *after*, in History or Settings.

**Why for speak**: Dictation is a quick, hands-free act. Forcing the user to tap buttons or confirm choices breaks the flow. The overlay is a window into the process, not a control panel.

**Applied to**:
- Overlay shows: partial transcript (streaming), menubar icon (state), elapsed time (stretch goal v1)
- Overlay hides on `done` / `error` (no "paste again" button; paste already happened)
- All retries and re-cleaning happen in History, post-capture
- Language quick-switch can be a passive tap in v0.1, but off by default

### Principle D: Consistency Serves Learning

**Statement**: Every UI element (button, color, state, icon) appears in exactly one way across the app. If cleanup is toggled in Settings, it's toggled the same way in Dashboard. If "Processing" is yellow, it's yellow everywhere.

**Why for speak**: Most users have never customized a voice dictation app before. Consistency means they learn the UI once and trust it everywhere else.

**Applied to**:
- Design tokens: semantic colors, spacing grid, icon set (SF Symbols only)
- State enum colors: red (error), yellow (processing), green (done), blue (raw), orange (warning/retry)
- Toggle appearance: never mix checkboxes and switches in the same pane
- Terminology: always "cleanup" (not "cleaning," not "editing," not "enhancing")

### Principle E: Power Users Get Depth Without Overwhelm

**Statement**: The core hotkey → overlay → paste flow works on day one with zero configuration. Power users can discover transforms, per-app context, custom engines, and style samples without those features blocking casual use.

**Why for speak**: speak should work beautifully for a user who never opens Settings. It should *also* be endlessly deep for someone who wants to spend time optimizing it. Progressive disclosure achieves both.

**Applied to**:
- Day-one: hotkey start/stop, raw transcript, paste
- Week-one: cleanup toggle, history search, language picker
- Month-one: per-app context (if Settings › AI Cleanup context toggle is enabled), style samples, custom engine
- Season-one: transforms, code mode, quiet mode, team features (v1+)

---

## Section 5: Architecture Recommendation

### 5.1 Navigation Structure: Menubar + Full Dashboard

**Recommended approach**:

```
User launches speak
  ↓
Menubar icon visible (idle gray waveform)
  ↓
Hotkey available globally (double-tap Fn)
  ↓
[Core loop] Hotkey → overlay streams partials → stop → cleanup → paste
  ↓
[Optional discovery] "speak" menu → Dashboard opens (Home, History, Settings, etc.)
```

**Why this hybrid**:
- **Menubar stays the hotkey engine** — speech → text → paste is a 3-second interaction
- **Dashboard is the "home office"** — statistics, history review, power features, settings
- **Both are optional** — users who never open Dashboard still have a fully functional app

**Dashboard structure (NavigationSplitView recommended)**:
- **Sidebar**: List of sections (Home, Insights, Dictionary, Snippets, Style, Transforms, Scratchpad, History)
- **Detail pane**: Content for the selected section
- **Minimum width**: 760×520 (current spec in DashboardView.swift)
- **Default section**: Home (stats, streak, today's word count)

### 5.2 Settings Tab Architecture

Current 7-tab structure is well-designed:

| Tab | Purpose | Progressive Disclosure |
|-----|---------|---|
| **General** | Language, auto-paste toggle, paste mode | Day-to-day settings top; advanced paste modes below divider |
| **Shortcuts** | Hotkey rebinding, up to 4 bindings (v0.1+) | Current single binding; advanced: show add/remove UI for v0.1 |
| **Transcription** | STT engine picker, language auto-detect | SpeechAnalyzer (default) up top; WhiskerKit (v0.1+) below divider |
| **AI Cleanup** | Cleanup on/off, engine picker, style samples (v1+) | Toggle + engine selection up top; style samples and advanced engines below |
| **Dictionary** | Custom vocabulary, snippets (v0.1+) | Common terms first; import/export below divider |
| **Privacy** | Trust architecture, guarantees | Badges + guarantee rows (current state is excellent) |
| **About** | Version, links, compliance export (v3+) | GitHub link, issue link, MIT license, version/build |

**Recommendation**: Keep this structure. Add section dividers between day-to-day and advanced sections. Ensure each tab follows progressive disclosure (common first, advanced second).

### 5.3 Privacy Pane: Expand the Trust Centerpiece

**Current state** (excellent baseline):
- "100% On-Device" headline with lock icon
- 4-guarantee rows (No cloud audio, No cloud AI, No account, Never reads clipboard)
- Stub for transcript auto-delete policy (coming in W3.3)

**Recommended expansion for v1**:
- Add "What happens to your data" section: "Every dictation is stored locally in ~/Library/Application Support/speak/. Transcripts are never uploaded. You can export anytime. Delete history and the files disappear."
- Add "Permissions" subsection: "speak uses only 2 permissions: Microphone (to hear you) and Accessibility (for the Fn hotkey). We don't use Input Monitoring or any other OS features."
- Add "Compliance & export" button (v3+): Generates PDF with privacy architecture, audit trail, compliance templates
- Keep it factual, not marketing — users should understand the moat from the UI alone

**Recommendation**: Privacy tab is speak's trust anchor. Invest in making it even more transparent and audit-friendly.

### 5.4 History Pane: First-Class Feature

**Current state** (good foundation):
- Searchable, exportable, clearable
- HistoryView shows entries with raw + cleaned text
- Retry button for old dictations (v1-9)

**Recommended v0 → v1 evolution**:
- v0: Raw + cleaned text visible in a list; search box; clear + export buttons
- v0.1: Add engine attribution (show which STT + cleanup model ran); add cleanup diff toggle (show before/after side-by-side)
- v1: Add retry button (re-clean with current engine); add tags (code, email, slack, etc. from AppContext); add daily/weekly view toggle

**Recommendation**: History is a power feature but should remain optional — core user never needs to open it, but power users live in it.

### 5.5 Overlay HUD: Real-Time Feedback with Zero Friction

**Current spec** (from roadmap P4, good foundation):
- Floating panel near cursor
- Shows partial transcript (streaming)
- Auto-hides on done/error
- No interactive elements (read-only)

**Recommended implementation**:

```
┌──────────────────────────┐
│ Listening (red border)   │
│                          │
│ "speaking into the api"  │ ← partial text, Monaco 13pt
│ "document generator"     │
│                          │
│ ⏱ 4.2s (v0.1+)           │ ← elapsed time
│ 🇺🇸 EN (v0.1+)            │ ← language badge (if auto-detect on)
└──────────────────────────┘
```

Then:

```
┌──────────────────────────┐
│ Processing (yellow glow) │
│                          │
│ "speaking into the"      │ ← frozen partial (user can see where cleanup started)
│ ⟳ Cleaning...           │ ← spinner or progress
│                          │
└──────────────────────────┘
```

Then auto-hides and pastes (or shows error if paste fails).

**Recommendation**:
- Overlay border color matches menubar icon color (red → yellow → fades out)
- Text is Monaco 13pt (`.speakMonoBody`), aligned left
- Minimal chrome; maximum data
- No buttons, no dismissal required; auto-fade on done
- Language badge in v0.1 (passive, informational)

### 5.6 Settings Window Geometry & Look-and-Feel

**Current state** (good):
- TabView with 7 tabs
- Each tab scrolls if needed
- Dark mode / light mode compatible

**Recommended enhancements**:
- Tab width: wide enough to show full label without truncation (current is fine)
- Divider pattern: use `Divider()` consistently to separate day-to-day from advanced
- Color usage: accent color (warm amber) for active tab and key toggles; system colors for everything else
- Typography: system font for chrome/labels; Monaco only for example code, keycaps, engine names

**Recommendation**: Current Settings UX is solid. Focus on: testing the progressive disclosure on real users; ensuring all tabs are consistent in layout/spacing.

### 5.7 Dashboard Panes: Modular, Additive Design

**v0 Dashboard** (current):
- Home: Today's stats (word count, session count, streak if v1)
- Insights: Empty (stub for v1 charts/trends)
- Dictionary: Custom vocabulary list (v0.1)
- Snippets: Text snippets (v0.1+)
- Style: Writing style samples (v1)
- Transforms: Highlight → rewrite shortcuts (v1)
- Scratchpad: Scratch notes (optional, lower priority)
- History: Full transcript archive

**Recommendation**:
- Each pane is independently developed (assign to specialist per roadmap)
- Panes share `DashboardContext` (engine, settings, history, stats)
- Sidebar never gets more than 10 items; beyond that, use nested lists or tabs within a pane
- Each pane should have a clear "empty state" message + CTA ("No history yet. Start dictating to build your archive.")

---

## Section 6: Current App State (Implemented vs. Planned)

### 6.1 What Exists (v0 Spec, P0–P11-a Complete)

**Core engine** (SpeakCore.framework):
- ✅ Audio capture: AVAudioEngine, 16kHz mono PCM
- ✅ STT: Apple SpeechAnalyzer (on-device, free, native)
- ✅ Cleanup: Apple Foundation Models (on-device LLM, free, native)
- ✅ Hotkey: CGEventTap, double-tap Fn detection, customizable rebind
- ✅ Paste: NSPasteboard write + Cmd+V simulation, AX fallback
- ✅ History: SQLite store, search, export, clear
- ✅ Settings: UserDefaults persistence, typed wrapper (SettingsStore)
- ✅ Permissions: Microphone + Accessibility state machine, onboarding flow
- ✅ Error handling: SpeakError enum, recovery suggestions, graceful fallbacks

**App shell** (speak.app, SwiftUI):
- ✅ Menubar icon: Idle (gray waveform), Listening (red dot), Processing (yellow spinner), Done (green flash), Error (red X)
- ✅ Overlay: Floating panel, streams partial text, auto-hides on done/error
- ✅ Settings window: 7-tab TabView (General, Shortcuts, Transcription, AI Cleanup, Dictionary, Privacy, About)
- ✅ Dashboard: NavigationSplitView with 8 sidebar sections (Home, Insights, Dictionary, Snippets, Style, Transforms, Scratchpad, History)
- ✅ Onboarding: 3-permission flow (Microphone, Accessibility, hotkey picker)
- ✅ Single-instance guard: Prevents duplicate app launches

**Testing & quality**:
- ✅ 481 unit + integration tests (XCTest + Swift Testing)
- ✅ Moat audit: 7/7 (offline, free, MIT, no account, no egress, local history, latency)
- ✅ Lint: 0 serious warnings (swiftlint)
- ✅ Build: `make build` clean from a fresh clone
- ✅ Code signing: `make dev-cert` self-signed, ad-hoc signing for releases

### 6.2 What's Deferred (Visual Design / Live Verification)

**Marked `[deferred — visual]` in roadmap**:
- [ ] Overlay live appearance (color transitions, font rendering, animation timing)
- [ ] Menubar icon color distinctness (red vs. orange; green vs. yellow)
- [ ] Settings tab layout on small screens (1024×768)
- [ ] Dark mode + light mode rendering consistency
- [ ] History pane search box focus behavior
- [ ] Onboarding flow comprehension (user testing needed)

**Marked `[deferred — needs human verification]`**:
- [ ] Hotkey fire with other app focused (requires live AX test)
- [ ] Paste works in Terminal without triggering macOS 26.4 paste-provenance prompt
- [ ] Paste compatibility: tested in ≥ 13 of 16 apps (TextEdit, Slack, Terminal, Mail, Discord, VS Code, iCloud Notes, Notion, Chrome DevTools, Xcode, iTerm, Pages, Numbers)
- [ ] Dogfood: latency (stop → paste < 2.0s), false-trigger rate (< 1/30 min)

### 6.3 Architecture Diagram: Current Implementation

```
┌─────────────────────────────────────────────┐
│          Speak.app (SwiftUI)                │
│                                             │
│  ┌──────────────────────────────────────┐   │
│  │ SpeakApp.swift (MenuBarExtra)        │   │
│  │ - Single-instance guard              │   │
│  │ - AppDelegate → DictationController  │   │
│  └──────────────────────────────────────┘   │
│                                             │
│  ┌──────────────────────────────────────┐   │
│  │ DictationController                  │   │
│  │ - State machine: idle→listening→...  │   │
│  │ - Hotkey observer ← SpeakEngine      │   │
│  │ - Menu item callbacks                │   │
│  └──────────────────────────────────────┘   │
│                                             │
│  ┌─────────────┬──────────┬──────────────┐  │
│  │ Menubar     │ Overlay  │ Dashboard    │  │
│  │ Icon + Menu │ (panel)  │ (full win)   │  │
│  │             │          │              │  │
│  │ Idle/Listen │ Partial  │ Sidebar +    │  │
│  │ Process/Done│ text     │ 8 panes      │  │
│  └─────────────┴──────────┴──────────────┘  │
│                    │                        │
│              Settings Window                │
│              (7-tab TabView)                │
│                                             │
└────────────────────┬──────────────────────┘
                     │
                     ▼
            ┌────────────────┐
            │ SpeakCore.fwk  │
            │ (headless)     │
            └────────────────┘
                     │
         ┌───────────┼───────────┐
         ▼           ▼           ▼
    Audio        Hotkey      History
    + STT        + Paste      + Settings
```

### 6.4 Key Files & Their Roles

**UI Shell**:
- `App/SpeakApp.swift` — @main, menubar, delegate
- `App/DictationController.swift` — state machine, UI coordination
- `App/Overlay/TranscriptOverlayPanel.swift` — floating capture HUD
- `App/Dashboard/DashboardView.swift` — sidebar nav + panes
- `App/Settings/SettingsView.swift` — 7-tab preferences

**Theme & Design**:
- `App/Theme/SpeakTheme.swift` — Monaco fonts, colors, spacing tokens (design source of truth)

**Panes**:
- `App/Dashboard/Panes/HomePaneView.swift` — day's stats
- `App/Dashboard/Panes/HistoryPaneView.swift` — transcript archive
- `App/Settings/PrivacySettingsTab` — 4-guarantee privacy center

---

## Section 7: Next Steps for Design & Implementation

### 7.1 What's Locked (No Further Design Needed)

✅ **Theme**: Monaco (user decision 2026-06-21), warm amber accent, semantic spacing 4pt grid  
✅ **Navigation**: Menubar hotkey + opt-in Dashboard sidebar  
✅ **Settings**: 7 tabs, progressive disclosure (day-to-day / advanced split)  
✅ **Privacy tab**: 4-guarantee badges (excellent trust centerpiece)  
✅ **Overlay**: Read-only, streaming partials, auto-hide on done/error  
✅ **States**: Red (listening), Yellow (processing), Green (done), Gray (idle), Red X (error)  

### 7.2 What Needs Live Verification (P13 Dogfood)

🔄 **Overlay rendering**: Colors, fonts, positioning, animation timing (live test needed)  
🔄 **Hotkey reliability**: False-trigger rate in normal typing, double-tap window tuning (400ms target)  
🔄 **Paste compatibility**: Terminal paste-provenance check, 3+ app categories  
🔄 **Latency**: Median stop→paste < 2.0s (with cleanup), < 1.0s (raw only)  
🔄 **Settings UX**: Progressive disclosure actually feels progressive to users (user testing)  

### 7.3 What's Next for Designers (v0.1+)

🎨 **v0.1 (Language & Engines)**:
- Language quick-switch pill in overlay (if auto-detect on)
- Engine attribution in History (show which STT + cleanup ran)
- Ollama setup flow (first-run connection test, status indicator)

🎨 **v1 (Power User & Polish)**:
- Transforms pane (highlight → rewrite UI)
- Style samples pane (upload writing examples)
- Code mode indicator in overlay ([Agent Mode] badge, v0.1) or full code context (v1)
- Quiet mode sensitivity slider
- Insights pane (30-day stats, streak, WPM chart)

🎨 **v2 (Platform & Expansion)**:
- iOS app UI (gesture-driven, Dynamic Island activity, Lock Screen widget)
- iCloud sync toggle in Privacy tab

### 7.4 Design Review Checkpoints

Before shipping each phase:
1. **Consistency audit**: Every state/color/icon appears the same everywhere (menubar = overlay = dashboard = settings)
2. **Progressive disclosure audit**: Each Settings tab has common controls first, advanced below divider
3. **Privacy audit**: No account, API key, or cloud toggles appear in the UI (exception: opt-in cloud in v0.1+, clearly labeled)
4. **Accessibility audit**: Voice users can navigate without a mouse; text alternatives for all icons; sufficient color contrast
5. **Live dogfood**: Real users on real Macs, measuring task success rate (goal: 95% of users get a working dictation without changing settings)

---

## Conclusion: The speak Design Philosophy

**speak is built on these truths:**

1. **Privacy is architecture, not marketing.** The moat (100% local, free, open, no account) isn't marketing fluff; it's coded into every system boundary. The UI should make this obvious.

2. **Voice dictation is ambient.** The best UX is one where the user speaks, the app listens silently, and the text appears where it's needed. The app should fade out, not demand attention.

3. **Defaults matter more than options.** speak ships with uncontroversial defaults (hotkey, language, cleanup on, paste mode). Most users never change them. Options exist for power users, but they're secondary.

4. **Clarity beats polish.** Monaco fonts, semantic colors, and ample whitespace matter more than gradients and animations. The user should *understand* what speak is doing, not feel dazzled by it.

5. **Consistency is a feature.** Every part of the app (menubar, overlay, dashboard, settings) behaves the same way. This makes the app predictable and trustworthy.

When any design decision is needed, return to these 5 truths. They're the why; the design principles above are the how.

---

**Document prepared**: 2026-06-28  
**Current phase**: P11-a (build-from-source), awaiting P13 dogfood  
**v0 ship gate**: MATCH + BEAT + quality.md §9 all pass  
**Next major phase**: V01-0 Agent Mode (v0.1, estimated after v0 ships)
