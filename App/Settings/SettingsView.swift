// App/Settings/SettingsView.swift
//
// The Settings window — a TabView-based multi-section preferences UI.
//
// ARCHITECTURE (P11-c):
//   A 6-tab TabView following the macOS `Settings` scene idiom (`tabItem` + SF Symbol).
//   Sections:
//     General · Transcription · AI Cleanup · Hotkey & Input · Privacy & Data · About
//
//   Progressive disclosure: each tab puts the common, day-to-day control up top;
//   advanced/future options (alt engines) are clearly secondary below a divider.
//
// CLEANUP-ENABLED COLLAPSE (P11-c):
//   The legacy `cleanupEnabled` boolean and the 4-level `cleanupLevel` picker were
//   two overlapping "no cleanup" controls. They are now unified:
//     - The AI Cleanup tab shows ONE picker (`effectiveCleanupLevel`, computed on
//       `SettingsStore`) instead of a Toggle + Picker pair.
//     - `.none` = off (equivalent to the old toggle being false).
//     - Style/engine pickers are disabled when level == .none (progressive disclosure).
//   `SettingsStore.cleanupEnabled` and `.cleanupLevel` remain the stored source of
//   truth so `SpeakEngine` and the dashboard StylePane continue to work unchanged.
//   The `effectiveCleanupLevel` setter keeps both in sync. [decision: P11-c]
//
// EXTENSION POINTS (do NOT fill in — later phases own these):
//   - Snippets section: future phase
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

    // The controller is needed for the Hotkey & Input tab: it provides `activeBinding`
    // (observed reactively post-recorder-save) and `rebindHotkey(_:)`.
    // It also provides `historyStore` for the Privacy & Data tab.
    // `store` is extracted separately so child tabs don't depend on the whole controller.
    let store: SettingsStore
    let controller: DictationController

    // [decision: P11-c — default tab is General; user re-selects across launches]
    @State private var selectedTab: SettingsTab = .general

    init(controller: DictationController) {
        self.controller = controller
        self.store = controller.settingsStore
    }

    var body: some View {
        TabView(selection: $selectedTab) {

            // 1 — General (theme, notifications, language)
            GeneralSettingsTab(store: store)
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsTab.general)

            // 2 — Transcription (language, engine, custom vocabulary)
            TranscriptionSettingsTab(store: store)
                .tabItem { Label("Transcription", systemImage: "mic") }
                .tag(SettingsTab.transcription)

            // 3 — AI Cleanup (effectiveCleanupLevel collapse lives here)
            AICleanupSettingsTab(store: store)
                .tabItem { Label("AI Cleanup", systemImage: "wand.and.stars") }
                .tag(SettingsTab.aiCleanup)

            // 4 — Hotkey & Input (hotkey recorder, streaming, auto-paste)
            HotkeyInputSettingsTab(store: store, controller: controller)
                .tabItem { Label("Hotkey & Input", systemImage: "keyboard") }
                .tag(SettingsTab.hotkeyInput)

            // 5 — Privacy & Data (moat surface + clear/export history)
            PrivacyDataSettingsTab(store: store, controller: controller)
                .tabItem { Label("Privacy & Data", systemImage: "lock.shield") }
                .tag(SettingsTab.privacyData)

            // 6 — About
            AboutSettingsTab()
                .tabItem { Label("About", systemImage: "info.circle") }
                .tag(SettingsTab.about)
        }
        // [decision: P11-c — 760pt wide × 520pt tall for 6-tab layout.
        //  SpeakSpacing.xl = 32, so 760 = 32 * ~23.75; 520 fits Privacy & Data
        //  section with badge, four guarantee rows, and button controls.]
        .frame(minWidth: 760, minHeight: 520)
    }
}

// MARK: - Tab identifier

private enum SettingsTab: Hashable {
    case general, transcription, aiCleanup, hotkeyInput, privacyData, about
}

// MARK: - 1. General

/// General: appearance (theme), notifications, paste mode, and language selection.
/// [decision: P11-c — consolidates user-facing preferences that apply globally]
private struct GeneralSettingsTab: View {
    let store: SettingsStore

    // Locale list loaded async from SpeechTranscriber.supportedLocales.
    @State private var supportedLocales: [Locale] = []
    @State private var installedLocaleIDs: Set<String> = []
    @State private var localesLoaded = false
    @State private var showLanguageResetAlert = false
    @State private var pendingResetLocale: Locale?

