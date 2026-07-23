// App/Overlay/TranscriptOverlayView.swift
//
// The SwiftUI content hosted inside `TranscriptOverlayPanel`.
//
// W2.2 — VoiceInk-grade HUD rebuild:
//   • 4 visual states: .listening (live waveform + partial text),
//     .processing ("Cleaning up…" / "Pasting…" spinner),
//     .done (checkmark flash), .error (red pill + reason + retry).
//   • Live waveform: 15-bar reactive visualizer driven by `level` (W2.1).
//     Per-bar phase offset via `levelBarHeightsPhased(level:phase:)` in LevelMath.
//   • Monaco design: all text uses `Font.speakMono(...)` tokens from `SpeakTheme`.
//   • Reduce-motion: `NSWorkspace.accessibilityDisplayShouldReduceMotion` disables
//     the breathing animation and all animated transitions.
//   • VoiceOver: `accessibilityLabel` + `.accessibilityAddTraits(.updatesFrequently)`
//     on the partial-text region; state transitions post announcements via
//     `NSAccessibility.post(element:notification:)`.
//   • In-HUD cancel affordance: Escape is handled by `OverlayController`'s global
//     event monitor — the panel never becomes key (focus-steal prevention).
//
// Design tokens: all from `SpeakTheme` — no magic font names or raw hex colors.
// Bar constants are tagged [decision] with sources in benchmark.md §7.

import AppKit
import SpeakCore
import SwiftUI

// MARK: - OverlayState

/// The visual state of the recording HUD. Driven by `DictationController`
/// as the dictation lifecycle transitions.
public enum OverlayState: Sendable, Equatable {
    case listening
    case processing
    case done
    /// W2.2: an error occurred. Reason is stored separately on `OverlayViewModel.errorReason`
    /// so `OverlayState` stays payload-free and `Equatable` conformance is automatic.
    case error
}

// MARK: - OverlayDestinationChoice (PE-3 live panel)

/// The destination choices shown as chips in the live panel while listening — the three
/// AI destinations (Agent / Write / Note). Raw is the AI-off base core, never a chip.
///
/// A lightweight, `Sendable`, `Identifiable` value so the SwiftUI strip needn't bind to the
/// full `Profile`/`ProfileStore`. `DictationController` maps a tapped choice back to the
/// user's (possibly edited) profile via `profileID`. (specs/live-panel-prompt-shaper.md.)
enum OverlayDestinationChoice: String, CaseIterable, Identifiable, Sendable {
    case agent, write, note, raw

    var id: String { rawValue }

    var label: String {
        switch self {
        case .agent: return "Agent"
        case .write: return "Write"
        case .note:  return "Note"
        case .raw:   return "Raw"
        }
    }

    /// SF Symbol for the chip / pill. Mirrors the built-in profile icons.
    var icon: String {
        switch self {
        case .agent: return "list.bullet.rectangle"
        case .write: return "sparkles"
        case .note:  return "note.text"
        case .raw:   return "waveform"
        }
    }

    /// `Raw` means AI off for this dictation (base-core passthrough), not a profile override.
    var isRaw: Bool { self == .raw }

    /// Stable id of the matching built-in — used to look up the live profile in `ProfileStore`.
    var profileID: UUID {
        switch self {
        case .agent: return DefaultProfiles.agent.id
        case .write: return DefaultProfiles.write.id
        case .note:  return DefaultProfiles.note.id
        case .raw:   return DefaultProfiles.raw.id
        }
    }

    /// Pristine built-in fallback when `ProfileStore` has no match for `profileID`.
    var fallbackProfile: Profile {
        switch self {
        case .agent: return DefaultProfiles.agent
        case .write: return DefaultProfiles.write
        case .note:  return DefaultProfiles.note
        case .raw:   return DefaultProfiles.raw
        }
    }

    /// Map a resolved profile id to a choice (nil if it isn't one of the four built-ins).
    init?(profileID id: UUID) {
        if id == DefaultProfiles.agent.id { self = .agent } else if id == DefaultProfiles.write.id {
            self = .write
        } else if id == DefaultProfiles.note.id {
            self = .note
        } else if id == DefaultProfiles.raw.id {
            self = .raw
        } else {
            return nil
        }
    }
}

// MARK: - OverlayViewModel

