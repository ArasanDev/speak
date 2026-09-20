// App/Overlay/OverlayKnobsRow.swift
//
// Labeled rows of compact segmented chips for per-dictation overrides —
// strength (AI cleanup level), format, tone, length. Extracted from
// TranscriptOverlayView.swift to respect strict line limits (<800 lines).
//
// The rows are labeled (2026-11): fourteen unlabeled chips read as noise —
// the label column is what makes the grid scannable. "Strength" leads
// because it answers the most-asked runtime question — how hard the model
// works on the raw transcript for THIS dictation (Auto follows the saved
// Settings level; Raw bypasses the model entirely).
//

import AppKit
import SpeakCore
import SwiftUI

// MARK: - OverlayKnobsRow (PE-4)

/// Labeled rows of compact segmented chips — strength, format, tone, length —
/// for per-dictation overrides. Mutates `model` directly (same @Observable
/// reference) and fires `model.onKnobChanged?()` on each change. [decision PE-4]
///
/// Internal (not `private`) so `CodingCustomizationView` (App/Overlay/CodingCustomizationView.swift)
/// can reuse it rather than duplicating the chip logic in the new
/// coding-customization panel. [decision P-Code: reuse existing knob plumbing]
struct OverlayKnobsRow: View {
    let model: OverlayViewModel

    /// Width of the row label column — one value so the chip grids align
    /// vertically down the panel. [decision: 58 pt — fits "Strength" at
    /// caption size with breathing room; wider would starve the chips.]
    private static let labelColumnWidth: CGFloat = 58

    var body: some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.xs) {
            knobRow("Strength") {
                ForEach(StrengthChoice.all) { choice in
                    knobChip(label: choice.label, isActive: model.perDictationLevel == choice.level) {
                        model.perDictationLevel = choice.level
                        model.onKnobChanged?()
                    }
                }
            }
            knobRow("Format") {
                ForEach(OutputFormat.allCases, id: \.self) { fmt in
                    knobChip(label: Self.formatLabel(fmt), isActive: model.perDictationFormat == fmt) {
                        model.perDictationFormat = fmt
                        model.onKnobChanged?()
                    }
                }
            }
            knobRow("Tone") {
                ForEach(Tone.allCases, id: \.self) { tone in
                    knobChip(label: Self.toneLabel(tone), isActive: model.perDictationTone == tone) {
                        model.perDictationTone = tone
                        model.onKnobChanged?()
                    }
                }
            }
            knobRow("Length") {
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
                            .font(.speakBody(.caption))
                    }
                    .foregroundStyle(Color.secondary.opacity(0.8))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cancel this dictation without pasting")
            }
        }
    }

    /// One labeled chip row — the label column keeps every chip grid
    /// left-aligned so the panel reads as a table, not scattered buttons.
    private func knobRow(_ label: String, @ViewBuilder chips: () -> some View) -> some View {
        HStack(alignment: .center, spacing: SpeakSpacing.xs) {
            Text(label)
                .font(.speakBody(.caption))
                .foregroundStyle(Color.speakMica)
                .frame(width: Self.labelColumnWidth, alignment: .leading)
            HStack(spacing: 2) {
                chips()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func knobChip(label: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.speakBody(.caption))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(isActive ? Color.speakUIAccent.opacity(0.45) : Color.speakSurface)
                )
                .foregroundStyle(isActive ? Color.primary : Color.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isActive ? [.isSelected, .isButton] : .isButton)
    }

    /// The strength row's choices — `nil` is "Auto" (follow the saved
    /// Settings level); `.none` is "Raw" (paste the transcript untouched).
    private struct StrengthChoice: Identifiable {
        let label: String
        let level: CleanupLevel?
        var id: String { label }

        static let all: [StrengthChoice] = [
            StrengthChoice(label: "Auto", level: nil),
            StrengthChoice(label: "Raw", level: CleanupLevel.none),
            StrengthChoice(label: "Light", level: .light),
            StrengthChoice(label: "Medium", level: .medium),
            StrengthChoice(label: "High", level: .high),
        ]
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
