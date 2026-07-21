// Speak/App/Workspace/EvidenceCardView.swift
//
// SwiftUI renderer for Rich Media Evidence Cards returned by tagged agents and plugins.
// Uses centralized design system tokens (`Color.speak*`, `Font.speakMono*`).

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
                .foregroundColor(.speakBone)

            // Dynamic Task Checklist
            if !payload.checklist.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(payload.checklist) { item in
                        HStack(spacing: 8) {
                            statusIcon(for: item.status)

                            Text(item.title)
                                .font(.speakMonoCaption)
                                .foregroundColor(item.status == .done ? .speakMica : .speakBone)
                                .strikethrough(item.status == .done)

                            Spacer()
                        }
                    }
                }
                .padding(8)
                .background(Color.speakInk.opacity(0.4))
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
                                    .font(.speakMonoCaption)
                            }
                            .foregroundColor(.speakMica)

                            Text(diff.patch)
                                .font(.speakMonoCaption)
                                .padding(6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.black.opacity(0.3))
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
                            .font(.speakMonoCaption)
                            .foregroundColor(.speakAgentViolet)
                    }

                    if !payload.videos.isEmpty {
                        Label("\(payload.videos.count) Videos", systemImage: "film")
                            .font(.speakMonoCaption)
                            .foregroundColor(.speakAgentViolet)
                    }

                    if payload.audioPath != nil {
                        Label("Audio Summary", systemImage: "waveform")
                            .font(.speakMonoCaption)
                            .foregroundColor(.speakHumanAmber)
                    }
                }
            }
        }
        .padding(12)
        .background(Color.speakInk2)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.speakCardBorder, lineWidth: 1)
        )
        .cornerRadius(8)
    }

    @ViewBuilder
    private func statusIcon(for status: TaskChecklistStatus) -> some View {
        switch status {
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.speakDelivered)
                .font(.system(size: 12))

        case .inProgress:
            Image(systemName: "progress.indicator")
                .foregroundColor(.speakAgentViolet)
                .font(.system(size: 12))

        case .blocked:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.speakHumanAmber)
                .font(.system(size: 12))

        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(.speakOnAir)
                .font(.system(size: 12))

        case .pending:
            Image(systemName: "circle")
                .foregroundColor(.speakMica)
                .font(.system(size: 12))
        }
    }
}
