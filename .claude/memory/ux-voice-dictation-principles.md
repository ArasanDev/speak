---
name: ux-voice-dictation-principles
description: "10 core UX design principles for speak derived from modern voice dictation, privacy-first, and AI transparency research (WWDC 2025-2026 aligned)"
metadata: 
  node_type: memory
  type: project
  originSessionId: 7c3a8745-710d-4a05-871e-8dc689091fae
---

# Voice Dictation UX Design Principles

Research synthesis from modern UX best practices, WWDC guidance, and privacy-first design patterns. Applied to speak's interface architecture.

## The 10 Principles

### 1. Interim-to-Final State Progression
Real-time transcription displays intermediate results as they arrive (provisional text, lighter/faded), followed by confident final results once confirmed. Users see feedback instantly (proving the system heard them) while final text stabilizes once speech ends.

**For speak:** Show provisional transcription updating live, then highlight or settle final segments once SpeechAnalyzer marks them confirmed. Distinguish states visually (e.g., faded vs. solid text).

### 2. Minimal Privacy UI — Privacy as Default, Not Permission
Privacy embedded silently into design rather than asking repeatedly. Since speak is 100% local-first, communicate this once at setup, then disappear—never expose collection prompts or consent dialogs.

**For speak:** Show privacy status once in onboarding ("All processing happens on your Mac"). Add subtle badge in settings. Never ask for permission to record or process locally.

### 3. Voice Feedback & System Acknowledgment
Hotkey activation feels fragile without feedback. Show simple visual cue (breathing animation, pulse), brief sound signal, or waveform to reassure users the system heard and is processing.

**For speak:** On hotkey press, show animated pulse (menu bar or highlight) + low-key sound. During transcription, display animated waveform or pulsing indicator.

### 4. Multimodal Integration — Voice as Entry, Visual Feedback as Default
Voice initiates, but visual feedback (text, status, controls) is essential. Never rely on voice alone. Combination benefits accessibility (hearing impairment, quiet environments, cognitive load).

**For speak:** Display transcribed text prominently as it arrives. Show cleanup progress with visual indicators. Let users review and edit before pasting.

### 5. Real-Time Processing Visualization (AI Transparency Patterns)
When AI "neat-writes," show what's happening using proven patterns:
- **Living Breadcrumb** (lightweight): "Fixing grammar" → "Checking tone" (simple status transitions)
- **Dynamic Checklist** (multi-step): "1. Checking tone ✓, 2. Fixing grammar (in progress), 3. Formatting (pending)"
- **Thinking Toggle** (optional): "View Details" button for deeper transparency
- **Audit Trail** (post-completion): Review decision logic after cleanup finishes

Users understand delays when they know *why*. Visible checklist manages expectations better than silent spinner.

**For speak:** Use Dynamic Checklist or Living Breadcrumb in corner badge/toast. Show completed ✓, current (spinner), pending (outlined). Never show raw logs—sanitize and abstract messages.

### 6. Stable Streaming Display — No Layout Shift During Text Arrival
As transcribed text streams character-by-character, layout must remain stable. Avoid reflows, wrapping, scrolling thrash. Jittery text is cognitively exhausting and prevents reading.

**For speak:** Allocate fixed-height region for transcribed text. Auto-scroll to bottom only if user already at bottom; stop if they scroll up. Render text character-by-character into live text node (not rebuilding paragraphs). Batch DOM updates once per animation frame.

### 7. Accessible Voice Activation — Hotkey Design for All Users
Global hotkey (double-tap Fn) must be discoverable, remappable, and paired with visual/auditory feedback. Hotkey is often a barrier for those with motor/hearing/cognitive differences; activation accessibility is as important as voice accessibility.

**For speak:** Offer onboarding step showing hotkey + customization. Display active hotkey in settings prominently. Consider visual toggle (menu bar button) as fallback. Test activation with diverse users early.

### 8. Progressive Disclosure — Simple by Default, Details on Demand
Primary UI shows only essentials: activate → transcribe → paste. Additional controls (cleanup settings, history, advanced options) hide in secondary panel/menu, revealed only when users explicitly ask.

**For speak:** Minimal interface: hotkey status + settings gear (bottom-left). In settings panel, organize into collapsible sections (Cleanup, Audio, History). Never show advanced options in main view.

### 9. On-Device Processing Clarity — Communicate Privacy Through Visible Design
UI should visually signal processing is local. Can be: label ("Processing on your Mac"), indicator (local-machine icon, no cloud icon), or *absence* of network spinners. If UI looks identical to cloud-based dictation app, users assume same privacy model.

**For speak:** Avoid spinners resembling cloud processing. Show "On your Mac" or local-machine icon in status area. Display "100% Local Processing" badge in settings. Never expose API calls or network requests in UI.

### 10. Conversational, Natural-Language Interaction
All UI text should be plain, conversational—no jargon, no technical messages. Status messages should feel like a colleague, not a machine dumping debug output. Users trust interfaces that speak plainly.

**For speak:** Audit all UI copy for jargon. Avoid acronyms without explanation. Use present-tense verbs ("Fixing grammar") not passive ("Grammar is being fixed"). Keep messages to one short sentence.

---

## WWDC Alignment

**WWDC 2025–2026 Guidance:**
- Expose core actions via **App Intents** with streaming, multi-turn support (aligns: Principles 3, 5)
- Use **SpeechAnalyzer API** for on-device STT (aligns: Principles 2, 9)
- Emphasize **visual intelligence** and screen feedback for voice interactions (aligns: Principle 4)

## Implementation Priority for v0

**Critical path (P0 for v0):**
1. Principle 1 (Interim-to-Final) + Principle 6 (Stable Streaming) — core to real-time transcription feel
2. Principle 2 (Minimal Privacy UI) + Principle 9 (Local Processing Clarity) — differentiator
3. Principle 3 (Voice Feedback) — makes hotkey interaction feel responsive
4. Principle 5 (Processing Visualization) — critical if cleanup is enabled in v0

**Can ship in v0.1:**
- Principles 4, 7, 8, 10 — important but not blocking core loop

## Research Sources

- Apple HIG Sidebars: https://developer.apple.com/design/human-interface-guidelines/sidebars
- Privacy-First UX (letket, 2026): https://letket.com/privacy-first-design-ux-best-practices-2026/
- AI Transparency Patterns (Smashing Magazine, 2026): https://www.smashingmagazine.com/2026/05/practical-interface-patterns-ai-transparency/
- Streaming UI Best Practices (Smashing Magazine, 2026): https://www.smashingmagazine.com/2026/05/designing-stable-interfaces-streaming-content/
- Voice UI Design Guide (Fuse Lab Creative, 2026): https://fuselabcreative.com/voice-user-interface-design-guide-2026/
- Real-Time Transcription (getStream): https://getstream.io/glossary/real-time-transcription/
- WWDC26 Sessions: https://developer.apple.com/wwdc26/

**Research date:** June 28, 2026