/// Observable model bridging `DictationController` → `TranscriptOverlayView`.
/// `@MainActor` because all writes come from `DictationController` (also @MainActor).
@Observable
@MainActor
final class OverlayViewModel {
    var partialText: String = ""
    var overlayState: OverlayState = .listening

    // MARK: PE-3 live-panel strip

    /// Destination chips shown while listening. Empty ⇒ no strip (e.g. AI cleanup off —
    /// profiles would do nothing). Set by `DictationController` at dictation start.
    var destinationChoices: [OverlayDestinationChoice] = []

    /// The active (highlighted) destination — the one that will run. nil ⇒ none highlighted.
    var activeDestinationChoice: OverlayDestinationChoice?

    /// Invoked when the user taps a destination chip. `DictationController` maps the choice
    /// to a profile and applies a per-dictation override (does NOT change the saved default).
    var onSelectDestination: ((OverlayDestinationChoice) -> Void)?

    /// PE-3c: `true` while the anchored profile-selector card covers the HUD. Toggled open by
    /// the destination pill; closed by picking an option or pressing Escape. The calm HUD
    /// (waveform/transcript/timer) shows when `false`.
    var isProfilePanelOpen: Bool = false

    /// PE-3c-2: `true` when the card has swapped to the Agent **category** page (after the user
    /// picks Agent). The destinations page shows when `false`. Reset whenever the card opens.
    var isShowingAgentCategories: Bool = false

    /// PE-3c-2: the active Agent category (highlighted on the category page). Default `.task`.
    var activeCategory: AgentCategory = .task

    /// PE-3c-2: invoked when the user taps a category chip. `DictationController` threads it
    /// into the per-dictation Agent override.
    var onSelectCategory: ((AgentCategory) -> Void)?

    /// PE-3c-3: `true` when the ⌄more affordance on the category page is expanded, revealing
    /// rare categories (Code). Reset to `false` whenever the category page opens fresh so the
    /// row is always collapsed on entry. Stored on the model (not @State) so the reset is a
    /// single write on the open path — no onChange needed.
    var isCategoryMoreExpanded: Bool = false

    /// Elapsed seconds since the current dictation started listening.
    var elapsedSeconds: Int = 0

    /// Microphone level (0…1), smoothed RMS from `AudioCapture` (W2.1).
    /// 0.0 when idle; driven live during `.listening`.
    var level: Double = 0.0

    /// W2.2: Short error reason shown in the error pill. Nil when not in `.error` state.
    var errorReason: String?

    /// W2.2: `true` when AI cleanup will run after capture; drives "Cleaning up…" vs "Pasting…".
    /// Set at `start()` time from `DictationController.settingsStore`.
    var isCleaningUp: Bool = true

    // MARK: PE-3.2 pin-to-context banner

    /// `true` when the "pin this destination?" banner should appear below the waveform row.
    /// Set via `OverlayController.showPinBanner` / `hidePinBanner`. Reset in start/stop/cancel.
    var showPinPrompt: Bool = false

    /// Short label shown in the pin banner, e.g. "Always Agent · Task here?"
    var pinContextLabel: String = ""

    /// Called when the user taps [Pin] in the banner.
    var onPin: (() -> Void)?

    /// Called when the user taps [✕] in the banner to dismiss without pinning.
    var onDismissPin: (() -> Void)?

    // MARK: PE-4: per-dictation knob overrides [decision PE-4]

    /// Per-dictation format override. `.asIs` = "Auto" (no override; profile default applies).
    /// Reset at dictation start via `OverlayController.start()` and `resolveActiveDestination`.
    var perDictationFormat: OutputFormat = .asIs

    /// Per-dictation tone override. `.neutral` = "Auto" (no override).
    var perDictationTone: Tone = .neutral

    /// Per-dictation length override. `.preserve` = "Auto" (no override).
    var perDictationLength: LengthBias = .preserve

    /// Fired when the user changes any knob. `DictationController` wires this to set
    /// `didOverrideThisSession = true` so the stop-time profile apply runs.
    var onKnobChanged: (() -> Void)?

    /// Cancel this dictation without pasting. Wired to `cancelDictation()` by
    /// `DictationController`. Only valid during `.listening` state.
    var onCancel: (() -> Void)?

    /// Re-run cleanup on the last raw transcript. Wired to `recleanCurrentTranscript()`.
    /// Only valid after `.done` when a raw transcript is available. [decision PE-4]
    var onReclean: (() -> Void)?

