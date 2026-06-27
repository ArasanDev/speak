// App/Settings/SettingsView.swift
//
// The Settings window — a TabView-based multi-section preferences UI.
//
// ARCHITECTURE (W3.1):
//   Replaced the flat 4-section Form with a 7-tab TabView following the macOS
//   `Settings` scene idiom (`tabItem` + SF Symbol). Sections:
//     General · Shortcuts · Transcription · AI Cleanup · Dictionary · Privacy · About
//
//   Progressive disclosure: each tab puts the common, day-to-day control up top;
//   advanced/future options (alt engines) are clearly secondary below a divider.
//
// CLEANUP-ENABLED COLLAPSE (W3.1):
//   The legacy `cleanupEnabled` boolean and the 4-level `cleanupLevel` picker were
//   two overlapping "no cleanup" controls. They are now unified:
//     - The AI Cleanup tab shows ONE picker (`effectiveCleanupLevel`, computed on
//       `SettingsStore`) instead of a Toggle + Picker pair.
//     - `.none` = off (equivalent to the old toggle being false).
//     - Style/engine pickers are disabled when level == .none (progressive disclosure).
//   `SettingsStore.cleanupEnabled` and `.cleanupLevel` remain the stored source of
//   truth so `SpeakEngine` and the dashboard StylePane continue to work unchanged.
//   The `effectiveCleanupLevel` setter keeps both in sync. [decision: W3.1]
//
// EXTENSION POINTS (do NOT fill in — later waves own these):
//   - Shortcuts / hotkey recorder: W3.2 (builder-input + builder-app)
//   - Pasting / restore-clipboard: W3.4 (builder-input)
//   - Snippets section: future wave
//
// THREADING:
//   All SwiftUI view bodies are implicitly @MainActor.
//   SettingsStore is @unchecked Sendable and safe to read on main.
//
// DESIGN LANGUAGE:
//   Monaco tokens for content/data text (SpeakTheme). System font for tab chrome,
//   labels, and picker text (per SpeakTheme header contract). SpeakSpacing grid
//   for all padding/spacing — no magic numbers.

import SpeakCore
import SwiftUI

// MARK: - SettingsView (root)

struct SettingsView: View {

    // The controller is needed for the Shortcuts tab: it provides `activeBinding`
    // (observed reactively post-recorder-save) and `rebindHotkey(_:)`.
    // `store` is extracted separately so child tabs don't depend on the whole controller.
    @ObservedObject var store: SettingsStore
    @ObservedObject var controller: DictationController

    // [decision: W3.1 — default tab is General; user re-selects across launches]
    @State private var selectedTab: SettingsTab = .general

    init(controller: DictationController) {
        self.controller = controller
        self.store = controller.settingsStore
    }

    var body: some View {
        TabView(selection: $selectedTab) {

            // 1 — General
            GeneralSettingsTab(store: store)
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsTab.general)

            // 2 — Shortcuts (recorder live in W1.1)
            ShortcutsSettingsTab(store: store, controller: controller)
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
                .tag(SettingsTab.shortcuts)

            // 3 — Transcription
            TranscriptionSettingsTab(store: store)
                .tabItem { Label("Transcription", systemImage: "mic") }
                .tag(SettingsTab.transcription)

            // 4 — AI Cleanup (effectiveCleanupLevel collapse lives here)
            AICleanupSettingsTab(store: store)
                .tabItem { Label("AI Cleanup", systemImage: "wand.and.stars") }
                .tag(SettingsTab.aiCleanup)

            // 5 — Dictionary (custom vocabulary — matches DictionaryPaneView binding)
            DictionarySettingsTab(store: store)
                .tabItem { Label("Dictionary", systemImage: "character.book.closed") }
                .tag(SettingsTab.dictionary)

            // 6 — Privacy (moat surface)
            PrivacySettingsTab()
                .tabItem { Label("Privacy", systemImage: "lock.shield") }
                .tag(SettingsTab.privacy)

            // 7 — About
            AboutSettingsTab()
                .tabItem { Label("About", systemImage: "info.circle") }
                .tag(SettingsTab.about)
        }
        // [decision: W3.1 — 560pt wide suits a 7-tab layout; 480pt min-height
        //  fits the Privacy section with its badge + four claims. SpeakSpacing.xl = 32,
        //  so 560 = 32 * ~17.5; rounded to the nearest clean value.]
        .frame(minWidth: 560, minHeight: 480)
    }
}