    var body: some View {
        Form {
            Section {
                Picker("Appearance", selection: Binding(
                    get: { store.appTheme },
                    set: { store.appTheme = $0 }
                )) {
                    Text("Light").tag(AppTheme.light)
                    Text("Dark").tag(AppTheme.dark)
                    Text("System (default)").tag(AppTheme.system)
                }
                .pickerStyle(.menu)
            } header: {
                Text("Theme")
            }

            Section {
                Toggle("Enable notifications", isOn: Binding(
                    get: { store.notificationsEnabled },
                    set: { store.notificationsEnabled = $0 }
                ))
                Text("Show notifications for dictation completion and errors.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Notifications")
            }

            Section {
                if !localesLoaded {
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
                    Text("No supported languages found — SpeechAnalyzer may not be available on this device.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .task {
                async let supported = SpeechTranscriberLocaleSource.supportedLocales()
                async let installed = SpeechTranscriberLocaleSource.installedLocales()
                let (s, i) = await (supported, installed)
                supportedLocales = s
                installedLocaleIDs = Set(i.map(\.identifier))
                localesLoaded = true

                if !s.isEmpty && !s.contains(where: { $0.identifier == store.language.identifier }) {
                    let fallback = s[0]
                    store.language = fallback
                    pendingResetLocale = fallback
                    showLanguageResetAlert = true
                }
            }

            Section {
                Picker("Paste Mode", selection: Binding(
                    get: { store.pasteMode },
                    set: {
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
                let name = pendingResetLocale.flatMap {
                    $0.localizedString(forIdentifier: $0.identifier)
                } ?? pendingResetLocale?.identifier ?? "the first supported language"
                Text("Your previously selected language is no longer available. " +
                     "Language has been reset to \(name).")
            }
        )
    }
}

// MARK: - 4. Hotkey & Input

/// Hotkey & Input: hotkey binding, activation mode, and input/output controls.
/// Shows the current hotkey binding and lets the user record a new one.
///
/// Trigger-mode changes made *within* the recorder sheet are applied atomically via
/// `controller.rebindHotkey(_:)`, which updates both the live monitor and
/// `store.triggerMode` in one call. [decision: P11-c]
///
/// Note on Hybrid mode: `HotkeyBinding.Trigger` has two cases (`doubleTap`, `hold`).
/// A third `hybrid` case was intentionally not added — it requires runtime detection
/// logic in HotkeyMonitor and is deferred to a later phase.
private struct HotkeyInputSettingsTab: View {
    let store: SettingsStore
    let controller: DictationController

    @State private var showingRecorder: Bool = false

    var body: some View {
        Form {
            Section {
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
                Text("Record any key+modifier combo or a modifier-only key (e.g. Right-Command, Fn).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Auto-paste after dictation", isOn: Binding(
                    get: { store.autoPasteEnabled },
                    set: { store.autoPasteEnabled = $0 }
                ))
                Text("When enabled, cleaned text is automatically pasted at the cursor after dictation ends.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Output")
            }
        }
        .formStyle(.grouped)
        .padding(SpeakSpacing.md)
    }
}

// MARK: - 2. Transcription

/// Transcription: speech engine configuration and custom vocabulary hints.
/// Language selection is now in General. [decision: P11-c]
private struct TranscriptionSettingsTab: View {
    let store: SettingsStore
    @State private var newTerm: String = ""

    var body: some View {
        Form {
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
            } footer: {
                Text("Alternative engines (WhisperKit, whisper.cpp) arrive in v0.1 and v1.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack(spacing: SpeakSpacing.sm) {
                    TextField("Add a word or name\u{2026}", text: $newTerm)
                        .textFieldStyle(.roundedBorder)
                        .font(.speakMonoBody)
                        .onSubmit(addTerm)
                    Button("Add", action: addTerm)
                        .disabled(newTerm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                Text("Custom words are fed to the speech recogniser as contextual hints so speak spells your names and terms correctly.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Divider()

                let terms = store.customVocabulary
                if terms.isEmpty {
                    VStack(spacing: SpeakSpacing.sm) {
                        Image(systemName: "character.book.closed")
                            .font(.system(size: 24))
                            .foregroundStyle(.tertiary)
                        Text("No custom words yet.")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(SpeakSpacing.md)
                } else {
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
                    }
                }
            } header: {
                Text("Custom Vocabulary")
            } footer: {
                Text("Custom vocabulary is matched against transcriptions to improve accuracy for your specific names and terms.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
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
    let store: SettingsStore

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

// MARK: - 5. Privacy & Data

/// Privacy & Data: the structural moat (four on-device guarantees) + data controls.
/// This is marketing AND trust: a local-first app's clearest differentiator.
/// [decision: P11-c — add export/clear/reset buttons for P11 compliance]
private struct PrivacyDataSettingsTab: View {
    let store: SettingsStore
    let controller: DictationController

    @State private var showResetConfirmation = false
    @State private var resetError: String?
    @State private var showResetError = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SpeakSpacing.lg) {

                // Badge block — lock icon + headline
                HStack(alignment: .top, spacing: SpeakSpacing.md) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 40))
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
                        icon: "clipboard.fill",
                        title: "Never reads your clipboard",
                        detail: "speak only writes to the clipboard to paste your dictation. It never reads what is already there."
                    )
                }
                .padding(SpeakSpacing.lg)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.speakSurface)
                )

                // Data controls — reset settings, clear history, export data.
                VStack(alignment: .leading, spacing: SpeakSpacing.md) {
                    Text("Data Management")
                        .font(.headline)

                    Button(action: { showResetConfirmation = true }) {
                        HStack {
                            Image(systemName: "arrow.counterclockwise")
                            Text("Reset All Settings to Defaults")
                            Spacer()
                        }
                        .foregroundStyle(.primary)
                    }
                    .padding(.vertical, SpeakSpacing.sm)
                    .padding(.horizontal, SpeakSpacing.md)
                    .background(Color.speakSurface)
                    .cornerRadius(6)

                    Button(action: {
                        Task {
                            do {
                                try await controller.historyStore.clear()
                                SpeakLog.app.info("History cleared via Settings")
                            } catch {
                                resetError = error.localizedDescription
                                showResetError = true
                            }
                        }
                    }) {
                        HStack {
                            Image(systemName: "trash")
                            Text("Clear All History")
                            Spacer()
                        }
                        .foregroundStyle(.primary)
                    }
                    .padding(.vertical, SpeakSpacing.sm)
                    .padding(.horizontal, SpeakSpacing.md)
                    .background(Color.speakSurface)
                    .cornerRadius(6)

                    Button(action: {
                        Task {
                            do {
                                let exported = try await controller.historyStore.export()
                                let pasteboard = NSPasteboard.general
                                pasteboard.clearContents()
                                pasteboard.setString(exported, forType: .string)
                                SpeakLog.app.info("History exported via Settings")
                            } catch {
                                resetError = error.localizedDescription
                                showResetError = true
                            }
                        }
                    }) {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                            Text("Export History as JSON")
                            Spacer()
                        }
                        .foregroundStyle(.primary)
                    }
                    .padding(.vertical, SpeakSpacing.sm)
                    .padding(.horizontal, SpeakSpacing.md)
                    .background(Color.speakSurface)
                    .cornerRadius(6)

                    Text("History is stored locally on your Mac. Export creates a JSON backup on your clipboard.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(SpeakSpacing.lg)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.speakSurface)
                )
            }
            .padding(SpeakSpacing.lg)
        }
        .alert(
            "Reset Settings?",
            isPresented: $showResetConfirmation,
            actions: {
                Button("Cancel", role: .cancel) { }
                Button("Reset", role: .destructive) {
                    store.resetToDefaults()
                }
            },
            message: {
                Text("This will reset all settings to their defaults. History is not affected.")
            }
        )
        .alert(
            "Error",
            isPresented: $showResetError,
            actions: {
                Button("OK", role: .cancel) { resetError = nil }
            },
            message: {
                if let error = resetError {
                    Text(error)
                }
            }
        )
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

// MARK: - 6. About

private struct AboutSettingsTab: View {

    // Static URL constants — compile-time literals guaranteed non-nil, but
    // URL(string:) returns Optional so we store as URL? and map at the call site
    // rather than force-unwrap. [decision: P11-c — no force-unwrap rule]
    fileprivate static let githubURL = URL(string: "https://github.com/tamilarasanraja/speak")
    fileprivate static let issuesURL = URL(string: "https://github.com/tamilarasanraja/speak/issues")

    // Version string from the bundle — zero magic strings. [decision: P11-c]
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
            // compiler can prove the optionality at the call site. [decision: P11-c]
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
    // CGEventTap and requires HistoryStore). Use a simplified init path for the preview.
    SettingsPreviewWrapper()
}

private struct SettingsPreviewWrapper: View {
    private let store = SettingsStore()
    var body: some View {
        TabView {
            GeneralSettingsTab(store: store)
                .tabItem { Label("General", systemImage: "gearshape") }
            TranscriptionSettingsTab(store: store)
                .tabItem { Label("Transcription", systemImage: "mic") }
            AICleanupSettingsTab(store: store)
                .tabItem { Label("AI Cleanup", systemImage: "wand.and.stars") }
            AboutSettingsTab()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(minWidth: 760, minHeight: 520)
    }
}
#endif
