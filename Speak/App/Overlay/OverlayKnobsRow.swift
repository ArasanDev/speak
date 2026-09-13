// App/Overlay/OverlayKnobsRow.swift
//
// Three rows of compact segmented-style chips — format, tone, length — for
// per-dictation overrides. Extracted from TranscriptOverlayView.swift to respect
// strict line limits (<800 lines).

import AppKit
import SpeakCore
import SwiftUI

// MARK: - OverlayKnobsRow (PE-4)

/// Three rows of compact segmented-style chips — format, tone, length — for
/// per-dictation overrides. Mutates `model` directly (same @Observable reference)
/// and fires `model.onKnobChanged?()` on each change. [decision PE-4]
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
                            .font(.speakBody(.caption))
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
                .font(.speakBody(.caption))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(isActive ? Color.speakUIAccent.opacity(0.30) : Color.speakSurface)
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
