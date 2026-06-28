# Voice Dictation Landscape Analysis — Smart Design Patterns & Opportunities for `speak`

> **Date**: 2026-06-28  
> **Scope**: Competitive analysis of 7 apps (Wispr Flow, Superwhisper, MacWhisper, VoiceInk, FluidVoice, Aiko, TypeWhisper) across 8 UX dimensions.  
> **Purpose**: Identify smart design decisions that fit `speak`'s local-first, free, no-account moat.  
> **Audience**: T13 architectural improvements synthesis.  

---

## Section 1: Competitive Feature Matrix

| **Dimension** | **Wispr Flow** | **Superwhisper** | **MacWhisper** | **VoiceInk** | **FluidVoice** | **Aiko** | **TypeWhisper** | **Smart Observation** |
|---|---|---|---|---|---|---|---|---|
| **Real-time Feedback** | Cloud RTT ~700ms p99 → 1–2s `[verified]` | Not documented `[inferred]` | Transcription focus, less live RTT `[inferred]` | Live overlay, local `[unverified]` | Live word-by-word volatile `[verified]` | Polling model, not streaming `[inferred]` | Not documented `[inferred]` | **Local apps (FluidVoice, Aiko) beat cloud RTT; overlay latency <500ms is table-stakes for live UX.** |
| **Streaming vs. Final Display** | Streams raw → shows cleanup result on stop `[verified]` | Streams partials during recording `[inferred]` | Batch transcription (file-focused) `[verified]` | Live volatile partials `[unverified]` | Live volatile, shows partials in overlay `[verified]` | Async polling → HUD update `[inferred]` | Live partials expected `[inferred]` | **Frontier (Wispr) shows final cleaned result post-stop, not live stream; FluidVoice/Aiko stream volatiles. Hybrid (stream raw, overlay cleanup on stop) is uncommon—opportunity.** |
| **Paste vs. Keystroke Injection** | Pasteboard write + paste `[verified]` | Keystroke injection supported `[inferred]` | Paste-based insertion `[verified]` | Paste `[unverified]` | Keystroke injection (pluggable) `[inferred]` | Paste to pasteboard `[inferred]` | Likely keystroke injection (OSS) `[inferred]` | **Keystroke injection > paste in Citrix/RDP/locked-down envs; paste simpler but fails in VMs. speak write-never-read + Cmd+V bypasses prompt (needs P6 test in Terminal).** |
| **Hotkey Activation** | Double-tap Fn + toggle Fn+Space (hands-free) `[verified]` | Custom modifiers (hold+tap cycle); push-to-talk; mouse buttons 4–10 `[verified]` | Single hotkey, transcription workflow `[verified]` | Customizable hotkey (unclear if multi-bind) `[unverified]` | Customizable, multi-bind support `[inferred]` | Single hotkey, toggle mode `[inferred]` | Customizable (OSS default) `[inferred]` | **Multi-binding (up to 4 per action) is rare; only Superwhisper documents it. Wispr's hands-free Fn+Space toggle is elegant (no stop hotkey needed). speak's double-tap-Fn-start + single-tap-stop is clean; document rationale.** |
| **False-Trigger Prevention** | Not documented `[unverified]` | Cancel-if-<30s; long-record confirmation prompt `[verified]` | Not applicable (file-focused) | Not documented `[unverified]` | Acoustic fingerprinting + post-trigger audio `[unverified]` | Not documented `[unverified]` | Not documented `[unverified]` | **Superwhisper's 30s cancel threshold is smart (prevents accidents); false-trigger mitigation via acoustic fingerprinting + 1s post-trigger audio can mitigate 95.8% of false triggers (research-backed).** |
| **Settings Location** | Sidebar menu + in-app Settings pane `[verified]` | Configuration tab in app `[verified]` | File dialog (transcription-focused) `[verified]` | Menu bar + settings UI (steeper curve noted) `[unverified]` | Settings pane in main window `[inferred]` | Menu bar + preferences `[inferred]` | Settings UI location unclear `[inferred]` | **Sidebar IA (Wispr) is most discoverable; menu-bar-only (Aiko, TypeWhisper) is minimal but hides power-user settings. speak: gear icon + modal vs. sidebar depends on app shell (menubar vs. full-window).** |
| **Per-App Context Awareness** | Tone/cleanup level per app category `[verified]` | Power Mode auto-switches per app/URL `[verified]` | N/A (file-focused) | Smart Modes (Email, Tweet, Chat, Custom) `[unverified]` | Tone adaptation per app detected `[unverified]` | Not documented `[inferred]` | Not documented `[inferred]` | **VoiceInk Power Mode (auto-detect active app → apply saved profile) is elegant; Wispr's per-app tone is UX-friendly. speak's `AppContext` → cleanup-prompt-injection is v0.1 (V01-3); auto-apply per-app rules is v1+ refinement.** |
| **Cleanup Quality & Tone Options** | Auto Cleanup (4 levels: None/Light/Medium/High); Transforms (Polish, Prompt Engineer); Personalized Style `[verified]` | Tone adjustment, Enhancement modes `[inferred]` | Minimal (transcription-only) | Grammar correction, tone adjustment, 5 pre-built modes (Email, Tweet, Chat, Default, Custom) `[unverified]` | Per-app tone (formal/casual) + post-processing model `[verified]` | Basic cleanup (filler removal, punctuation) `[inferred]` | Likely basic cleanup + tone `[inferred]` | **Wispr's 4-level granularity + Transforms (Polish/Prompt Engineer) set frontier. speak's on-device Foundation Models cleanup + settings toggle is BEAT (local vs. cloud); tone/style matrix (v1) should match Wispr's breadth.** |
| **History & Search** | Temp "retry"; no persistent history `[unverified]` | Not documented `[inferred]` | Batch transcription files (filesystem) | Not documented `[inferred]` | Not documented `[inferred]` | Not documented `[inferred]` | Not documented `[inferred]` | **No competitor has searchable persistent history (Wispr's gap identified in verification-ledger §3). speak's local, searchable, exportable history is BEAT row v0 (§4 benchmark). No other app owns this.** |
| **Multi-Language Support** | 100+ languages, auto-detect, code-switch, Hinglish `[verified]` | Not documented `[inferred]` | Not applicable (file transcription) | Not documented `[inferred]` | English-focused, locale extensible `[inferred]` | English + Whisper locales `[inferred]` | Likely 100+ via Whisper `[inferred]` | **Frontier: 100+ with auto-detect + code-switch. Auto-detect is 10–15% less accurate than explicit selection (research-backed). speak v0: en-US/en-GB; v0.1+: SpeechAnalyzer locales; v1: 99-lang via WhisperKit. Hinglish is niche (speak addresses via Sarvam Saaras v3 v0.1+).** |
| **Error Recovery** | Scratchpad fallback (paste fails → Scratchpad opens with text); Paste-last-transcript shortcut (Ctrl+Cmd+V) `[verified]` | Not documented `[inferred]` | Batch transcription (error = re-run file) | Not documented `[unverified]` | Not documented `[inferred]` | Not documented `[inferred]` | Not documented `[inferred]` | **Wispr's Scratchpad fallback is elegant (visible artifact prevents data loss). speak's `.caf` buffer + Retry/Discard HUD on relaunch (v1 V1-8) is BEAT (crash recovery). Neither app documents app-specific paste failures gracefully.** |

---

## Section 2: Smart Design Patterns (5-7 Wedges)

### Pattern 1: **Volatile → Final Streaming Overlay**
**What**: Show live, mutable "volatile" (partial) transcript in an in-app overlay during recording, then when recording stops, show the cleaned final result in the same space.  
**Who does it**: FluidVoice (documented: live partials in overlay); Wispr Flow (posts cleanup after stop, not live partials).  
**Why it's smart**: 
- User sees *immediate* feedback (within ~500ms) that speech is being captured (solves "did it hear me?" anxiety).
- No jumping text during recording (raw partials are jarring; wait for stop).
- Cleanup delay is transparent (user sees "cleaning..." or results post-stop, not mid-stream).
- Reduces eye fatigue vs. scanning a fixed remote status bar.

**Applies to speak?** **Yes (v0 CORE).** The volatile→final pattern matches speak's "live word-by-word volatile transcript" (benchmark §4 MATCH row). speak's overlay should:
- Show partials updating <500ms lag during capture.
- Transition to cleaned text post-stop (or show "Cleaning..." spinner if >500ms LLM delay).
- Position near cursor (reduces eye travel vs. fixed overlay).

**Effort**: v0. The volatiles are already being generated by `SpeechAnalyzer`; hook them to the overlay seam.

---

### Pattern 2: **App-Aware Mode Switching (Power Mode Pattern)**
**What**: User sets up a "Mode" (cleanup tone, vocabulary, formatting rules) for an app, then the dictation engine auto-detects the active app and applies the right Mode transparently.  
**Who does it**: VoiceInk Power Mode (auto-detect app → apply saved Mode's transcription + enhancement settings); Wispr per-app tone (less automatic, but tone-per-app-category).  
**Why it's smart**:
- Zero friction: user doesn't manually toggle modes between Email and Slack.
- Semantic consistency: "casual_slack" vs. "formal_email" feels natural.
- Discoverable in settings (list of apps × modes is visible).
- Reusable: once set, it "just works."

**Applies to speak?** **Maybe (v1, V1-3 priority).** speak's `AppContext` (7 classes: Code, Email, Chat, etc.) is the foundation. The pattern would be:
- Auto-detect active app bundle ID (already done).
- Apply per-AppContext cleanup prompt injection (v0.1 does this).
- *Enhancement*: let user drag-reorder AppContext priority, or set custom bundle IDs.

**Effort**: v1. Requires UI for app→context binding + bundle ID customization (medium effort).

---

### Pattern 3: **Scratchpad Paste-Failure Fallback**
**What**: If paste fails (paste blocked by app, pasteboard locked, etc.), auto-open a Scratchpad with the transcript so the user can copy and manually paste if needed.  
**Who does it**: Wispr Flow (documented: "Scratchpad reliably opens with dictated text as a fallback whenever a paste fails").  
**Why it's smart**:
- **Data never gets lost.** Paste fails in restricted app → transcript is visible and recoverable.
- **Reduces support friction.** User doesn't post "my text disappeared!" support tickets.
- **Visible recovery.** User knows something went wrong (Scratchpad appears) and can act.
- **Graceful degradation.** From "type for me" → "paste-assist me."

**Applies to speak?** **Yes (v0.1 or v1, depending on Scratchpad roadmap).** speak should:
- Detect paste failure (`.pasteboardBusy` error state already exists in code).
- Open a read-only Scratchpad showing the clean transcript with a "Copy" button.
- Option: offer "Retry Paste" button with a ~2s delay (in case app was just locked).

**Effort**: v0.1. The Scratchpad seam exists; wire error-state handling to open it (low effort).

---

### Pattern 4: **Undo via Raw-Transcript Fallback**
**What**: Let the user toggle between the cleaned transcript and the raw (pre-cleanup) transcript to undo overzealous AI editing. Show both in the app history or via a quick "View Raw" option.  
**Who does it**: Wispr Flow (undo function reveals raw transcripts; users can scroll back to see what was said vs. what Flow cleaned).  
**Why it's smart**:
- **Builds trust in cleanup.** User can audit: "did Cleanup actually improve this, or butcher it?"
- **Recovers from overcorrection.** Sometimes the raw is better (esp. for code, URLs, proper names).
- **Data transparency.** User controls the final text, not the AI.

**Applies to speak?** **Yes (v0.1 or v1, V01-4 adjacent).** speak should:
- Store both `rawTranscript` and `cleanedTranscript` in history.
- In History detail view, toggle "Raw ↔ Cleaned" to compare.
- (Optional) "Accept Raw" button to revert to raw if cleanup was wrong.

**Effort**: v0.1. History already stores both; add a toggle in the History detail view (low effort).

---

### Pattern 5: **Customizable Multi-Hotkey Binding**
**What**: Allow users to bind the same action (Start Dictation) to multiple hotkeys (e.g., double-tap Fn *and* mouse button 4 *and* custom Ctrl+Shift+D) so they can pick what feels natural.  
**Who does it**: Superwhisper (up to 4 hotkeys per action documented); Wispr (Fn default, but does not document multi-bind; likely limited to 1 per action).  
**Why it's smart**:
- **Accessibility win.** User with one hand can use mouse button; mouse-free user uses Fn; power users hotkey.
- **Habit compatibility.** Users migrating from different apps bring different muscle memory.
- **No false conflicts.** Up to 4 binding attempts can be rejected gracefully (not silently dropped or conflicting).

**Applies to speak?** **Yes (v0.1, V01-5).** speak's hotkey seam should:
- Allow up to 4 bindings per action (default: double-tap Fn for start; single-tap for stop).
- Support Fn, modifier+key, mouse buttons 4–10.
- Validate conflicts (warn if binding collides with system or app shortcuts).
- Persist in settings; document the limit ("max 4 bindings").

**Effort**: v0.1. Requires UI for hotkey binding + conflict detection (medium effort); the hotkey engine already supports it.

---

### Pattern 6: **Tone Sampling (Few-Shot Personal Style)**
**What**: Let users upload 3–5 writing samples (email excerpt, Slack message, formal memo), then use those as few-shot examples to guide the cleanup LLM toward the user's personal voice.  
**Who does it**: Wispr (Personalized Style setting; not clear if samples-based or just tone-level slider); `speak` roadmap (v1 V1-11: "Up to 5 samples → few-shot injection in cleanup prompt").  
**Why it's smart**:
- **Preserves user voice.** "Formal" tone setting is generic; sample-based is personalized.
- **Discoverable.** User pastes an example, sees immediate improvement in cleanup output.
- **Flexible.** Same sample mechanism works for "code style," "technical writing," "casual Slack."

**Applies to speak?** **Yes (v1, V1-11).** Implementation:
- Settings → "Writing Samples" section with 5 text fields (Email, Code, Chat, Formal, Custom).
- Cleanup prompt injects samples as few-shot context: *"Based on these examples of my writing: [sample1], [sample2], ..., rewrite this transcript in my voice."*
- Optional: auto-detect "tone" from samples (e.g., avg word length, punctuation density).

**Effort**: v1. Requires settings UI + prompt template tuning (low-medium effort).

---

### Pattern 7: **History as the Canonical Artifact** (speak's BEAT)
**What**: Every dictation session is automatically stored in a searchable, exportable local history with metadata (timestamp, app, engine, cleanup mode, duration). History is the source of truth for what you dictated.  
**Who does it**: **NO ONE.** Wispr has temp "retry"; Otter has cloud sync (but that's a meeting transcriber, not a dictation app). This is an open wedge.  
**Why it's smart**:
- **Audit trail.** User can prove "I said X" (useful for sales notes, legal dictation, etc.).
- **Writing research.** See word count, WPM trends, cleanup effectiveness over time.
- **Recovery.** If paste-failure Scratchpad gets closed, history is still there.
- **Privacy+Moat.** Local history (not cloud) differentiates speak from Wispr.

**Applies to speak?** **YES (v0 BEAT row §4).** speak should:
- Auto-save every session to SQLite (already roadmapped; P0 done per AGENTS.md).
- Full-text search on cleaned transcript + raw transcript.
- Metadata: timestamp, duration, app bundle ID, cleanup mode, WPM, word count.
- Export as CSV/JSON.
- UI: "History" tab with day-grouped feed (matching Wispr Home design per wispr-flow-ui-verified.md).

**Effort**: v0 (already roadmapped). Search + export are v0.1 refinements.

---

## Section 3: Underutilized Areas in `speak` (Opportunities)

### Opportunity 1: **Per-App Cleanup Context Beyond AppContext Class**

**Current approach**: `speak` has `AppContext` (7 hardcoded classes: Code, Email, Chat, Docs, Slack, Terminal, Default). Cleanup prompt is injected per class.

**Smarter alternative**: Allow custom bundle ID → AppContext binding, so user can map their proprietary internal tools (Jira, Confluence, custom in-house app) to cleanup rules.

**Why it fits the moat**: 
- Completely local (no cloud config).
- Free (no per-app subscription).
- No account (settings live in ~/Library/Preferences).
- Competitive edge: Wispr's "per-app tone" only works for known apps (Gmail, Slack, etc.); speak's customizable bundle-ID binding is more flexible.

**Implementation**: 
- Settings: "Custom App Rules" section.
- User pastes bundle ID (e.g., `com.taska.jira`), selects AppContext or custom cleanup tone.
- Cleanup prompt: check bundle ID → inject matched context.

**Effort**: v1 (V1-3 refinement). Low: settings UI + bundle-ID lookup in cleanup seam.

**Research gap**: Validate that users actually want this. Is "Code, Email, Chat, Docs, Slack, Terminal" enough, or do knowledge workers juggle 15 different apps with distinct writing styles?

---

### Opportunity 2: **Live Cleanup Streaming (Not Just Volatiles)**

**Current approach**: speak shows live *raw* volatiles in the overlay, then swaps to cleaned text on stop (latency: depends on Foundation Models speed, typically <1s).

**Smarter alternative**: Stream *both* raw and cleaned in real-time, side-by-side in the overlay, so user sees live cleanup happening. (E.g., raw: "uh, the quick brown fox uh jumps" → cleaned: "The quick brown fox jumps" updating live.)

**Why it fits the moat**: 
- Builds trust: user sees cleanup working in real time, not as a black box.
- Reduces cognitive load: no mystery lag between stop and paste.
- Competitive edge: Wispr streams to cleanup result on stop (hidden latency); FluidVoice likely streams raw only. side-by-side is uncommon.

**Implementation**: 
- Overlay shows two lines: [RAW VOLATILE] and [CLEANED VOLATILE].
- Every partial from SpeechAnalyzer feeds to both rendering + LLM cleanup pipeline.
- Cleaned line updates ~200–500ms behind raw (lower latency than waiting for stop).

**Effort**: v1 (V1+). Medium: requires async cleanup pipeline running in parallel with transcription (not just batch-on-stop). Trade-off: higher CPU/memory during dictation.

**Risk**: Cleanup model latency (Foundation Models on-device STT is ~500ms per phrase). If cleanup lags too far behind raw, side-by-side is confusing (user thinks cleanup failed).

**Research gap**: Test whether side-by-side helps or confuses users. A/B test: side-by-side vs. single final-text overlay.

---

### Opportunity 3: **App-Specific Paste Behavior Detection**

**Current approach**: speak writes to pasteboard, simulates Cmd+V, assumes it works everywhere. If paste fails, error state is generic.

**Smarter alternative**: Maintain a local list of "paste failure risk" apps (Terminal post-26.4, Citrix, vmware, RDP), and for those, either:
1. Warn user pre-dictation ("Paste may fail in Terminal; will offer Scratchpad fallback").
2. Auto-fallback to keystroke injection (if user enabled it in settings).
3. Auto-open Scratchpad on failure (already part of Pattern 3).

**Why it fits the moat**: 
- Reduces surprise errors.
- Accessible (users in restricted envs can still dictate).
- Competitive edge: Wispr doesn't document app-specific paste failure; speak can be transparent.

**Implementation**: 
- Settings: "Paste Risk Apps" list (pre-populated with known failures; user can add custom).
- Dictation UX: before starting, check active app against risk list → show banner or suggestion.
- Foundation: already mapped paste behavior per benchmark §3 row (Terminal Test at P6).

**Effort**: v1 (V1+). Low: just configuration + UI. Requires actual Terminal paste testing to populate the risk list.

**Research gap**: Conduct P6-level empirical testing in Terminal, Slack, VS Code, Citrix (if available) to document which apps fail and under what conditions.

---

## Section 4: Over-Engineered Areas (Simplify or Defer)

### Over-Engineered 1: **Multi-Language Auto-Detect in v0**

**Current roadmap**: v0 = en-US/en-GB only. v0.1 = SpeechAnalyzer installed locales (user can add manually via macOS System Settings → Language & Region). v1 = WhisperKit 99-lang.

**Assessment**: This is *correctly* staged, not over-engineered. Skip.

---

### Over-Engineered 2: **Custom Vocabulary Learning from Corrections (Defer to v0.1+)**

**Current**: benchmark §4 row V01-4 "Auto-dictionary learning: user-corrected word appears in custom vocabulary after accepting HUD proposal; max 3/session cap enforced."

**Problem**: This feature is sophisticated but niche:
- Requires post-paste HUD interaction (extra UX step).
- Whisper/SpeechAnalyzer vocab is already broad; few users will correct more than 1–2 words per session.
- SQLite custom-vocab table is simple, but the HUD + diff logic adds surface area.
- Research shows Wispr's auto-learned words are tagged with ✨ sparkle, but no evidence of high user adoption.

**Recommendation**: **Defer to v0.1+.** v0 ships with manual dictionary editing (Settings → Custom Terms). v0.1 adds auto-learn on HUD accept. This prioritizes ship velocity in v0.

**Effort saved**: 2–3 days (HUD + diff detection + SQLite writes).

---

### Over-Engineered 3: **Per-App Custom Vocabulary (Defer to v1)**

**Current**: benchmark §4 row V01-4 mentions "custom vocabulary"; does not specify per-app.

**Problem**: Maintaining separate word lists per app (Email vocab vs. Code vocab) is cognitively heavy:
- Settings become a matrix (app × word).
- Most users won't populate 15 separate lists.
- Wispr's approach (single global dictionary + per-app tone) is simpler and sufficient.

**Recommendation**: **v0/v0.1: global dictionary only.** v1 (V1-3 or later) adds per-app overrides if needed. Start simple.

**Effort saved**: 1–2 days (settings matrix UI + filtered-dictionary logic).

---

## Section 5: Verdict & Recommendations for T13

### Top 3 Quick Wins (v0.1 candidates)
1. **Implement Scratchpad paste-failure fallback** (Pattern 3). Data loss is the worst UX failure. Wireup: ~1 day.
2. **Dual-hotkey binding** (Pattern 5, simplified). Support double-tap-Fn + one custom hotkey. ~1 day.
3. **History toggle (Raw ↔ Cleaned)** (Pattern 4). Store both transcripts; add toggle in History detail. ~1 day.

### Medium-Term Refinements (v1)
1. **App-Aware Mode Switching** (Pattern 2). Auto-apply per-app cleanup context.
2. **Writing Sample Few-Shot** (Pattern 6). Let users upload tone samples.
3. **App-Specific Paste Behavior Detection** (Opportunity 3). Test Terminal + document failures.

### Ship v0 As-Is (Don't Defer)
- The volatile→final streaming overlay (Pattern 1) is core and already roadmapped.
- History as canonical artifact (Pattern 7) is v0 BEAT row; non-negotiable.
- Per-app context awareness via AppContext (Pattern 2 v0.1 step) is v0.1; v0 can ship with Default context.

### Research Before Committing
1. **Do users want side-by-side raw+cleaned streaming** (Opportunity 2)? Or does it confuse? Test in dogfood.
2. **Which apps actually fail paste?** Run the Terminal paste test (benchmark §3 P6 critical path) before documenting app-specific behavior.
3. **Does history search + export matter?** Ship v0 with history storage; v0.1 adds search + export if users demand it.

---

## Sources

### Primary Research (Verified 2026-06-20 to 2026-06-28)
- Wispr Flow UI Verification: `/Users/tamil/Developers/deepvoice/research/wispr-flow-ui-verified.md`
- Benchmark & Competitive Matrix: `/Users/tamil/Developers/deepvoice/docs/benchmark.md` (§1–2, MATCH/BEAT rows)
- Verification Ledger: `/Users/tamil/Developers/deepvoice/specs/verification-ledger.md` (primary sources for Wispr, category, Apple SDK)

### Web Sources (Fetched 2026-06-28)
- [Wispr Flow Review 2026](https://spokenly.app/blog/wispr-flow-review)
- [Superwhisper Keyboard Shortcuts Documentation](https://superwhisper.com/docs/get-started/settings-shortcuts)
- [VoiceInk Features & Design](https://tryvoiceink.com/features)
- [FluidVoice — Free Open Source Voice-to-Text for macOS](https://altic.dev/fluid)
- [Voice-to-Text Apps Multi-Language January 2026](https://willowvoice.com/blog/best-voice-to-text-apps-multi-language-users)
- [Wispr Flow Command Mode Documentation](https://docs.wisprflow.ai/articles/4816967992-how-to-use-command-mode)
- [DictaFlow vs Wispr Flow in 2026](https://medium.com/@ryanshrott/dictaflow-vs-wispr-flow-in-2026-which-dictation-app-actually-works-everywhere-13ade7d94f8d)
- [False Trigger Mitigation in Voice Systems (Research)](https://arxiv.org/pdf/2105.06598)
- [Speaker Fingerprinting in Voice AI](https://www.assemblyai.com/blog/speaker-fingerprinting-voice-ai)

---

## Appendix: Evidence Tags

- `[verified]` — Primary source (web fetch, official docs, user screenshot) confirms claim.
- `[inferred]` — Logical inference from observed behavior or missing documentation; likely but not confirmed.
- `[unverified]` — No primary source found; claim is speculative or from outdated reviews.

**All claims in Sections 3–4 (Opportunities & Over-Engineering) are recommendations pending user validation in dogfood; not architectural mandates.**