// MARK: - Tab identifier

private enum SettingsTab: Hashable {
    case general, shortcuts, transcription, aiCleanup, dictionary, privacy, about
}

// MARK: - 1. General

/// General: paste mode + future general controls.
/// `pasteMode` was previously in "Text Insertion" — folded here per W3.1 scope note.
private struct GeneralSettingsTab: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        Form {
            Section {
                Picker("Paste Mode", selection: Binding(
                    get: { store.pasteMode },
                    set: {
                        // Guard: `.accessibility` is a v1 stub — `.disabled(true)` on the
                        // tag row is visual-only and does not block keyboard navigation.
                        // Intercept and reject the write so the stored value stays `.cmdV`.
                        // [decision: custom binding guard — the only correct way to prevent
                        //  a disabled Picker row from being selected via keyboard nav on macOS]
                        guard $0 != .accessibility else { return }
                        store.pasteMode = $0
                    }
                )) {
                    Text("Cmd+V (default)").tag(PasteMode.cmdV)
                    Text("Accessibility API  (v1 — coming soon)")
                        .tag(PasteMode.accessibility)
                        .disabled(true)
                        .foregroundStyle(.secondary)
                }
                .pickerStyle(.menu)
                Text("Cmd+V is the default and works in almost every app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Text Insertion")
            }

            // W3.4 extension point — Pasting / restore-clipboard belongs here.
            // [stub: W3.4 (builder-input) owns the restore-clipboard toggle]
            Section {
                HStack {
                    Image(systemName: "arrow.uturn.left.circle")
                        .foregroundStyle(.secondary)
                    Text("Restore clipboard after paste")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Coming in W3.4")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            } header: {
                Text("Clipboard")
            }
        }
        .formStyle(.grouped)
        .padding(SpeakSpacing.md)
    }
}

// MARK: - 2. Shortcuts