    /// Speak the last finished transcript aloud (H-2 — VoiceOut readback), or stop if
    /// already speaking. Wired to `DictationController.toggleReadback()`. `nil` when
    /// `SettingsStore.readbackEnabled == false` — the button is hidden entirely in that
    /// case, exactly like `onReclean`'s "only shown when meaningful" contract.
    /// [decision H-2: reuses the re-clean button's `.done`-window visibility pattern —
    /// set at dictation start, nil'd by `OverlayController.stop()`/`cancelImmediate()`.]
    var onReadback: (() -> Void)?

    // MARK: Prompt-customization panel (P-Code)
    //
    // [decision P-Code v2] The base HUD's destination/Agent-category picker (the
    // `profileSelectorCard` — destinations page + Agent category page) is REMOVED from
    // the live UI per locked product direction: the base overlay shows only waveform +
    // transcript + timer + ONE button. That button opens this same panel, now repurposed
    // as a real-time PROMPT editor (default system prompt + an appendable custom-
    // instructions field) rather than a category selector. `isProfilePanelOpen` /
    // `isShowingAgentCategories` / `activeCategory` / `onSelectCategory` above are left
    // in place (DictationController's per-app profile resolution still depends on
    // `activeCategory`) but are no longer reachable from any View — nothing in the base
    // HUD ever sets `isProfilePanelOpen = true` anymore.

    /// `true` while the separate, dynamically-sized `CodingCustomizationPanel` is open.
    /// Toggled open by the base HUD's single button; toggled closed by the panel's own
    /// close affordance. Unlike `isProfilePanelOpen`, this does NOT cover the base HUD —
    /// it drives visibility of a second, independent `NSPanel` owned by
    /// `OverlayController`, anchored above the base HUD so the two never overlap.
    var isCodingPanelOpen: Bool = false

    /// Invoked whenever `isCodingPanelOpen` changes and the actual `NSPanel` must be
    /// shown/hidden to match. Wired by `OverlayController` — a pure overlay/UI concern,
    /// so it does not need to route through `DictationController` like the destination/
    /// category callbacks above.
    var onCodingPanelOpenChanged: ((Bool) -> Void)?

    /// The resolved profile's system prompt for the CURRENT dictation, shown read-only
    /// in the prompt-customization panel so the user can see what governs cleanup right
    /// now. Set by `DictationController.beginDictation()` from `activeDestination
    /// .systemPrompt` (the same per-app-resolved profile the engine will use); reset to
    /// "" on stop/cancel. [decision P-Code v2]
    var defaultSystemPrompt: String = ""

    /// Free-form text the user typed into the prompt-customization panel's "Additional
    /// instructions" field for THIS dictation. Read directly by `DictationController` at
    /// stop time (mirrors how `perDictationFormat`/`perDictationTone`/`perDictationLength`
    /// are read) and appended — via `PromptBuilder` — as the freshest instruction before
    /// the transcript. Reset to "" at the start of every dictation. [decision P-Code v2:
    /// append-only "custom addition" field, not full prompt replacement — the user's
    /// stated preference for simplicity + correctness of wiring.]
    var customInstructions: String = ""
}

// MARK: - VisualEffectView

/// Thin AppKit-backed SwiftUI wrapper that applies NSVisualEffectView material.
/// Internal (not `private`) so `AuroraOverlayView` (H-UI) can reuse it — the
/// glassy background material is shared chrome, not style-specific behavior.
struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = blendingMode
        v.state = .active
        return v
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

// MARK: - WaveformView

/// A 15-bar waveform driven by `level` (0…1) with per-bar phase offset.
///
/// Bar heights are computed by `levelBarHeightsPhased(level:phase:barCount:…)` in
/// `LevelMath.swift` — a pure function that makes the waveform look organic while
/// remaining fully unit-testable. When `reduceMotion` is true (Accessibility setting),
/// the phase animation and idle-breathing are suppressed; bars still reflect the live
/// level value (information, not decoration).
///
/// Bar geometry decisions — all [decision] in benchmark.md §7:
///   - 15 bars: VoiceInk blueprint (competitor research W0, §0 finding #1).
///   - 2 pt width: thin "audio analyser" look, distinct from the 5-bar v0 design.
///   - 2 pt gap: breathing room; 15 × (2 + 2) = 60 pt total, fits the panel.
///   - 3 pt min height: always visible at silence — never disappears.
///   - 20 pt max height: fits the 80 pt panel with 12 pt vertical padding each side.
private struct WaveformView: View {

