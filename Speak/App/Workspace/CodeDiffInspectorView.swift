// Speak/App/Workspace/CodeDiffInspectorView.swift
//
// Interactive syntax-highlighted code diff inspector for Evidence Cards.
// Highlights additions (+) in green, deletions (-) in red, and neutral lines in mica gray.
// Styled with centralized design system tokens (`Color.speak*`, `Font.speakMono*`).

import SpeakCore
import SwiftUI

public struct CodeDiffInspectorView: View {
    public let file: String
    public let patch: String

    @State private var isExpanded: Bool = true

    public init(file: String, patch: String) {
        self.file = file
        self.patch = patch
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header Bar
            HStack {
                Button(action: { isExpanded.toggle() }) {
                    HStack(spacing: 6) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.speakMica)

                        Image(systemName: "doc.text")
                            .font(.system(size: 11))
                            .foregroundColor(.speakAgentViolet)

                        Text(file)
                            .font(.speakMonoCaption)
                            .foregroundColor(.speakBone)
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                Text("\(patchLines.count) lines")
                    .font(.system(size: 10))
                    .foregroundColor(.speakMica)
            }

            // Expanded Line-by-Line Highlighted Diff
            if isExpanded {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(patchLines.enumerated()), id: \.offset) { _, line in
                        diffLineView(line)
                    }
                }
                .padding(8)
                .background(Color.black.opacity(0.4))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.speakCardBorder, lineWidth: 1)
                )
            }
        }
    }

    private var patchLines: [String] {
        patch.components(separatedBy: .newlines)
    }

    private func diffLineView(_ line: String) -> some View {
        HStack(spacing: 6) {
            Text(line)
                .font(.speakMonoCaption)
                .foregroundColor(lineColor(for: line))
                .lineLimit(1)

            Spacer()
        }
        .padding(.vertical, 1)
        .padding(.horizontal, 4)
        .background(lineBackgroundColor(for: line))
        .cornerRadius(2)
    }

    private func lineColor(for line: String) -> Color {
        if line.hasPrefix("+") {
            return Color.speakDelivered
        } else if line.hasPrefix("-") {
            return Color.speakOnAir
        } else {
            return Color.speakBone
        }
    }

    private func lineBackgroundColor(for line: String) -> Color {
        if line.hasPrefix("+") {
            return Color.speakDelivered.opacity(0.12)
        } else if line.hasPrefix("-") {
            return Color.speakOnAir.opacity(0.12)
        } else {
            return Color.clear
        }
    }
}
