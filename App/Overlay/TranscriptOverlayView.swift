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
}

// MARK: - VisualEffectView

/// Thin AppKit-backed SwiftUI wrapper that applies NSVisualEffectView material.
private struct VisualEffectView: NSViewRepresentable {
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

    // [PE-3c] Calm HUD by default (waveform · transcript · timer · destination pill);
    // clicking the pill opens an anchored selector card that covers the HUD. The card's
    // buttons live in the same FirstMouseHostingView, so clicks register in the
    // non-activating panel without focus steal (proven live in PE-3b).
    private var listeningContent: some View {
        Group {
            if model.isProfilePanelOpen {
                profileSelectorCard
            } else {
                calmListeningRow
            }
        }
        .padding(.horizontal, SpeakSpacing.md)
        .padding(.vertical, SpeakSpacing.sm + SpeakSpacing.xs)   // = 12 pt [decision]
    }

    /// The calm default: live waveform, partial text, elapsed timer, destination pill, and
    /// (when `showPinPrompt`) a pin-suggestion row below. [decision PE-3.2: pin row lives
    /// outside the selector card so it survives card-close on leaf selection.]
    private var calmListeningRow: some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.xs) {
            HStack(alignment: .center, spacing: SpeakSpacing.sm) {
                WaveformView(level: model.level, isActive: true)
                    .frame(width: WaveformView.totalWidth)
                textContent
                Text(Self.durationLabel(model.elapsedSeconds))
                    .font(.speakMonoCaption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                if !model.destinationChoices.isEmpty {
                    destinationPill
                }
            }
            if model.showPinPrompt {
                pinPromptRow
            }
        }
    }

    /// PE-3.2 pin suggestion row. Appears below the waveform row after the user overrides
    /// the same app's destination twice. [Pin] commits; [✕] dismisses and resets the counter.
    private var pinPromptRow: some View {
        HStack(spacing: SpeakSpacing.xs) {
            Image(systemName: "pin.fill")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            Text(model.pinContextLabel)
                .font(.speakMonoCaption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
            Button {
                model.onPin?()
            } label: {
                Text("Pin")
                    .font(.speakMonoCaption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.accentColor.opacity(0.20))
                    )
                    .foregroundStyle(Color.primary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Pin this destination for this app")
            Button {
                model.onDismissPin?()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss pin suggestion")
        }
    }

    /// PE-3c destination pill: shows the active destination (and the category when Agent) +
    /// a chevron; tap opens the card.
    private var destinationPill: some View {
        let active = model.activeDestinationChoice ?? .write
        let label = active == .agent ? "\(active.label) · \(model.activeCategory.displayName)" : active.label
        return Button {
            model.isShowingAgentCategories = false   // always open on the destinations page
            model.isProfilePanelOpen = true
        } label: {
            HStack(spacing: 3) {
                Image(systemName: active.icon)
                Text(label)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 7))
            }
            .font(.speakMonoCaption)
            .padding(.horizontal, SpeakSpacing.xs + 2)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(0.08))
            )
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Destination \(label). Tap to change for this dictation.")
    }

    /// PE-3c selector card. Two pages: destinations (Agent/Write/Note/Raw) and — after Agent
    /// is picked — the Agent **category** tier (PE-3c-2). Picking a leaf option applies the
    /// per-dictation override and closes; Escape closes (handled by OverlayController).
    @ViewBuilder
    private var profileSelectorCard: some View {
        if model.isShowingAgentCategories {
            agentCategoryPage
        } else {
            destinationPage
        }
    }

    private var destinationPage: some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.xs) {
            HStack {
                Text("Shape this dictation")
                    .font(.speakMonoCaption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text("esc")
                    .font(.speakMonoCaption)
                    .foregroundStyle(Color.secondary.opacity(0.6))
            }
            HStack(spacing: SpeakSpacing.xs) {
                ForEach(model.destinationChoices) { choice in
                    profileButton(choice)
                }
            }
            // PE-4: per-dictation knob overrides + cancel (format / tone / length).
            OverlayKnobsRow(model: model)
                .padding(.top, SpeakSpacing.xs)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func profileButton(_ choice: OverlayDestinationChoice) -> some View {
        let isActive = choice == model.activeDestinationChoice
        return Button {
            model.onSelectDestination?(choice)
            // Agent has a deeper tier — swap to its categories instead of closing.
            // Every other destination is a leaf: apply + close.
            if choice == .agent {
                model.isShowingAgentCategories = true
            } else {
                model.isProfilePanelOpen = false
            }
        } label: {
            VStack(spacing: 2) {
                Image(systemName: choice.icon)
                    .font(.system(size: 13))
                Text(choice.label)
                    .font(.speakMonoCaption)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, SpeakSpacing.xs)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isActive ? Color.accentColor.opacity(0.30) : Color.primary.opacity(0.08))
            )
            .foregroundStyle(isActive ? Color.primary : Color.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(choice == .agent
            ? "Agent — choose a category"
            : "Shape this dictation as \(choice.label)")
        .accessibilityAddTraits(isActive ? [.isSelected, .isButton] : .isButton)
    }

    /// PE-3c-2: the Agent category tier. A back affordance returns to destinations; picking a
    /// category threads it into the Agent override and closes the card.
    private var agentCategoryPage: some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.xs) {
            HStack(spacing: SpeakSpacing.xs) {
                Button {
                    model.isShowingAgentCategories = false   // back to destinations
                } label: {
                    HStack(spacing: 2) {
                        Image(systemName: "chevron.left").font(.system(size: 9))
                        Text("Agent").font(.speakMonoCaption)
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back to destinations")
                Spacer(minLength: 0)
                Text("esc")
                    .font(.speakMonoCaption)
                    .foregroundStyle(Color.secondary.opacity(0.6))
            }
            // Primary categories (Code lives behind a future ⌄more, per the spec).
            HStack(spacing: SpeakSpacing.xs) {
                ForEach(Self.primaryCategories, id: \.self) { category in
                    categoryButton(category)
                }
            }
            // PE-4: per-dictation knob overrides + cancel (format / tone / length).
            OverlayKnobsRow(model: model)
                .padding(.top, SpeakSpacing.xs)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The primary Agent categories shown in the card (Code is deferred to a `⌄more` affordance).
    static let primaryCategories: [AgentCategory] = [.task, .fix, .ask, .commit, .shell]

    private func categoryButton(_ category: AgentCategory) -> some View {
        let isActive = category == model.activeCategory
        return Button {
            model.onSelectCategory?(category)
            model.isProfilePanelOpen = false
            model.isShowingAgentCategories = false
        } label: {
            Text(category.displayName)
                .font(.speakMonoCaption)
                .frame(maxWidth: .infinity)
                .padding(.vertical, SpeakSpacing.xs)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isActive ? Color.accentColor.opacity(0.30) : Color.primary.opacity(0.08))
                )
                .foregroundStyle(isActive ? Color.primary : Color.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Agent category \(category.displayName)")
        .accessibilityAddTraits(isActive ? [.isSelected, .isButton] : .isButton)
    }

    /// Format elapsed seconds as `m:ss` for the HUD (e.g. 0:05, 1:23).
    static func durationLabel(_ seconds: Int) -> String {
        let s = max(0, seconds)
        return "\(s / 60):\(String(format: "%02d", s % 60))"
    }

    @ViewBuilder
    private var textContent: some View {
        if model.partialText.isEmpty {
            Text("Listening\u{2026}")
                .font(.speakMonoBody)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel("Listening for speech")
                .accessibilityAddTraits(.updatesFrequently)
        } else {
            Text(model.partialText)
                .font(.speakMonoBody)
                .foregroundStyle(.primary)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
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
private struct OverlayKnobsRow: View {
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
#endif