    let level: Double
    let isActive: Bool          // true = listening; false = silent/idle

    // [decision: 15 bars — VoiceInk blueprint, benchmark.md §7]
    private static let barCount: Int = 15
    // [decision: 2 pt bar width — thin analyser look, benchmark.md §7]
    private static let barWidth: CGFloat = 2.0
    // [decision: 2 pt gap — breathing room, 15 × 4 pt = 60 pt total, benchmark.md §7]
    private static let barGap: CGFloat  = 2.0
    // [decision: 3 pt min — always visible at silence, benchmark.md §7]
    private static let minHeight: Double = 3.0
    // [decision: 20 pt max — fits 80 pt panel, benchmark.md §7]
    private static let maxHeight: Double = 20.0

    /// Computed width of the waveform block (used by callers for `.frame(width:)`).
    static var totalWidth: CGFloat {
        CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * barGap  // = 30 + 28 = 58 pt
    }

    /// Animated phase for the per-bar offset (0…1). Drives the organic waveform
    /// movement when listening. Suppressed when reduce-motion is on.
    @State private var animPhase: Double = 0.0
    /// Idle-breathing amplitude (0…1). Only used when `isActive == false` and
    /// reduce-motion is off. Suppressed when reduce-motion is on.
    @State private var breathPhase: Double = 0.0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: Self.barGap) {
            ForEach(Array(barHeights.enumerated()), id: \.offset) { _, height in
                RoundedRectangle(cornerRadius: Self.barWidth / 2, style: .continuous)
                    .fill(barColor)
                    .frame(width: Self.barWidth, height: CGFloat(height))
            }
        }
        // [decision: 0.08 s animation — snappier than v0's 0.12 s for 15-bar feel]
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.08), value: level)
        .onAppear {
            guard !reduceMotion else { return }
            startPhaseAnimation()
            if !isActive { startBreathing() }
        }
        .onChange(of: isActive) { _, newValue in
            guard !reduceMotion else { return }
            if !newValue { startBreathing() } else { breathPhase = 0.0 }
        }
    }

    private var barColor: Color {
        isActive ? Color.primary.opacity(0.7) : Color.primary.opacity(0.35)
    }

    private var barHeights: [Double] {
        if isActive {
            return levelBarHeightsPhased(
                level: level,
                phase: animPhase,
                barCount: Self.barCount,
                minHeight: Self.minHeight,
                maxHeight: Self.maxHeight
            )
        } else {
            // Idle breathing when not active.
            let breathLevel = 0.12 + 0.12 * breathPhase   // [decision: 0.12…0.24 idle range]
            return levelBarHeightsPhased(
                level: breathLevel,
                phase: animPhase,
                barCount: Self.barCount,
                minHeight: Self.minHeight,
                maxHeight: Self.maxHeight
            )
        }
    }

    /// Advance the phase over time so adjacent bars appear to ripple.
    private func startPhaseAnimation() {
        withAnimation(
            // [decision: 1.8 s cycle — organic wave rhythm, VoiceInk-inspired feel]
            Animation.linear(duration: 1.8).repeatForever(autoreverses: false)
        ) {
            animPhase = 1.0
        }
    }

    /// Gentle idle breathing when not actively listening.
    private func startBreathing() {
        withAnimation(
            // [decision: 1.4 s breath cycle — slightly slower than active phase]
            Animation.easeInOut(duration: 1.4).repeatForever(autoreverses: true)
        ) {
            breathPhase = 1.0
        }
    }
}

// MARK: - TranscriptOverlayView

/// The visible card shown during live dictation.
/// Renders four visual states: listening, processing, done, error.
struct TranscriptOverlayView: View {
    let model: OverlayViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // [task #32] The overlay is a read-only live status surface during a dictation —
        // NOT a Settings entry point. The bottom-left gear was a Settings duplicate; it
        // is removed per the locked direction (overlay = live control, not settings).
        // A live profile-control affordance belongs here later (Profile Engine), not a gear.
        ZStack {
            // Frosted-glass background — pulls from behind the panel.
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            contentLayer
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(2)  // prevent shadow clipping at the edge
        .onChange(of: model.overlayState) { _, newState in
            postAccessibilityAnnouncement(for: newState)
        }
    }

    @ViewBuilder
    private var contentLayer: some View {
        switch model.overlayState {
        case .listening:
            listeningContent

        case .processing:
            processingContent

        case .done:
            doneContent

        case .error:
            errorContent
        }
    }

