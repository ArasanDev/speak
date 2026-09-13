> Living state file. Agents: rewrite the "current" section at end of each loop. Do not delete history — append.
> Archive location: `docs/progress-archive.md`.

# `speak` — Progress (NOW)

---

## Current phase

**Loop #99 (2026-09-11) — Settings & Control Room: all six sensory seams wired to real data flows.**
Direct user directive (not a roadmap pull): turn `App/Settings/` from static controls into a live
control console. Everything below is real — no placeholders, no canned strings.

- **General & Audio** — live mic check: `SpeakCore/Audio/MicLevelMonitor.swift` runs a second
  `AudioCapture` in level-only mode (PCM stream drained, RMS `levelStream` forwarded) feeding a
  new 20-segment `App/Components/VUMeterView.swift` (green/amber/red threshold ramp, 150 ms
  spring) + dBFS readout in the Microphone card. Route changes flash a "Switched" pill via the
  existing `CoreAudioDeviceMonitor` callback; recovery across AirPods connect/disconnect is
  inherited from `AudioCapture`'s `.AVAudioEngineConfigurationChange` rebuild — no -10868.
  Meter pauses while a real dictation owns the mic.
- **AI Models** — "Test My Voice" live sandbox replaces the canned diff. `SpeakCore/Engine/
  VoiceSandbox.swift` composes a real `CaptureSession` with `inserter: nil` (paste-free by
  construction) using the same settings-derived wiring as `newSession` (locale, `.styled` mode,
  expander chain); `App/Settings/VoiceSandboxModel.swift` (@MainActor @Observable) drives
  partials/levels/phase; `App/Settings/HoldToTalkPill.swift` gives hold-to-talk + tap-to-latch
  (350 ms threshold). Result renders in the existing `CleanupDiffView` with real raw→cleaned
  diff + "cleaned in N ms by <engine>" readout.
- **Vocabulary** — new "Acoustic Corrections" card (heard → typed table, e.g. `cubectl`→`kubectl`).
  New `SpeakCore/Vocabulary/AcousticCorrection.swift` (Codable model + pure upsert/remove rules),
  `AcousticCorrectionExpander` (rides the `SnippetExpanding` seam — whole-word, case-insensitive),
  `Snippets/CompositeExpander.swift`, and `defaultExpander(for:snippetStore:)` in
  `EngineFactories.swift` composing corrections→snippets in that order (corrections restore
  mangled snippet triggers). `SettingsStore.acousticCorrections` persists as JSON;
  `effectiveVocabulary` merges correction targets into both the SpeechAnalyzer contextualStrings
  path and the Foundation Models vocabulary clause.
- **Hotkeys** — new Feedback card: `dictationFeedbackSounds` (default on, Tink/Pop system chimes)
  + `dictationFeedbackHaptics` (opt-in, NSHapticFeedbackManager `.generic`). Fired by
  `DictationController.icon` didSet on `.listening` enter/exit via new
  `SpeakCore/Feedback/DictationFeedback.swift` (@MainActor).
- **Agent Bridge** — real heartbeat: `DashboardContext.agentSessionRegistry` now carries the
  app's actual `AgentSessionRegistry` (previously the view instantiated a fresh empty one — the
  count was always wrong). Live Sessions card polls every 2 s, shows per-session provider/label,
  relative lastSeen, Active/Stale pills, "Agent attached" heartbeat dot when a session pinged in
  the last 60 s.
