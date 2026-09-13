// App/Settings/SpeechToTextSettingsView.swift
//
// "Speech to Text" — the first pipeline layer of the dedicated Settings
// experience. Recognition engine, speech language, live microphone status,
// and text delivery (insertion + streaming). Rows use the SettingsChrome
// card/row primitives (title + description left, control right).
//
// The Microphone card is ordered as the diagnostic flow a user runs when
// dictation "isn't hearing me": permission gate → what the current input
// actually is → live level proof → the input-source chooser.

import AppKit
import SpeakCore
import SwiftUI

// MARK: - SpeechToTextSettingsView

@MainActor
struct SpeechToTextSettingsView: View {
    let context: DashboardContext

    private var store: SettingsStore { context.settingsStore }

    var body: some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.lg) {
            engineCard
            LanguageCard(store: store)
            MicrophoneCard(context: context)
            insertionCard
        }
    }

    // MARK: - Recognition engine

    private var engineCard: some View {
        SettingsSectionCard(title: "Recognition") {
            SettingsRow(
                "Engine",
                description: engineNote
            ) {
                Picker("", selection: Binding(
                    get: { store.sttEngine },
                    set: { store.sttEngine = $0 }
                )) {
                    Text("Apple Speech").tag(STTEngine.appleSpeech)
                    Text("WhisperKit (v0.1+)").tag(STTEngine.whisperKit)
                    Text("whisper.cpp (v1+)").tag(STTEngine.whisperCpp)
                }
                .pickerStyle(.menu)
                .fixedSize()
            }
        }
    }

    private var engineNote: String {
        switch store.sttEngine {
        case .appleSpeech:
            return "On-device Apple speech recognition — private, free, always available."
        case .whisperKit:
            return "Arrives in v0.1 — dictation uses Apple Speech until then."
        case .whisperCpp:
            return "A v1 option aimed at Intel-era compatibility."
        }
    }

    // MARK: - Text insertion

    private var insertionCard: some View {
        SettingsSectionCard(title: "Text Insertion") {
            SettingsRow(
                "Paste Mode",
                description: "Simulates ⌘V at the insertion point — works in almost every app."
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
                .tint(.speakUIAccent)
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
                HStack(spacing: SpeakSpacing.xs) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.speakBody(.caption))
                        .foregroundStyle(Color.speakWarning)
                    Text("The full language list couldn't be loaded — your current selection still applies.")
                        .font(.speakBody(.caption))
                        .foregroundStyle(Color.speakMica)
                    Spacer(minLength: SpeakSpacing.sm)
                    Button("Retry") {
                        listState = .loading
                        Task { await loadLocales() }
                    }
                    .font(.speakBody(.caption))
                    .buttonStyle(.borderless)
                    .tint(.speakUIAccent)
                }
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

/// Live mic check, ordered as the "is it hearing me?" diagnostic flow:
/// permission gate → the effective input device → live level proof → the
/// input-source picker. A real-time 20-segment VU meter is driven by a
/// `MicLevelMonitor` side-channel capture while the card is visible, and a
/// route-switch flash fires only when the EFFECTIVE device actually changes
/// (AudioCapture rebuilds its tap on `.AVAudioEngineConfigurationChange`, so
/// AirPods connect/disconnect never surfaces CoreAudio -10868).
private struct MicrophoneCard: View {
    let context: DashboardContext
    @State private var currentDevice: CoreAudioDeviceMonitor.DeviceInfo?
    @State private var systemDefaultDevice: CoreAudioDeviceMonitor.DeviceInfo?
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
            // 1 — The gate: nothing below this row works until it's granted.
            SettingsRow(
                "Microphone Permission",
                description: permissionDescription
            ) {
                permissionControl
            }

            SettingsRowSeparator()

            // 2 — The answer to "what's hearing me right now": the device name
            // sits prominent on the trailing edge; specs + routing source
            // carry the description.
            if let dev = currentDevice {
                SettingsRow(
                    "Current Input",
                    description: currentInputDescription(dev)
                ) {
                    HStack(spacing: SpeakSpacing.sm) {
                        if routeFlash {
                            SettingsStatusPill(text: "Switched", tint: .speakHumanAmber)
                                .transition(.opacity)
                        }
                        Text(dev.name)
                            .font(.speakBody(.base))
                            .foregroundStyle(Color.speakBone)
                            .lineLimit(1)
                    }
                }
            } else {
                SettingsRow(
                    "Current Input",
                    description: micStatus == .granted
                        ? "No input device detected — connect a microphone or check macOS Sound settings."
                        : "Unknown until microphone access is granted."
                ) {
                    if micStatus == .granted {
                        SettingsStatusPill(text: "No Device", tint: .speakWarning)
                    }
                }
            }

            SettingsRowSeparator()

            // 3 — Live proof. The meter is a side-channel capture, paused while
            // a real dictation owns the mic.
            SettingsRow(
                "Input Level",
                description: levelDescription
            ) {
                HStack(spacing: SpeakSpacing.sm) {
                    VUMeterView(level: level)
                        .opacity(monitoring ? 1 : 0.35)
                    Text(dbLabel)
                        .font(.speakMonoFace(.caption))
                        .foregroundStyle(Color.speakMica)
                        // [decision] fixed readout width — keeps the meter from
                        // reflowing as the dB readout changes digit count.
                        .frame(width: 62, alignment: .trailing)
                }
            }

            // 4 — The chooser. Only shown when there's a real choice to make
            // or a stale pin to explain.
            if showsInputSource {
                SettingsRowSeparator()
                inputSourceSection
            }
        }
        .onAppear {
            updateStatus()
            refreshDevices()
            if monitorToken == nil {
                monitorToken = CoreAudioDeviceMonitor.shared.registerCallback { _ in
                    Task { @MainActor in
                        refreshDevices(flashOnResolvedChange: true)
                    }
                }
            }
            if topologyToken == nil {
                topologyToken = CoreAudioDeviceMonitor.shared.registerTopologyCallback { _ in
                    Task { @MainActor in
                        refreshDevices(flashOnResolvedChange: true)
                    }
                }
            }
            startMonitorIfAble()
        }
        // TCC grants made in System Settings don't notify the app — poll so a
        // "Denied → user fixes it → returns" round-trip turns green live.
        // [decision: matches PrivacyHealthSettingsView; no KVO exists for TCC]
        .task { await pollMicStatus() }
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
            rawRMS = 0
        }
        .onChange(of: context.isDictating?() ?? false) { _, dictating in
            // A real dictation owns the mic + shows its own level HUD — pause
            // the settings meter for the duration so two engines don't tap at once.
            if dictating {
                levelMonitor.stop()
                monitoring = false
                level = 0
                rawRMS = 0
            } else {
                startMonitorIfAble()
            }
        }
    }

    // MARK: - Permission row

    @ViewBuilder
    private var permissionControl: some View {
        switch micStatus {
        case .granted:
            SettingsStatusPill(text: "Granted", tint: .speakOK)

        case .requesting:
            HStack(spacing: SpeakSpacing.sm) {
                ProgressView().controlSize(.small)
                SettingsStatusPill(text: "Requesting", tint: .speakMica)
            }

        case .notDetermined:
            HStack(spacing: SpeakSpacing.sm) {
                SettingsStatusPill(text: "Not Granted", tint: .speakWarning)
                Button("Grant Access") { requestMicrophoneAccess() }
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
                    .tint(.speakUIAccent)
            }

        case .denied:
            // Once denied, `requestMicrophone()` never re-prompts — the only
            // path back is the TCC toggle in System Settings.
            HStack(spacing: SpeakSpacing.sm) {
                SettingsStatusPill(text: "Denied", tint: .speakError)
                Button("Open System Settings…") { openMicrophoneSettings() }
                    .controlSize(.small)
            }

        case .restricted:
            // MDM / Screen Time policy — no user-side toggle exists.
            SettingsStatusPill(text: "Restricted", tint: .speakError)
        }
    }

    private var permissionDescription: String {
        switch micStatus {
        case .granted:
            return "Audio is captured and transcribed on this Mac — it never leaves the device."
        case .notDetermined:
            return "Required for dictation — macOS will ask once."
        case .requesting:
            return "Answer the macOS prompt to continue."
        case .denied:
            return "speak is off under System Settings → Privacy & Security → Microphone."
        case .restricted:
            return "Blocked by a device-management or parental-controls policy on this Mac."
        }
    }

    private func requestMicrophoneAccess() {
        guard let manager = context.permissionManager else {
            openMicrophoneSettings()
            return
        }
        micStatus = .requesting
        Task {
            let result = await manager.requestMicrophone()
            micStatus = result
            if result == .granted { startMonitorIfAble() }
        }
    }

    private func openMicrophoneSettings() {
        let urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }

    private func updateStatus() {
        micStatus = context.permissionManager?.status(.microphone) ?? .notDetermined
    }

    /// Re-checks TCC every 1.5 s while visible — grants can change in System
    /// Settings without notifying the app. Skips `.requesting` so the poll
    /// doesn't overwrite the in-flight prompt state.
    private func pollMicStatus() async {
        while !Task.isCancelled {
            let latest = context.permissionManager?.status(.microphone) ?? .notDetermined
            if latest != micStatus, micStatus != .requesting {
                micStatus = latest
                if latest == .granted { startMonitorIfAble() }
            }
            try? await Task.sleep(for: .milliseconds(1500))
        }
    }

    // MARK: - Input level row

    private var levelDescription: String {
        if micStatus != .granted {
            return "Grant microphone access above to see a live level."
        }
        if context.isDictating?() ?? false {
            return "Paused while dictating — the floating HUD shows your live level."
        }
        if let monitorError {
            return "Meter unavailable — \(monitorError)"
        }
        if currentDevice == nil {
            return "No input device to meter — connect a microphone."
        }
        return "Live while this card is open — speak to confirm your voice is heard."
    }

    private var dbLabel: String {
        guard monitoring, rawRMS > 0 else { return monitoring ? "−∞ dB" : "—" }
        let db = max(20.0 * log10(rawRMS), -60)
        return String(format: "%.0f dB", db)
    }

    // MARK: - Input source picker

    /// The chooser only earns its space when it can change something: more
    /// than one connected input, or a stale pin that needs explaining.
    private var showsInputSource: Bool {
        inputDevices.count > 1 || pinnedDeviceMissing
    }

    private var inputSourceSection: some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.xs) {
            Text("Input Source")
                .font(.speakBody(.caption, semibold: true))
                .foregroundStyle(Color.speakMica)
                .padding(.horizontal, SpeakSpacing.md)
                .padding(.top, SpeakSpacing.sm)

            VStack(spacing: 0) {
                inputSourceRow(
                    uid: nil,
                    name: "System Default",
                    detail: systemDefaultDetail
                )
                ForEach(inputDevices, id: \.id) { dev in
                    inputSourceSeparator
                    inputSourceRow(
                        uid: dev.uid,
                        name: dev.name,
                        detail: deviceDetail(dev)
                    )
                }
                if pinnedDeviceMissing {
                    inputSourceSeparator
                    missingPinRow
                }
            }
            .speakInset()
            .padding(.horizontal, SpeakSpacing.md)
            .padding(.bottom, SpeakSpacing.sm)
        }
    }

    /// Hairline inside the picker well, aligned to the row text.
    private var inputSourceSeparator: some View {
        Divider()
            .overlay(Color.speakCardBorder.opacity(0.6))
            .padding(.leading, SpeakSpacing.sm)
    }

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
                VStack(alignment: .leading, spacing: SpeakSpacing.xs) {
                    Text(name)
                        .font(.speakBody(.base))
                        .foregroundStyle(Color.speakBone)
                    Text(detail)
                        .font(.speakMonoFace(.caption))
                        .foregroundStyle(Color.speakMica)
                }
                Spacer()
                Image(systemName: "checkmark")
                    .font(.speakBody(.caption, semibold: true))
                    .foregroundStyle(Color.speakUIAccent)
                    .opacity(selected ? 1 : 0)
            }
            .padding(.horizontal, SpeakSpacing.sm)
            .padding(.vertical, SpeakSpacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// The stored pin whose hardware is gone — shown dimmed inside the list so
    /// the fallback is explained where the choice lives, and picking "System
    /// Default" clears it.
    private var missingPinRow: some View {
        HStack(spacing: SpeakSpacing.sm) {
            VStack(alignment: .leading, spacing: SpeakSpacing.xs) {
                Text(context.settingsStore.preferredInputDeviceName ?? "Pinned microphone")
                    .font(.speakBody(.base))
                    .foregroundStyle(Color.speakMica)
                Text("Not connected — using the system default until it returns.")
                    .font(.speakBody(.caption))
                    .foregroundStyle(Color.speakMica)
            }
            Spacer()
            SettingsStatusPill(text: "Disconnected", tint: .speakWarning)
        }
        .padding(.horizontal, SpeakSpacing.sm)
        .padding(.vertical, SpeakSpacing.sm)
    }

    /// What "System Default" currently resolves to — a name (data → mono),
    /// more informative than a "recommended" tagline.
    private var systemDefaultDetail: String {
        if let dev = systemDefaultDevice {
            return "Currently \(dev.name)"
        }
        return "No input device detected"
    }

    /// Specs line for a device row — omits anything the HAL couldn't report
    /// (a 0 sample rate or channel count reads as absence, not "0 Hz").
    private func deviceDetail(_ dev: CoreAudioDeviceMonitor.DeviceInfo) -> String {
        var parts: [String] = []
        if let rate = formattedSampleRate(dev.sampleRate) { parts.append(rate) }
        if dev.channelCount > 0 { parts.append("\(dev.channelCount) ch") }
        return parts.isEmpty ? "Input device" : parts.joined(separator: " · ")
    }

    /// "48 kHz" / "44.1 kHz" style — nil when the device reports no rate.
    private func formattedSampleRate(_ rate: Double) -> String? {
        guard rate > 0 else { return nil }
        if rate >= 1000 {
            return String(format: "%g kHz", rate / 1000)
        }
        return "\(Int(rate)) Hz"
    }

    /// Description for the effective input — specs plus whether it came from
    /// the system default, a live pin, or a fallback because the pin is gone.
    private func currentInputDescription(_ dev: CoreAudioDeviceMonitor.DeviceInfo) -> String {
        var parts: [String] = []
        if let rate = formattedSampleRate(dev.sampleRate) { parts.append(rate) }
        if dev.channelCount > 0 {
            parts.append("\(dev.channelCount) channel\(dev.channelCount == 1 ? "" : "s")")
        }
        if let uid = context.settingsStore.preferredInputDeviceUID, uid == dev.uid {
            parts.append("pinned")
        } else if pinnedDeviceMissing {
            let name = context.settingsStore.preferredInputDeviceName ?? "pinned mic"
            parts.append("system default — “\(name)” is disconnected")
        } else {
            parts.append("system default")
        }
        return parts.joined(separator: " · ")
    }

    /// `true` when a pin is stored but its device isn't in the current roster —
    /// the picker shows the "not connected → system default" explanation.
    private var pinnedDeviceMissing: Bool {
        guard let uid = context.settingsStore.preferredInputDeviceUID else { return false }
        return !inputDevices.contains { $0.uid == uid }
    }

    /// Refreshes the roster, the raw system default (for the picker's
    /// "Currently …" line), and the EFFECTIVE device (pinned-or-default)
    /// shown in the Current Input row — the honest "what's feeding you"
    /// answer. `flashOnResolvedChange` marks the row only when the effective
    /// input truly changed, so a default-device shuffle that a pin absorbs
    /// stays quiet.
    private func refreshDevices(flashOnResolvedChange: Bool = false) {
        let monitor = CoreAudioDeviceMonitor.shared
        inputDevices = monitor.listInputDevices()
        systemDefaultDevice = monitor.currentDefaultInputDevice()
        let resolved = monitor.resolvedInputDevice(
            preferredUID: context.settingsStore.preferredInputDeviceUID
        )
        let resolvedChanged = resolved?.uid != currentDevice?.uid
        currentDevice = resolved
        if flashOnResolvedChange, resolvedChanged, resolved != nil {
            flashRouteChange()
        }
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
            monitorError = error.localizedDescription
        }
    }

    private func flashRouteChange() {
        withAnimation(.spring(duration: 0.15)) { routeFlash = true }
        Task {
            try? await Task.sleep(for: .milliseconds(1600))
            withAnimation(.spring(duration: 0.15)) { routeFlash = false }
        }
    }
}