/// Shortcuts: shows the current hotkey binding and lets the user record a new one.
/// The recorder sheet (HotkeyRecorderView) was added in W1.1.
///
/// Trigger-mode changes made *within* the recorder sheet are applied atomically via
/// `controller.rebindHotkey(_:)`, which updates both the live monitor and
/// `store.triggerMode` in one call. The picker below remains as a shortcut for
/// changing only the trigger mode without re-recording the key.
///
/// Note on Hybrid mode: `HotkeyBinding.Trigger` has two cases (`doubleTap`, `hold`).
/// A third `hybrid` case was intentionally not added — it requires runtime detection
/// logic in HotkeyMonitor and is deferred to a later wave. The picker offers the two
/// working modes only.
private struct ShortcutsSettingsTab: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var controller: DictationController

    // Sheet state for the recorder.
    @State private var showingRecorder: Bool = false

    var body: some View {
        Form {
            Section {
                // Trigger mode picker — key-agnostic labels; the actual key
                // is shown via `controller.activeBinding.displayString` below.
                Picker("Activation Mode", selection: Binding(
                    get: { store.triggerMode },
                    set: { store.triggerMode = $0 }
                )) {
                    Text("Double-tap (toggle)").tag(HotkeyBinding.Trigger.doubleTap)
                    Text("Hold (push-to-talk)").tag(HotkeyBinding.Trigger.hold)
                }
                .pickerStyle(.inline)

                Group {
                    switch store.triggerMode {
                    case .doubleTap:
                        Text("Tap the hotkey twice to start; tap once to stop.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                    case .hold:
                        Text("Hold the hotkey to record; release to stop and paste.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Activation")
            }

            Section {
                HStack {
                    Text("Current Hotkey")
                    Spacer()
                    // Monaco for the keybinding label (data, not chrome). [decision: W3.1]
                    // Reads `controller.activeBinding.displayString` so the label refreshes
                    // immediately after a recorder save without a relaunch. [decision: W1.1]
                    Text(controller.activeBinding.displayString)
                        .font(.speakMonoBody)
                        .foregroundStyle(.primary)
                        .padding(.horizontal, SpeakSpacing.sm)
                        .padding(.vertical, SpeakSpacing.xs)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.speakSurface)
                        )
                }

                // Record button — opens the HotkeyRecorderView sheet.
                Button("Record\u{2026}") {
                    showingRecorder = true
                }
                .sheet(isPresented: $showingRecorder) {
                    HotkeyRecorderView(
                        initialBinding: controller.activeBinding,
                        onSave: { newBinding in
                            controller.rebindHotkey(newBinding)
                            showingRecorder = false
                        },
                        onCancel: {
                            showingRecorder = false
                        }
                    )
                }
            } header: {
                Text("Hotkey")
            } footer: {
                // Hybrid mode (hold + double-tap timing disambiguation) is deferred
                // — it requires HotkeyMonitor detection work. Only two modes ship in W1.1.
                Text("Record any key+modifier combo or a modifier-only key (e.g. Right-Command, Fn). Hybrid mode comes in a later wave.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(SpeakSpacing.md)
    }
}

// MARK: - 3. Transcription

private struct TranscriptionSettingsTab: View {
    @ObservedObject var store: SettingsStore

    // Locale list loaded async from SpeechTranscriber.supportedLocales.
    // Seeded with the current selection so the picker is never visually blank
    // while loading (the selected row always appears even before the full list
    // arrives). [decision: 1.2 — seed avoids a blank-picker flash on open]
    @State private var supportedLocales: [Locale] = []
    @State private var installedLocaleIDs: Set<String> = []
    @State private var localesLoaded = false
    /// `true` when the stored locale was not in the supported list and was auto-reset.
    /// Drives the unsupported-locale alert so the reset is visible to the user.
    @State private var showLanguageResetAlert = false
    /// The locale the settings were silently reset TO — named in the alert message.
    @State private var pendingResetLocale: Locale?

    var body: some View {
        Form {
            Section {
                if !localesLoaded {
                    // Loading state — show a spinner until the async fetch completes.
                    // [decision: 1.2 — ProgressView placeholder; avoids blank picker]
                    HStack {
                        Text("Language")
                        Spacer()
                        ProgressView()
                            .controlSize(.small)
                    }
                } else {
                    Picker("Language", selection: Binding(
                        get: { store.language.identifier },
                        set: { store.language = Locale(identifier: $0) }
                    )) {
                        ForEach(supportedLocales, id: \.identifier) { locale in
                            HStack(spacing: SpeakSpacing.xs) {
                                Text(SpeechTranscriberLocaleSource.displayName(for: locale))
                                // Indicate locales that still need a model download.
                                // [decision: 1.2 — informational label; provisionAsset
                                //  handles the actual download at transcription time]
                                if !installedLocaleIDs.contains(locale.identifier) {
                                    Text("(download)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .tag(locale.identifier)
                        }
                    }
                    .pickerStyle(.menu)
                }
            } header: {
                Text("Language")
            } footer: {
                if localesLoaded && supportedLocales.isEmpty {
                    // SpeechTranscriber not available on this device (e.g., Intel Mac).
                    // The existing engine falls back gracefully; the picker just shows nothing.
                    Text("No supported languages found — SpeechAnalyzer may not be available on this device.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .task {
                // Fetch the locale lists concurrently; both are get async.
                // [verified: SpeechTranscriber.supportedLocales: [Locale] { get async }
                //  and SpeechTranscriber.installedLocales: [Locale] { get async }
                //  from Apple developer docs, 2026-06-22]
                async let supported = SpeechTranscriberLocaleSource.supportedLocales()
                async let installed = SpeechTranscriberLocaleSource.installedLocales()
                let (s, i) = await (supported, installed)
                supportedLocales = s
                installedLocaleIDs = Set(i.map(\.identifier))
                localesLoaded = true

                // If the stored locale is not in the supported list, reset to
                // the first supported locale to avoid a stuck-blank picker — but
                // surface an alert rather than resetting silently.
                // [decision: alert on unsupported-locale reset — the user deserves
                //  to know their language preference changed; Monaco caption below
                //  is the secondary affordance. benchmark.md §7]
                if !s.isEmpty && !s.contains(where: { $0.identifier == store.language.identifier }) {
                    let fallback = s[0]
                    store.language = fallback
                    pendingResetLocale = fallback
                    showLanguageResetAlert = true
                }
            }

            Section {
                Picker("Speech Engine", selection: Binding(
                    get: { store.sttEngine },
                    set: { store.sttEngine = $0 }
                )) {
                    Text("Apple SpeechAnalyzer (default)")
                        .tag(STTEngine.appleSpeech)
                    Text("WhisperKit  (v0.1 — coming soon)")
                        .tag(STTEngine.whisperKit)
                        .disabled(true)
                        .foregroundStyle(.secondary)
                    Text("whisper.cpp  (v1 — coming soon)")
                        .tag(STTEngine.whisperCpp)
                        .disabled(true)
                        .foregroundStyle(.secondary)
                }
                .pickerStyle(.menu)
                Text("Apple SpeechAnalyzer runs 100% on-device — no audio ever leaves your Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Engine")
                    .font(.caption)
            } footer: {
                Text("Alternative engines (WhisperKit, whisper.cpp) arrive in v0.1 and v1.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(SpeakSpacing.md)
        .alert(
            "Language Reset",
            isPresented: $showLanguageResetAlert,
            actions: {
                Button("OK", role: .cancel) { pendingResetLocale = nil }
            },
            message: {
                // Show the locale display name when available; fall back to identifier.
                let name = pendingResetLocale.flatMap {
                    $0.localizedString(forIdentifier: $0.identifier)
                } ?? pendingResetLocale?.identifier ?? "the first supported language"
                Text("Your previously selected language is no longer available. " +
                     "Language has been reset to \(name).")
            }
        )
    }
}

// MARK: - 4. AI Cleanup

/// AI Cleanup: unified effectiveCleanupLevel picker collapses the old toggle + level pair.
/// Style and Engine pickers are disabled when level == .none (progressive disclosure).
/// A live diff preview shows what each intensity level actually changes — the W4.1
/// transparency moat. The preview uses a canned sample transcript (FM is unavailable
/// on dev Macs) with illustrative cleaned outputs that match each intensity's prompt
/// contract. [decision W4.1: canned sample in Settings preview; live diff is in History]
///
/// Wave 2.1 additions:
///   - Engine picker now offers Foundation Models (default) + Ollama (opt-in) +
///     MLX (opt-in, v0.1+). Ollama and MLX rows are always enabled in the picker
///     but the cleaners behind them are stubs (`isAvailable == false`) — the user
///     selects them, then sees the guided-setup sheet explaining what to install.
///   - `OllamaSetupSheet` is presented when the user picks Ollama and explains
///     how to install Ollama and pull a model. The sheet has no live connection
///     test in v0 — networking code is moat-forbidden in App/ (see `OllamaCleaner.swift`).
///
/// The engine picker is *independent of* the cleanup level — it controls which engine
/// runs when cleanup is active, so it is only disabled when `cleanupActive == false`.
private struct AICleanupSettingsTab: View {
    @ObservedObject var store: SettingsStore

    /// Derived: cleanup is active when effectiveCleanupLevel != .none.
    private var cleanupActive: Bool { store.effectiveCleanupLevel != .none }

    // MARK: - Ollama setup sheet state

    /// Whether to show the Ollama guided-setup sheet.
    @State private var showOllamaSetup: Bool = false

    // MARK: - Canned sample for the diff preview

    /// The fixed raw transcript used as the diff preview source.
    /// Chosen to show all four intensity levels meaningfully:
    ///   - light: strips "um"/"you know", adds periods and commas
    ///   - medium: additionally tightens "was thinking that maybe" → "think"
    ///   - high: additionally restructures into two clean sentences
    /// [decision W4.1: single canned input, four distinct cleaned outputs; this is
    ///  illustrative — the live engine may clean differently depending on context]
    private let sampleRaw =
        "um I was thinking that maybe we should like move the meeting to thursday " +
        "because you know on wednesday I have a conflict with another thing"

    /// Returns the canned cleaned output for `level`. These strings match the
    /// intensity ladder description in `CleanupLevel.levelDescription` so the
    /// user can read both and understand what each level does.
    /// [decision W4.1: named function (not a switch inline) so test fixtures can
    ///  call the same mapping without instantiating the view]
    private func sampleCleaned(for level: CleanupLevel) -> String? {
        switch level {
        case .none:
            // None = raw passthrough; cleanedText nil triggers "No AI cleanup" state.
            return nil

        case .light:
            // Light: filler removal + punctuation. Words and structure unchanged.
            return "I was thinking that maybe we should like move the meeting to Thursday, " +
                   "because on Wednesday I have a conflict with another thing."

        case .medium:
            // Medium: + sentence tightening. "was thinking that maybe" → "think",
            //         "another thing" → "another commitment".
            return "I think we should move the meeting to Thursday. " +
                   "I have a conflict on Wednesday."

        case .high:
            // High: + restructuring + paragraph clarity. Two clean, complete sentences.
            return "Let\u{2019}s move the meeting to Thursday. I have a scheduling conflict on Wednesday."
        }
    }

    // MARK: - Engine-picker binding

    /// A binding that maps between `CleanupEngine` (associated-value enum) and the
    /// picker rows. The Ollama row uses a canonical model tag; picking Ollama from a
    /// Foundation-Models state seeds the `model` field with the default Ollama model.
    ///
    /// [decision Wave 2.1: picker tags use canonical defaults (.ollama(model:"qwen2.5:3b"),
    ///  .mlx(model:"Qwen2.5-3B-Instruct-4bit")) instead of empty strings, so the stored
    ///  engine is immediately meaningful for the future real implementation.]
    private var engineBinding: Binding<CleanupEngine> {
        Binding(
            get: { store.cleanupEngine },
            set: { newEngine in
                store.cleanupEngine = newEngine
                // When the user picks Ollama, surface the guided-setup sheet so they
                // know what to install. The sheet is informational in v0.
                if case .ollama = newEngine {
                    showOllamaSetup = true
                }
            }
        )
    }

    var body: some View {
        Form {
            // Primary control — the collapsed single picker.
            Section {
                Picker("Cleanup Level", selection: Binding(
                    get: { store.effectiveCleanupLevel },
                    set: { store.effectiveCleanupLevel = $0 }
                )) {
                    ForEach(CleanupLevel.allCases, id: \.self) { level in
                        Text(level.displayName).tag(level)
                    }
                }
                .pickerStyle(.inline)

                // Description updates live with the selection.
                Text(store.effectiveCleanupLevel.levelDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Intensity")
            } footer: {
                Text("None = raw transcript pasted with no AI changes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // W4.1 diff preview — shows exactly what the selected intensity changes.
            // CleanupDiffView handles .none → "No AI cleanup applied" state internally.
            // [decision W4.1: Settings preview uses canned illustrative text; live
            //  diffs from real dictations appear in History]
            Section {
                CleanupDiffView(
                    rawText: sampleRaw,
                    cleanedText: sampleCleaned(for: store.effectiveCleanupLevel)
                )
                // Constrain height so the form stays scrollable on small displays.
                // [decision W4.1: 160pt = ~4 lines at speakMonoBody — enough to read
                //  the diff without dominating the Settings pane]
                .frame(minHeight: 160)
            } header: {
                Text("Preview")
            } footer: {
                Text("Illustrative preview — your actual results may vary. Live diffs appear in History.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Voice / style — disabled when cleanup is off.
            Section {
                Picker("Voice", selection: Binding(
                    get: { store.cleanupStyle },
                    set: { store.cleanupStyle = $0 }
                )) {
                    ForEach(CleanupStyle.allCases, id: \.self) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .pickerStyle(.menu)
                .disabled(!cleanupActive)
                if !cleanupActive {
                    Text("Set a cleanup level above to enable voice selection.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Voice")
            }

            // Engine — Wave 2.1: picker enabled; Ollama/MLX are opt-in stubs.
            // Selecting Ollama presents the guided-setup sheet (no live detection in v0).
            // Selecting MLX shows a "v0.1+ — coming soon" note in the picker footer.
            Section {
                Picker("Cleanup Engine", selection: engineBinding) {
                    // v0 default — always available (requires Apple Intelligence on device).
                    Text("Foundation Models").tag(CleanupEngine.foundationModels)
                    // v0.1 opt-in — localhost Ollama server; stub in v0 (isAvailable=false).
                    // Canonical default model: Qwen2.5 3B — small, fast, quality.
                    Text("Ollama (local server)").tag(CleanupEngine.ollama(model: "qwen2.5:3b"))
                    // v0.1+ opt-in — MLX on-device; stub in v0 (third-party dep forbidden).
                    Text("MLX (v0.1+, coming soon)")
                        .tag(CleanupEngine.mlx(model: "Qwen2.5-3B-Instruct-4bit"))
                        .foregroundStyle(.secondary)
                }
                .pickerStyle(.menu)
                .disabled(!cleanupActive)

                // Engine-specific status note below the picker.
                // [decision Wave 2.1: single Text that switches on the selected engine,
                //  so context is always visible without needing to open a sheet]
                engineStatusNote
            } header: {
                Text("Engine")
            } footer: {
                engineFootnote
            }
            .sheet(isPresented: $showOllamaSetup) {
                OllamaSetupSheet(isPresented: $showOllamaSetup)
            }
        }
        .formStyle(.grouped)
        .padding(SpeakSpacing.md)
    }

    // MARK: - Engine-picker contextual text

    /// One-line status note shown below the engine picker. Updates live with the selection.
    @ViewBuilder
    private var engineStatusNote: some View {
        switch store.cleanupEngine {
        case .foundationModels:
            Text("Foundation Models runs on-device — no network, no account.")
                .font(.caption)
                .foregroundStyle(.secondary)

        case .ollama:
            HStack(spacing: SpeakSpacing.xs) {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                // Clarify stub status so user knows why cleanup still falls back to raw.
                Text("Requires Ollama — see setup guide.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Setup guide\u{2026}") { showOllamaSetup = true }
                    .font(.caption)
                    .buttonStyle(.borderless)
            }

        case .mlx:
            Text("MLX support arrives in v0.1 — currently falling back to raw transcript.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// Footer text below the Engine section. Varies by selection.
    @ViewBuilder
    private var engineFootnote: some View {
        switch store.cleanupEngine {
        case .foundationModels:
            Text("Requires Apple Intelligence on this Mac. Falls back to raw transcript when unavailable.")
                .font(.caption)
                .foregroundStyle(.secondary)

        case .ollama:
            Text("Ollama support arrives in v0.1. In v0, speak falls back to raw transcript when this engine is selected.")
                .font(.caption)
                .foregroundStyle(.secondary)

        case .mlx:
            Text("MLX requires third-party Swift packages; available from v0.1.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - 5. Dictionary

/// Dictionary: custom vocabulary for the STT recognizer.
/// Binding pattern mirrors DictionaryPaneView to stay consistent — the store
/// is the single source of truth for both surfaces.
private struct DictionarySettingsTab: View {
    @ObservedObject var store: SettingsStore
    @State private var newTerm: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.md) {
            // Add bar
            HStack(spacing: SpeakSpacing.sm) {
                TextField("Add a word or name\u{2026}", text: $newTerm)
                    .textFieldStyle(.roundedBorder)
                    .font(.speakMonoBody)
                    .onSubmit(addTerm)
                Button("Add", action: addTerm)
                    .disabled(newTerm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, SpeakSpacing.md)
            .padding(.top, SpeakSpacing.md)

            Text("Custom words are fed to the speech recogniser as contextual hints so speak spells your names and terms correctly.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, SpeakSpacing.md)

            Divider()

            let terms = store.customVocabulary
            if terms.isEmpty {
                VStack(spacing: SpeakSpacing.sm) {
                    Image(systemName: "character.book.closed")
                        .font(.system(size: 32))
                        .foregroundStyle(.tertiary)
                    Text("No custom words yet.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(SpeakSpacing.lg)
            } else {
                List {
                    ForEach(terms, id: \.self) { term in
                        HStack {
                            Text(term)
                                .font(.speakMonoBody)
                            Spacer()
                            Button {
                                removeTerm(term)
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.borderless)
                            .help("Remove \(term)")
                        }
                        .padding(.vertical, SpeakSpacing.xs)
                    }
                }
                .listStyle(.inset)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(SpeakSpacing.md)
    }

    private func addTerm() {
        let updated = CustomVocabulary.adding(newTerm, to: store.customVocabulary)
        store.customVocabulary = updated
        newTerm = ""
    }

    private func removeTerm(_ term: String) {
        store.customVocabulary = CustomVocabulary.removing(term, from: store.customVocabulary)
    }
}

// MARK: - 6. Privacy (moat surface)

/// Privacy: the structural moat — four concrete on-device guarantees, calm and premium.
/// This is marketing AND trust: a local-first app's clearest differentiator.
private struct PrivacySettingsTab: View {

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SpeakSpacing.lg) {

                // Badge block — lock icon + headline
                HStack(alignment: .top, spacing: SpeakSpacing.md) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 40))
                        // Teal/green conveys "safe" without overriding the amber accent.
                        // [decision: system green — native macOS feel, no custom color needed]
                        .foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: SpeakSpacing.xs) {
                        Text("100% On-Device")
                            .font(.speakMonoTitle)
                        Text("speak never sends your voice, your words, or your clipboard anywhere.")
                            .font(.speakMonoCaption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(SpeakSpacing.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.speakSurface)
                )

                // Four guarantee rows
                VStack(alignment: .leading, spacing: SpeakSpacing.md) {
                    PrivacyGuaranteeRow(
                        icon: "mic.slash.fill",
                        title: "No cloud audio",
                        detail: "Speech is processed by Apple SpeechAnalyzer entirely on your Mac. Audio never leaves the device."
                    )
                    Divider()
                    PrivacyGuaranteeRow(
                        icon: "brain.head.profile",
                        title: "No cloud AI",
                        detail: "Neat-writing uses Apple Foundation Models — the neural engine on your chip. No API call, no account, no quota."
                    )
                    Divider()
                    PrivacyGuaranteeRow(
                        icon: "person.slash",
                        title: "No account required",
                        detail: "speak is free, open-source, and MIT-licensed. There is no sign-in, no subscription, and no usage metering."
                    )
                    Divider()
                    PrivacyGuaranteeRow(
                        icon: "clipboard.fill",  // clipboard → icon for the clipboard topic
                        title: "Never reads your clipboard",
                        detail: "speak only writes to the clipboard to paste your dictation. It never reads what is already there."
                    )
                }
                .padding(SpeakSpacing.lg)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.speakSurface)
                )

                // W3.3 extension point — auto-delete transcript policy belongs here.
                // [stub: W3.3 owns transcript auto-delete and audio-retention policy]
                HStack {
                    Image(systemName: "timer")
                        .foregroundStyle(.secondary)
                    Text("Transcript auto-delete policy")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Coming in W3.3")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(SpeakSpacing.md)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.speakSurface)
                )
            }
            .padding(SpeakSpacing.lg)
        }
    }
}

/// A single privacy guarantee row: icon + title + detail.
private struct PrivacyGuaranteeRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: SpeakSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(.green)
                .frame(width: 24)  // [decision: 24pt icon column width = 3× SpeakSpacing.sm]
            VStack(alignment: .leading, spacing: SpeakSpacing.xs) {
                Text(title)
                    .font(.speakMonoBody)
                Text(detail)
                    .font(.speakMonoCaption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - 7. About

private struct AboutSettingsTab: View {

    // Static URL constants — compile-time literals guaranteed non-nil, but
    // URL(string:) returns Optional so we store as URL? and map at the call site
    // rather than force-unwrap. [decision: W3.1 — no force-unwrap rule]
    fileprivate static let githubURL = URL(string: "https://github.com/tamilarasanraja/speak")
    fileprivate static let issuesURL = URL(string: "https://github.com/tamilarasanraja/speak/issues")

    // Version string from the bundle — zero magic strings. [decision: W3.1]
    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        return [version, build.map { "(\($0))" }]
            .compactMap { $0 }
            .joined(separator: " ")
    }

    var body: some View {
        VStack(spacing: SpeakSpacing.lg) {
            Spacer()

            // App name + version in Monaco — content voice, not chrome.
            VStack(spacing: SpeakSpacing.sm) {
                Image(systemName: "waveform")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.speakAccent)
                Text("speak")
                    .font(.speakMonoTitle)
                if !appVersion.isEmpty {
                    Text("v\(appVersion)")
                        .font(.speakMonoCaption)
                        .foregroundStyle(.secondary)
                }
                Text("Free · Open-source · MIT")
                    .font(.speakMonoCaption)
                    .foregroundStyle(.secondary)
            }

            Divider()
                .frame(maxWidth: 200)  // [decision: short decorative divider, visual balance]

            // Links — URL(string:) with compile-time literals always succeeds, but
            // force-unwrap is banned by the hard rules. Use static lets so the
            // compiler can prove the optionality at the call site. [decision: W3.1]
            VStack(spacing: SpeakSpacing.sm) {
                AboutSettingsTab.githubURL.map { url in
                    Link("View on GitHub", destination: url)
                        .font(.speakMonoCaption)
                }
                AboutSettingsTab.issuesURL.map { url in
                    Link("Report an issue", destination: url)
                        .font(.speakMonoCaption)
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(SpeakSpacing.lg)
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Settings — General") {
    // Preview with a stub DictationController is not practical (it starts a
    // CGEventTap). Use a simplified init path for the preview.
    SettingsPreviewWrapper()
}

private struct SettingsPreviewWrapper: View {
    private let store = SettingsStore()
    var body: some View {
        TabView {
            GeneralSettingsTab(store: store)
                .tabItem { Label("General", systemImage: "gearshape") }
            AICleanupSettingsTab(store: store)
                .tabItem { Label("AI Cleanup", systemImage: "wand.and.stars") }
            PrivacySettingsTab()
                .tabItem { Label("Privacy", systemImage: "lock.shield") }
            AboutSettingsTab()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(minWidth: 560, minHeight: 480)
    }
}
#endif