    // MARK: - Listening state

    // [decision P-Code v2] The base HUD ALWAYS renders the calm row — no state swap, no
    // covering card. Locked product direction: the base overlay shows exactly waveform +
    // live transcript + elapsed timer + ONE button, nothing else, and never changes shape
    // when that button is pressed. The button opens `CodingCustomizationPanel` — a
    // SEPARATE `NSPanel` anchored above this fixed frame (see `OverlayController` /
    // `CodingCustomizationPanel`) — so this view's own layout never transitions.
    private var listeningContent: some View {
        calmListeningRow
            .padding(.horizontal, SpeakSpacing.md)
            .padding(.vertical, SpeakSpacing.sm + SpeakSpacing.xs)   // = 12 pt [decision]
    }

    /// The (only) listening layout: live waveform, partial text, elapsed timer, and the
    /// single prompt-customization button. [decision P-Code v2: pixel-identical across
    /// the entire `.listening` state — pressing the button never resizes or swaps this row.]
    private var calmListeningRow: some View {
        HStack(alignment: .center, spacing: SpeakSpacing.sm) {
            WaveformView(level: model.level, isActive: true)
                .frame(width: WaveformView.totalWidth)
            textContent
            Text(Self.durationLabel(model.elapsedSeconds))
                .font(.speakMonoCaption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            customizeButton
            closeButton
        }
    }

    /// The base HUD's single button: opens the separate `CodingCustomizationPanel`
    /// (real-time prompt editor) anchored above this fixed frame. Does not mutate any
    /// state that affects THIS view's layout — only `isCodingPanelOpen`, which the
    /// second panel (not this one) reacts to. [decision P-Code v2]
    private var customizeButton: some View {
        Button {
            model.isCodingPanelOpen.toggle()
            model.onCodingPanelOpenChanged?(model.isCodingPanelOpen)
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Customize the prompt for this dictation")
        .accessibilityAddTraits(model.isCodingPanelOpen ? [.isSelected, .isButton] : .isButton)
    }

    private var closeButton: some View {
        Button {
            model.onCancel?()
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.secondary.opacity(0.8))
        }
        .buttonStyle(.plain)
        .help("Cancel dictation and hide overlay")
        .accessibilityLabel("Cancel dictation")
    }

    // [decision P-Code v2] The PE-3.2 pin-suggestion row (`pinPromptRow`) and the PE-3c
    // destination/Agent-category picker (`destinationPill`, `profileSelectorCard`,
    // `destinationPage`, `profileButton`, `agentCategoryPage`, `primaryCategories`/
    // `rareCategories`, `categoryButton` — formerly in
    // App/Overlay/TranscriptOverlayView+ProfileSelector.swift, now deleted) are removed:
    // the base HUD shows exactly waveform + transcript + timer + one button, nothing
    // else. `OverlayViewModel.showPinPrompt`/`pinContextLabel`/`onPin`/`onDismissPin` and
    // `isProfilePanelOpen`/`isShowingAgentCategories`/`activeCategory`/`onSelectCategory`
    // are left in place on the model (DictationController's pin-to-context and per-app
    // category state still use them) but nothing in this View sets or renders from them
    // anymore — the destination/category chip taps that used to drive them no longer exist.

    /// Format elapsed seconds as `m:ss` for the HUD (e.g. 0:05, 1:23).
    static func durationLabel(_ seconds: Int) -> String {
        let s = max(0, seconds)
        return "\(s / 60):\(String(format: "%02d", s % 60))"
    }

    @ViewBuilder
    private var textContent: some View {
        if model.partialText.isEmpty {
            Text("Listening\u{2026}")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel("Listening for speech")
                .accessibilityAddTraits(.updatesFrequently)
        } else {
            Text(model.partialText)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
                .lineSpacing(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentTransition(.interpolate)
                .accessibilityLabel(model.partialText)
                .accessibilityAddTraits(.updatesFrequently)
        }
    }

    // MARK: - Processing state

    private var processingContent: some View {
        HStack(spacing: SpeakSpacing.sm) {
            ProgressView()
                .scaleEffect(0.7)
                .frame(width: 16, height: 16)
            // W2.2: honest copy — "Cleaning up…" only when cleanup is actually running.
            Text(model.isCleaningUp ? "Cleaning up\u{2026}" : "Pasting\u{2026}")
                .font(.speakMonoBody)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            closeButton
        }
        .padding(.horizontal, SpeakSpacing.md)
        .padding(.vertical, SpeakSpacing.sm + SpeakSpacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel(model.isCleaningUp ? "Cleaning up transcription" : "Pasting transcription")
    }

    // MARK: - Done state

    private var doneContent: some View {
        HStack(spacing: SpeakSpacing.sm) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.system(size: 15))
            Text("Done")
                .font(.speakMonoBody)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            // [H-2] Read-back affordance: visible only when readbackEnabled is on.
            // Same pattern as re-clean below — tapping toggles speak/stop, never queues.
            if model.onReadback != nil {
                Button {
                    model.onReadback?()
                } label: {
                    Image(systemName: "speaker.wave.2")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Read this back aloud")
                .accessibilityLabel("Read the transcript back aloud")
            }
            // [PE-4] Re-clean affordance: visible only when a raw transcript is available.
            if model.onReclean != nil {
                Button {
                    model.onReclean?()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Re-clean with current settings")
            }
        }
        .padding(.horizontal, SpeakSpacing.md)
        .padding(.vertical, SpeakSpacing.sm + SpeakSpacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel("Dictation complete")
    }

    // MARK: - Error state (W2.2)

    /// Red pill with a short reason string. The retry affordance is to press the
    /// hotkey again — shown in the label below the reason. Escape or tapping the
    /// hotkey dismisses the HUD (the Escape monitor is still active in error state).
    private var errorContent: some View {
        HStack(spacing: SpeakSpacing.sm) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
                .font(.system(size: 15))
            VStack(alignment: .leading, spacing: 2) {
                Text("Error")
                    .font(.speakMonoBody)
                    .foregroundStyle(.primary)
                if let reason = model.errorReason, !reason.isEmpty {
                    // Truncate the technical reason to one line — this is a status
                    // pill, not an alert. Full detail is in the os.Logger stream.
                    Text(reason)
                        .font(.speakMonoCaption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Text("Press Escape or try again")
                    .font(.speakMonoCaption)
                    .foregroundStyle(Color.secondary.opacity(0.7))
            }
            Spacer(minLength: 0)
            closeButton
        }
        .padding(.horizontal, SpeakSpacing.md)
        .padding(.vertical, SpeakSpacing.sm + SpeakSpacing.xs)
        .accessibilityLabel(accessibilityErrorLabel)
    }

    private var accessibilityErrorLabel: String {
        var label = "Dictation error."
        if let reason = model.errorReason, !reason.isEmpty {
            label += " \(reason)."
        }
        label += " Press Escape or try again."
        return label
    }

    // MARK: - VoiceOver state announcements

    /// Post a VoiceOver notification when the overlay state changes.
    /// Uses `NSAccessibility.post(element:notification:)` — the standard macOS
    /// mechanism for screen-reader state announcements from non-focused windows.
    /// [decision W2.2: announcement on every state transition so VoiceOver users
    ///  know when dictation has finished without watching the screen]
    private func postAccessibilityAnnouncement(for state: OverlayState) {
        let message: String
        switch state {
        case .listening:   message = "Listening"
        case .processing:  message = model.isCleaningUp ? "Cleaning up" : "Pasting"
        case .done:        message = "Done"
        case .error:       message = "Dictation error. Press Escape or try again."
        }
        // `NSApp` is the closest NSObject proxy for a non-key panel announcement.
        // The notification `.announcementRequested` + userInfo string is the
        // documented pattern for custom announcements.
        // [verified: NSAccessibility.NotificationUserInfoKey — macOS 26 renamed API]
        NSAccessibility.post(
            element: NSApp as AnyObject,
            notification: .announcementRequested,
            userInfo: [
                NSAccessibility.NotificationUserInfoKey.announcement: message,
                NSAccessibility.NotificationUserInfoKey.priority: NSAccessibilityPriorityLevel.high.rawValue
            ]
        )
    }
}

// MARK: - OverlayKnobsRow (PE-4)

/// Three rows of compact segmented-style chips — format, tone, length — for
/// per-dictation overrides. Extracted from `TranscriptOverlayView` to keep its
/// type body within the linter budget. Mutates `model` directly (same @Observable
/// reference) and fires `model.onKnobChanged?()` on each change. [decision PE-4]
///
/// Internal (not `private`) so `CodingCustomizationView` (App/Overlay/CodingCustomizationView.swift)
/// can reuse it rather than duplicating the format/tone/length chip logic in the new
/// coding-customization panel. [decision P-Code: reuse existing knob plumbing]
struct OverlayKnobsRow: View {
    let model: OverlayViewModel

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 2) {
                ForEach(OutputFormat.allCases, id: \.self) { fmt in
                    knobChip(label: Self.formatLabel(fmt), isActive: model.perDictationFormat == fmt) {
                        model.perDictationFormat = fmt
                        model.onKnobChanged?()
                    }
                }
            }
            HStack(spacing: 2) {
                ForEach(Tone.allCases, id: \.self) { tone in
                    knobChip(label: Self.toneLabel(tone), isActive: model.perDictationTone == tone) {
                        model.perDictationTone = tone
                        model.onKnobChanged?()
                    }
                }
            }
            HStack(spacing: 2) {
                ForEach(LengthBias.allCases, id: \.self) { len in
                    knobChip(label: Self.lengthLabel(len), isActive: model.perDictationLength == len) {
                        model.perDictationLength = len
                        model.onKnobChanged?()
                    }
                }
            }
            // Cancel affordance: abandon this dictation without pasting. [decision PE-4]
            HStack {
                Spacer(minLength: 0)
                Button {
                    model.isProfilePanelOpen = false
                    model.onCancel?()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "xmark.circle")
                            .font(.system(size: 10))
                        Text("Cancel")
                            .font(.speakMonoCaption)
                    }
                    .foregroundStyle(Color.secondary.opacity(0.6))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cancel this dictation without pasting")
            }
        }
    }

    private func knobChip(label: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.speakMonoCaption)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(isActive ? Color.accentColor.opacity(0.30) : Color.primary.opacity(0.06))
                )
                .foregroundStyle(isActive ? Color.primary : Color.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isActive ? [.isSelected, .isButton] : .isButton)
    }

    static func formatLabel(_ f: OutputFormat) -> String {
        switch f {
        case .asIs:      return "Auto"
        case .paragraph: return "Prose"
        case .bullets:   return "List"
        case .numbered:  return "Num."
        case .codeBlock: return "Code"
        case .verbatim:  return "Verb."
        }
    }

    static func toneLabel(_ t: Tone) -> String {
        switch t {
        case .neutral: return "Auto"
        case .terse:   return "Terse"
        case .formal:  return "Formal"
        case .casual:  return "Casual"
        }
    }

    static func lengthLabel(_ l: LengthBias) -> String {
        switch l {
        case .preserve: return "Auto"
        case .condense: return "Condense"
        case .expand:   return "Expand"
        }
    }
}

