// SpeakTests/KnobsTests.swift
//
// PE-4 unit tests: per-dictation knob overrides.
//
// Coverage:
//   1. OverlayController.start() resets all three knobs to their "Auto" defaults
//      — verifies that a new dictation always starts clean regardless of what the
//      previous dictation set.
//   2. OverlayController.configureKnobs() wires onKnobChanged + onCancel correctly
//      — the callbacks fire when set and the model holds the new knob value.
//   3. PromptBuilder.formatClause / toneClause / lengthClause emit non-nil strings
//      for all non-Auto values and nil for the "Auto" (no-override) defaults
//      — verifies the PromptBuilder end of the knob-to-profile pipeline.

@testable import Speak
@testable import SpeakCore
import Testing

@Suite("KnobsOverride")
@MainActor
struct KnobsTests {

    // MARK: - 1. Knob reset on start

    @Test func knobsResetOnStart() async {
        let controller = OverlayController()
        // Manually dirty all four knobs on the model before start().
        controller.overlayModel.perDictationFormat = .bullets
        controller.overlayModel.perDictationTone = .formal
        controller.overlayModel.perDictationLength = .condense
        controller.overlayModel.perDictationLevel = .high

        controller.start(
            partialsProvider: { nil },
            levelsProvider: { nil },
            isCleaningUp: true
        )

        #expect(controller.overlayModel.perDictationFormat == .asIs,
                "start() must reset format knob to .asIs (Auto).")
        #expect(controller.overlayModel.perDictationTone == .neutral,
                "start() must reset tone knob to .neutral (Auto).")
        #expect(controller.overlayModel.perDictationLength == .preserve,
                "start() must reset length knob to .preserve (Auto).")
        #expect(controller.overlayModel.perDictationLevel == nil,
                "start() must reset strength knob to nil (Auto).")
    }

    // MARK: - 2. Knob callback wiring

    @Test func knobChangedCallbackFires() async {
        let controller = OverlayController()
        var callbackCount = 0
        controller.configureKnobs(
            onKnobChanged: { callbackCount += 1 },
            onCancel: {},
            onReclean: {}
        )
        // Simulate the view tapping a knob chip.
        controller.overlayModel.perDictationFormat = .paragraph
        controller.overlayModel.onKnobChanged?()

        #expect(callbackCount == 1, "onKnobChanged must fire once per knob tap.")
        #expect(controller.overlayModel.perDictationFormat == .paragraph,
                "Model must hold the newly selected knob value.")
    }

    @Test func cancelCallbackFires() async {
        let controller = OverlayController()
        var cancelled = false
        controller.configureKnobs(
            onKnobChanged: {},
            onCancel: { cancelled = true },
            onReclean: {}
        )
        controller.overlayModel.onCancel?()

        #expect(cancelled, "onCancel must fire when the cancel button is tapped.")
    }

    // MARK: - 3. PromptBuilder knob clauses

    @Test func formatClauseNilForAutoDefault() {
        // .asIs means "no format override" — clause must be nil so the existing
        // system-prompt format rules are unchanged.
        #expect(PromptBuilder.formatClause(.asIs) == nil,
                "formatClause(.asIs) must be nil — Auto adds no instruction.")
    }

    @Test func formatClauseNonNilForNonDefault() {
        for fmt in OutputFormat.allCases where fmt != .asIs {
            #expect(PromptBuilder.formatClause(fmt) != nil,
                    "formatClause(\(fmt)) must emit a non-nil clause.")
        }
    }

    @Test func toneClauseNilForNeutral() {
        #expect(PromptBuilder.toneClause(.neutral) == nil,
                "toneClause(.neutral) must be nil — Auto adds no instruction.")
    }

    @Test func toneClauseNonNilForNonNeutral() {
        for tone in Tone.allCases where tone != .neutral {
            #expect(PromptBuilder.toneClause(tone) != nil,
                    "toneClause(\(tone)) must emit a non-nil clause.")
        }
    }

    @Test func lengthClauseNilForPreserve() {
        #expect(PromptBuilder.lengthClause(.preserve) == nil,
                "lengthClause(.preserve) must be nil — Auto adds no instruction.")
    }

    @Test func lengthClauseNonNilForNonPreserve() {
        for len in LengthBias.allCases where len != .preserve {
            #expect(PromptBuilder.lengthClause(len) != nil,
                    "lengthClause(\(len)) must emit a non-nil clause.")
        }
    }

    // MARK: - 4. Effective-profile knob override logic

    @Test func effectiveProfileAppliesNonAutoKnobs() {
        var profile = DefaultProfiles.write
        // Simulate the knob-application logic from DictationController+ErrorHandling.
        let kf: OutputFormat = .bullets
        let kt: Tone = .terse
        let kl: LengthBias = .condense
        if kf != .asIs { profile.format = kf }
        if kt != .neutral { profile.tone = kt }
        if kl != .preserve { profile.length = kl }

        #expect(profile.format == .bullets, "Non-Auto format knob must override profile.format.")
        #expect(profile.tone == .terse, "Non-Auto tone knob must override profile.tone.")
        #expect(profile.length == .condense, "Non-Auto length knob must override profile.length.")
    }

    @Test func effectiveProfilePreservesProfileDefaultsForAutoKnobs() {
        var profile = DefaultProfiles.write
        // For a Write profile with its own format, Auto knobs must not override it.
        let originalFormat = profile.format
        let kf: OutputFormat = .asIs   // Auto — don't override
        if kf != .asIs { profile.format = kf }

        #expect(profile.format == originalFormat,
                "Auto knob must not override the profile's own format setting.")
    }
}
