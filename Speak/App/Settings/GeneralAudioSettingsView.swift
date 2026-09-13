// App/Settings/GeneralAudioSettingsView.swift
//
// "General & Audio" — the first category of the dedicated Settings experience.
// Startup, speech language, live microphone status, text insertion, and
// voice-out readback. Rows use the SettingsChrome card/row primitives
// (title + description left, control right).

import SpeakCore
import SwiftUI

// MARK: - GeneralAudioSettingsView

@MainActor
struct GeneralAudioSettingsView: View {
    let context: DashboardContext

    @ObservedObject private var launchAtLogin = LaunchAtLoginManager.shared

    private var store: SettingsStore { context.settingsStore }

    var body: some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.lg) {
            startupCard
            LanguageCard(store: store)
            MicrophoneCard(context: context)
            insertionCard
            voiceOutCard
        }
    }

    // MARK: - Startup

    private var startupCard: some View {
        SettingsSectionCard(title: "Startup") {
            SettingsRow(
                "Launch at Login",
                description: "Start speak in the background when you log in."
            ) {
                Toggle("", isOn: Binding(
                    get: { launchAtLogin.isEnabled },
                    set: { launchAtLogin.setEnabled($0) }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
            }
        }
    }

    // MARK: - Text insertion

    private var insertionCard: some View {
        SettingsSectionCard(title: "Text Insertion") {
            SettingsRow(
                "Paste Mode",
                description: "Cmd+V works in almost every app."
            ) {
                Picker("", selection: Binding(
                    get: { store.pasteMode },
                    set: { guard $0 != .accessibility else { return }; store.pasteMode = $0 }
                )) {
                    Text("Cmd+V").tag(PasteMode.cmdV)
                    Text("Accessibility (v1)").tag(PasteMode.accessibility)
                }
                .pickerStyle(.menu)
                .fixedSize()
            }

            SettingsRowSeparator()

            SettingsRow(
                "Streaming",
                description: "Type cleaned text live as you speak, instead of pasting at the end."
            ) {
                Picker("", selection: Binding(
                    get: { store.streamingMode },
                    set: { store.streamingMode = $0 }
                )) {
                    Text("Live keystrokes").tag(StreamingMode.keystrokeInjection)
                    Text("Off").tag(StreamingMode.off)
                }
                .pickerStyle(.menu)
                .fixedSize()
            }

            SettingsRowSeparator()

            SettingsRow(
                "Reveal words while cleaning",
                description: "Keep the raw transcript visible in the HUD while AI cleanup runs."
            ) {
                Toggle("", isOn: Binding(
                    get: { store.revealTextWhileProcessing },
                    set: { store.revealTextWhileProcessing = $0 }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
            }
        }
    }

    // MARK: - Voice out

    private var voiceOutCard: some View {
        SettingsSectionCard(title: "Voice Out") {
            SettingsRow(
                "Read back finished transcripts",
                description: "Adds a speaker button after each dictation to hear it read aloud on-device."
            ) {
                Toggle("", isOn: Binding(
                    get: { store.readbackEnabled },
                    set: { store.readbackEnabled = $0 }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
            }
        }
    }
}

// MARK: - LanguageCard

/// Speech language picker. The picker renders immediately — it always contains
/// the stored locale, so the control is usable before the locale list loads.
/// The list itself loads async from `DictationTranscriberLocaleSource` (the
/// engine the capture path actually runs) behind a bounded fetch; rows marked
/// "(download)" are supported but not yet installed on-device.
///
/// [fix: settings hang + wrong-engine reset] The previous version gated the
/// whole control on an unbounded `SpeechTranscriber.supportedLocales` await
/// (spinner forever when the speech-assets daemon stalls), then compared raw
/// identifiers — persisted "en_IN" never matched SDK "en-IN" — and force-reset
/// `store.language` behind a modal alert on every Settings open. Now: fetch is
/// bounded, identifiers are normalized, a missing stored locale stays
/// selectable (never auto-reset, never alerts), and the stored identifier is
/// silently canonicalized through the SDK's own equivalence matcher.
private struct LanguageCard: View {
    let store: SettingsStore

    private enum ListState { case loading, ready, unavailable }

    @State private var supportedLocales: [Locale] = []
    @State private var installedLocaleIDs: Set<String> = []
    @State private var listState: ListState = .loading

    var body: some View {
        SettingsSectionCard(title: "Language") {
            SettingsRow(
                "Dictation Language",
                description: "Applied to the next dictation — no restart needed."
            ) {
                HStack(spacing: SpeakSpacing.sm) {
                    Picker("", selection: Binding(
                        get: { normalizedID(store.language) },
                        set: { store.language = Locale(identifier: $0) }
                    )) {
                        ForEach(pickerLocales, id: \.identifier) { locale in
                            Text(localeLabel(for: locale))
                                .tag(normalizedID(locale))
                        }
                    }
                    .pickerStyle(.menu)
                    .fixedSize()
                    if listState == .loading {
                        ProgressView().controlSize(.small)
                    }
                }
            }
            if listState == .unavailable {
                Text("The full language list couldn't be loaded — your current selection still applies.")
                    .font(.speakBody(.caption))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, SpeakSpacing.md)
                    .padding(.bottom, SpeakSpacing.sm)
            }
        }
        .task { await loadLocales() }
    }

    /// Supported locales with the stored locale guaranteed present — the
    /// picker never renders an empty or unselectable state.
    private var pickerLocales: [Locale] {
        let storedID = normalizedID(store.language)
        guard !supportedLocales.contains(where: { normalizedID($0) == storedID }) else {
            return supportedLocales
        }
        return [store.language] + supportedLocales
    }

    private func loadLocales() async {
        guard let lists = await DictationTranscriberLocaleSource.fetchLists() else {
            listState = .unavailable
            return
        }
        supportedLocales = lists.supported
        installedLocaleIDs = Set(lists.installed.map(normalizedID))
        listState = .ready
        // Deliberately no canonicalization write: `supportedLocale(equivalentTo:)`
        // fuzzy-matches (en_IN → en_US when en-IN isn't dictation-supported),
        // so writing its result could silently change the user's language.
        // Normalized picker tags already render "en_IN" correctly, and the
        // engine resolves equivalence at session start.
    }

    private func normalizedID(_ locale: Locale) -> String {
        DictationTranscriberLocaleSource.normalizedIdentifier(for: locale)
    }

    private func localeLabel(for locale: Locale) -> String {
        let name = DictationTranscriberLocaleSource.displayName(for: locale)
        return installedLocaleIDs.contains(normalizedID(locale)) ? name : "\(name) (download)"
    }
}

// MARK: - MicrophoneCard

/// Live mic check: current default input device (CoreAudioDeviceMonitor),
/// a real-time 20-segment VU meter driven by a `MicLevelMonitor` side-channel
/// capture, and a route-switch flash when the input device changes mid-view
/// (AudioCapture rebuilds its tap on `.AVAudioEngineConfigurationChange`, so
/// AirPods connect/disconnect never surfaces CoreAudio -10868).
private struct MicrophoneCard: View {
    let context: DashboardContext
    @State private var currentDevice: CoreAudioDeviceMonitor.DeviceInfo?
    @State private var monitorToken: UUID?
    @State private var topologyToken: UUID?
    @State private var micStatus: PermissionState = .notDetermined
    @State private var levelMonitor = MicLevelMonitor()
    @State private var level: Double = 0
    @State private var rawRMS: Double = 0
    @State private var monitoring = false
    @State private var monitorError: String?
    @State private var routeFlash = false
    @State private var inputDevices: [CoreAudioDeviceMonitor.DeviceInfo] = []

    var body: some View {
        SettingsSectionCard(title: "Microphone") {
            if let dev = currentDevice {
                SettingsRow(
                    dev.name,
                    description: deviceDescription(dev)
                ) {
                    if routeFlash {
                        SettingsStatusPill(text: "Switched")
                            .transition(.opacity)
                    } else {
                        SettingsStatusPill(text: "Active")
                    }
                }
            } else {
                SettingsRow(
                    "System Default Microphone",
                    description: "Automatically follows connected headphones, AirPods, or external mics."
                )
            }

            if inputDevices.count > 1 {
                SettingsRowSeparator()

                SettingsRow(
                    "Input Source",
                    description: pinnedDeviceMissing
                        ? "\(context.settingsStore.preferredInputDeviceName ?? "Pinned microphone") isn't connected — using the system default until it returns."
                        : "Pick a mic, or follow the system default. Applies live, even mid-dictation."
                )

                VStack(alignment: .leading, spacing: SpeakSpacing.xs) {
                    inputSourceRow(
                        uid: nil,
                        name: "System Default",
                        detail: "Follows whatever macOS selects — recommended"
                    )
                    ForEach(inputDevices, id: \.id) { dev in
                        inputSourceRow(
                            uid: dev.uid,
                            name: dev.name,
                            detail: "\(Int(dev.sampleRate)) Hz · \(dev.channelCount)ch"
                        )
                    }
                }
                .padding(.vertical, SpeakSpacing.xs)
            }

            SettingsRowSeparator()

            SettingsRow(
                "Input Level",
                description: monitorError ?? "Live while this card is open — speak to confirm your voice is heard."
            ) {
                HStack(spacing: SpeakSpacing.sm) {
                    VUMeterView(level: level)
                    Text(dbLabel)
                        .font(.speakMonoCaption)
                        .foregroundStyle(.secondary)
                        .frame(width: 62, alignment: .trailing)
                }
            }

            SettingsRowSeparator()

            SettingsRow(
                "Microphone Permission",
                description: "Required for on-device voice dictation. Audio never leaves your Mac."
            ) {
                if micStatus == .granted {
                    SettingsStatusPill(text: "Granted", tint: .speakDelivered)
                } else {
                    HStack(spacing: SpeakSpacing.sm) {
                        SettingsStatusPill(text: "Missing", tint: .orange)
                        Button("Grant Access") {
                            Task {
                                await context.permissionManager?.requestMicrophone()
                                updateStatus()
                                startMonitorIfAble()
                            }
                        }
                    }
                }
            }
        }
        .onAppear {
            updateStatus()
            refreshDevices()
            if monitorToken == nil {
                monitorToken = CoreAudioDeviceMonitor.shared.registerCallback { _ in
                    Task { @MainActor in
                        flashRouteChange()
                        refreshDevices()
                    }
                }
            }
            if topologyToken == nil {
                topologyToken = CoreAudioDeviceMonitor.shared.registerTopologyCallback { _ in
                    Task { @MainActor in
                        refreshDevices()
                    }
                }
            }
            startMonitorIfAble()
        }
        .onChange(of: context.settingsStore.preferredInputDeviceUID) { _, _ in
            refreshDevices()
        }
        .onDisappear {
            if let token = monitorToken {
                CoreAudioDeviceMonitor.shared.unregisterCallback(token)
                monitorToken = nil
            }
            if let token = topologyToken {
                CoreAudioDeviceMonitor.shared.unregisterCallback(token)
                topologyToken = nil
            }
            levelMonitor.stop()
            monitoring = false
            level = 0
        }
        .onChange(of: context.isDictating?() ?? false) { _, dictating in
            // A real dictation owns the mic + shows its own level HUD — pause
            // the settings meter for the duration so two engines don't tap at once.
            if dictating {
                levelMonitor.stop()
                monitoring = false
            } else {
                startMonitorIfAble()
            }
        }
    }

    // MARK: - Input source picker

    /// One selectable row in the Input Source list. `uid == nil` is the
    /// "System Default" option; device rows persist the stable hardware UID
    /// (plus the display name, so an unplugged pin still reads as a name).
    /// Writes go through `SettingsStore` — `DictationController`'s observer
    /// pushes them into the engine, which live-switches a running capture.
    private func inputSourceRow(uid: String?, name: String, detail: String) -> some View {
        let selected = context.settingsStore.preferredInputDeviceUID == uid
        return Button {
            context.settingsStore.preferredInputDeviceUID = uid
            context.settingsStore.preferredInputDeviceName = uid == nil ? nil : name
            refreshDevices()
        } label: {
            HStack(spacing: SpeakSpacing.sm) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? Color.primary : Color.secondary)
                    .font(.speakBody(.caption))
                VStack(alignment: .leading, spacing: 1) {
                    Text(name)
                        .font(.speakBody(.caption))
                        .foregroundStyle(.primary)
                    Text(detail)
                        .font(.speakMonoCaption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if uid != nil, uid == currentDevice?.uid {
                    SettingsStatusPill(text: "Active")
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Top-row description: format string for the effective device, noting
    /// whether it arrived via the system default or the picker pin.
    private func deviceDescription(_ dev: CoreAudioDeviceMonitor.DeviceInfo) -> String {
        let source = context.settingsStore.preferredInputDeviceUID == nil
            ? "follows the system default input"
            : "pinned below"
        return "\(Int(dev.sampleRate)) Hz · \(dev.channelCount) channel\(dev.channelCount == 1 ? "" : "s") — \(source)."
    }

    /// `true` when a pin is stored but its device isn't in the current roster —
    /// the picker shows the "not connected → system default" explanation.
    private var pinnedDeviceMissing: Bool {
        guard let uid = context.settingsStore.preferredInputDeviceUID else { return false }
        return !inputDevices.contains { $0.uid == uid }
    }

    /// Refreshes both the roster and the EFFECTIVE device (pinned-or-default)
    /// shown at the top of the card — the honest "what's feeding you" answer.
    private func refreshDevices() {
        inputDevices = CoreAudioDeviceMonitor.shared.listInputDevices()
        currentDevice = CoreAudioDeviceMonitor.shared.resolvedInputDevice(
            preferredUID: context.settingsStore.preferredInputDeviceUID
        )
    }

    // MARK: - Level monitor

    private func startMonitorIfAble() {
        guard !monitoring, micStatus == .granted, !(context.isDictating?() ?? false) else { return }
        do {
            try levelMonitor.start { rms in
                Task { @MainActor in
                    rawRMS = rms
                    level = levelSmoothedAsymmetric(
                        previous: level,
                        target: levelPerceptual(rms: rms)
                    )
                }
            }
            monitoring = true
            monitorError = nil
        } catch {
            monitorError = "Meter unavailable: \(error.localizedDescription)"
        }
    }

    private var dbLabel: String {
        guard monitoring, rawRMS > 0 else { return monitoring ? "−∞ dB" : "—" }
        let db = max(20.0 * log10(rawRMS), -60)
        return String(format: "%.0f dB", db)
    }

    private func updateStatus() {
        micStatus = context.permissionManager?.status(.microphone) ?? .notDetermined
    }

    private func flashRouteChange() {
        guard monitoring || currentDevice != nil else { return }
        withAnimation(.spring(duration: 0.15)) { routeFlash = true }
        Task {
            try? await Task.sleep(for: .milliseconds(1600))
            withAnimation(.spring(duration: 0.15)) { routeFlash = false }
        }
    }
}