// MARK: - Preview

// HONESTY BOUNDARY: these previews verify *content layout* only (text, waveform
// bars, icons, padding). They do NOT verify panel/window-server behavior:
// floating-over-other-apps, bottom-center positioning, `.nonactivatingPanel`,
// `canBecomeKey=false`, or hide-on-done timing — those are irreducibly live.

#if DEBUG
/// Listening — placeholder state. No partial text; shows idle waveform.
#Preview("Listening — placeholder") {
    let model = OverlayViewModel()
    model.overlayState = .listening
    model.partialText = ""
    model.level = 0.0
    return TranscriptOverlayView(model: model)
        .frame(width: 340, height: 60)
}

/// Listening — with live level (mid volume). 15 bars reactive to 0.6 level.
#Preview("Listening — live level 0.6") {
    let model = OverlayViewModel()
    model.overlayState = .listening
    model.partialText = "the quick brown fox"
    model.level = 0.6
    return TranscriptOverlayView(model: model)
        .frame(width: 340, height: 60)
}

/// Processing — cleanup spinner. Shows "Cleaning up…" (cleanup on).
#Preview("Processing — cleanup on") {
    let model = OverlayViewModel()
    model.overlayState = .processing
    model.isCleaningUp = true
    return TranscriptOverlayView(model: model)
        .frame(width: 340, height: 60)
}