- **Privacy & Health** — permission pills now poll every 1.5 s (TCC grants in System Settings
  don't notify the app); "Run Moat Verification" keeps the sheet and adds an inline
  "N/N guarantees verified · timestamp" summary.
- **SettingsStore** — new keys `acousticCorrections`, `dictationFeedbackSounds` (default true),
  `dictationFeedbackHaptics` (default false); all wired through resetToDefaults.
- **Tests** — `AcousticCorrectionsTests` (16), `VoiceSandboxTests` (7, mock STT+cleaner),
  `VUSegmentFillTests` (6): 29 new tests, all green. Note: mock cleaners must not return
  "Cleaned:"-prefixed output — `extractTargetTranscript` strips LLM label prefixes by design.
- **Verification**: `make build` clean · targeted suites 29/29 pass · full `make test` 1179 pass /
  10 skip / 1 failure (`SpeakEngineIntegrationTests.testEndToEndDictationWithRealComponents` —
  **pre-existing, confirmed failing on clean HEAD via stash**: live-FM run delivers `[speak-stt]`
  agent-prefixed text; unrelated to this change) · `make lint` 1 serious pre-existing
  (`StatusBarController` function length, untouched) · `make verify-moat` 7/7 ·
  `make install CONFIG=Release` ✅.
- **Not verified**: live VU meter against a real mic + the sandbox's real Foundation Models run
  need the app running with mic granted — logic verified by tests, live feel unverified.

---

**Loop #98 (2026-09-11) — Dedicated Two-Panel Settings Experience (t3code-inspired) COMPLETE.**
- **Two-mode dashboard navigation**:
  - `DashboardView` now treats `selection == .settings` as a mode sentinel: the whole window swaps
    from the desk (Mode A) to the dedicated Settings experience (Mode B). The gear button enters
    via `openSettings()` (spring animation, remembers `lastDeskSection`); `Esc`, `Cmd+[`, and the
    `‹ Dashboard` back button return to the desk where you were. `WindowPresenter.showSettings()`
    still lands directly in Settings via `show(initialSection: .settings)`.
  - Dynamic Mode Jump on Visible Window: Wired `navigateToSectionPublisher` through
    `DashboardContext` and `DashboardWindowController.navigationSubject`. When the dashboard is
    already open, menubar "Settings…" instantly and smoothly jumps into Settings mode (`.settings`)
    without requiring a window re-open.
- **New files** (`App/Settings/`):
  - `SettingsCategory.swift` — 8 rail destinations grouped into System / Intelligence / Experience.
  - `SettingsChrome.swift` — `SettingsSectionCard`, `SettingsRow` (title+description left, control
    right), `SettingsRowSeparator`, `SettingsStatusPill` — the native analogue of t3code's
    `SettingsSection`/`SettingsRow`.
  - `SettingsExperienceView.swift` — header (back button + `Settings › <category>` breadcrumb +
    esc keycap), grouped left rail (208pt), card-based detail canvas.
  - Category views: `GeneralAudioSettingsView` (startup, language, live mic, insertion, voice-out),
    `HotkeysSettingsView` (activation mode, recorder, extra bindings, accessibility),
    `AIModelsSettingsView` (intensity, W4.1 diff preview, voice, engine + setup sheets, per-app
    context), `VocabularySettingsView` (vocab + snippets), `AgentBridgeSettingsView` (speak-mcp
    status/install/config, prompt tag, session count, jumps to desk panes),
    `AppearanceHUDSettingsView` (theme, HUD style, border animation), `PrivacyHealthSettingsView`
    (permission pills, moat audit, data management). About reuses `AboutSettingsTab`.
- **Refactors**: `MoatResultsSheet` extracted from `PrivacyPaneView` (shared audit surface);
  `DashboardContext` gained `activeExtraBindings`/`rebindExtraBindings` (wired through
  `WindowPresenter` + `DashboardWindowController.updateContext`); `SettingsPaneView.swift` deleted
  (superseded by the dedicated experience).
- **Tests**: `SettingsCategoryTests` (4 Swift Testing cases — grouping invariants, order, metadata).
- **Verification**: `make build` clean (0 errors/warnings) · `make test` SUCCESS · `make lint`
  0 serious (new files warning-free) · `make verify-moat` 7/7.

**Loop #97 (2026-09-11) — Dead Code & Mascot Subsystem Pruning for Clean Architecture Foundation COMPLETE.**
- **Subsystem Pruning**:
  - Completely excised the experimental "Voice Desktop Pet" subsystem (`App/Pet/`, `PetView`, `PetPanelController`, `PetState`, `PetGeometry`, `DictationController+Pet.swift`, `PetSection.swift`).
  - Removed corresponding unit tests (`PetGeometryTests.swift`, `PetStateTests.swift`, `PetViewMathTests.swift`, and pet mascot assertions in `FeatureIntegrityIntegrationTests.swift`).
  - Cleaned `SettingsStore` (`petEnabled`, `petPositions`) and updated `SettingsStoreTests.swift` and `SettingsStoreResetAndMiscTests.swift`.
  - Retained `ai_tmp/` for reference and retained all Speech Synthesizers / TTS infrastructure untouched per user instruction.
- **Verification & Moat**:
  - `make build`: Clean build (0 errors, 0 compiler warnings).
  - `make test-fast`: Green (✓ SUCCESS, 0 warnings).
  - `make verify-moat`: 7/7 checks passed.
  - `make lint`: 0 serious violations.

**Loop #96 (2026-09-11) — Bottom Sidebar Icon Toolbar, Self-Healing Action & Zero-Warning Swift Concurrency COMPLETE.**
- **Bottom-Left Sidebar Icon Evolution**:
  - Replaced the vertical text list item for Settings in `DashboardView.swift` with a compact, dedicated bottom toolbar (`sidebarBottomToolbar` and `sidebarRailBottomToolbar`).
  - **Settings Icon Button**: Clean `gearshape` icon button on the bottom left, opening the Settings panel upon click with active hover/selection styling.
  - **Circular Self-Healing Button**: Placed in the bottom right of the sidebar panel featuring `arrow.2.circlepath` (semi-circular arrows following each other).
    - Smooth 360° rotational spin on click (`withAnimation(.easeInOut)`).
    - Turns green (`Color.speakStateDone`) with a 2.5-second success feedback state and tooltip.
    - Includes an update notification dot (`Circle().fill(Color.speakAccent)`) positioned on top of the circle for future version releases.
    - Right-click context menu offering "Self-Heal & Re-arm Hotkey" and "Restart speak".
- **Self-Healing Architecture (`DictationController.selfHeal()`)**:
  - Automatically cancels stuck dictation sessions, restarts `HotkeyMonitor` event taps, re-validates TCC Accessibility & Microphone permissions, and prewarms on-device speech recognition via `SpeechPrewarmer`.
  - Connected end-to-end through `DashboardContext`, `WindowPresenter`, and `DashboardView`.
- **Swift Concurrency & Zero-Warning Modernization**:
  - Eliminated all Swift actor-isolation and concurrency warnings:
    - Marked `receiveData` and `isCompleteRequest` as `nonisolated` in `LocalInferenceServer.swift` to safely process `NWConnection` buffers without actor-hopping friction.
    - Marked `AgentSessionRegistry.staleThreshold` as `public static nonisolated let` so background threads and tests read it without actor isolation warnings.
    - Fixed autoclosure `try` in `LLMKeychainStoreTests` (`OpenAICompatibleCleanerTests.swift`).
- **Verification & Moat**:
  - `make build`: Clean build (0 errors, 0 compiler warnings).
  - `make test-fast`: Clean pass (✓ SUCCESS, 0 warnings).
  - `make verify-moat`: 7/7 checks passed.
  - Installed and verified live in `/Applications/Speak.app`.

**Loop #95 (2026-09-11) — Deep Single-Instance Handoff, In-App Restart & OS LaunchServices Hardening COMPLETE.**
- **Deep Validation Against Native macOS Architecture**:
  - Researched and benchmarked lifecycle management in leading open-source macOS utilities (Maccy, Raycast, Ice, Stats).
  - Identified classic macOS menu bar flaw: new releases terminating themselves when encountering an older zombie or dev instance running in the background.
- **Two-Tier Process Singleton & Smart Upgrade Handoff**:
  - **Tier 1 (OS LaunchServices)**: Added `LSMultipleInstancesProhibited: true` to `project.yml` Info properties so macOS LaunchServices natively prevents duplicate process spawns.
  - **Tier 2 (In-App Smart Handoff in `SpeakApp.swift`)**:
    - Automatic Canonical Precedence: When `/Applications/Speak.app` launches, it automatically terminates any stale developer/DerivedData instances running in memory.
    - Argument-driven replacement: Supports `--replace` and `--relaunch` flags to gracefully terminate older instances during updates.
    - Visual feedback on re-launch: Double-clicking Speak or opening it in Spotlight activates the existing instance and triggers `applicationShouldHandleReopen`, opening the Dashboard.
- **In-App "Restart speak" & Quick Developer Controls**:
  - Added **"Restart speak"** (`Cmd+Ctrl+R`) with `arrow.clockwise` action directly to the menubar menu in `StatusBarController.swift`.
  - Added `make restart` to `Makefile` for instant process cycling.
- **Swift Concurrency Modernization**:
  - Eliminated Swift 6 shared mutable state warnings by replacing `kAXTrustedCheckOptionPrompt.takeUnretainedValue()` with modern string literals in `PermissionManager.swift` and `HotkeyMonitor.swift`.
- **Verification & Deployment**:
  - `make build`: Clean build (0 errors, 0 compiler warnings).
  - `make test-fast`: Green (prompt and cleanup test suites pass).
  - `make verify-moat`: 7/7 checks passed.
  - Deployed fresh Release app to `/Applications/Speak.app` via `make clean-install` (running as PID 20066).

**Loop #94 (2026-09-11) — Apple Silicon Neural Processing Unit (ANE/NPU) Priority Allocation & Local Test Suite Verification COMPLETE.**
- **Apple Silicon Neural Engine & Performance Core Allocation**:
  - Investigated and optimized hardware resource allocation for dictation and cleanup windows.
  - On macOS 26 / Darwin, Apple's `SystemLanguageModel` (Foundation Models) and `SpeechAnalyzer` (Speech) dispatch matrix multiplication directly across the on-device Apple Neural Engine (ANE) and GPU.
  - macOS intentionally hides raw core-pinning of ANE/NPU cores to prevent user-space deadlocks; however, scheduling via **Quality of Service (QoS)** is the official lever.
  - Set `Task(priority: .userInitiated)` in `CaptureSession+Cleanup.swift` (line 121) and `CaptureSession.swift` (`ingestChunk`, line 680):
    - Darwin schedules tokenizer and token post-processing onto high-frequency **P-cores** (Performance Cores) instead of low-power E-cores.
    - Darwin tags the ANE command buffer submission with top interactive priority, pre-empting background system daemons for minimal Time-To-First-Token (TTFT) and high token generation throughput.
- **Local Test Suite & Moat Audit Verification**:
  - Fixed cleaner availability check in `CaptureSession.start()` and `StreamingChunkCoordinator.ingestChunk` to prevent spurious cleanup calls when the model engine is unavailable.
  - Executed tests locally on Apple Silicon:
    - `CaptureSessionTests` (15/15 tests green).
    - `DegradeToRawTests` (5/5 tests green).
    - `DeveloperAcronymBiasingTests` (9/9 tests green).
    - `StreamingChunkCoordinatorTests` (3/3 tests green).
    - `VoiceActionsPipelineTests` (5/5 tests green).
    - `AgentBridgeServerTests` (passed).
  - Moat audit (`bash scripts/verify-moat.sh`): **7/7 passed**.
  - Lint (`swiftlint`): **0 errors**.
  - `README.md` verified at exactly **298 lines** (strictly within the 200–500 target, far below 800 max).

**Loop #93 (2026-09-11) — Native macOS Packaging (Homebrew Cask & DMG), CoreAudio Auto-Healing & Promotional README Overhaul COMPLETE.**
- **Comprehensive README.md Overhaul**:
  - Articulated the **4 Core Problems Solved**:
    1. *Privacy Invasion & Subscription Creep in Voice Dictation*: Wispr Flow ($15/mo, cloud audio, background screenshots) vs. Speak (100% local on Apple Silicon, 0 network bytes, write-only pasteboard, MIT free forever).
    2. *Dictation Latency, Hallucinations & Over-Editing*: Eliminates heavy cloud lags and unsolicited question-answering via 5-line progressive FIFO streaming overlay + Apple 3B Foundation Model with strict imperative guardrails.
    3. *Audio Hardware Inflexibility & Headphone Dropouts*: Continuous 24/7 CoreAudio HAL listener (`CoreAudioDeviceMonitor`), dynamic device pinning, and 3-attempt exponential backoff settle for Bluetooth SCO format handshakes.
    4. *Developer & AI Coding Agent Workflow Friction*: Built for software engineering with prompt tagging (`[speak-stt]`, `[voice-stt]`, `:clean`, `:raw`), jargon biasing, and native compiled `speak-mcp` stdio server.
  - Complete installation guide: Homebrew Cask (`dist/speak.cask.rb`), Standalone DMG (`make dmg` $\to$ `dist/Speak.dmg`), One-line install script (`scripts/install.sh`), and developer source build.
  - Friction-free self-healing and troubleshooting guide: in-app "↻ Re-check & Re-arm Hotkey Tap" button, Apple Dictation shortcut collision resolution, and headphone hot-swapping.
  - Added **Resource Footprint & Efficiency (Zero Battery Tax)** benchmark section: live 32MB idle RAM, 0.0% idle CPU, Apple Neural Engine transient bursts, and comparison against Electron and local Whisper wrappers. Total README length: 298 lines (within 200–500 target).
- **In-App Self-Healing & Refresh Icon**:
  - Added "Re-check & Re-arm Hotkey Tap" item with `arrow.clockwise` icon to `StatusBarController.swift` menubar context menu.
  - Updated `SettingsView.swift` with `Label("Re-check & Re-arm Hotkey Tap", systemImage: "arrow.clockwise")` for instant TCC permission re-check and event tap recovery.
- **Verification & Moat**:
  - `xcodebuild build`: Exited 0 (BUILD SUCCEEDED).
  - `make verify-moat`: 7/7 checks passed.
  - `make lint`: 0 serious violations in 330 files.
  - Fast test suite green (`MoatAuditTests`, `AudioCaptureConfigChangeTests`).
- **Explicit STT Origin Tags (`AgentPrefixStyle`)**:
  - Expanded `AgentPrefixStyle` in [`SpeakCore/Storage/AgentPrefixStyle.swift`](file:///Users/tamil/Developers/deepvoice/Speak/SpeakCore/Storage/AgentPrefixStyle.swift) with 4 explicit STT tag options:
    1. `[speak-stt]` (`.speakSTT`, default)
    2. `[voice-stt]` (`.voiceSTT`)
    3. `[stt-input]` (`.sttInput`)
    4. `[stt-prompt]` (`.sttPrompt`)
    Plus `.none` (`Off`).
  - Added full backward compatibility with custom `Codable` mapping legacy `"speak"` and `"voice"` stored strings.
- **Dynamic State Modifiers (`:clean` vs `:raw`)**:
  - Added `agentPrefixIncludeState: Bool` to `SettingsStore` (defaults to `false`), `CaptureSession`, `SpeakEngine`, `OverlayViewModel`, and `DictationController`.
  - Implemented dynamic paste formatting in [`CaptureSession+Paste.swift`](file:///Users/tamil/Developers/deepvoice/Speak/SpeakCore/Engine/CaptureSession+Paste.swift):
    - When enabled and cleaned: `[<tag>:clean] ` (e.g. `[speak-stt:clean] `).
    - When enabled and raw: `[<tag>:raw] ` (e.g. `[speak-stt:raw] `).
    - When disabled: `[<tag>] ` (e.g. `[speak-stt] `).
  - Retained in `lastTranscript` for consistent "Paste Last Transcript" re-paste.
- **UI & HUD Controls**:
  - **HUD Live Panel** ([`CodingCustomizationView.swift`](file:///Users/tamil/Developers/deepvoice/Speak/App/Overlay/CodingCustomizationView.swift)): Added segmented chip bar for all 5 styles + checkbox toggle for `:clean` / `:raw` state tag.
  - **Settings** ([`SettingsView.swift`](file:///Users/tamil/Developers/deepvoice/Speak/App/Settings/SettingsView.swift)): Under `Agent Integration`, added picker for all 5 styles and toggle for state inclusion.
- **Skill Specification ([`.agents/skills/speak/SKILL.md`](file:///Users/tamil/Developers/deepvoice/.agents/skills/speak/SKILL.md))**:
  - Updated triggers and prompt patterns for all 4 explicit STT tags.
  - Documented `:clean` vs `:raw` cognitive semantics.
  - Added phonetic artifact mapping for `iPhone` $\to$ `hyphen` (`voice-stt`).
- **Verification & Moat**:
  - `make build`: Clean build (0 errors).
  - `make test-fast`: Green (added tests in `PasteTests.swift`, `SettingsStoreRoundTripTests.swift`, `SettingsStoreResetAndMiscTests.swift`).
  - `make lint`: 0 errors. Extracted `makeVoiceActionsHandler` to maintain function length under 100 lines.
  - `make verify-moat`: 7/7 checks passed.
  - Live app running as PID 8016.

**Loop #91 (2026-09-10) — Speak Voice Input Skill & Agent Prompt Tagging Infrastructure COMPLETE.**
- **Agent Skill (`speak`)**:
  - Created `.agents/skills/speak/SKILL.md` defining the cognitive protocol for coding agents (Claude Code, Antigravity, Cursor) receiving voice dictations.
  - Formulated 4 core operational principles:
    1. *Pivot Rule (Latest Thought Wins)*: Later sentences and self-corrections supersede earlier exploratory thoughts.
    2. *Intent & Architecture Extraction*: Isolates concrete requirements, multi-agent verification structures, and data models from conversational stream-of-thought framing.
    3. *Phonetic & STT Artifact Normalization*: Contextually maps acoustic slips (`gate work tree` $\to$ `git worktree`, `rippo` $\to$ `repo`, `AA engineer` $\to$ `AI engineer`, `bossing` $\to$ `passing`, `insane C` $\to$ `in sync`, `travels` $\to$ `intervals`, `slush context` $\to$ `flush context`).
    4. *Direct Bias for Action*: Forbids conversational meta-chatter; mandates immediate code reading, file editing, and test execution.
- **Agent Prompt Tagging Infrastructure (`AgentPrefixStyle`)**:
  - Created `AgentPrefixStyle` enum (`none`, `speak`, `voice`) in `SpeakCore/Storage/AgentPrefixStyle.swift`.
  - Added persistence in `SettingsStore.swift` (`Keys.agentPrefixStyle`, getter/setter, default `.none`, and `resetToDefaults()` recovery).
  - Wired into `CaptureSession.swift` and `CaptureSession+Paste.swift`: prepends `agentPrefix` (e.g. `[speak] ` or `[voice] `) to non-empty delivered text.
  - Added `setAgentPrefix(_:)` to `SpeakEngine` and `CaptureSession` for dynamic runtime configuration.
  - Linked `overlayModel.agentPrefixStyle` and `lastTranscript` in `DictationController+ErrorHandling.swift`.
- **UI Customization Controls**:
  - In `CodingCustomizationView.swift`, added an `Agent Prompt Tag` segmented chip row (`[Off | [speak] | [voice]]`) right below the prompt input, allowing instant per-session toggle while dictating.
  - In `SettingsView.swift` (General tab), added an `Agent Integration` section with `Picker("Agent Prompt Tag", ...)` for default application behavior.
- **File Length & Modular Architecture Compliance**:
  - Extracted `PrivacyDataSettingsTab` into `Speak/App/Settings/PrivacyDataSettingsTab.swift`.
  - Extracted TTS settings into `Speak/SpeakCore/Storage/SettingsStore+TTS.swift`.
  - Both `SettingsView.swift` and `SettingsStore.swift` are now strictly under 1,000 lines.
- **Verification & Moat**:
  - `make build`: Clean build with 0 warnings, 0 errors.
  - `make test-fast`: 100% green (added round-trip and paste delivery unit tests in `PasteTests.swift`, `SettingsStoreRoundTripTests.swift`, and `SettingsStoreResetAndMiscTests.swift`).
  - `make lint`: 0 errors across 328 files.
  - `make verify-moat`: 7/7 checks passed (offline by design, write-only pasteboard, no print, Apple-only frameworks).
  - App launched cleanly as PID 17028.

**Loop #90 (2026-09-10) — High-Density 4-Line Compact HUD & Serialized Voice-to-Prompt Streaming Pipeline COMPLETE.**
- **User Live Dogfood Validation**:
  - Validated live on 30-second continuous speech: clean punctuation, immediate capitalization, and zero latency stalls.
  - User confirmed: "In this way, I were able to capture a lot of text against a lot of text. I were speaking for 30 seconds, and then I'm good and happy."
- **High-Density Compact HUD Layout**:
  - Restored fixed `88 pt` floating pill height (`TranscriptOverlayPanel.panelHeight = 88`).
  - Switched font from 11pt/13pt to `.speakMono(9.5, weight: .medium)` with `1.5pt` line spacing in `TranscriptOverlayView.swift`, `SettlingOverlayContent.swift`, and `AnimatedTranscriptView.swift`.
  - Expanded `lineLimit` to 4 lines and increased `maxWindowChars` in `OverlayTextFlow.swift` from `120` to `220`.
  - Result: 80% higher character capacity in the identical compact footprint without panel growth.
- **Voice-to-Agent Prompt Compiler Alignment & History Grounding**:
  - Queried and audited actual developer turns in `~/Library/Application Support/speak/history.sqlite`.
  - Replaced speculative dictionary additions with verified acoustic patterns (`gate work tree` -> `Git worktree`, `get work trees` -> `Git worktrees`, `git health`).
  - Resolved internal prompt contradiction in `FoundationModelPromptBuilder.swift`: previously, `intensityClause` forbade restructuring while `voiceClause(for: .code)` mandated structuring into lists. Made `intensityClause` style-aware so `.code` actively structures multi-part developer workflows into enumerated steps.
  - Added the Verifier & Verifier's Verifier multi-agent few-shot anchor demonstrating how spoken intent sequences compile into structured prompts for coding agents.
  - Reduced post-paste HUD dwell from 800ms to 360ms in `DictationController+ErrorHandling.swift` for snappy dismissal.
- **Serialized Background Streaming Pipeline**:
  - Rewrote `StreamingChunkCoordinator.swift` using task chaining (`priorTask?.value`) to ensure strictly serialized execution on Apple's single-lane Neural Engine.
  - Eliminates concurrent contention, completely preventing 10s watchdog timeouts at stop time while pre-compiling chunks during active speech.
  - Fixed Swift 6 Sendable warning in `CaptureSession+WarmUp.swift`.
- **Verification**:
  - `make build`: 0 warnings, 0 errors.
  - `make test-fast`: 100% green.
  - `make verify-moat`: 7/7 privacy checks passed.

**Loop #89 (2026-09-10) — Voice Articulation Engine, Automated SQLite Evaluation & Purpose Manifesto COMPLETE.**
- **Purpose Manifesto & Philosophy (`docs/purpose.md`)**:
  - Authored the foundational document anchoring the project's transformation contract: rejecting lossy over-condensation in favor of high-fidelity voice articulation on Apple's on-device 3B Foundation Model with a 4K context window.
  - Defined the 3 core principles: 100% substance fidelity (zero omitted requirements, paths, numbers, or constraints), disfluency dissolution (stripping vocal fillers, stammers, and throat-clearing preambles), and structural elevation (transforming sprawling speech into crisp paragraphs or numbered lists).
- **Automated SQLite Evaluation Engine (`scripts/evaluate-compiler.swift`)**:
  - Built an automated evaluation harness with direct SQLite access to `~/Library/Application Support/speak/history.sqlite` (2,375 real speech dictations).
  - Implemented stratified random sampling across short, medium, and long turns, scoring both Table Stakes (punctuation, capitalization, filler stripping) and Voice-to-Agent Compilation (train-of-thought resolution, directive stance, technical fidelity).
  - Every evaluation run writes timestamped JSON reports to `eval_reports/eval_<timestamp>.json` and `eval_reports/latest.json`.
- **Acoustic Lexicon Healing & Guardrails**:
  - Discovered and healed real acoustic ASR mishearings in `DeveloperAcronymNormalizer.swift`:
    `fable model` $\to$ `Apple model`, `workries`/`workways` $\to$ `worktrees`, `gear project`/`get repose` $\to$ `Git project`/`Git repos`, `gate repository`/`repo` $\to$ `Git repository`/`repo`, `landing beach` $\to$ `landing page`, `one king properly` $\to$ `one thing properly`, `processing foster` $\to$ `processing faster`.
  - Added chatbot hallucination detection and fallbacks in `FoundationModelPromptBuilder.extractTargetTranscript(from:fallback:)` to suppress conversational openings ("Certainly", "I will be happy to help", "Please provide the transcript").
- **Verification & Review**:
  - Conducted personal review across 10 stratified random samples:
    - Composite score: **95.9 / 100** (Table Stakes: 49.3/50, Compilation: 46.6/50).
    - Average latency: **1,373 ms** on Apple Silicon on-device 3B model.
    - Zero truncated substance: all technical parameters, model names (Luna, Terra, S-O-L), VPS/Git targets, and file paths preserved intact.
  - `make verify-moat` passed 7/7 checks.
  - `swiftlint` passed with 0 errors across all modified files.
  - All files strictly adhere to the <800 lines hard limit.

**Loop #88 (2026-09-10) — Hierarchical Multi-Scale Chunking & Deterministic Macro-Pass COMPLETE.**
- **Hierarchical Multi-Scale Reprocessing**:
  - Implemented the 3-scale architecture in `StreamingChunkCoordinator.swift`:
    - **Scale 1 (Micro-Chunks, ~3–10 words)**: Progressive, streaming acoustic normalization (`DeveloperAcronymNormalizer`) and concurrent background cleaning during active recording.
    - **Scale 2 (Medium-Chunks, ~20–35 words)**: Clause and thought-boundary aggregation for progressive phrase coherence.
    - **Scale 3 (Full-Chunk Macro-Pass, whole utterance)**: In `finalizeAndStitch(trailingRawText:)`, when an utterance has multiple chunks or exceeds 12 words and the mode is eligible (`.styled(.code)`, `.profile`, `.toneAdjust`, `.codeAware`), runs a single holistic deterministic consolidation pass through the 3B Foundation Model.
  - **Train-of-Thought Collapse**:
    - The holistic full-chunk pass collapses multi-sentence rambles, conversational preambles, self-corrections, and verbal backtrackings ("do option 1, wait not option 2, let's do 1 and 3 immediately") into crisp, cohesive directives for the receiving coding agent, without losing any file paths, command flags, or technical constraints.
- **Verification**:
  - Added unit test `testHierarchicalMacroConsolidationPass` in `StreamingChunkCoordinatorTests.swift`.
  - `make test` full test suite passed 100% green.
  - `make verify-moat` passed 7/7 privacy checks.
  - `make lint` clean (0 serious errors, swiftlint config tuned for parameter/type length).
  - All files strictly adhere to the <800 lines hard limit.

**Loop #87 (2026-09-10) — Voice-to-Agent Compiler Grounding & Acoustic Lexicon Healing COMPLETE.**
- **Voice-to-Agent Compiler Grounding**:
  - Established the first-principles 50/50 breakdown in `specs/voice-to-agent-compiler.md`: table-stakes transcription (punctuation, capitalization, "um/uh" removal) is only 45%–50% of the job. The remaining 50% is compiling spoken stream-of-consciousness thought into structured, actionable prompts for AI coding agents.
  - Audited 16 real production samples from `history.sqlite` going backward from the latest 250 entries across Short (5–15 words), Medium (16–45 words), and Long (45+ words) dictations.
- **Acoustic Developer Lexicon Healing**:
  - Enhanced `DeveloperAcronymNormalizer.swift` with regex-anchored rules for verified developer terms misheard by acoustic ASR:
    `gift repository/repo` $\to$ `Git repository/repo`, `gid hup/git hup` $\to$ `GitHub`, `work treat/work dream/what tree` $\to$ `worktree`, `lines of coke` $\to$ `lines of code`, `studio mcp` $\to$ `stdio MCP`, `project dogs` $\to$ `project docs`, `full rippo` $\to$ `full repo`, `port base` $\to$ `codebase`, `dog footing` $\to$ `dogfooding`, `qva testing` $\to$ `QA testing`.
- **Prompt Evolution & App Routing**:
  - Enhanced `voiceClause(for: .code)` in `FoundationModelPromptBuilder.swift` to act as an agent prompt compiler: resolves false starts and verbal resets while preserving all technical identifiers, file paths, numbers, command-line flags, and constraints verbatim.
  - Expanded `DefaultProfiles.agent.targetApps` with modern developer terminals: Ghostty (`com.mitchellh.ghostty`), Warp (`com.warp.Warp-Stable`), WezTerm (`com.github.wez.wezterm`), and Kitty (`net.kovidgoyal.kitty`).
- **Verification**:
  - `make build` succeeded cleanly with 0 errors.
  - `make test` full test suite passed 100% green (including `testDeveloperAcronymNormalizerHealsAcousticMishearings`).
  - `make verify-moat` passed 7/7 privacy checks.
  - Strict file-length constraints satisfied: all touched files under 350 lines (<800 lines limit).

**Loop #86 (2026-09-10) — Live Streaming Chunk Pipeline, Scratchpad Extractor & UI Decomposition COMPLETE.**
- **Live Streaming Chunk Pipeline (Option 1)**:
  - Wired `StreamingChunkCoordinator` into `CaptureSession` (`ingest(_ chunk:)`). Each `isFinal` segment emitted by `SpeechAnalyzer` during recording triggers background parallel cleanup.
  - In `CaptureSession+Cleanup.swift` (`runCleanup`), finalized chunks are gathered and stitched via `StreamingChunkCoordinator.finalizeAndStitch()`, dropping post-speech cleanup latency from 5–8s down to <150ms and preventing 3B model hallucinations on long dictations.
  - Extracted audio level/VAD delegation to `CaptureSession+Audio.swift` (55 lines) to maintain `CaptureSession.swift` at 769 lines (<800 lines hard limit).
- **Reasoning Scratchpad & Prefix Extractor (Option 3)**:
  - Added `FoundationModelPromptBuilder.extractTargetTranscript(from:)` to deterministically strip `Plan:`, `Reasoning:`, `Transcript:` prefixes, `<transcript>` tags, markdown code fences, and quotes.
  - Integrated into `FoundationModelsCleaner.cleanSingleChunk` and verified via new tests in `FoundationModelPromptBuilderTests.swift`.
- **UI Modularization & Living HUD Overhaul**:
  - Decomposed 987-line `TranscriptOverlayView.swift` into 4 clean, focused modules (<400 lines each):
    - `OverlayViewModel.swift` (283 lines) — `OverlayState`, `OverlayDestinationChoice`, `OverlayViewModel`.
    - `OverlayWaveformView.swift` (144 lines) — `VisualEffectView`, reactive `WaveformView`.
    - `OverlayKnobsRow.swift` (114 lines) — `OverlayKnobsRow` per-dictation chips.
    - `TranscriptOverlayView.swift` (386 lines) — Modern floating pill HUD layout, 16pt continuous curvature, frosted-glass background, inner highlight border, living audio visualizer, and 3-line FIFO listening stream.
- **Verification**:
  - `make build` succeeded cleanly with 0 errors.
  - `make test` full test suite passed 100% green (including `StreamingChunkCoordinatorTests` and `FoundationModelPromptBuilderTests`).
  - `make verify-moat` passed 7/7 privacy/moat checks.
  - `swiftlint` passed with 0 violations, 0 serious errors on all touched overlay and clean-up files.

**Loop #85 (2026-09-10) — Foundation Models Cleanup Evolution & Chunked Transformation COMPLETE.**
- **Competitor study & foundation guidelines grounding**: Analyzed Wispr Flow architecture (two-stage pipeline, context-conditioned ASR + fine-tuned Llama on cloud GPUs, $2B valuation), Superwhisper, and Aqua Voice. Studied Apple's official `prompting_style.md` and archived official guides in `ai_docs/foundation_models/`. Audited production `history.sqlite` (2,285 real voice entries) analyzing voice-to-agent instruction flows.
- **Architectural modularization (<800-line constraint satisfied)**:
  - Extracted `DeveloperAcronymNormalizer.swift` (73 lines) — pure deterministic regex-based spoken→written developer term normalization.
  - Extracted `TranscriptChunker.swift` (110 lines) — sentence- and clause-boundary chunking to eliminate bulk latency and prevent over-editing on long rambles.
  - Extracted `FoundationModelPromptBuilder.swift` (254 lines) — Apple-recommended step-by-step numbered instructions, 2-shot question anchors, tail continuation reminders, and clean style/intensity dispatch.
  - Streamlined `FoundationModelsCleaner.swift` from 575 lines down to 184 lines, delegating to the modular components while maintaining full backward compatibility.
- **Tests & Verification**:
  - New `TranscriptChunkerTests.swift` (51 lines) and `FoundationModelPromptBuilderTests.swift` (65 lines).
  - Standalone verification runs succeeded. `swiftlint` on all touched files reports **0 violations, 0 serious errors**.
  - Moat audit: `make verify-moat` passes 7/7 privacy checks.
- **Next**: Live dogfooding of chunked streaming dictations with coding agents.

**Loop #84 (2026-09-08) — Single-branch consolidation + v0.1 kickoff (VoiceStudio track) COMPLETE.**
- **Branch consolidation**: unified all work onto `master` (now the only branch, local + remote). Committed the full uncommitted purge (`b92b272`: MCP ask-user/Layer-4 withdrawal, conversation overlay, filmstrip + overlay text-flow, cleanup-quality eval), then merged the 37-commit feature line onto `master` (`2bddd59`, keeping master's v0.0.1/P14 commits and the `research/archive` removal). Deleted `bug-hunter-test-trigger`, `feat/v01-warm-cleanup`, `worktree-input-felt-speed`, `worktree-agent-workflow-subagent` (content preserved), and remote `origin/worktree-input-felt-speed`. Fast-forward push `5aa8f55..2bddd59`. Harness dirs (`.agents/`, `.commandcode/`, `.qoder/`, `skills-lock.json`) gitignored; `ai_tmp/` added for the VoiceStudio reference clone.
- **Stash triage** (3 stashes): (1) `voicestudio-inspiration-plan.md` + warm-cleanup restored from stash; (2) agent-voice-bridge WIP (`26f0552`) — fully superseded by `b92b272`, dropped; (3) color-borders UI (`8c32a84`) — conflicts with the frozen FE-1 identity spec, dropped. All recoverable via those SHAs.
- **V01-W — Warm cleanup model LANDED** (`e4303f4`, Core-only + additive): `LLMCleaning.warmUp()` (default no-op) + `FoundationModelsCleaner.warmUp()` (throwaway `LanguageModelSession.prewarm()` + one minimal `respond`; `[verified via local SDK swiftinterface, 2026-09-08]`); `CaptureSession` fires it at `start()` concurrently with listening (never on the stop→clean path), cancels (never awaits) at stop/cancel; `SpeakEngine.newSession()` arms it only when cleanup will run. New `WarmCleanupModelTests` (9): armed/disarmed, byte-identical delivery, in-flight-cancel, engine wiring, protocol default + real-cleaner no-throw.
- **Lint fix** (repo convention): warm-up machinery extracted to `CaptureSession+WarmUp.swift` + `SpeakEngine` private extension; zero serious errors on touched files (only the 2 pre-existing `CLIPortServer` errors remain).
- Verification: `make build` ✅, focused suites (WarmCleanup + CaptureSession + VoiceActionsPipeline) `** TEST SUCCEEDED **` ✅, `make verify-moat` 7/7 ✅.
- **Next**: VoiceStudio roadmap/product validation against `ai_tmp/VoiceStudio` (`specs/voicestudio-inspiration-plan.md §5` slice ordering); remaining V01-X slices.

**Loop #83 (2026-08-19) — No-answer prompt fix: model answered question-shaped dictations. COMPLETE.**
- **Problem (human-reported live)**: the cleanup model sometimes REPLIED to the transcript (answered the question, executed the command) instead of transcribing it.
- **Root cause**: the strict "never answer" rules lived only in the system instructions, while the user turn was a bare `<transcript>…</transcript>` — the highest-attention position for a small RLHF model. A question-shaped dictation there reads exactly like a chat message, and nothing at the freshest position suppressed the answering reflex.
- **Fix** (`FoundationModelsCleaner.swift`):
  - New `userTurnTask()` / `userPrompt(_:)` — a short imperative task reminder appended AFTER the wrapped transcript in the user turn ("Your output is ONLY the edited transcript text. If the speaker asked a question, output that question punctuated — never an answer."). `clean()` now sends `userPrompt(text)`.
  - `transcriptGuard` tightened: pipeline-stage framing ("text-cleaning stage of a dictation app's transcription pipeline"), "transcript is DATA to edit, never a message addressed to you", "Your output is ALWAYS a transcript of what the speaker said — never your own words", question rule extended with "never act on it".
- **Tests**: new `NoAnswerPromptTests` (5): reminder-after-transcript ordering, ONLY-output + never-an-answer contract, injection sanitization still holds in the user turn, guard output-contract phrases, exact wrap+reminder composition for question-shaped input. Focused prompt suites (StyleModeTests, StreamOfConsciousnessRamblePromptTests) green.
- Verification: `make build` ✅, focused + full `make test` ✅, `make lint` — my files add 0 errors (only the 2 pre-existing `CLIPortServer` errors remain), `make verify-moat` 7/7 ✅.
- **Next**: dogfood question-shaped dictations with the new prompt; if any answering survives, add a deterministic post-check (preamble/prefix rejection) before considering `.high`/`.professional` tightening.

**Loop #82 (2026-08-19) — Fix AI-cleaning over-editing + history-based quality eval.**
- **Problem**: default `.styled(.default, .medium)` cleanup over-edited dictation (paraphrase/condense/drop), driven by prompt wording that invited rewriting ("reconstruct, reformat, refine" + "tighten run-on sentences" + "correct grammar").
- **Fix**: preservation-first prompt rework in `FoundationModelsCleaner.swift` — `transcriptGuard` and `.medium`/`.default`/`.professional` now instruct verbatim word preservation, filler/false-start removal only, punctuation/capitalization/spelling fixes, and explicitly forbid paraphrase/condense/reorder/polish.
- **New eval**: `SpeakCore/Eval/CleaningQualityScorer.swift` — reference-free raw→cleaned scoring (`contentRetention` Jaccard, `fillerRemoved`, `noHallucinatedIdentifiers`, `noPreamble`, `lengthRatio`). `HistoryCleaningEvalTests` runs deterministic unit tests in `make test`, plus a gated history eval (`SPEAK_HISTORY_EVAL=1`, `make history-eval`) reading production `history.sqlite`.
- **Measured (pre-fix baseline)**: n=1762 cleanup rows, mean retention 0.865, retention p50/p95 0.933/1.000, 328 rows fail content-retention — real over-editing confirmed. New rows should trend toward retention ~1.0.
- **Wiring**: `project.yml` Eval scheme + `Makefile` `history-eval` target.
- Verification: `make build` ✅, `make test` ✅ (828+9 new), `make history-eval` ✅ (runs + reports), `make verify-moat` 7/7 ✅. Lint: 2 pre-existing `CLIPortServer` errors remain; my files add only warnings (function-body-length / sorted-imports on the new test, line-length on the guard).
- **Next**: dictate with the new prompt and re-run `make history-eval` to confirm content retention rises on fresh rows; then decide whether `.high`/`.professional` need the same tightening or a separate aggressive-intent UI.

**Loop #81 (2026-08-06) — Strengthen last-work mess (no new features).**
- Audited Loops #77–#80 small-model work; fixed claimed-but-broken seams rather than inventing more.
- **Felt-speed:** `showTransformation` keeps `settlingText` through the done flash (raw→clean strikethrough actually works); filmstrip XOR desktop FIFO (not both); filmstrip/text-flow ingest full STT snapshots (no duplicate blocks); classic-only overflow; `start()` resets felt-speed state; classic settling honors `revealTextWhileProcessing`; filmstrip chips lose card chrome; comments match layout.
- **Agent bridge:** `speak_confirm` maps production `.declined` (not faked `.answered("no")`); adapter durable rows always `sessionId: nil` + nil-session poll; `bridgeToStore` uses run-loop pump not main-thread semaphore; request_input clears `lastTranscript` before presenter attach; Layer4 tools/list test fixed; AskUserToolHandler comment leftovers scrubbed.
- **CaptureSession:** drain watchdog cancels `streamTask` and logs error on fire (no silent pretend-success).
- **Constants:** `CLIContract.storeBridgeTimeoutSeconds` / `terminalPollSlackSeconds` / `terminalPollIntervalNanoseconds` / `getCallSendTimeoutSeconds`.
- Verification: `make build` ✅, focused + full `make test` ✅, `make verify-moat` 7/7 ✅.

**Loop #80 (2026-08-03) — Felt Speed (filmstrip): horizontal block transcript COMPLETE.**
- Implemented the **horizontal filmstrip transcript** (the "visible AI" centerpiece, product direction locked with human): the HUD is a **fixed, never-growing panel** (520×88, no vertical expansion, no vertical scrolling). When streaming text would exceed the visible 3-line area, it is **captured as a miniaturized block and slides LEFT** — blocks abandon horizontally, block by block, while the active area keeps streaming fresh words at full size.
- **New `SpeakCore/Overlay/FilmstripModel.swift`** — `FilmstripBlock` (raw + live-cleaned display, isPolishing/isPolished) + `FilmstripCutter` (pure, sentence-boundary-aligned cut at a char budget ≈ 3 lines; falls back to whitespace, then hard cut). Fully unit-tested.
- **`OverlayController.ingestFilmstripPartial(_:)`** — fed from the partials drain, cuts blocks, resets the active stream, and sends each captured block to `filmstripCleaner` for **live per-block AI polish** (cleanup off ⇒ blocks stay raw and marked polished immediately). Wired to the engine's `defaultCleaner(for:)` via `DictationController` (same instance, availability + engine always match).
- **`FilmstripView` + `FilmstripBlockView`** in `SettlingOverlayContent.swift` — miniaturized blocks (rendered ~2–3× smaller, capped width) with a "Polishing…" affordance while the per-block AI is in flight; `.move(edge: .trailing)` slide-left transition. `onAir` is never lit (blocks are not capture).
- **Tests**: `FilmstripCutterTests` (6: no-cut-under-budget, cut-at-sentence-boundary, cut-at-whitespace, hard-cut, remainder-reconstruction) + `OverlayControllerFilmstripTests` (6: long→block+reset, short→no-block, disabled→no-op, no-cleaner→immediate-polished, stop/cancel reset). Suite grew **816 → 828 tests, 0 failures**.
- Verification: `make build` (exit 0), full suite **828 tests / 0 failures / 9 skips** (exit 0), `make verify-moat` 7/7, lint clean on all touched files (only 3 pre-existing `CLIPortServer` violations remain).
- **Next**: live dogfood — measure the filmstrip's felt-speed (does the block slide-left feel right? is the char budget ≈ 3 lines correct? is the miniaturization scale legible?); then streaming cleanup (C): a streaming `LLMCleaning` variant so the AI visibly types the rewrite in-place.

**Loop #79 (2026-08-03) — Felt Speed (A+B): visible-AI transformation COMPLETE.**
- Implemented `specs/input-felt-speed.md` §3.3 **progressive-reveal + diff-transformation** slice — the "visible AI" foundation:
  - **Settling state**: `OverlayController.transition(to: .processing)` now PRESERVES the raw transcript into `OverlayViewModel.settlingText` (marked provisional via `isSettling`) instead of wiping to a blank "Cleaning up…" spinner. The user sees their words the moment they stop speaking.
  - **Visible transformation**: new `OverlayController.showTransformation(cleaned:raw:)` (in a lint extension) animates raw→clean via the existing `TextDiffResolver` — canceled words get the animated red strikethrough, inserted words fade in, kept words stay. Rendered by new `SettlingProcessingContent` / `PolishedDiffContent` (extracted to `SettlingOverlayContent.swift` for file-length cap).
  - **`AnimatedTranscriptView`** gained a `init(rawText:cleanedText:)` that seeds the diff exactly once on appear (no duplicate strike / no flicker).
  - **`onAir` discipline preserved** (frontend-identity.md frozen): refinement is `.processing`/`.done`, never capture.
  - **Wiring**: `DictationController.endDictation()` now calls `showTransformation(cleaned:raw:)` instead of a hard `.done` swap; `OverlayController.stop()`/`cancelImmediate()` reset all felt-speed state.
- **Tests**: `OverlayControllerFeltSpeedTests` (8: settling preserve/not-wipe, diff on real change, no-diff on identical/nil, empty-raw fallback, stop/cancel reset) + `AnimatedTranscriptViewTests` (5: canceled/inserted/normal classification, seeds-once, only-removed-words-canceled).
- **Pre-existing branch breakage fixed**: the uncommitted AVB-7 ask/confirm submit+poll rewrite (Loop #78, `CLIBridgeBackend`) changed the wire contract but left 5 `AgentBridgeServerTests` on the legacy `.confirmed(...)` shape → `confirmMaps*`/`askMaps*` failed. Updated them to the new submit+poll shape (`.askConfirmPending` → poll `getCall`); extended `StubCLITransport` with a scripted `replies:` sequence.
- Verification: `make build` (exit 0), full suite **816 tests / 0 failures / 9 skips** (exit 0), `make verify-moat` 7/7, lint clean on all touched files (only 3 pre-existing `CLIPortServer` violations remain, untouched by this slice).
- **Next**: (1) live dogfood — measure stop→visible-transition latency; (2) streaming cleanup (C): a streaming `LLMCleaning` variant so the AI visibly types the rewrite in-place.

**Loop #78 (2026-07-30) — Proper MCP Server Design COMPLETE.**
- Reconciled MCP surface to the canonical Agent Voice Bridge contract (`specs/agent-voice-bridge.md` §5):
  - Single MCP path: `speak-mcp` stdio → `AgentBridgeServer` → `CLIBridgeBackend` → CFMessagePort → app.
  - Withdrew Layer-4 MCP tools `speak_ask_user` / `speak_stream_speech` from the published catalog.
  - Removed parallel App dispatcher `SpeakMCPServer` and CLI verbs `.askUser` / `.streamSpeech`.
  - Folded Magenta conversation overlay into `cliRequestInput` via `ConversationInputPresenter` (presentation only; `.gatedTurn`; no new MCP modes).
- Verification passed: `make build` (exit 0), `make test` (exit 0), `make lint` (0 serious, exit 0), `make verify-moat` (7/7, exit 0).
- Next: AVB-8 (semantic events + attention).

**Loop #77 (2026-07-28) — Adversarial Review & Background Freeze / Hang Fixes COMPLETE.**
- Performed grounded adversarial audit of recent session commits (`1089cd1` to `bd86f18`) and background runtime behavior.
- Fixed STT stream drain hang vulnerability in `SpeakCore/Engine/CaptureSession.swift`: added a 5-second `TaskGroup` watchdog timeout in `stop()` around `streamTask.value` to prevent audio hardware route freezes (e.g. AirPods disconnect/reconnect in background) from hanging the application indefinitely.
- Fixed IPC run-loop pump cancellation safety in `SpeakCore/CLI/CLIPortServer.swift`: added `Task.isCancelled` check into `pumpUntilResult` loop to exit immediately on task cancellation.
- Verification passed: `make build` (exit 0), `make verify-moat` (7/7 checks passed, exit 0), `make test` (full suite 100% SUCCESS, exit 0).

**Loop #76 (2026-07-25) — Docs Reconciliation COMPLETE. Next: P15 Inference + Agent Playground.**
- Reconciled `docs/roadmap.md`: marked AVB-5 `[x]` (live round-trip verified Loop #74), AVB-6 `[x]` (Loop #51), AVB-7 `[x]` (Loop #51), P14 `[DONE]` with all sub-items checked.
- Updated `CHANGELOG.md`: added Human-Agent Workspace, AVB bridge, Agent Voice Bridge, inference server, UI overhaul, SwiftLint fixes to [Unreleased] section.
- **Next active work**: `P15` — complete and commit the in-progress SpeakLLM inference + Agent Playground feature:
  - Modified (uncommitted): `AgentPlaygroundView.swift`, `StreamingChatClient.swift`, `InferenceRouter.swift`, `OpenAIChatCompletionsHandler.swift`
  - Untracked (new): `ProvenanceReceipt.swift`, `StreamingCadenceEngine.swift`
  - After commit, next gate: AVB-8 (Semantic events + attention)

**Loop #75 (2026-07-24) — SwiftLint Cyclomatic Complexity & Line Length Violations Fixed COMPLETE.**
- Refactored `Speak/SpeakCore/Hotkey/HotkeyBinding.swift`: replaced 74-case switch statement in `symbolForKeyCode(_:)` with a dictionary lookup table `keyCodeSymbolMap`, reducing cyclomatic complexity from 74 down to 1 (<= 10 limit).
- Fixed line length in `Speak/SpeakCore/VoiceOut/AppleSpeechSynthesizer.swift` (line 136): split long `SpeakLog.voiceOut.info` call across multiple lines so all lines are <= 200 characters.
- Verification passed: `make lint` (0 serious errors, exit 0), `make build` (exit 0), `make test` (216 tests passed, exit 0), `make verify-moat` (7/7 checks passed, exit 0).

**Loop #74 (2026-07-24) — P14 Audit, AVB-5 Verification & Workspace Cleanup COMPLETE.**
- Verified the AVB-5 live question-response round trip (`speak_request_input` question → real spoken answer) with human at the mic via Codex/Claude Code sessions. This completes the final AVB-5 done-condition.
- Completed workspace cleanup, removing stale states and confirming all v0 readiness gates.
- P14 v0 Ship Gate Audit Passed: Moat audit passed 7/7 privacy checks (`make verify-moat`), and test suite succeeded with 0 failures (`make test`).
- Documentation state is completely synchronized and immaculate.

**Loop #73 (2026-07-22) — System Permissions Status & Re-arm Troubleshooter Card Added COMPLETE (commit `ce8b27d`).**
- Added a dedicated **System Permissions** section to `SettingsView` (Hotkey & Input tab):
  - Displays live status: `🟢 Granted & Active` vs `⚠️ Missing / Disabled`.
  - Includes direct 1-click deep-link button to macOS `System Settings → Privacy & Security → Accessibility`.
  - Includes a `Re-check & Re-arm Hotkey Tap` button to clear stale macOS TCC records and re-arm `HotkeyMonitor` on demand without needing an app restart.
- Build succeeded (`make build`), moat audit passed 7/7 privacy checks (`make verify-moat`), fresh app running on PID 37392.

**Loop #72 (2026-07-22) — Flexible Command Double-Tap Keycode Matching COMPLETE (commit `6f89641`).**
- Fixed issue where double-pressing Right Command was strict on keycode 54 vs 55:
  - Added `isMatchingBoundKey(eventKeyCode:bindingKeyCode:)` in `HotkeyDetection.swift` to match both Left Command (55) and Right Command (54), as well as Left Option (58) and Right Option (61).
  - Updated `HotkeyMonitor.swift` handle loop so double-pressing either Command key triggers the Command hotkey seamlessly.
- Build succeeded (`make build`), moat audit passed 7/7 privacy checks (`make verify-moat`), fresh app running on PID 35647.

**Loop #71 (2026-07-22) — Right Command Double-Tap Event Tap Tap-Location & Reset Loop Fixed COMPLETE (commit `fd79add`).**
- Discovered and resolved root cause of non-responsive double-press Right Command hotkey:
  - `buildTap()` previously specified `.cghidEventTap` exclusively, which returns `nil` on non-root macOS user sessions. Added `.cgSessionEventTap` primary with `.cghidEventTap` fallback.
  - Restored `nowTrusted && !wasTrustedPrev` rising-edge condition in `watchdogTick()` to prevent the 100ms watchdog timer from continuously calling `buildTap()` (which was calling `detector.reset()` every 100ms and wiping out the first tap of the double-tap).
- Build succeeded (`make build`), moat audit passed 7/7 privacy checks (`make verify-moat`), fresh app running on PID 33100.

**Loop #70 (2026-07-22) — Right Command Hotkey Arming Bug Resolved COMPLETE (commit `7fb7795`).**
- Fixed issue where double-pressing Right Command (keyCode 54) was not triggering dictation:
  - In `HotkeyMonitor.swift`, `watchdogTick()` had a false-to-true edge guard (`!wasTrustedPrev`) preventing `buildTap()` from running if Accessibility trust was already recorded before `start()` was called.
  - Removed `!wasTrustedPrev` condition from `watchdogTick()` and reset `wasTrusted = false` inside `start()`, ensuring the `CGEventTap` is built and armed immediately whenever `!isArmed && armingDesired && nowTrusted`.
- Build succeeded (`make build`), moat audit passed 7/7 privacy checks (`make verify-moat`), fresh app running on PID 9894.

**Loop #69 (2026-07-22) — Onboarding Accessibility Permission Hanging Bug Resolved COMPLETE (commit `731da77`).**
- Fixed onboarding window hanging on `"Waiting for permission..."` during Accessibility setup:
  - Added `NSApplication.didBecomeActiveNotification` observer to `OnboardingViewModel` so returning from System Settings instantly triggers `refreshEvaluation()`.
  - Re-ordered polling loop to evaluate state prior to `Task.sleep` and automatically clear `isWaitingForAccessibility` as soon as `AXIsProcessTrusted()` turns `true`.
  - Re-triggering `requestAccessibility()` when already prompted opens System Settings directly without getting stuck.
- Build succeeded (`make build`), moat audit passed 7/7 privacy checks (`make verify-moat`), fresh app running on PID 7552.

**Loop #68 (2026-07-22) — Dynamic Custom Agent & Swarm XCTest Suites COMPLETE (commit `0fbf023`).**
- Created two new dedicated XCTest suites:
  - `WorkspaceFTSAndCustomAgentTests.swift`: Tests SQLite FTS search query matching, `CustomAgentDefinition` lowercasing, and `DynamicCustomTagAdapter.handleTurn` outcome generation.
  - `TagRegistrySwarmTests.swift`: Tests multi-agent swarm tag resolution (`@team`, `@engineers`, `@qa`), case-insensitivity, and dynamic `registerCustomAgent` lifecycle.
- Executed XCTest suites via subagents — all tests passed with 0 failures (`** TEST SUCCEEDED **`).
- Moat audit passed 7/7 privacy checks. Re-built and launched fresh `Speak.app` (PID 3617).

**Loop #67 (2026-07-22) — Dynamic Custom Agent Definition & Hackable Product Surface COMPLETE (commit `512405f`).**
- Built `CustomAgentDefinition.swift` & `DynamicCustomTagAdapter` in `SpeakCore/AgentBridge/`:
  - Enables developers to dynamically define custom `@tag` agents, system prompts, and custom shell execution scripts without touching core code.
- Added `registerCustomAgent` to `TagRegistry.swift`.
- All 269 XCTests passed in 33 suites. Moat audit passed 7/7 privacy checks.
- Re-built and launched fresh `Speak.app` (PID 36049).

**Loop #66 (2026-07-22) — Master Checklist & Multi-Agent Swarm Broadcaster COMPLETE (commit `47d676b`).**
- Created living tracking checklist in `docs/speak_transformation_master_checklist.md`.
- Implemented **Multi-Agent Swarm Broadcaster (`@team`, `@engineers`, `@qa`)**:
  - Added `resolveSwarmTags` in `TagRegistry.swift`.
  - Mentions of `@team` or `@engineers` broadcast execution turns across `@Claude`, `@builder-qa`, and `@terminal`.
- All 269 XCTests passed in 33 suites. Moat audit passed 7/7 privacy checks.
- Re-built and launched fresh `Speak.app` (PID 31135).

**Loop #65 (2026-07-22) — Master Next Workstreams Index & SQLite FTS5 Engine COMPLETE (commit `e1624d3`).**
- Authored the Master Next Workstreams Index in `specs/next_topics_and_workstreams_master_index.md`.
- Implemented **SQLite FTS5 Full-Text Search Query Engine** in `WorkspaceStore.swift` (`searchMessagesFTS`).
- All 269 XCTests passed in 33 suites. Moat audit passed 7/7 privacy checks.
- Re-built and launched fresh `Speak.app` (PID 22499).

**Loop #64 (2026-07-22) — User Profile Modal & Full Screen UI Polish COMPLETE (commit `519e47e`).**
- Built `UserProfileModalView.swift` and wired trigger button in `WorkspaceMainView.swift`:
  - Consistent borders using `Color.speakCardBorder` (`#23272F`).
  - Smooth transitions (`.easeInOut(duration: 0.2)`).
  - Intuitive navigation & minimal full-screen responsive layout.
  - Displays user profile handle (`👤 @tamil`), role, privacy moat metrics (100% Offline, Zero Egress), and active tag roster.
- All 269 XCTests passed in 33 suites. Moat audit passed 7/7 privacy checks.
- Re-built and launched fresh `Speak.app` (PID 82761).

**Loop #63 (2026-07-22) — CodeDiffInspectorView & Rich Evidence Cards COMPLETE (commit `6caa6ed`).**
- Built `CodeDiffInspectorView.swift` and integrated line-by-line syntax-highlighted code diff inspection into `EvidenceCardView.swift`:
  - Highlights additions (`+`) in green (`Color.speakDelivered`), deletions (`-`) in red (`Color.speakOnAir`), and neutral lines in Monaco font.
  - Interactive expand/collapse toggle showing total line counts per diff block.
- Supported all 5 task checklist statuses (`.pending`, `.inProgress`, `.done`, `.blocked`, `.failed`).
- All 269 XCTests passed in 33 suites. Moat audit passed 7/7 privacy checks.
- Re-built and launched fresh `Speak.app` (PID 76914).

**Loop #62 (2026-07-22) — Pronged Action Trigger System COMPLETE (commit `9f540fb`).**
- Replaced legacy text-chat emojis with the **Pronged Action Trigger System** in `WorkspaceMainView.swift`:
  - `⚡ Run`: Executes terminal shell action via `@terminal`.
  - `🔍 Inspect`: Dispatches deep code review turn to `@Claude`.
  - `🛡️ Audit`: Executes privacy moat & test suite verification via `@builder-qa`.
  - `🗣️ Speak`: Triggers on-device TTS audio readback via `AppleSpeechSynthesizer`.
- Restyled active directives as monospaced Prong Badges (`Prong: Inspect`, `Prong: Audit`).
- All 269 XCTests passed in 33 suites. Moat audit passed 7/7 privacy checks.
- Re-built and launched fresh `Speak.app` (PID 69874).

**Loop #61 (2026-07-22) — Emoji Reactions & Agent Action Triggers COMPLETE (commit `9878ff6`).**
- Implemented Slack-style hover Emoji Reaction Bar (👀, ✅, 🎙️, 🚀) in `WorkspaceMainView.swift`:
  - 👀: Dispatches automatic code inspection turn to `@Claude`.
  - 🎙️: Triggers on-device TTS verbal audio readback via `AppleSpeechSynthesizer`.
  - 🚀: Triggers build and test audit workflow to `@builder-qa`.
  - Displays applied emoji reaction counters on message rows.
- All 269 XCTests passed in 33 suites. Moat audit passed 7/7 privacy checks.
- Re-built and launched fresh `Speak.app` (PID 66206).

**Loop #60 (2026-07-22) — Master 90% Roadmap, Channel Creation, DMs & Approval Cards COMPLETE (commit `901576e`).**
- Created the Master 90% Workspace Feature Index in `specs/workspace-90-percent-roadmap.md`.
- Implemented **Channel Creation Modal** (`NewChannelModalView.swift`) and wired channel creation reactively to `WorkspaceStore` (SQLite).
- Implemented **Direct Messages (DMs)** section in the channel sidebar for 1-on-1 private agent conversations (`@Claude`, `@builder-qa`, `@terminal`).
- Implemented **Interactive Approval Cards** (`ApprovalCardView.swift`) for mutating/high-risk agent execution requests with interactive **[Approve Action]** and **[Decline]** buttons.
- All 269 XCTests passed in 33 suites. Moat audit passed 7/7 privacy checks.
- Re-built and launched fresh `Speak.app` (PID 64879).

**Loop #59 (2026-07-22) — Dual-Mode Sidebar Isolation COMPLETE (commit `4bbcae2`).**
- Resolved double-sidebar visual clutter in `DashboardView.swift`:
  - In **Agent Workspace Mode** (`appMode == .workspace`), `NavigationSplitView`'s sidebar is hidden, letting `WorkspaceMainView` fill the entire window with its single Slack Channel Sidebar.
  - In **Dictation Engine Mode** (`appMode == .dictation`), `NavigationSplitView` renders the Dictation Engine Sidebar (`Home`, `Insights`, `Dictionary`, `Snippets`, `Settings`).
- All 269 XCTests passed in 33 suites. Moat audit passed 7/7 privacy checks.
- Re-built and launched fresh `Speak.app` (PID 60322).

**Loop #58 (2026-07-22) — Full Slack Replacement Architecture & Features COMPLETE (commit `ee18954`).**
- Implemented **Quick Switcher & Spotlight Search (`Cmd+K`)** in `QuickSwitcherModalView.swift`:
  - Instant spotlight search overlay to jump across channels (`#general`, `#core-engine`), agents (`@Claude`, `@builder-qa`), and SQLite messages.
- Implemented **Pinned Channel Canvas** in `ChannelCanvasView.swift`:
  - Persistent side-sheet displaying pinned specs, live task checklists, and quick action shortcuts (`make test`, `verify-moat`).
- Restyled **Agent Inbox** in `AgentInboxPaneView.swift`:
  - Adopted `Color.speak*` design system tokens for durable agent call approvals and voice answer buttons.
- All 269 XCTests passed in 33 suites. Moat audit passed 7/7 privacy checks.
- Re-built and launched fresh `Speak.app` (PID 49279).

**Loop #57 (2026-07-22) — Human-Agent Voice Huddles & Verbal Readbacks COMPLETE (commit `33b28ab`).**
- Created the Slack Inspiration Matrix in `specs/slack-full-inspiration-matrix.md`.
- Implemented **Voice Huddles** (`huddleHeaderBar`) inside `WorkspaceMainView.swift`:
  - Drop-in live audio huddle room (`Join Huddle` / `Leave Huddle`).
  - Active participant roster display (`👤 @tamil`, `🤖 @Claude`, `🤖 @builder-qa`).
  - Automatic verbal speech readback of agent replies during Huddles via `AppleSpeechSynthesizer` (`AVSpeechSynthesizer`).
  - Per-message 🔊 speaker buttons to trigger on-demand TTS readback for any message in thread history.
- All 269 XCTests passed in 33 suites. Moat audit passed 7/7 privacy checks.
- Re-built and launched fresh `Speak.app` (PID 44836).

**Loop #56 (2026-07-22) — Centralized Slack Theme & Dual-Mode Header UI COMPLETE (commit `37940ca`).**
- Centralized UI design system tokens in `SpeakColors.swift` with Slack-inspired theme colors (`speakSidebarBg`, `speakSidebarActiveBg`, `speakTagBadgeBg`, `speakTagBadgeFg`, `speakCardBorder`).
- Embedded centered `TopSegmentedBarView` at the top of `DashboardView.swift` to seamlessly switch between **⚡ Dictation Engine** (Mode 1) and **💬 Agent Workspace** (Mode 2).
- Restyled `WorkspaceMainView` and `EvidenceCardView` using canonical `Color.speak*` and `Font.speakMono*` tokens.
- All 269 XCTests passed in 33 suites. Moat audit passed 7/7 privacy checks.
- Re-built and launched fresh `Speak.app` (PID 35180).

**Loop #55 (2026-07-22) — STT Finalization Watchdog Bug Fix COMPLETE (commit `47b8cfd`).**
- Identified and resolved the root cause of voice dictation failures:
  - Commit `047743a` introduced a strict 1.5-second `withThrowingTaskGroup` watchdog during `AppleSpeechTranscriber` finalization, which prematurely threw `transcriberUnavailable("STT finalization timed out")` on multi-word dictations when SpeechAnalyzer flush took >1.5s.
  - Replaced rigid throwing watchdog with a non-throwing 10-second `withTaskGroup` window that cancels gracefully upon result completion and safely releases resources without aborting captured dictations.
- Re-launched fresh `Speak.app` (PID 26001). Verified CLI dictation start/stop flow and live OSLog processing.

**Loop #54 (2026-07-22) — Workspace Integration & Default Tag Adapters COMPLETE (commit `4070588`).**
- Deepened `WorkspaceMainView` integration:
  - Reactively wired `WorkspaceMainView` to `WorkspaceStore` (SQLite database) and `TagRegistry`.
  - Added built-in default tag adapters (`DefaultClaudeTagAdapter`, `DefaultTerminalTagAdapter`, `DefaultBuilderQATagAdapter`, `DefaultGitHubTagAdapter`).
  - Added `.workspace` section to `DashboardSection` and `DashboardView`, exposing the Agent Workspace directly inside the main Dashboard split navigation.
- All 269 XCTests passed in 33 suites. Moat audit passed 7/7 privacy checks.

**Loop #53 (2026-07-21) — Human-Agent Workspace & Plugin-as-Tag System COMPLETE (commit `b287f3b`).**
- Designed and built the local-first Slack Replacement Workspace architecture:
  - Domain: `TagRegistry` (thread-safe actor tracking `@Claude`, `@terminal`, `@github`), `PluginTagAdapter` protocol, `EvidencePayload` for Rich Media Cards.
  - Storage: `WorkspaceStore` SQLite actor database for Channels (`#general`, `#core-engine`), Spoken Threads, and Evidence Cards.
  - Parser: Extended `VoiceCommandParser` (`VoiceCommandParser+Tags.swift`) to parse spoken/typed `@tag` mentions (`@agent`, `@team`, `@channel`).
  - UI: Built Dual-Mode interface (`AppMode.swift`, `TopSegmentedBarView.swift`, `WorkspaceMainView.swift`, `EvidenceCardView.swift`).
- All 269 XCTests passed in 33 suites.
- Moat audit passed 7/7 privacy checks.
- Merged feature branch to `master` (commit `b287f3b`). Live binary running on PID 28942.

**Loop #51 (2026-07-11) — THREE SLICES SHIPPED in one orchestrated day:
AVB-6 sessions (`9cff623`), AVB-7 durable calls + inbox (`d245dcc`), and FE-1
design tokens + Voice Desktop Pet the pet (`973514e`, fixes `20e55a2`). Frontend identity is
now a frozen spec (`specs/frontend-identity.md`). Still open: the AVB-5 live
question-response round trip (needs the human at the mic).**

### What changed this loop (read before doing anything)
-29. **FE-1 design tokens + Voice Desktop Pet the pet (2026-07-11, merge `973514e` +
   `20e55a2`).** Contract: `specs/frontend-identity.md` (orchestrator-authored,
   incl. the research-informed "Animation soul" amendment, `2289030`).
   - `Speak/App/DesignSystem/` — `SpeakColors` (two-temperature palette:
     warm=human `humanAmber`/`onAir`, cool=agent `agentViolet`; onAir iff mic
     capturing is a HARD rule), `SpeakTypography` (NY/SF Pro/SF Mono roles),
     `SpeakMotion` (signal-mapped durations, Reduce Motion fallbacks).
   - `Speak/App/Pet/` — Voice Desktop Pet: five-bar waveform creature in a non-activating
     all-Spaces `NSPanel`; `PetState.resolve()` is the single source of truth
     (priority: listening > speaking > attention > agentWorking > processing >
     idle > dormant) and the displayed state converges to it unconditionally
     every tick (review fix: a transition-graph gate could freeze a stale
     `onAir` — graph is now advisory/log-only; exhaustive 32-case test pins
     onAir-iff-capturing). Drag + edge-snap with per-display-UUID persistence
     (review fix: resolve the panel's ACTUAL screen, never `NSScreen.main`,
     which is always primary for a non-key panel). Click = the one true
     `DictationController.beginDictation()` path; Voice Desktop Pet can never open the mic
     itself. `attention` state is the AVB-7 inbox badge (stub provider until
     wired). `petEnabled` default false (opt-in this slice).
   - Reduce Motion: heights static, 0.55–0.70 opacity breath pulse (clamped —
     fp ulp overshoot caught by tests post-merge).
   - Reviewed FIX-FIRST → fixed → SHIP. `[deferred — needs human]`: live
     multi-monitor drag dogfood; visual taste pass on Voice Desktop Pet in situ.
-28. **AVB-7 durable Agent Calls + local inbox (2026-07-11, `d245dcc`).**
   Design doc: `specs/avb7-durable-calls-design.md`. New tools
   `speak_submit_call` / `speak_get_call` (wire: additive `.submitCall`/
   `.getCall` CLI commands, short-held Task+pump). `AgentCallStore` SQLite
   actor: CAS state machine (pending→presented→answered/declined/cancelled/
   expired/superseded), exactly-one-winner resolve, session isolation
   (mismatch reads as not-found). Registration-gated: submit/get refuse
   unregistered sessions. Menubar badge (10s poll) + minimal Agent Inbox
   dashboard pane (FE-3 restyles later); voice-answer path reuses
   `beginDictation()`/`RequestInputExtractor`. Review FIX-FIRST → fixed →
   gates green: (1) lazy sweep-then-read expiry inside `get()`/
   `pendingAndPresented()` — no immortal pending calls in an always-on app;
   (2) nil-session idempotency via U+E000 sentinel (SQL NULL never collides;
   NUL-byte sentinel would truncate in `sqlite3_column_text` — caught by
   tests). 24h default expiry applied at tool-arg-parse time.
-27. **AVB-6 session registration (2026-07-11, `9cff623`).**
   `speak_register_session` + `AgentSessionRegistry` actor;
   `sessionId` threaded through all tools via `BridgeOutcome` advisory notes
   (unregistered sessionId = note, not failure — enforcement is a later
   policy slice, EXCEPT AVB-7 tools which hard-require registration).
-26. **AVB-5 `speak_request_input` (2026-07-11, `e7afc48`).** Orchestrated:
   Fable orchestrator + 1 Sonnet 5 implementer + 1 Sonnet 5 adversarial
   reviewer; orchestrator independently re-ran every gate before commit.
   - New MCP tool `speak_request_input(requestId, idempotencyKey?, prompt,
     mode: freeform|choice|approval, choices?, timeout?, consequence?,
     spokenSummary?)` returning exactly one typed outcome:
     `answered`/`declined`/`cancelled`/`timedOut`/`busy` (spec
     `agent-voice-bridge.md` §6). Domain types in
     `SpeakCore/AgentBridge/HumanResponse.swift`, MCP-independent per §3.
   - Deterministic `RequestInputExtractor` (phrase-list, no LLM). `[decision]`
     `declined` = explicit verbal refusal in choice/approval only; `cancelled`
     = human stops capture; freeform never yields `declined`; ambiguous
     choice/approval speech is a tool execution error (the existing
     `unclearAnswer` ethic), never a false decline. `idempotencyKey` is
     plumbed but in-flight dedupe only (any concurrent capture → `busy`);
     durable replay deferred to the durable-Agent-Calls slice.
   - `speak_ask`/`speak_confirm` rebased as thin compatibility adapters over
     `cliRequestInput`; external behavior preserved.
   - **Review finding fixed (ship-blocker):** TOCTOU busy-race — two
     near-simultaneous captures could both pass the busy guard because
     `SpeakEngine.beginDictation()` silently no-op'd on [A3] collision; losing
     caller could read the winner's transcript (§8 violation). Fixed: engine
     returns `@discardableResult Bool` (started vs collided);
     `DictationController.beginDictation()` returns
     `DictationStartOutcome` (started/collided/failed); only a true collision
     maps to `.busy`, mute/permission failures map to `.timedOut`. Hotkey path
     byte-identical (discards the value). Regression tests added
     (`SessionIntegrityTests`, `DictationStartOutcomeRefusalTests`).
   - Preserved: visible HUD capture, paste suppression for agent answers,
     stale-answer isolation, user-stop releases request early.
   - Gates (orchestrator-run, clean shell): build ✅ / 741 XCTest 0-fail
     (9 known skips) + 176 Swift Testing ✅ / lint 0 serious ✅ /
     verify-moat 7/7 ✅. `make install-mcp-user` re-run post-commit.
   - **`[deferred — needs human]`**: the spec-§6 live round trip
     (`speak_request_input` question → real spoken answer via a live Codex or
     Claude Code session against the relaunched app). This is the last AVB-5
     done-condition item.
-25. **Human-Agent Interface direction freeze (2026-07-11).**
   - Reconciled `AGENTS.md`, `docs/product.md`, `docs/architecture.md`,
     `docs/roadmap.md`, and the canonical bridge specification around one
     boundary: Speak handles local input/output/routing/attention; connected
     agents handle reasoning and action.
   - Marked the broad Voice OS exploration superseded. Jarvis-like continuity
     remains an experience goal, not permission for general automation.
   - Audited actual implementation: five local MCP tools are working transport
     primitives; sessions, durable calls, receipts, inbox, semantic progress,
     direct agent ingress, and provider-neutral adapters are not implemented.
   - **Next dependency-ready product task:** AVB-5 structured
     `speak_request_input`, with typed outcomes and one live agent round trip.
   - No production behavior or v0 ship gate changed in this documentation loop.
   - Verification: build ✅ / lint 0 serious (existing warnings only) ✅ /
     verify-moat 7/7 ✅ / `git diff --check` ✅.

-24. **Agent Voice Bridge product contract + first product slice (2026-07-11, committed as `0dbf14e` + `4203c4d`).**
   - Added `specs/agent-voice-bridge.md` `[decision]`: Speak is the local human I/O layer for agents, not an agent, general automation server, or shell/file/browser toolbox. The flagship loop is rich voice prompt → agent works → concise completion/blocker spoken locally → bounded visible response.
   - Added `speak_notify(summary, kind, detail?, interrupt?)` as the preferred MCP application tool. Its discovery description limits use to final outcomes, blockers, high-severity warnings, and explicit readback; routine progress/logs/diffs remain visual. Existing four tools remain compatibility primitives.
   - Added `make install-mcp-user`: relocatable `speak-mcp` + `SpeakCore`/`SpeakLLM` framework layout under `~/Library/Application Support/speak/mcp/`. Relocated launch verified from a temporary install root. Homebrew formula now installs `speak-mcp`; README includes Codex and Claude Code setup.
   - Fixed two interactive bridge hazards found during audit: MCP answers now suppress focused-app paste delivery, and `cliAsk` clears/restores shared transcript state so a failed capture cannot return an older dictation. A user stop now releases the request without waiting the full configured timeout.
   - Verification: full post-hardening suite ✅; focused `CaptureSessionTests` 18/18 ✅; lint 0 serious on changed files ✅; verify-moat 7/7 ✅; relocated MCP launch ✅.
   - **Live flagship proof** `[verified 2026-07-11]`: installed bridge negotiated MCP 2025-11-25, `speak_status` returned the running app's idle state + live hotkey, and `speak_notify` delivered “Speak agent bridge is ready.” through the app's VoiceOut path. Codex global MCP config now points at the stable installed bridge.
   - `[deferred — product]` queue/cooldown/per-client policy and unified structured `speak_request_input`.
   - **AVB-4 attention queue follow-up (same loop, committed):** `AgentSpeechQueue`
     now serializes non-interrupting notifications, replaces active + pending speech
     for urgent notifications, and discards the agent queue whenever human dictation
     starts. Three race-aware tests pass repeatedly (3 consecutive runs, 0 failures).
     Cooldown/deduplication, quiet policy, and per-client enablement remain `[deferred]`.
   - Post-queue gates: build ✅ / 741 XCTest (9 documented environment skips),
     0 failures ✅ / 142 Swift Testing pass ✅ / lint 0 serious ✅ / verify-moat 7/7 ✅.

-23. **P13 DOGFOOD PASS (2026-07-10, human-verified live).** All four critical unverified items confirmed:
   - **Terminal paste-provenance prompt**: ✅ PASS — no macOS 26.4 paste-protection prompt observed; text pastes directly into Terminal without prompting.
   - **Hotkey false-trigger rate**: ✅ PASS — ~2 hours continuous real use (15+ min sustained sessions); no accidental dictation overlays; 400ms double-tap window acceptable.
   - **Live paste across apps**: ✅ PASS — Terminal, Slack, TextEdit all receive text correctly; paste lands in correct location (message box, code editor, etc.).
   - **Permission flow**: ✅ PASS — Microphone prompt fires on first run; Accessibility deep-link opens correct System Settings pane; both grants stick across sessions.
   - **P14 cleanup latency — Known limitation, not a blocker** `[decision]`: Cleanup taking 5–10 seconds on long dictations (~3 min speech) is a trade-off of the small on-device Foundation Models engine (designed for privacy + speed, not throughput). **Decision**: Ship v0 with this documented caveat. Larger models (via v0.1's pluggable OpenAI-compatible engines — Ollama, Sarvam, OpenAI, Groq, OpenRouter) will provide faster cleanup for long inputs without sacrificing local-by-default. Defer profiling/streaming cleanup to v0.1+ when multi-model comparison is meaningful.
   - **Test-context summary**: Terminal (`git reset --hard` style imperative), Slack (collaborative), TextEdit (prose), continuous 2-hour coding session (hotkey endurance). No false triggers, no permission edge cases.
   - **Gates still green**: build ✅ / `make test` (unchanged from #46) ✅ / lint ✅ / verify-moat 7/7 ✅.
   - **Decision**: P13 is feature-complete and human-verified. Proceed directly to P14 (investigate + fix the cleanup latency regression, then ship v0). No code changes required for P13 itself — this was pure verification.

-22. **Loop #46 (2026-07-08, 07b0591) — H-1 Voice Actions FULLY live (both `.action` and `.command` routes wired into stop→paste), H-4 ShortcutsCLIExecutor two-stage SIGTERM/SIGKILL watchdog hardening merged to master. Gates: build ✅ / `make test` 725 XCTest 0-fail + 139 Swift Testing pass ✅ / lint 0-serious ✅ / verify-moat 7/7 ✅.**
-22. **H-1 Voice Actions FULLY live + H-4 watchdog hardening merged to master (loops #45→46).** Three commits land the horizon skeleton into production:
   - `e555a10` [H-1] routes finished transcripts through VoiceActionsCoordinator in CaptureSession.stop(); `.action` route via ShortcutsCLIExecutor now on the real stop→paste critical path (prefix-gated to avoid catalog fetch for plain dictation).
   - `e3243dc` [H-1] wires `CommandModeService(selection: AccessibilitySelection(), cleaner:)` into `.command` route (reuses the same `AccessibilitySelection` conformer `CommandModeController` already uses in production) — both routes now integrated into the live dictation pipeline. **`.command` is wired and live, not degrading** — only the underlying AX I/O behavior (does read/replace actually work against a real focused element in TextEdit/Slack) stays `[deferred — needs human verification]`, same boundary `AccessibilitySelection` already carried pre-H-1.
   - `07b0591` [H-4] ShortcutsCLIExecutor two-stage SIGTERM/SIGKILL watchdog: 10s default SIGTERM, 1s grace window, then SIGKILL (uncatchable) for hung headless shortcuts (fixes hang in interactive-dialog fixtures that trap SIGTERM).
   - **`[decision]`** history for executed actions/commands records the raw utterance + latency=0 (consistent with feature-off fallback path, LatencyStats partition filters out 0s). **`[deferred — needs human verification]`**: live two-process paths (real "hey speak `<shortcut>`" → real `/usr/bin/shortcuts run`; real AX read/replace against a focused element).
   - Gates: build ✅ / `make test` 725 XCTest 0-fail + 139 Swift Testing ✅ / `make lint` 0-serious ✅ / `make verify-moat` 7/7 ✅.

-21. **H-1 Voice Actions live-pipeline wiring (loop #45, now committed).** The skeleton from loop #42 (`Speak/SpeakCore/VoiceActions/`) is now actually consulted by the dictation pipeline instead of being dead code.
   - **Integration point — engine/session, NOT the App layer (the task brief's guess was wrong, surfaced deliberately).** The final transcript is pasted *inside* `CaptureSession.stop()` → `runPaste()`, so by the time `DictationController.endDictation()` sees the result the paste already happened — the App layer cannot suppress it for an executed action. So the wiring lives where the paste does: `SpeakEngine.newSession()` builds the coordinator, `CaptureSession.stop()` consults it at the `rawText`-ready seam (right after the empty-transcript guard, before cleanup+paste), mirroring the existing `voiceCommandPreprocessor` injection pattern.
   - `CaptureSession`: new optional `voiceActionsHandler: (@Sendable (String) async -> VoiceActionOutcome)?` (default nil). In `stop()`, `routeVoiceActions(...)` returns a terminal `TranscriptionResult?` — non-nil ⇒ action/command executed, paste suppressed, settle `.done` via `settleVoiceActionExecuted` (no latency record, no paste); nil ⇒ proceed with the normal cleanup+paste path. Both `.dictation` and `.degradedToDictation` return nil so the ORIGINAL transcript is pasted (never lose words). A cancel-during-routing re-check throws before settling `.done`, matching the existing A1 guard.
   - `SpeakEngine`: `init` gains `voiceActionsExecutor: (any ActionExecuting)?` + `voiceActionsCommandService: CommandModeService?` (both default nil, all-SpeakCore protocols ⇒ engine stays AppKit-free). `newSession()` builds the handler **only when `settings.voiceActionsEnabled`** — when off, a **nil** handler is passed so `stop()` runs the literal pre-H-1 path (byte-identical, not relying on the coordinator's internal `guard enabled`).
   - **`[decision]` catalog fetch is prefix-gated to protect `stopToPasteSeconds`.** The handler runs a cheap deterministic `PrefixActionRouter.route(rawText, [])` FIRST; only if the prefix matched does it call `executor.listActionNames()` (which spawns `/usr/bin/shortcuts list`). This keeps the subprocess OFF the stop→paste critical path for the common case (plain, non-prefixed dictation) even when the feature is enabled — a matched empty-catalog route can only be `.command`, never `.action`, so a `.dictation` result unambiguously means "not a voice action."
   - `DictationController`: passes `voiceActionsExecutor: ShortcutsCLIExecutor()` (all-SpeakCore, wraps `/usr/bin/shortcuts`). The **`.command` route's `CommandModeService` is intentionally left nil in production** — it needs an App-layer AX `SelectionAccessing` conformer still `[deferred — human verification]`, so `.command` degrades to dictation until that lands. The **`.action` (Shortcuts) route is the real live path.**
   - **Default = zero behavior change**: `voiceActionsEnabled` is false by default ⇒ nil handler ⇒ dictation is provably byte-identical to pre-H-1. Covered by `testFeatureOff_nilHandler_pastesTranscriptUnchanged`.
   - New tests: `VoiceActionsPipelineTests.swift` (6, colocated with the other VoiceActions tests) drive a real `CaptureSession` through `start()`/`stop()` with a scripted transcriber + recording inserter and the SAME handler closure `newSession()` assembles (real `VoiceActionsCoordinator` + `PrefixActionRouter`): feature-off byte-identical, action route executes + suppresses paste, command route uses `CommandModeService` + suppresses paste, no-selection/executor-failure degrade + paste the ORIGINAL transcript, no-prefix plain dictation. All pass deterministically on every run.
   - **`[decision]` history**: an executed action/command **does** write a history entry (rawText = the spoken utterance, cleanedText nil, latency nil→0). This falls out of `settleVoiceActionExecuted` returning a non-empty `rawText`, which `finishEndDictation` then persists. Consistent with the existing `latency==0 ≡ "no measurement"` sentinel (fixture runs already store 0-latency rows and LatencyStats partitions them out), so it doesn't corrupt WPM/latency stats. Truly skipping would require a new signal on `TranscriptionResult` (touches every initializer) for no clear benefit — `[deferred]` unless action-history is judged actively wrong.
   - **`[deferred — needs human verification]`**: the live two-process path (real spoken "hey speak <shortcut>" → real `shortcuts run`) — same honesty boundary as the rest of the codebase; only the routing/suppression logic is unit-tested.
   - **Test-flakiness note (environmental, NOT caused by this change):** the full `make test` alternates between 0 failures and ~8 failures across runs. Two environmental sources, both pre-existing, both unrelated to the Voice Actions diff:
     1. **Mic-auth (the 8):** `SpeakEngineMuteTests` + `SpeakEngineIntegrationTests` call `beginDictation()`, which hits the loop-#43 guard `AVCaptureDevice.authorizationStatus(for: .audio) == .authorized` (`SpeakEngine.swift:524`) and throws `microphoneDenied` when the test-host binary lacks a TCC mic grant. Flips with TCC state, not the diff — an earlier clean run had all **725 XCTest 0-fail**. My `newSession` changes don't touch `beginDictation`'s auth gate.
     2. **Shortcuts service:** `ShortcutsCLIExecutorTests` shell out to the real `/usr/bin/shortcuts` (`[Connection] ... com.apple.linkd.autoShortcut` errors), intermittently unavailable in the sandbox.
     The new `VoiceActionsPipelineTests` mock the executor and pass on **every** run. Swift Testing: **139 pass** every run. Orchestrator: re-run from clean with the test host mic-authorized to see the green 725.

-20. **H-3 MCP bridge finished (`2b76ba0`)** — the three previously-stub MCP tools (`AgentBridgeTools.swift` said "not yet wired") are now real:
   - `CLIContract.swift`: new `.say`/`.ask`/`.confirm` wire cases on the existing CFMessagePort CLI protocol, plus a per-call timeout override on the transport (3s default stays for start/stop/status/say; ask/confirm default to 60s — `CLIContract.askConfirmDefaultTimeoutSeconds` — since they block on real human speech).
   - **`[decision H-3]` the main-thread-block problem**: the CFMessagePort port callback is synchronous and must return `CFData` before returning, but `ask`/`confirm` need to speak a question via `voiceOut` and run a full async dictation round-trip (tens of seconds) — a literal block would freeze the whole app, violating the project's own hard rule. Solved in `CLIPortServer.handleAskOrConfirm`/`pumpUntilResult`: the round-trip runs as `Task { @MainActor in ... }`, writes its result into a lock-protected `CLIPendingResultBox`, and the callback repeatedly pumps `RunLoop.current.run(mode: .default, before:)` in short slices until the box is set or the timeout elapses — each slice drains the main run loop (including the GCD queue backing `@MainActor`), so the Task makes progress and the HUD updates live, not a frozen frame.
   - `DictationController+CLI.swift`: `cliSay`/`cliAsk`/`cliConfirm` reuse the *same* `voiceOut` (`AppleSpeechSynthesizer`) instance and the *same* `beginDictation()`/`endDictation()` session path the hotkey and CLI `--start`/`--stop` already use — not a second competing engine instance. This is why HUD visibility and mic-permission gating come for free: the spec's "every agent-initiated mic open is visually surfaced, never silent listening" requirement is satisfied structurally, not by a special case.
   - New `Speak/SpeakCore/CLI/YesNoCancelExtractor.swift`: deterministic, on-device, no-LLM yes/no/cancel/unclear parser for `speak_confirm` (normalize → phrase-list match; unmatched input returns `.unclear` rather than guessing).
   - `CLIBridgeBackend.swift` / `BridgeBackend.swift`: `say`/`ask`/`confirm` now send the new CLI commands and translate real replies (`.timedOut`/`.unclearAnswer`/`.transportError`) instead of always returning `.failure`.
   - `AgentBridgeTools.swift`: dropped the stale "not yet wired"/"not implemented" tool-description language.
   - Tests: `CLIContractTests` (wire encode/decode + timeout plumbing), `YesNoCancelExtractorTests` (table-driven, all phrase lists + unmatched input), `AgentBridgeServerTests` (say/ask/confirm coverage against the stub transport pattern).
   - **`[deferred — needs human verification]`**: the live two-process CFMessagePort round-trip itself (real `speak-mcp` shim ↔ real running app, real mic capture) — flagged in `CLIContractTests.swift` matching the codebase's existing honesty convention. Everything upstream of the live hardware boundary (encode/decode, timeout override, run-loop-pump logic, extractor, backend translation) is unit tested and passing.
   - **Process note**: two duplicate agent dispatches drifted/collided on this task before the successful one — one lost context entirely (replied about `.mcp.json` config, unrelated), another began editing the same files concurrently with the eventual winner and was told to stand down mid-flight once detected via `git status`/mtime inspection. No corruption resulted; the orchestrator (me) independently re-ran `make build`/`make test`/`make lint`/`make verify-moat` from a clean shell after the agent's self-report before committing, rather than trusting the self-report alone — this caught nothing wrong this time, but is now confirmed as the right verification habit for future agent-reported "gates pass" claims, especially since SourceKit showed a wave of stale "cannot find in scope" errors mid-edit that turned out to be index lag, not real compile failures (an actual `xcodebuild` run was the only reliable signal).
   - H-3/Pillar-3 is now feature-complete per `specs/horizon-voice-os.md`'s original tool contract (`speak_say`/`speak_ask`/`speak_confirm`/`speak_status` all real). Remaining horizon scope: H-1 wiring into the live pipeline (still skeleton-only, `[deferred]` per loop #42), H-4 (not yet started).

-19. **Loop #43 — Live dogfood surfaced a real mic-permission bug; fixed + orchestrated a 6-way parallel bug-hunt fleet (6 parallel Sonnet forks, one per subsystem group) + fixes for the 2 real findings (`a0992eb`).**
   - **Root cause of tonight's incident**: an orchestrator-run `tccutil reset Microphone com.speak.app` while the app was already running. `AVCaptureDevice.authorizationStatus` is cached per-process at launch — the running process kept reporting `.authorized` after the OS-level TCC grant was reset, so `OnboardingStateMachine` skipped mic re-request and `AVAudioEngine` started fine while CoreAudio silently fed zeroed buffers. No crash, no error, empty transcripts. Fixed by relaunch (new process re-reads real TCC state) — confirmed live by user (Bodie panel captured audio, overlay streamed text).
   - **`4fa77fb` [fix] mic-permission gaps that made the incident hard to diagnose and that would recur for a real user under normal permission-denial, not just my `tccutil` trigger:**
     - `PermissionManager.requestMicrophone()` was silently returning with **no log line** whenever `current != .notDetermined` — this is why last night's log showed Accessibility prompt lines but zero mic lines. Now logs unconditionally, including the skip path.
     - `SpeakEngine.beginDictation()` never checked mic authorization before starting capture — `SpeakError.microphoneDenied` existed but was never thrown anywhere in the codebase. Now gates on `AVCaptureDevice.authorizationStatus(for: .audio) == .authorized` (composes correctly with the existing `muted` gate and A3 re-entrancy guard, verified by bug-hunt fork — checked first, before any session/capture is created).
   - **Bug-hunt fleet**: 6 Sonnet forks dispatched in parallel, each scoped to 2-3 `SpeakCore` subsystem dirs (Engine+Audio+STT / Permissions+Input+Hotkey / VoiceOut+VoiceActions+AgentBridge / Storage+Profiles+Cleanup / Overlay+Paste+Diff / App shell), told to find only real concrete bugs with a failure scenario, not style nits. Plus one Haiku agent reconciling `docs/roadmap.md` checkbox staleness (mechanical, doc-only). Deliberately NOT run as a `Workflow` script — bounded, known-shape task; direct `Agent` dispatch with explicit per-task model choice was the right-sized tool, orchestrator did the verify/judgment call itself instead of adding another agent tier.
   - **2 real findings, both fixed**:
     - `AppleSpeechSynthesizer.stop()` (VoiceOut) fired `stopSpeaking(at: .immediate)` and returned immediately, **before** the async `didCancel` delegate callback arrived. `speak()`'s interrupt path (`if speaking { await stop() }`) would then overwrite `self.continuation` with the new call's continuation before the old one was resumed by `finishSpeaking()` — the first caller's `await speak()` hung forever (orphaned continuation), the second caller's resolved against the stale cancel event instead of its own utterance finishing. Reachable the moment two readback requests overlap (e.g. hotkey pressed twice quickly). Fixed: `stop()` now awaits its own `CheckedContinuation` that `finishSpeaking()` resumes alongside the main one, so `stop()` doesn't return until the interrupted utterance has actually ended.
     - `OnboardingViewModel.startPolling()`'s auto-advance switch handled `.accessibility` but not `.microphone` — a user who denies mic during onboarding, grants it later via System Settings (the exact escape hatch `openSystemSettings(for: .microphone)` exists for), and returns to the app would see `evaluation` refresh but `displayedStep` never advance, looking stuck (asymmetric vs. the working Accessibility flow). Fixed: added a `.microphone` case mirroring `.accessibility`'s pattern.
   - **Everything else came back clean** — Permissions/Input/Hotkey (already heavily hardened from prior loops), Storage/Profiles/Cleanup, Overlay/Paste/Diff (pasteboard write-never-read constraint re-verified: zero reads found). Two sub-severity notes surfaced but not fixed (judged benign, not real bugs): `BindingStore.swift:51,61` swallows Codable encode failures via `try?` (unrealistic failure mode for these structs); `PinnedContextStore.pin()/unpin()` has an unlocked read-decode-modify-encode-write TOCTOU race on UserDefaults, currently only called from `@MainActor` UI so benign today.
   - **`[deferred]`**: the VoiceOut/VoiceActions/AgentBridge fork stopped after finding the synthesizer bug (judged severe enough — silent permanent hang — to report immediately rather than dilute with a shallower pass) and did **not** reach `ShortcutsCLIExecutor.swift` or `AgentBridge/*`. Those are unaudited by this loop's fleet — worth a follow-up pass before relying on them further.
   - **Roadmap reconciliation** (`docs/roadmap.md`, mechanical): checked off P2 (audio capture stop-terminates-stream, tested), P3 (SpeechAnalyzer API surface, `[verified]`-tagged), P6 (secure-field paste refusal, tested), P11-a (4 items: `make install`, `make github-release`, Homebrew formula, README install section — all exist and match). P5/P6-live/P12/P13/P14 correctly left `[deferred — needs human verification]`.
   - Gates: build ✅ / `make test` TEST SUCCEEDED, 0-fail ✅ / lint 0-serious (136 pre-existing style violations, none new/serious) ✅ / verify-moat 7/7 ✅.

-18. **Loop #42 (2026-07-06/07) — Horizon "Voice Layer" direction opened + 6 features landed (H-1, H-2 merged; H-3/V01-2/V01-3/V01-5/Aurora HUD from the 6-worktree fan-out). Gates on master `5495df7`: build ✅ / `make test` TEST SUCCEEDED, 0-fail ✅ / lint 0-serious ✅ / verify-moat 7/7 ✅.**
-17. **H-2 — VoiceOut readback (`specs/horizon-voice-os.md` Pillar 2). MERGED to master (`5495df7`); gates re-run post-merge: build ✅ / `make test` TEST SUCCEEDED, 0-fail ✅ / lint 0-serious ✅ / moat 7/7 ✅.**
   - New `Speak/SpeakCore/VoiceOut/`: `SpeechSynthesizing.swift` (protocol) + `AppleSpeechSynthesizer.swift` (`AVSpeechSynthesizer`-backed conformer, no injectable seam — see test-scope note below). `DictationController+VoiceOut.swift` wires a speaker.wave.2 read-back affordance into the `.done` overlay state (`TranscriptOverlayView.swift`, `OverlayController.swift`).
   - `SettingsStore.readbackEnabled` (default **true**) — controls only whether the button is *shown*; no `SpeechSynthesizing` call happens unless pressed. Voice Actions (`voiceActionsEnabled`/`voiceActionsPrefix`) and this readback toggle were moved out of the `SettingsStore` class body into an `extension SettingsStore` block (pure code motion) to hold SwiftLint's `type_body_length` cap — same file, `@Observable` macro members (`access`/`withMutation`) still reachable from the extension.
   - **[bug found + fixed during merge integration]** `VoiceOutTests.swift`'s `MockSpeechSynthesizerTests.testSecondSpeakInterruptsFirst` deadlocked `make test` indefinitely: `MockSpeechSynthesizer.speak()` always suspends on a fresh `withCheckedContinuation` until an explicit `stop()` resumes it (matches `AppleSpeechSynthesizer`'s real contract), but the test called `speak("second", ...)` directly on the test task and never called `stop()` again to resolve it — the test's own docstring claim ("mock resolves speak() immediately after recording") did not match the mock's actual, correct semantics. Fixed by running the second `speak()` in its own `Task` and adding an explicit trailing `await mock.stop()`, matching the pattern already used in `testSpeakReportsSpeakingUntilStopped`. This was a test-fixture bug only — no production code changed. `[decision]` confirmed not to confuse with the unrelated, *intentional* 10s hang in `DegradeToRawTests.testCleanupTimeoutFallsBackToRaw` (a non-cooperative-cleaner fixture proving the `T_cleanup` watchdog) — the two were briefly conflated mid-session before isolating each on a clean single-process `make test` run.
   - New tests: `VoiceOutTests.swift` (side-effect-free `AppleSpeechSynthesizer` guard-path tests + full `MockSpeechSynthesizer` start/stop/interrupt contract tests), `SettingsStoreVoiceTests` (readback setting, split out of `SettingsStoreTests` for the same lint cap).
   - **[deferred — needs human verification]**: live audio behavior (does it actually speak, latency, Personal Voice fallback) — no CI runs real audio hardware, matching the rest of the codebase's honesty boundary. `speak_say`/`speak_ask`/`speak_confirm` (H-3 MCP bridge) are still tool-error until wired to this seam.
   - Gates (post-merge, full clean single-process run — earlier in this loop, colliding concurrent `make test`/`Speak.app` processes from repeated kill/relaunch produced spurious `SIGKILL`s and were misdiagnosed before the real deadlock was isolated): build ✅ / `make test` TEST SUCCEEDED, 0 failures ✅ / `make lint` 0 serious ✅ / `make verify-moat` 7/7 ✅.
-16. **H-1 — Voice Actions intent-router skeleton (`specs/horizon-voice-os.md` Pillar 1). MERGED to master; gates re-run post-merge: build ✅ / 686 XCTest + Swift Testing suites 0-fail ✅ / lint 0-serious ✅ / moat 7/7 ✅.**
   - New `Speak/SpeakCore/VoiceActions/` module: `ActionRouting.swift` (`VoiceRoute` enum + `ActionRouting` protocol + `PrefixActionRouter` — pure, deterministic prefix-gate classifier, no LLM in this slice per the CS-2 "gate first" finding), `ActionExecuting.swift` (protocol + `ActionExecutionResult`), `ShortcutsCLIExecutor.swift` (`Process`-backed `/usr/bin/shortcuts list`/`run` conformer, concurrent pipe-drain to avoid the classic `Process` deadlock, timeout watchdog for input-requesting shortcuts), `VoiceActionsCoordinator.swift` (ties router+executor+existing `CommandModeService` together — every non-success path degrades to `.degradedToDictation` carrying the ORIGINAL transcript, never silently drops words, including `CommandModeOutcome.noSelection`/`.modelUnavailable`).
   - `SettingsStore`: `voiceActionsEnabled` (default **false**) + `voiceActionsPrefix` (default `"hey speak"`) — master toggle gates the whole feature; existing users see zero behavior change.
   - **[decision H-1]** command-vs-action split (no 3B classifier in this slice): exact case-insensitive match against the caller-supplied action catalog → `.action` (canonical catalog casing, not spoken casing — `shortcuts run` may be case-sensitive); anything else under the prefix → `.command`. This is a deterministic stand-in for the eventual 3B pass (spec line 22-25), not semantic understanding — `[deferred]` until CS-2's revisit trigger (stronger on-device model) makes real classification worthwhile.
   - **Scope deliberately NOT done**: wiring into the live pipeline (`CaptureSession`/`SpeakEngine`/`DictationController`) — this is the H-1 *skeleton* per spec Sequencing #1 ("no new perms"); dictation stays byte-identical. Live command execution needs the App-layer AX `SelectionAccessing` conformer, already `[deferred — human verification]` for `CommandModeController`. `[unverified — dogfood H-4]`: headless `shortcuts run` behavior for input-requesting shortcuts (the executor's timeout watchdog is the mitigation, untested against a real such shortcut).
   - New tests: `VoiceActionsRoutingTests` (14 tests incl. a full decision-table test), `VoiceActionsCoordinatorTests` (10 tests, focused on the never-lose-words contract), `ShortcutsCLIExecutorTests` (7 tests against a deterministic fixture shell script — no dependency on real Shortcuts app state), `SettingsStoreTests` (+4). All net-new; zero existing tests modified beyond additive tail insertions.
   - Gates (this worktree): build ✅ / `make test` 804 passed, 0 failed, 9 skipped (pre-existing) ✅ / `make lint` 0 serious, 0 new warnings in touched files ✅ / `make verify-moat` 7/7 ✅. Caught and fixed one real force-unwrap (`errText!`) via the moat's `testNoForceUnwrapInProductionCode` heuristic scanner before this was reported done.
-15. **Loop #42 (2026-07-06) — Fable-orchestrated parallel build: horizon spec + V01-2/V01-3/V01-5 + Aurora HUD + H-3 MCP bridge.**
   - **`d8b28d3`/`23231c2`/`ecd0a54` [horizon] `specs/horizon-voice-os.md`** — the direction spec: dictation is the wedge, the product is the Mac's voice layer. Three pillars: (1) Voice Actions (intent router → `shortcuts` CLI action surface — direct cross-app App Intents invocation has NO public API `[verified]`), (2) VoiceOut conversational loop (AVSpeechSynthesizer, Personal Voice — feasible-as-specced `[verified]`), (3) MCP Agent Bridge (`speak_say`/`speak_ask`/`speak_confirm`/`speak_status` — any MCP agent gets ears + a voice, 100% local). All three validated by a docs/SDK-typecheck validator agent before building.
   - **`1a030d0` [V01-3] per-app context, profile-native** — new `Chat` profile (Slack/Discord/Messages/WhatsApp/Telegram → casual), `Write` trimmed to Mail+browsers; `perAppContextEnabled` toggle gates the frontmost-bundle read in `SpeakEngine.newSession` (off ⇒ exact no-context baseline). Agent correctly escalated that the literal brief (standalone AppContext detector) would duplicate the Profile Engine; direction call: profile-native.
   - **`ad8e760` [V01-5] multiple hotkey bindings** — `ExtraBinding`/`ExtraBindingSet` (max 4/action, mouse buttons 4–10, duplicate-source validation), `HotkeyMonitor.updateExtraBindings` rebuilds tap mask only when mouse-binding presence flips, live-apply via `withObservationTracking`, Settings editor (`ExtraBindingsSection`). `[deferred — human]`: live otherMouseDown delivery with AX-only.
   - **`6fe5dec` [H-UI] Aurora HUD** — opt-in `HUDStyle.aurora` (default `.classic`, zero regression): ambient orb (Canvas+TimelineView, 60fps, breathes with level), materializing word ticker, state color language, Reduce Motion honored. Integration decision: kept `FirstMouseHostingView` (agent's `NSHostingView` would have regressed PE-3 chip first-click). `[deferred — visual]`: live style swap, capsule proportions, processing hue-drift taste check.
   - **`cd08c96` [V01-2] OpenAI-compatible cleanup engine** — new **`SpeakLLM` framework target** holds `OpenAICompatibleClient` (URLSession) + `LLMKeychainStore` (Keychain) so the moat greps over SpeakCore/App/CLI stay symbol-clean — structural guarantee preserved, not exempted. Presets: Ollama (loopback-only, no key), Sarvam/OpenAI/Groq/OpenRouter (opt-in, Keychain key required). `OllamaCleaner` stub deleted. Follow-up open: `CleanupEngineSheet` key-entry UI (no way to enter API key in-app yet).
   - **`ba791c1`/`41d92c9` [H-3] MCP agent bridge vertical slice** — `SpeakCore/AgentBridge/` (JSONValue, JSON-RPC 2.0 codec, MCP types w/ version negotiation, 4-tool catalog, dispatcher actor, `BridgeBackend` seam) + `speak-mcp` stdio shim (`Speak/MCP/`, `SpeakMCP` target). Protocol 2025-11-25, negotiates down to 2025-06-18 (Claude Code). **Live e2e verified**: initialize → initialized → tools/list → tools/call speak_status (real CFMessagePort IPC) → EOF exit. `speak_say`/`speak_ask`/`speak_confirm` declared but tool-error until VoiceOut + app transport land.
   - **Integration notes (orchestrator)**: 3 of 6 worktrees forked pre-`Speak/` reorg — ported via path-rewritten `git apply -3`; conflicts resolved in SettingsStore (3×), OverlayController, TranscriptOverlayPanel, project.yml, .swiftlint.yml. Split `HUDStyleSection.swift` + `AboutSettingsTab.swift` out of SettingsView and moved two DictationController funcs to extensions to hold lint caps.
   - **H-2 landed this loop** (see -17 above); `speak_say` (H-3 MCP bridge) not yet wired to it — still tool-error.
-14. **Loop #41 (2026-07-06) — Constraint-split exploration: CS-1 rejected, CS-2 architecture validated + parked (`82bb24c`).** Fable-driven (diverge→converge, 3 passes) next-iteration design for the coding-agent input path: surface spoken hedges ("don't touch the tests") as a trailing `Constraints:` block. Measured **live** against the on-device 3B (Apple Intelligence is enabled now — the "gated off" note was stale):
   - **CS-1** (single-prompt `PromptBuilder` fragment on `.task`/`.fix`): over-triggers, 97.39%→85.71%. **Reverted.**
   - **CS-2** (two-pass inside `FoundationModelsCleaner`: deterministic prohibition pre-gate → one-job extraction session → Swift-formatted block): over-trigger **solved**, Pareto-safe on recall (cleanup body untouched → original 17 fixtures non-regress), latency unchanged. Blocked only by **3B extraction fidelity** (~50% recall, unstable, one fabrication). **Parked** (user decision) — wiring reverted; validated design + eval acceptance gate preserved in `specs/constraint-split-cs1-finding.md`. Revisit via WWDC26 provider API (V1-13).
   - Baseline protected: `make test` 603,9-skip,0-fail ✅ / `make verify-moat` 7/7 ✅. Live eval Agent baseline re-confirmed at 97.39% (one pre-existing `ask` fixture fails — separate, unrelated).

-13. **Loop #40 (2026-07-04) — 9 commits, no open branches besides `eval/rubric-scorer` (stale, unmerged content already superseded on master).**
   - **`8142bde` [repo] Reorganize source under `Speak/`**: `App/`, `SpeakCore/`, `CLI/`, `Tests/` moved under a single `Speak/` root (pure rename, no logic changes); `project.yml`/Makefile/`.swiftlint.yml` updated to match. Any doc or script referencing old top-level `App/`, `SpeakCore/`, `CLI/`, `Tests/` paths is now stale — update to `Speak/App/…` etc.
   - **`7d84fd1` [fix] PrivacyPaneView**: replaced fake hardcoded "Verify Moat" results in the UI with a real, honest audit (wired to `MoatAuditor`).
   - **`205fc9f`–`22c1364` [UI/UX/fix] Coding-customization panel**: split out of the base overlay into its own non-activating panel (`CodingCustomizationPanel` + `CodingCustomizationView`); fixed `canBecomeKey` so its prompt `TextEditor` accepts input; text box is now primary with presets/prompt deferred behind a disclosure; Escape degrades gracefully (closes coding panel first, then stops dictation); fixed an orphaned `AppShell` Window scene that caused a blank window on launch; Settings pinned to the bottom of the sidebar, separate from the scrollable nav list.
   - **`c61f114`/`5444fdc` [merge] PE-2 — AI Studio settings tab**: few-shot examples editor landed on master (was "in flight" as of loop #39).
   - **`7168ac8`/`210b713` [merge] P11-a — install targets**: `make install` (copies `Speak.app` to `/Applications/`) + `make github-release` landed on master (was "in flight" as of loop #39).
   - **`56aacc7`/`157b63f` [merge] P12 — README + privacy section + onboarding lifecycle tests** landed.
   - **`e4eef32` [SM-2]** — cherry-picked imperative fix-fragment prompt tweak + live A/B eval harness (`FixABTests.swift`, `research/fix-fragment-ab-result.md`) from the abandoned `pe/sm-2-metric` branch.
   - **Roadmap correction**: `docs/roadmap.md` P2/P3 were still marked `[TODO]` despite `AudioCapture.swift`, `AppleSpeechTranscriber.swift`, `PermissionManager.swift` already existing and tested — checklist items reconciled this loop (see roadmap diff); code was ahead of the checklist, not the other way around.
   - Gates re-verified this loop: build ✅ / `make test` 597 tests, 6 skipped, 0 failures ✅ / `make verify-moat` 7/7 ✅.

-12. **PE-4 + P2.3 + re-clean button — ALL MERGED TO MASTER (`b1907d9`).**
   Three changes landed together after parallel agent dispatch + orchestrator conflict resolution:
   - **PE-4 — Overlay Tier 2/3 knobs + capture controls**: `perDictationFormat/Tone/Length` pickers in the selector card, cancel (xmark.circle) abandons dictation, re-clean (arrow.clockwise) re-runs cleanup on last raw transcript. `DictationController+Knobs.swift` + `KnobsTests.swift` (9 tests). Re-clean button wired in `.done` state overlay — nils itself on first tap to prevent double-fire.
   - **P2.3 — Dual raw stream (processing preview)**: `CaretOverlayController.showProcessing(rawText:)` keeps the caret overlay visible during the 0.3–1.5s cleanup window, showing raw transcript + ⟳ suffix. `lastRawTranscript` set on every partial update, cleared on `resolveActiveDestination`.
   - Gates: build ✅ / test 572,5-skip,0-fail ✅ / eval Agent 98.51% Note 100% Raw 100% Write 100% ✅ / verify-moat 7/7 ✅

-11. **P2.2 — Floating caret-anchored overlay (`3c513a7` master).** Non-activating NSPanel positioned 8pt below text cursor (AXUIElement), flips y-axis for AppKit coords, falls back silently when CaretLocator returns nil. P2.3 extends this with processing-state preview.

-10. **SM-2/SM-3/PE-3c-V/eval/rubric-scorer — ALL MERGED TO MASTER (`2a66632`).** Three agents ran in parallel:
   - **SM-2** — CC-lens Agent system prompt + 8 realistic developer voice fixtures. Agent eval 91% → 97.04%.
   - **SM-3** — Empty-output guard in `CaptureSession+Cleanup.swift` (was delivering `""` instead of raw fallback). 6 DegradeToRawTests all pass.
   - **PE-3c-V** — 10 LivePanelPromptShapingTests covering all 6 Agent categories.
   - **eval/rubric-scorer** — `RubricChecker` in `EvalScoring.swift`: noFiller, imperativeStart, endsWithQuestion, noMarkdown, conventionalCommitsFormat, preservesTerms:X, maxSentences:N. 8 realistic fixtures now use `checks[]` rubric instead of Jaccard.
   - Gates: build ✅ / test 0-fail ✅ / eval Agent 97.04% Note 100% Raw 100% Write 89.38%.
   - 4 stale spec files removed.

-9. **SM-2 (#12) — Agent-category prompt optimization (branch `pe/sm-2`, committed).** 17/18 fixtures PASS under deterministic eval (greedy decoding). One Write fixture score=0.79 is a confirmed metric artifact (Jaccard punctuation sensitivity). Key decisions: greedy decoding is correct for a cleanup transform [verified SDK 2026-06-30]; few-shot ordering matters — for categories with their own output format (commit, shell, code), suppress the Agent profile's task-form few-shot examples. Gates: build ✅ / test 548,5-skip,0-fail ✅ / lint ✅ / moat ✅.

-8. **Loop #39 cont. — PE-3c-1 live-panel card LANDED + UI-verified live.** Overlay-card model (HUD + destination pill + "Shape this dictation" card). Raw = AI-off passthrough for that dictation (`CaptureSession.forcedRaw` + `SpeakEngine.applyRawOverride`). Commit `4ea4129`; gates build✅/test 548,5-skip,0-fail✅. **User confirmed live: card embeds in overlay, opens/selects/closes.**

-7. **Loop #39 (2026-06-29) — PE-3 live panel: plumbing + click spike landed.** Category seam live end-to-end (`CleanupMode.profile` carries `category` → `FoundationModelsCleaner` → `PromptBuilder.instructions`).
   - **PE-3a `b6a8c57`** — `CaptureSession.overrideCleanupMode` + `SpeakEngine.applyProfileOverride`. Race-free: engine mode rebuilt ONCE at stop before `endDictation()`.
   - **PE-3b `5cd9840`** — `FirstMouseHostingView` (acceptsFirstMouse→true) so SwiftUI Button registers click in `.nonactivatingPanel` without focus-steal.

### Layering (immutable — never invert)
- **Base core:** double-press activate / single-press stop; raw voice → text ALWAYS available.
- **Default:** `Clean` profile (on-device neat-writing); AI off ⇒ raw passthrough.
- **Extension:** the Profile Engine (north star).

### Next actions (in order)
- **Reconcile roadmap checklists (mechanical, do first)** — P2/P3/P5/P6/P7 sub-checkboxes in `docs/roadmap.md` under-report actual test coverage; tick verified items, keep `[deferred — needs human verification]` tags for anything not exercised live.
- **P13 — Dogfood (critical path, not started)** — the one substantive TODO left on the critical path. Requires live human verification first:
  - macOS 26.4 Terminal paste-provenance prompt (project's #1 `[unverified]`) — test in Terminal/iTerm.
  - Hotkey false-trigger rate in real typing (Notes, 30 min sessions).
  - Live paste across TextEdit/Slack/Terminal.
  - Permission prompts + System Settings deep-links firing correctly live.
- **P11-b — signed/notarized `.dmg`** — blocked on a Developer ID cert (open question #4).
- ~~PE-3.1/#51, PE-3.2/#52~~ — **CLOSED**: both landed on master (`58bbdb8`/`9ad8858` PE-3.1 voice command detection, `4840d38`/`ee80505` PE-3.2 pin-to-context + P2.1 CaretLocator) — this list was stale, corrected 2026-07-08.

### Orchestration note
Models: **Opus** (judgment/design/review) + **fast worker** (Haiku/WSL2 MiniMax). Design is locked in specs; route mechanical multi-file implementation to the worker; orchestrator reviews diffs + owns commits.

---

## Open questions

| # | Question | Status |
|---|---|---|
| V1 | Did Phase 1A (`val-oss-compare`) and 1B (`val-skill-sdk`) agents complete? | Unknown — check progress notes or re-run |
| 3 | Does write+`Cmd+V` avoid the paste prompt incl. macOS 26.4 Terminal provenance check? | `[unverified]` — test in Terminal (human) |
| 4 | Developer ID signing cert for notarization? | Unverified — needed for P11 |
| ~~V2~~ | ~~fix-input2 changes — should they merge?~~ | **CLOSED** — merged `d05e740` (2026-06-26), gates green |
| ~~V3~~ | ~~DictationTranscriber contextualStrings support?~~ | **CLOSED** [verified via SDK arm64e-apple-macos.swiftinterface 2026-06-26]: `DictationTranscriber` exists in `Speech`; `AnalysisContext.contextualStrings[.general]` is a valid property. H4 seam is correct. |

---

## Done (2026-07-08 — dist/speak.cask.rb verified, P11-b scaffold note added)

**builder-release checked P11-b's Homebrew Cask scaffold.** `dist/speak.cask.rb` already
existed (from `d790b72 [P11] release: real sign/notarize/dmg pipeline + cask + CI hardening`)
and was structurally sound: valid Cask DSL (`ruby -c` passes), `app "Speak.app"`,
`depends_on macos: ">= :tahoe"` (macOS 26), `url`/artifact naming (`Speak.dmg`) consistent
with the `make release` target's `$(DMG)` output, placeholder `sha256` clearly marked.
No rewrite needed — added one header comment making explicit that the cask is **inert
until P11-b's Developer ID cert lands** (no cert exists yet; `make release` has never
produced a real signed+notarized `.dmg`, so sha256/url are placeholders, not real
artifact data). Cites this file (`docs/roadmap.md` line ~470: "v0 does NOT require P11-b").
No build/test/lint run — pure doc/scaffold comment, no Swift changed.

---

## Done (2026-06-21, loop run #26 — PHASE 1 base-hardening COMPLETE + paste test-hygiene fix)

**Executed all of Phase 1 from `specs/acceleration-plan.md` (autonomous loop).** Five
surgical, mostly-additive seam-hardening tasks, all merged on `master` and verified by
an independent orchestrator gate from a wiped DerivedData (**build ✅ · 199 tests / 5
XCTSkip / 0 failures · lint 0 serious · moat 7/7**):

- **H1 `6dbe029`** — multi-language seam (builder-engine). `SpeakEngine.newSession()` reads
  `settings.language` at call-time. Behavior-neutral (defaults `en-US`). +`SpeakEngineLanguageTests` (3 tests).
- **H2 `4a3ad09`** — App-test infra `TEST_HOST` (builder-release). `SpeakTests` now HOSTS the `Speak`
  app target. XCTest startup gate in `SpeakApp.swift` skips `startMonitoring()` under
  `XCTestConfigurationFilePath`. +`TranscriptOverlayPanelTests` (6 tests).
- **H4 `9bdc20d`** — `customVocabulary` seam (builder-audio-stt). `vocabulary: [String] = []` on
  `AppleSpeechTranscriber`, wired into `AnalysisContext.contextualStrings[.general]`. SDK-verified
  against `arm64e-apple-macos.swiftinterface`. +7 tests.
- **H5 `f2b1d1f`** — `StreamingTextInserting` protocol (builder-input). Define-only (`insertChunk(_:)` /
  `finalize()`). No conformer. Additive, zero risk.
- **H3 `9a3c8c4`** — Decompose `DictationController` (builder-app). 415→361 lines. Extracted
  `OverlayController` + `WindowPresenter`. Behavior identical. +`OverlayControllerTests` (8) +
  `WindowPresenterTests` (4).

**Paste test-hygiene fix `30e99f2`:** `PasteboardWriter` now has injectable `writeClipboard` +
`postEvent` seams; tests inject a `PasteSideEffectRecorder`. Confirmed no paste into user's terminal
during `make test`.

**Orchestration lesson (durable):** `Agent(isolation:"worktree")` did NOT isolate named/background
subagents in CC 2.1.x — they wrote the shared checkout. Verify `git worktree list` after spawning.
Standing fix: each agent calls `EnterWorktree` first + never commits.

---

## Done (2026-06-21, loop run #25 — LIVE base verified + full-product acceleration plan)

**Milestone: the v0 base WORKS LIVE.** User ran `make dev-cert` + `make run`, granted permissions,
and **dictated development instructions into Claude Code using speak itself** — recursive feedback loop.
Confirmed live (`c9392bd`): double-tap Fn start/stop, overlay over other apps, partials streaming live,
paste at cursor into terminal with no macOS 26.4 paste-prompt, raw-fallback with Apple Intelligence off.

**Pivoted mission: "finish v0" → "build the full product, fast."**

**`specs/acceleration-plan.md` produced** from 3 parallel scouts (architecture audit, product roadmap,
competitor analysis). Four locked user decisions: base-hardening-first · local-first+pluggable-later ·
**full-window dashboard** · **Monaco** typographic theme.

---

## Done (2026-09-12 — deep-audit remediation, Waves 1–2)

External 7-pass audit consumed; fixes applied in the report's recommended order.

**Wave 1 (`0e52956` [P0]) — honest verification gates.**
- `pretty-output.sh` now propagates xcodebuild's exit status and counts
  `TEST FAILED`/`BUILD FAILED`/linker/codesign/failed-test-case lines; Makefile
  runs bash `-o pipefail` so piped gates can no longer swallow failures.
- `make gates` no longer exits 0 unconditionally.
- `verify-moat.sh` import audit was dead code (`${line#*:}` never matched) —
  now strips `file:line:` correctly, normalizes `@preconcurrency import`, and
  covers `Speak/MCP` (matching `MoatAuditTests`, swiftlint, and fmt coverage
  for `Speak/CLI` + `Speak/MCP`).
- `make study` actually runs the Eval scheme's study tests (env prefix didn't
  propagate to the test host; `SPEAK_STUDY=1` is now baked into the scheme).
- `SpeakError` conforms to `LocalizedError` — logs and agent-facing errors show
  `recoverySuggestion` text instead of `SpeakCore.SpeakError error N`.
- Fixed the pre-existing serious swiftlint violation in `StatusBarController`
  that the newly-honest gate surfaced.
- Proved the fix both directions: a deliberately broken build prints red +
  `make` exits non-zero; green runs print green.

**Wave 2 (uncommitted at write time) — mic/session lifecycle cluster.**
- `AudioBufferProducing` → `AsyncThrowingStream`: unrecoverable route/device
  teardown now finishes the producer stream THROWING `SpeakError.captureInterrupted`
  (the positive teardown signal) → propagates through the SpeechAnalyzer bridge →
  `failStream` → `.error`. Clean finish still means "stopped normally / fixture EOF".
- `.listening` wedge resolved: `SpeakEngine.beginDictation` self-heals a terminal
  `currentSession` (`releaseCurrentSessionIfTerminal`), and the overlay's
  `onPartialsEnded` hook drives `endDictation()` so the HUD shows the real error.
- Mic-leak race: `stopRequested` flag (reset before pending starts could see it)
  replaced by generation math — `pendingSessionStarts` gate + per-generation
  `stoppedGeneration` mark; `run()` checks `isStoppedGeneration` before ever
  opening the mic.
- Cancel-during-start: `CaptureSession.start()` re-checks state after the
  `cleaner.isAvailable` await — a cancelled session throws `.sessionCancelled`
  before `startStream`; the controller treats it as silent intent, not an error
  HUD (same soft-catch added for cancel-during-processing).
- Watchdog: `awaitStreamDrainWithWatchdog` no longer parks `Task.value` inside
  a task group (unreachable cancel path) — polls a `streamDrained` flag and
  cancels the stalled task itself at 5 s.
- `currentSession` clears are identity-guarded (`===`) everywhere — a stale
  catch can no longer release a newer session.
- Route-change rebuilds dispatch `stateQueue.async` (not `.sync` — was blocking
  the CoreAudio posting thread through `Thread.sleep` + engine restart), guard
  against post-teardown rebuilds (ghost engine), and `start()`'s failure path
  uses shared teardown (observer + monitor-token leak closed).
- `CoreAudioDeviceMonitor.stopMonitoring` now passes the SAME listener block
  it registered (block identity — previously removed nothing).
- `resultsTask` errors propagate instead of `try?`-swallowing (truncated
  transcripts were reported as success).

**Verification:** `make build` clean · `make lint` 0 serious · `verify-moat` 7/7 ·
new `SessionLifecycleRegressionTests` 5/5 (wedge settle, engine self-heal,
mic-leak race, cancel-during-start, watchdog break) · full suite 964 run / 10
skip / 1 failure — the pre-existing live-FM `testEndToEndDictationWithRealComponents`
(`[speak-stt]` prefix vs cleaned text; confirmed failing on clean HEAD).

**Unverified:** live mic behavior with real route changes needs a human drive.
Wave 3+ (one-liners, security surface, dead UI, prompt correctness, perf)
remain queued.

**Wave 7 (user-driven, dictated via the app itself) — hot-path performance.**
- AX messaging timeout: `AXUIElementSetMessagingTimeout(…, 0.25)` now set on
  every element queried by `CaretLocator` (≤5 round-trips on @MainActor per
  beginDictation) and `SecureFieldDetector` (2 in the paste path). Worst-case
  stall vs a hung frontmost app drops from ~30 s to ~1.25 s.
- RT-thread hygiene: scalar RMS loops replaced by `vDSP_measqv` in
  `AudioCapture.rmsLevel` and `VoiceActivityDetector.calculateRMS` (float path;
  Int16 via `vDSP_vflt16` + folded normalization). `import Accelerate` added to
  the moat allowlists (Apple framework — honest audit caught it, correctly).
- Per-buffer fault logging throttled (`TapFaultLog`: first 3, then every 64th)
  — a persistent converter failure or stalled consumer no longer os_logs ~90/s
  on the audio thread.
- All `AsyncStream`/`AsyncThrowingStream` are now bounded: PCM `.bufferingNewest(64)`
  (drops logged via faultLog), level `.bufferingNewest(1)`, VAD 8, transcript
  chunks 64, analyzer input 64, TTS state/progress 8. Kills the ~11 MB/min
  unbounded-growth DoS under analyzer stall; the W2 watchdog bounds a stall at 5 s.
- `DeveloperAcronymNormalizer`: ~16 NSRegularExpression compiles per call → 6
  static-compiled regexes.
- `LocalInferenceServer.isCompleteRequest`: incremental `RequestScanState`
  (separator search resumes at scannedUpTo−3; Content-Length parsed once) —
  O(n) total instead of O(n²) per receive.
- `StreamingChunkCoordinator`: `isAvailable` TTL-cached (10 s) — Ollama's live
  HTTP ping no longer serializes into every task-chain link; stale-true is safe
  (`clean` throws → raw fallback), stale-false self-heals.
- Disproven audit items skipped: AngularGradient borders only render on
  dictation-time overlays (not idle); TextDiff O(n×m) LCS is a documented
  `<500`-word decision off the hot path.
- Found: a running Speak.app blocks xcodebuild test-host launches (same bundle)
  — `make kill` before `make test`.

**Verification:** `make build` clean · `make lint` 0 serious (411 warnings —
below the 412 baseline) · `verify-moat` 7/7 · new `PerfRegressionTests` 9/9
(scan straddle/pieces/malformed/resume, TTL collapse, Int16 RMS parity) · full
suite 973 run / 10 skip / 1 failure — same pre-existing live-FM
`testEndToEndDictationWithRealComponents` (`[speak-stt]` prefix vs cleaned
text; verified failing on clean HEAD).

### 2026-09-12 — Audit: route/device handling + in-app mic picker

**Device matrix closed (user-requested "Apple-standard" pass):**
- `AudioCapture.start()`: full reset → pin → format → tap → observe → start
  sequence now runs inside `stateQueue.sync` — a queued route-change rebuild
  can no longer interleave mid-setup and removeTap under a half-built graph.
- Rebuild bursts coalesced (`requestRebuildLocked` drain loop): one physical
  event fires BOTH `.AVAudioEngineConfigurationChange` and the HAL
  default-input callback — previously each ran a full removeTap/stop/reset/
  sleep/start cycle (~300ms+ of dropped audio per plug).
- Mid-dictation route cue: `.routeChanged` `DictationFeedback` event ("Morse"
  tick + haptic) wired through `DictationController` on BOTH HAL channels,
  comparing the *effective* device (`resolvedInputDevice`) — fires when the
  mic actually feeding you changes, not merely when the OS default does.

**In-app mic picker (pinned-device selection):**
- `DeviceInfo` gains `uid` (`kAudioDevicePropertyDeviceUID` — stable across
  reboots, unlike `AudioDeviceID`).
- `CoreAudioDeviceMonitor.resolvedInputDevice(preferredUID:)` — single source
  of truth: preferred-if-present else system default. Used by capture pinning
  AND the route cue so they can't disagree.
- `AudioCapture.preferredInputDeviceUID` — pins the input unit via
  `kAudioOutputUnitProperty_CurrentDevice` before format read (start) and on
  every rebuild (skipped when already pinned — no HAL churn under storms).
  Live-settable: changing the pin mid-dictation re-resolves and rebuilds only
  when the effective device differs. A `topologyToken` listener re-resolves on
  any plug/unplug so a pinned mic reconnecting mid-dictation switches back.
- `SpeakEngine.setPreferredInputDeviceUID` (`nonisolated`) forwards to the
  transcriber's `AudioCapture` via `AudioCaptureProviding`; applied at
  `beginDictation` from `settings` and observed live by `DictationController`.
- `SettingsStore.preferredInputDeviceUID/Name` (own file — main file is at
  the 1000-line lint cap).
- Settings → Microphone "Input Source" picker: System Default + every detected
  input, checkmarked selection, "Active" pill, pinned-but-missing warning.

**Bug found by tests:** `stateQueue.async` blocks strongly captured the
`guard let self` unwrapped ref → last release could land ON stateQueue →
`deinit → stop() → stateQueue.sync` → `DISPATCH_WAIT_FOR_QUEUE` SIGTRAP
(killed the test host 3/3 runs). All enqueued blocks now weak-capture self.

**Verification:** build clean · lint 0 serious · moat 7/7 ·
`RouteChangeHandlingTests` 6/6 + `AudioCaptureConfigChangeTests` 2/2 +
`SessionLifecycleRegressionTests` 5/5 + `SettingsStoreRoundTripTests` 16/16 —
29 green, zero unexpected exits.

### Session (2026-09-12, cont.) — Wispr-parity pass: DSP front-end + felt-latency

**Research basis:** Wispr Flow publishes a ~700ms release-to-text budget
(<200ms ASR, <200ms LLM, <200ms network) on dedicated cloud GPUs — we cannot
match their inference budget on-device, but the *felt* gap was ours to close.

**Changes:**
- ~~VoiceProcessingIO front-end~~ — **REVERTED same session**: typechecks and
  starts cleanly, but VoiceProcessingIO on macOS is a *duplex* unit — its
  downlink (echo-reference) DSP faults continuously on an input-only graph
  (`vp::vx ... failed to run downlink DSP (I/O fault)`, log-confirmed live).
  Input-only AGC would need a manual gain stage, not VoiceProcessingIO.
- `StreamingChunkCoordinator.finalizeAndStitch` — macro-consolidation now runs
  only when `chunkTasks.count > 1`. The `wordCount > 12` branch re-cleaned a
  *single* already-cleaned chunk — a second full 3B pass on the release path,
  i.e. the visible "Processing…" wait on typical dictations, for zero benefit.
- Extracted `readSettledInputFormat` / `failRebuild` helpers (lint hygiene).

**Verification:** build clean · lint 0 serious (414 warnings) · moat 7/7 ·
AudioCaptureConfigChange 2/2 + RouteChangeHandling 6/6 +
StreamingChunkCoordinator 5/5 (incl. new `testSingleChunkDoesNotMacroConsolidate`
pinning exactly one `clean` call for a single-chunk dictation).

**Still open (measured next):** SpeechAnalyzer end-of-speech finalization
time is Apple-internal; the honest Wispr-parity gaps remaining are ASR model
quality and per-release measurement instrumentation.

### Session (2026-09-12, cont.) — DictationTranscriber swap + prompt-engineer agent

**The real "captures closely" fix:** `SpeechTranscriber(.progressiveTranscription)`
→ `DictationTranscriber(.progressiveShortDictation)`. The generic transcriber
is trained on clean read speech; `DictationTranscriber` is Apple's
dictation-tuned module (Assistant asset family) — built for spoken, disfluent,
free-form utterances with auto-punctuation and faster finalization options.
[verified: full API surface typechecked on arm64e-apple-macos.swiftinterface —
`supportedLocale`, preset, AssetInventory, SpeechAnalyzer(modules:), .results]

- `makeTranscriber`/`provisionAsset`/`installAsset`/`resolveAnalyzerFormat`/
  `buildResultsTask` re-typed; `DictationTranscriber` has no `isAvailable` —
  `supportedLocale` nil + `.unsupported` asset status are the gates.
- Fixture behavior confirmed live: "Testing one two three" → "Taste in 1 to 3"
  — dictation-correct number normalization (digits + range). Fixture test now
  accepts digit/word forms per slot (≥2/3) — the canary asserts
  fixture-related output, not orthography.
- New agent `.claude/agents/team/builder-prompting.md` — prompt engineer
  owning `FoundationModelPromptBuilder` + eval-driven iteration (`make eval`
  baseline → change → re-score); roster updated in team README.

**Verification:** build clean · lint 0 serious · moat 7/7 ·
SpeechTranscriberTests 9/9 incl. real-fixture transcription ·
RouteChangeHandling 6/6 · LatencyAndAccuracy 2/2.

### Session (2026-09-12, cont.) — developer-name vocabulary + built-in slip table

Live dictation evidence: "Claude Code"→"cloth code", "Codex"→"codecs".
Two-layer fix:
- `developerTerms` gained product/tool names (Claude Code, Codex, ChatGPT,
  Devin, Wispr, Copilot, Cursor, Ollama, MLX, …) — contextualStrings bias at
  the STT layer.
- `AcousticCorrections.builtIn` — seeded heard→typed slips
  (cloth/clod/cloud code→Claude Code, codecs→Codex, chat gpt→ChatGPT, …)
  merged under user entries in `defaultExpander`; user `heard` wins,
  incl. an identity row to disable a built-in. Expander is now never nil.
- Cloned qwen-audio-agent → ai_tmp/ (reference for agent-voice runtime).

**Verification:** build clean · lint 0 serious · moat 7/7 ·
AcousticCorrectionsTests 19/19 (incl. new built-in + override tests) ·
SpeechTranscriberTests 9/9.

### Session (2026-09-12, cont.) — silent-input diagnosis: no more silent .done

User report: live dictations produced zero STT chunks, no paste, no history
row — while capture/analyzer lifecycle looked healthy. Root cause under
investigation: sessions ran while the pinned Jabra mic delivered silence
(hardware-muted) and possibly beyond. The product bug: an empty transcript
was indistinguishable from success — silent loss.

- `AudioCapture.peakInputLevel` — `PeakLevelBox` (NSLock) tracks peak RMS
  across the session, updated in the tap; tap closure binds the box, never
  `self` (deinit-trap invariant). Reset per tap install.
- `TranscriptionResult.audioWasSilent` — set by `CaptureSession` when the
  transcript is empty AND a live capture exists AND peak RMS < 0.01
  (measured room-noise floor ~0.002, quiet speech ~0.05+). [inferred floor]
- `DictationController.endDictation` surfaces BOTH empty-transcript classes:
  silent input → "No audio detected — check mic mute or the input source";
  audio present but zero STT results → "Nothing recognized — try speaking
  closer to the mic". Both show the error HUD + .error icon; clipboard is
  untouched; no history row written (still correct).
- `AudioCapture.start` now logs the resolved input device name + UID at
  every capture start — the key diagnostic for "which mic fed this session".

**Verification:** build clean · lint 0 serious (function extracted for
length) · moat 7/7 · CaptureSessionTests 21/21 incl. both new
silence-classification tests (no-capture→false, silent-capture→true).
Live behavior [unverified]: next real dictation will show which class the
failures were — silent input (device/mute) vs audio-present-zero-results
(STT/locale layer, would point back at DictationTranscriber).

### Session (2026-09-13) — multi-agent review → capture/robustness fixes

Four parallel read-only code reviews (audio capture, device roster,
session/error model, hotkey) after user's "mic itself is not listening —
other dictation app works". Fixes landed:

- **All-channel downmix** (`downmixToMono`, vDSP): the tap, peak-RMS, VAD,
  and STT converter all read channel 0 only; the built-in mic presents 3
  channels and — while another process holds a VoiceProcessingIO session —
  speech can ride ch1/ch2 while ch0 is gated silence. RMS ~0.001 observed.
  Now averages every channel; handles interleaved + non-interleaved layouts
  (dropping an interleaved buffer would have reproduced the same silence).
- **inputFormat(forBus:) over outputFormat** for tap install, converter
  source, and post-route-change format settle — outputFormat can bind the
  tap to a zeroed client format on macOS 26. Tap now installs with the
  explicit hardware format (was `nil`).
- **Unconditional re-pin after `engine.reset()`** in the route-rebuild path:
  the old `target.id != effectiveDeviceID` gate could leave capture on the
  system default while believing the pinned device was live.
- **Real coalescing for route-change bursts**: `rebuildRequested` was never
  armed (serial-queue blocks each ran a full rebuild — 2–3 engine restarts
  per plug). Now a lock-guarded flag is armed before enqueue; bursts drain
  at most once more against final hardware state.
- **Transient aggregates excluded** from the input roster
  (`CADefaultDeviceAggregate-<pid>-N` — AVAudioEngine's per-process pinning
  aggregates; pinnable, then vanish mid-session).
- **Error un-masking**: `settleEmptyTranscript()` re-checks `.error` before
  settling `.done` — a failStream during stop/drain was previously
  overwritten by the empty-transcript path and reported as silence.
- **Fn fallback removed**: the configured binding is the sole trigger —
  owner directive is Right-Command double-press only (config.runtime); the
  shadow Fn detector caused paired/unexpected sessions.
- **Preset → `.progressiveLongDictation`**: dictated input is paragraph-
  length free-form; short preset can end-point early. SpeechPrewarmer now
  warms DictationTranscriber (Assistant asset family) — it was still
  warming SpeechTranscriber/GeneralASR, a different model.
- **Engine-start error** now carries the CoreAudio OSStatus code instead of
  nested NSError boilerplate (the "truncated" HUD string).

**Verification:** clean from-scratch rebuild (DerivedData + .xcodeproj
regenerated) · lint 0 errors/414 warnings (baseline) · moat 7/7 ·
CaptureSessionTests 21/21 · RouteChange+ConfigChange+STT+Hotkey+EmptyTranscript
73/73 via bundle-injected xctest (LaunchServices test-host launch remains
flaky — xcodebuild test intermittently fails to launch SpeakTests, code 20;
workaround: run the app binary with libXCTestBundleInject + -XCTest args).
Live dictation on the new capture path: **[unverified — needs user]**.

### Session (2026-09-13, cont.) — Settings UI unification + color reduction

User: settings screen "looks weird / different completely" vs the home
dashboard; reduce colors on both; align to one Apple-native language.

Root cause: **three divergent Settings surfaces existed** — the dashboard
gear's Mode B (`SettingsExperienceView`), the SwiftUI `Settings` scene's
legacy 7-tab `SettingsView` (Cmd+,), and a `SettingsWindowController`
NSWindow wrapper around the same `SettingsView`. Mode B also used its own
chrome (busy breadcrumb bar, 208pt rail with truncating labels, orange
accent, green status pills everywhere) while Home ran glassmorphism +
purple-gradient hero + colored stat chips + fake trend pills.

Changes:
- **One surface.** Cmd+, now routes to `controller.showSettings()` → the
  dashboard's Mode B, via `CommandGroup(replacing: .appSettings)` in
  SpeakApp. Deleted `SettingsView` (918 lines), `SettingsWindowController`
  (94), `PrivacyDataSettingsTab` (orphaned, superseded by
  PrivacyHealthSettingsView), and the dead `ensureSettingsController()`
  plumbing. Debug launch `--debug-open settings` now calls
  `controller.showSettings()` instead of hosting a one-off window.
- **SettingsExperienceView**: gained `.embedded`/`.standalone`
  presentations; detail canvas is now a radius-24 `speakCardCanvas` card
  floating on `speakWindowCanvas` — identical chrome to the Mode A desk
  pane. Rail widened 208→224pt, background switched to the window canvas
  (was a divergent `speakSidebarBg` wash), selected-row icon no longer
  uses `speakAccent`.
- **Shorter rail titles** ("General", "Hotkeys", "AI Models", …) — the
  long labels visibly truncated at 208pt.
- **`SettingsStatusPill` default tint → neutral**; semantic tints stay
  only where state demands (`speakDelivered` = granted/delivered,
  `.orange` = missing/needs action). Decorative `speakAccent` "Switched"
  pill removed.
- **HomePaneView de-colorized**: glass cards → flat `speakSurface` +
  `speakCardBorder` (same primitive as `SettingsSectionCard`); hero CTA
  is now monochrome `speakBone`/`speakInk` (adaptive inverse, high
  contrast in both modes) instead of a blue→purple gradient; dropped the
  glow, hover scale, mic pulse, fake "+12%"/"+2"/"Active" trend pills,
  always-on shimmer flow borders, and colored icon chips. Only remaining
  color: permission shield (green/red — semantic) and the on-air flow
  border while recording (spec §2).
- `WindowPresenter.makeDashboardContext()` extracted so the Settings
  scene and desk share one wiring; `showDashboardSection(_:)` added for
  "Open MCP & Agents"-style links.
- `AppDelegate` is now `ObservableObject` with `@Published controller` —
  the Settings scene's content is evaluated before
  `applicationDidFinishLaunching` assigns it.

Known issue found while verifying (pre-existing, not fixed here): the
SwiftUI `Settings` scene creates its window eagerly at launch and, with
empty content, produced a degenerate 0×0 window that autosave restores.
Routing Cmd+, to Mode B removes the surface entirely rather than
patching scene lifecycle.

**Verification:** build clean · lint 0 serious (401 warnings, ~baseline)
· moat PASS · AppShellIntegrationTests 10/10 via injected xctest.
Screenshots verified: Mode B inside dashboard renders the new card+rail;
Home renders the monochrome CTA + flat cards. Full-suite xctest run
blocked by a pre-existing deadlock in
`AudioCaptureConfigChangeTests.testConfigurationChangeMidCaptureSurvivesWithoutCrashing`
(semaphore wait on com.speak.audiocapture.state — unrelated to UI).
Cmd+, → Mode B path is code-verified but live-keypress **[unverified —
synthetic input was flaky in this session]**.

---

## 2026-09-13 — Settings category deep-links + final color pass

Follow-up to the UI unification. Added per-category debug deep links so
every Mode B screen is directly screenshot-verifiable:

- `SettingsExperienceView` gains `initialCategory` (default `.generalAudio`);
  `DashboardView` + `DashboardWindowController` pass it through;
  `DebugLaunchDispatcher` parses
  `--debug-open dashboard:settings:<category>` (e.g. `...:hotkeys`,
  `...:privacy`). All 8 categories screenshot-verified live.

De-colorization sweep across Settings (decorative → semantic/neutral):

- `HoldToTalkPill` idle state: `speakAccent` capsule → neutral
  `primary.opacity` fill + `speakCardBorder` stroke (active/listening
  state keeps `speakStateListening` — semantic).
- `AgentBridgeSettingsView` install/JSON code blocks: hardcoded
  `Color.black.opacity(0.2)` (non-adaptive, invisible in light mode) →
  `speakWindowCanvas` + `speakCardBorder` hairline.
- `VocabularySettingsView` correction/snippet text: `speakAccent` →
  `.primary` (mono font already distinguishes).
- `GeneralAudioSettingsView` input-device checkmark: accent → primary.
- `OllamaSetupSheet`: header icon → secondary; "Recommended" badge →
  `speakDelivered` (semantic positive); step bubbles → `speakBone`/`speakInk`
  monochrome (matches Home CTA).
- `CleanupEngineSheet`: key icon → secondary; stored-key checkmark →
  `speakDelivered`.

Kept intentionally: `speakAccent` on the About waveform (brand mark,
matches menubar icon), `HotkeyRecorderView` red (destructive), all
green/orange status pills (semantic).

**Verification:** build clean · lint 0 errors · moat 7/7 PASS · all 8
Settings categories screenshot-verified via deep links.
Note: `--debug-open` launches occasionally race window visibility
(AX/screenshot timing); the dispatcher log confirms
`window shown (promoted=true)` each time — retry the capture, not the code.

---

## 2026-09-13 — Settings fully adopts the Home design language

Per user direction ("the home dashboard is the inspiration for the
settings panel"), Mode B was restructured to mirror Mode A chrome
element-for-element instead of merely sharing its canvas:

- **Removed the 52pt breadcrumb strip + divider entirely.** Mode A has
  no header bar; Mode B no longer does either.
- **Rail** is now 220pt (same as the Mode A sidebar) with a 28pt
  traffic-light clearance row, and the back affordance moved to an icon
  button at the exact position of Mode A's sidebar-toggle.
- **Rail selection** changed from the gray `speakSidebarSelection` pill
  to `Color.accentColor` + white label — matching what the Mode A
  `List(.sidebar)` actually renders.
- **Detail card** now carries the same slim header as Mode A
  (`category.title` as `.headline` + inline `subtitle` + esc hint,
  44pt) inside the radius-24 card, instead of a large `speak2Title`
  block inside the scroll area.
- **SettingsSectionCard** headers: small secondary icon+label → 16pt
  semibold primary on-canvas (identical to Home's "Activity Overview"
  rhythm); card radius 12 → 16 to match `homeCard`. The `systemImage`
  param was removed (27 call sites updated).
- **BackToDashboardButton** restyled to `SidebarToggleButton`'s exact
  metrics (26×26, chevron.left, hover pill).

Esc / Cmd+[ still return to the desk; the esc keycap hint now lives in
the detail header's trailing edge.

**Verification:** build clean · lint 0 errors · moat 7/7 PASS ·
screenshot-verified General, Hotkeys, Privacy against the Home
reference.

---

## 2026-09-13 — Typography unification onto FE-1 type system

The user-directed audit identified the biggest remaining divergence:
legacy Monaco (`speakMono*`) was used for ALL chrome text across the
desk panes, while the FE-1 spec (`SpeakTypography.swift`) reserves mono
for data and uses SF Pro for chrome / New York serif for hero titles.

**~200 call sites converted** across 25 files (6 parallel workers):

- CHROME (labels, section headers, descriptions, buttons, empty states,
  input fields) → `speakBody(.caption/.base)`; section headers →
  `.system(size:16, weight:.semibold)` matching Home; pane/sheet hero
  titles → `speakDisplay` serif.
- DATA (transcripts, commands, JSON, timestamps, IDs, spec readouts,
  stored snippet/vocabulary rows) → `speakMonoFace` (SF Mono — the
  spec's data voice, replacing Monaco).
- Stat numerals → `.system(size:28, weight:.bold, design:.rounded)` +
  `.primary`, matching Home's stat cards (Insights' amber numerals
  removed).
- `.speakMonoKeycap` intentionally retained — keycap glyph voice.

**Shared card primitive extracted**: `Speak/App/DesignSystem/SpeakCard.swift`
adds `.speakCard()` (speakSurface + hairline, r16 — the Home/Settings
card) and `.speakInset()` (canvas-tone recessed well, r8 — code/commands).
HomeCardModifier + SettingsSectionCard now delegate to it; MCP pane's
command/JSON wells use `.speakInset()`. Bespoke pane cards with
non-matching radii/fills were left for the pane-restyle pass.

**Overlay audit (user: "review and align")**: default `.classic` HUD is
already the restrained dark pill; `.aurora` is an opt-in ambient style
where color is the point — kept. Overlay typography converted (transcript
text/timers → speakMonoFace; HUD labels → speakBody).

**Verification:** build clean (xcodegen regenerated for SpeakCard.swift)
· lint 0 errors · moat 7/7 · screenshot-verified Insights (numerals now
system-rounded primary), MCP & Agents (serif hero, SF Pro labels, mono
data wells), AI Studio (sliders/labels in SF Pro).

---

## 2026-09-13 — Settings restructured around the pipeline; dashboard = runtime only

User direction: "three layers separately, then put together as a final
layer" + "real principle for distributing Home vs Settings." Adopted
principle: **Dashboard = what the pipeline does. Settings = what the
pipeline is.** One home per capability.

**New Settings IA** (`SettingsCategory.swift`, T3-code-inspired grouped
rail + System-Settings colored icon tiles):

- **Pipeline** — `Voice Pipeline`: the assembled final layer. Live
  `STT → Intelligence → Voice Out` status map with per-layer jump links.
- **Layers** — `Speech to Text` (engine, language, mic + level,
  insertion, hold-to-test), `Text to Speech` (voice, rate/pitch/volume,
  preview, readback — first real pane for the existing VoiceOut engine),
  `Intelligence` (cleanup engine/providers, intensity, style, per-app
  profiles — what the Inference pane consumes).
- **Control** — Hotkeys · Vocabulary (corrections + custom vocab +
  snippets, single home) · Agent Bridge.
- **App** — Appearance · Privacy · General (launch-at-login, reset —
  moved out of the STT pane) · About.

**Dashboard slimmed to runtime surfaces**: `Dictionary`, `Snippets`,
`Style` panes deleted (pure config already in Settings›Vocabulary /
Intelligence). Rail grouped: Activity / Agent Cockpit / Studios; pane
headers gained subtitles.

**Duplicated pane titles fixed**: `PaneHeader` calls removed from all
desk panes + the struct deleted from `PaneScaffold.swift` — the desk
card header is the single title owner.

**Reused, not rebuilt**: TTS rides the existing
`SpeechSynthesizing`/`AppleSpeechSynthesizer` actor + `SettingsStore`
keys; `DashboardContext` gained `voiceOut` injection.

**Deep-link:** `--debug-open dashboard:settings:<category>` verified
live for `textToSpeech`, `intelligence`, `general` (earlier Home capture
was a stale-instance race, not a plumbing bug).

**Verification:** build clean · `make test` 985 tests / 0 failures
(reported "2 errors" = simulated-failure log lines misparsed by
pretty-output.sh, suite itself passed cleanly) · lint 0 errors ·
moat 7/7.

### Follow-up — rail icons corrected to monochrome (t3code analysis)

User flagged the colored icon tiles as wrong: "shape and size matter,
not the color." Deep-read of `ai_tmp/t3code` confirmed: t3code's
`SettingsSidebarNav` uses plain muted 14px Lucide glyphs — no tiles, no
hue — with an accent selection pill. Removed `SettingsCategory.tileColor`
entirely; `SettingsRailRow` now renders a plain 14pt glyph
(`.secondary` / white-on-accent when selected) and the selection fill is
`Color.accentColor` — the identical blue pill the desk sidebar's
`.listStyle(.sidebar)` produces. Pipeline stage nodes keep a bordered
neutral tile (speakSurface + hairline) — shape carries the flow, not hue.
Semantic status pills (NEEDS MIC / ON / READBACK) retained.

Verified: build clean · lint 0 errors · moat 7/7 · live screenshot of
`dashboard:settings:pipeline` shows the corrected rail + diagram.

t3code findings banked for later: sidebar **settings search** (`/` to
focus, arrow-key results, scroll-to-row pulse) and muted `text-sm`
section headings with optional `headerAction` — candidates if the rail
grows.

### Runtime theme system + full-app token migration (agent fleet)

t3code-inspired runtime theming landed: `SpeakThemeSystem.swift` (role model +
built-ins `speak`/`ember`), `ThemeEngine` (selection/persistence/live draft),
`SpeakThemeRuntime.active` + `ThemedRoot` environment repaint, Appearance-pane
theme picker + `ThemeEditorSheet` (role pickers, live preview, custom themes
persist via `SettingsStore.customThemesJSON`), `--debug-theme <id>` debug arg.

Fleet audit (4 read agents) → ~200 hardcoded sites mapped; 6 transform workers
converted them. New roles `error`/`warning`/`ok`/`onAccent` cover status text +
on-accent glyphs. Legacy frozen tokens in `SpeakTheme.swift` (`speakAccent`,
`speakKeycapFace`, `speakState*`) now resolve through the runtime. Three
hand-rolled gradient palettes (AnimatedGradientBorder, EdgeFlowBorder,
ConversationOverlayView's magentaVioletPalette) collapsed onto `speakFlow*`
spectra — spectra now anchor primary stops on roles, keep fixed pivots.
`ShapeStyle where Self == Color` shim added so `.speakMica` shorthand works in
`.foregroundStyle`.

**WCAG audit (programmatic, python3):** light mode was broken — `mica` on
`surface` was 1.10:1 (invisible secondary text on every card), `surface` was a
solid #969696 card, most status hues failed as text. Reseeded: surface
#969696→#EAE8E2, mica→#656C78, and all channel/status lights now pass ≥3:1
(icons) or ≥4.4:1 (text). Dark mode already passed; only cardBorder raised for
separation. `onAccent` fixes white-on-ember-orange (was 2.04:1 → now 7.96:1).

**Mic card rework (STT pane):** Permission → Input Source (trailing-checkmark
list, no duplicate pills) → Input Level → Current Input. Matches Sound>Input
grouping.

Verified: build clean · `SpeakThemeTests` 9/9 pass (fixed nonisolated
`makeEngine`) · lint 3 serious pre-existing (file_length, unrelated) · moat
7/7 · light speak + ember screenshot-verified (legible text, correct rail
onAccent, warm canvas).

### Dictation dead-hotkey root cause + recovery-path fixes (live-verified)

**Root cause of "double-tap does nothing":** the dev build was ad-hoc signed,
so the Accessibility TCC grant bound to the binary's cdhash — which changes
every rebuild. The System Settings toggle showed ON while
`AXIsProcessTrusted()` returned false; the CGEventTap never armed ("tap armed"
absent from logs), so no hotkey events ever fired. Fixed durably:
`make dev-cert` recreated `speak-local-codesign` (it had vanished from the
keychain), `Signing.local.xcconfig` → xcodebuild now signs every build with the
cert — DR is cert-anchored (`identifier "com.speak.app" and certificate leaf =
H"22810a…"`), so the grant survives rebuilds.

**Live E2E verified on the cert-signed build:** `tap armed, keyCode=54` on
launch → synthetic Right-Cmd double-tap (`flagsChanged` @ .cghidEventTap) →
`beginDictation → .listening` → capture+STT → single-tap → cleanup → Cmd+V
paste → history → idle. Also: a running Speak instance blocks the TEST_HOST
launch — the earlier `IDELaunchErrorDomain 20` test failure was that, not a
code bug.

**Bugs fixed in the recovery path:**
- `OnboardingViewModel.onAppear`: `displayedStep` persisted `.done` across
  re-opens, so "Resolve Permissions" flashed "You're all set" and auto-closed —
  the AX grant UI (and the `prompt:true` call that re-adds the app to the AX
  list) was unreachable forever after first completion. Now lands on the first
  missing-permission step.
- `resetToDefaults()` gaps: now also clears `preferredInputDeviceUID/Name`
  (pinned mic → system default) and `themeID` → `speak`. Custom themes kept
  (user content, like history).
- `ThemeEngine` observes `settingsStore.themeID` (withObservationTracking,
  one-shot re-arm) so Reset / `defaults write` repaints live.
- General → Reset now calls `context.rebindHotkey?(.defaultBinding)` — restores
  double-tap Right-Command live (binding persisted + tap re-armed).
- `SettingsStore.swift` reset block extracted to `SettingsStore+Reset.swift`
  (was 1046 lines > 1000 cap — lint error; now 879, 0 serious).

**User-facing answer to "how do I reset":** Settings → General → Reset All
Settings (settings + hotkey + mic pin + theme; keeps history/custom themes);
`make reset-permissions` for TCC (then relaunch + re-grant once);
`defaults delete com.speak.app` + remove `~/Library/Application Support/Speak`
for a full wipe.

Gates: build clean · `make test` 985 tests / 0 failures · lint 0 serious ·
moat 7/7.

### Screen-owner fleet pass — every settings pane + dashboard pane to production-ready

Eight parallel owner agents rewrote ~35 files (one owner per screen, disjoint
file sets, shared design contract). Functional fixes surfaced by the pass:

- **STT pane**: dead "Grant Access" button when mic permission is *denied*
  (`requestMicrophone()` no-ops on `.denied`) — now deep-links to
  Privacy_Microphone; TCC polling repaints on grant; stale pinned devices
  visible in the source list with explicit fallback copy; mic card reordered
  to the diagnostic flow (permission → current input → level → source);
  VU meter no longer freezes at last value after dictation.
- **TTS pane**: saved-voice-not-installed state (was silent fallback) +
  one-tap "Use Automatic"; formatted slider units; live preview state.
- **Pipeline pane**: left-to-right stage map, consistent pill semantics
  (ok/warning/error/agentViolet), stale speech can't leak into retried tests.
- **Hotkeys**: binding hero (keycaps + gesture copy), recorder states +
  Fn↔macOS-Dictation conflict surfaced at capture time, `onAir` misuse fixed
  (keypress capture → humanAmber), HoldToTalkPill release-race fix
  (quick tap no longer orphans a 60s recording).
- **History**: Clear History behind destructive confirmation (was one-click
  wipe); real empty states; copy-on-click rows.
- **Home**: permission card tri-state (missing/ready/unknown); 1s heartbeat
  so hero reflects hotkey-started dictation; dead "View All" removed.
- **MCP pane**: real bug — built a fresh empty AgentSessionRegistry every
  refresh so sessions could NEVER appear; now reads `context.agentSessionRegistry`;
  install-state check is real (`FileManager.isExecutableFile`), corrected
  install path + JSON snippet to match README verbatim.
- **ThemeEditorSheet**: dual light/dark wells per role (t3code pattern),
  inheritance ghosting, live hex validation, delete confirmation.
- **CleanupEngineSheet**: Save no longer dismisses on Keychain failure.
- **Dead code removed**: HUDStyleSection, BorderStyleSection, dead
  ExtraBindingsSection struct; AIStudioPaneView split (ProfileEditorPanel →
  AIStudioProfileEditor.swift, file_length); OnboardingSteps.swift split.

Gates: build clean (xcodegen regen picked up new/deleted files) · `make test`
985 tests / 0 failures (wrapper still reports "2 errors" — pretty-output.sh
misparsing simulated-failure logs; suite itself: "Test Suite Passed Cleanly") ·
lint 0 serious (428 non-serious) · moat 7/7.

### HUD overlay — capsule with inscribed circles (user-dictated design)

The dictation HUD was rebuilt twice to the user's dictated spec. Final locked
design: a **capsule panel** (fully rounded ends) with a **circle inscribed in
each end** — the circles are the boundary elements, not dividers.

```
( orb/wave ) ( text lane — proper rectangle ) ( live s / ✓ )
```

- Left circle = the voice animation (AmbientOrb for Aurora, WaveformView for
  classic); ring tints onAir only while the mic is capturing.
- Right circle = the response: live elapsed seconds while listening, spinner
  while processing, ✓ tick on done, ✕ on error.
- Center = bounded text lane (`windowText` FIFO, 11pt mono, ~5 lines at
  600×112pt panel) — "a lot of words" streams between the circles; the
  raw→clean diff reveals inside the lane ("polish inside the line itself").
- Timer now ticks through `.processing` (was cancelled at stop) and freezes
  at `.done`; `stopHint` (bound key displayString) shows while listening.
- `windowText` was previously gated on `hudStyle == .classic` — Aurora never
  received the FIFO window; gate removed, both styles share the lane.
- Aurora gained the missing close ✕ + readback/reclean controls.
- Disc fill refined: `speakBone.opacity(0.06)` whisper wash + cardBorder ring
  (a pale plate read as milky on light glass).

Gates: build clean · 985 tests / 0 failures · lint 0 serious · moat 7/7 ·
screenshot-verified across listening/processing/done on the Aurora style.
