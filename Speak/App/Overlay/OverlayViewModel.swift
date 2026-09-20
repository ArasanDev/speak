// App/Overlay/OverlayViewModel.swift
//
// Observable model bridging DictationController → TranscriptOverlayView.
// Extracted from TranscriptOverlayView.swift to respect strict line limits (<800 lines)
// and maintain clean separation of concerns.

import AppKit
import Foundation
import SpeakCore

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
        if id == DefaultProfiles.agent.id {
            self = .agent
        } else if id == DefaultProfiles.write.id {
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

    /// Layer 3: Active bidirectional voice conversation loop manager.
    var conversationLoopManager: ConversationLoopManager?

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
    /// Ticks through `.listening` AND `.processing` (the right-circle readout
    /// shows capture + cleanup elapsed); frozen when `.done`/`stop()`/
    /// `showError` cancel the duration task.
    var elapsedSeconds: Int = 0

    /// Microphone level (0…1), smoothed RMS from `AudioCapture` (W2.1).
    /// 0.0 when idle; driven live during `.listening`.
    var level: Double = 0.0

    /// W2.2: Short error reason shown in the error pill. Nil when not in `.error` state.
    var errorReason: String?

    // MARK: Felt-speed — "settling" provisional state (input-felt-speed.md §3.3)

    /// The raw transcript preserved during the `.processing` window. The user just spoke
    /// these words — we keep them on screen (marked provisional) instead of wiping to a
    /// blank spinner while cleanup runs. [decision: raw text is already in the panel at
    /// stop; preserve it rather than clearing it. specs/input-felt-speed.md]
    var settlingText: String = ""

    /// `true` while the `.processing` window is showing `settlingText` as provisional.
    /// Drives the "polishing…" copy + dimmed rendering. This is NOT capture — it must
    /// never light `onAir` (specs/frontend-identity.md, frozen: onAir iff capturing).
    var isSettling: Bool = false

    /// `true` once cleanup has returned and we are animating raw→clean via the word diff.
    /// Set by `OverlayController` when the transformed text arrives; `false` for the raw
    /// (no-diff) fallback so the overlay shows a clean "Done" instead of a no-op diff.
    var isDiffTransforming: Bool = false

    /// The cleaned result to reveal. `nil` until cleanup returns. When non-nil,
    /// `TranscriptOverlayView` renders the raw→clean diff (canceled words struck).
    var revealedText: String?

    // MARK: Filmstrip — kept for tests; listening UI no longer uses it.
    // Product path is the 3-line FIFO window below. [decision: 2026-08-06 human —
    // remove minimizing chips / floating outbound; FIFO in-panel only.]

    /// Completed horizontal blocks (test / dormant filmstrip path).
    var filmstripBlocks: [FilmstripBlock] = []

    /// Live streaming remainder for the dormant filmstrip path.
    var activeStreamText: String = ""

    /// Dormant: filmstrip chips off. Listening uses the FIFO window instead.
    var isFilmstripEnabled: Bool = false

    // MARK: 3-line FIFO window (listening overflow)

    /// Pure FIFO state machine: when the 3-line budget fills, oldest text leaves
    /// first so newest speech keeps appending. Outbound chunks are discarded for
    /// now (not shown on a second panel). [decision: 2026-08-06 human]
    var textFlow = OverlayTextFlow()

    /// The text currently visible in the 3-line overlay window (newest end of
    /// the transcript). Updated on every partial ingest.
    var windowText: String = ""

    /// Unused mirror of flowed chunks (outbound ignored for now).
    var flowedChunks: [FlowedChunk] = []

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

    /// Per-dictation cleanup-strength override. `nil` = "Auto" — the session
    /// runs the saved `SettingsStore.cleanupLevel`. `.none` = "Raw" — skip the
    /// model for this dictation (routes to `applyRawOverride` at stop).
    /// `.light`/`.medium`/`.high` thread into `applyProfileOverride(level:)`.
    /// [decision: per-dictation only — the saved level in Settings is untouched.]
    var perDictationLevel: CleanupLevel? = nil

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

    /// Per-dictation agent prompt tagging style (Off, [speak-stt], [voice-stt], etc.).
    /// Initialized at dictation start from `SettingsStore.agentPrefixStyle`.
    var agentPrefixStyle: AgentPrefixStyle = .none

    /// Whether to append :clean or :raw state to the agent prompt tag.
    /// Initialized at dictation start from `SettingsStore.agentPrefixIncludeState`.
    var agentPrefixIncludeState: Bool = false
}