/// Processing — paste spinner. Shows "Pasting…" (cleanup off).
#Preview("Processing — cleanup off") {
    let model = OverlayViewModel()
    model.overlayState = .processing
    model.isCleaningUp = false
    return TranscriptOverlayView(model: model)
        .frame(width: 340, height: 60)
}

/// Done — checkmark confirmation.
#Preview("Done") {
    let model = OverlayViewModel()
    model.overlayState = .done
    return TranscriptOverlayView(model: model)
        .frame(width: 340, height: 60)
}

/// Done — with readback + re-clean affordances (both callbacks wired).
/// [H-2] Documents the read-back button's placement alongside re-clean.
#Preview("Done — readback + re-clean") {
    let model = OverlayViewModel()
    model.overlayState = .done
    model.onReadback = {}
    model.onReclean = {}
    return TranscriptOverlayView(model: model)
        .frame(width: 340, height: 60)
}

/// Error — red pill with reason. W2.2 new state.
#Preview("Error") {
    let model = OverlayViewModel()
    model.overlayState = .error
    model.errorReason = "Speech engine unavailable"
    return TranscriptOverlayView(model: model)
        .frame(width: 340, height: 60)
}

/// Error — no reason (engine didn't provide one).
#Preview("Error — no reason") {
    let model = OverlayViewModel()
    model.overlayState = .error
    model.errorReason = nil
    return TranscriptOverlayView(model: model)
        .frame(width: 340, height: 60)
}

