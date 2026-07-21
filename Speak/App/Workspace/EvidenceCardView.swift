// Speak/App/Workspace/EvidenceCardView.swift
//
// SwiftUI renderer for Rich Media Evidence Cards returned by tagged agents and plugins.
// Renders dynamic task checklists, code patch diffs, and media attachment previews.

import SpeakCore
import SwiftUI

public struct EvidenceCardView: View {
    public let payload: EvidencePayload

    public init(payload: EvidencePayload) {
        self.payload = payload
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Summary Header
            Text(payload.summary)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.primary)

            // Dynamic Task Checklist
            if !payload.checklist.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(payload.checklist) { item in
                        HStack(spacing: 8) {
                            statusIcon(for: item.status)
                            Text(item.title)
                                .font(.system(size: 12))
                                .foregroundColor(item.status == .done ? .secondary : .primary)
                                .strikethrough(item.status == .done)
                            Spacer()
                        }
                    }
                }
                .padding(8)
                .background(Color.secondary.opacity(0.08))
                .cornerRadius(6)
            }

            // Code Patch Diffs
            if !payload.diffs.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(payload.diffs, id: \.file) { diff in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: "doc.text")
                                    .font(.system(size: 11))
                                Text(diff.file)
                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            }
                            .foregroundColor(.secondary)

                            Text(diff.patch)
                                .font(.system(size: 11, design: .monospaced))
                                .padding(6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.black.opacity(0.15))
                                .cornerRadius(4)
                        }
                    }
                }
            }

            // Attachments (Images / Videos / Audio)
            if !payload.images.isEmpty || !payload.videos.isEmpty || payload.audioPath != nil {
                HStack(spacing: 12) {
                    if !payload.images.isEmpty {
                        Label("\(payload.images.count) Images", systemImage: "photo")
                            .font(.system(size: 11))
                            .foregroundColor(.accentColor)
                    }
                    if !payload.videos.isEmpty {
                        Label("\(payload.videos.count) Videos", systemImage: "film")
                            .font(.system(size: 11))
                            .foregroundColor(.accentColor)
                    }
                    if payload.audioPath != nil {
                        Label("Audio Summary", systemImage: "waveform")
                            .font(.system(size: 11))
                            .foregroundColor(.accentColor)
                    }
                }
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.04))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
        .cornerRadius(8)
    }

    @ViewBuilder
    private func statusIcon(for status: TaskChecklistStatus) -> some View {
        switch status {
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.system(size: 12))
        case .inProgress:
            Image(systemName: "progress.indicator")
                .foregroundColor(.blue)
                .font(.system(size: 12))
        case .blocked:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.system(size: 12))
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(.red)
                .font(.system(size: 12))
        case .pending:
            Image(systemName: "circle")
                .foregroundColor(.gray)
                .font(.system(size: 12))
        }
    }
}