/// Listening — the single customize button, shown highlighted (as it renders while
/// `CodingCustomizationPanel` is open). [decision P-Code v2: the base HUD's layout is
/// identical whether the panel is open or closed — this preview documents that.]
#Preview("Listening — customize panel open") {
    let model = OverlayViewModel()
    model.overlayState = .listening
    model.partialText = "open the customization panel"
    model.isCodingPanelOpen = true
    return TranscriptOverlayView(model: model)
        .frame(width: 340, height: 60)
}
#endif
// MARK: - AnimatedTranscriptView & FlowLayout

struct AnimatedTranscriptView: View {
    let text: String
    @State private var previousText: String = ""
    @State private var diffTokens: [DiffToken] = []
    @State private var cleanupTask: Task<Void, Never>? = nil

    var body: some View {
        ScrollViewReader { _ in
            ScrollView(.vertical, showsIndicators: false) {
                FlowLayout(spacing: 4) {
                    ForEach(Array(diffTokens.enumerated()), id: \.offset) { index, token in
                        TokenView(token: token)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onAppear {
            previousText = text
            let resolver = TextDiffResolver()
            diffTokens = resolver.resolve(raw: "", cleaned: text)
        }
        .onChange(of: text) { _, newText in
            let resolver = TextDiffResolver()
            let tokens = resolver.resolve(raw: previousText, cleaned: newText)
            
            withAnimation(.easeInOut(duration: 0.2)) {
                diffTokens = tokens
            }
            
            // Clean up canceled tokens after delay
            cleanupTask?.cancel()
            cleanupTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.8))
                guard !Task.isCancelled else { return }
                previousText = newText
                let cleanTokens = resolver.resolve(raw: "", cleaned: newText)
                withAnimation(.easeInOut(duration: 0.2)) {
                    diffTokens = cleanTokens
                }
            }
        }
    }
}

private struct TokenView: View {
    let token: DiffToken
    @State private var progress: CGFloat = 0

    var body: some View {
        Text(token.text)
            .font(.speakMonoBody)
            .foregroundStyle(token.state == .canceled ? .secondary : .primary)
            .overlay(
                Group {
                    if token.state == .canceled {
                        AnimatedStrikethroughLine(progress: progress)
                            .stroke(Color.red, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                            .onAppear {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    progress = 1.0
                                }
                            }
                    }
                }
            )
            // Canceled words look slightly faded
            .opacity(token.state == .canceled ? 0.6 : 1.0)
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.width ?? .infinity, subviews: subviews, spacing: spacing)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            let point = result.frames[index].origin
            subview.place(at: CGPoint(x: point.x + bounds.minX, y: point.y + bounds.minY), proposal: .unspecified)
        }
    }

    struct FlowResult {
        var size: CGSize = .zero
        var frames: [CGRect] = []
        
        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var currentX: CGFloat = 0
            var currentY: CGFloat = 0
            var lineHeight: CGFloat = 0
            
            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                if currentX + size.width > maxWidth && currentX > 0 {
                    currentX = 0
                    currentY += lineHeight + spacing
                    lineHeight = 0
                }
                frames.append(CGRect(origin: CGPoint(x: currentX, y: currentY), size: size))
                currentX += size.width + spacing
                lineHeight = max(lineHeight, size.height)
            }
            size = CGSize(width: maxWidth, height: currentY + lineHeight)
        }
    }
}
