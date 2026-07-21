// Speak/App/Workspace/ChannelCanvasView.swift
//
// Persistent Channel Canvas Side-Sheet.
// Pinned persistent project spec, live task checklist, and system action shortcuts.

import SpeakCore
import SwiftUI

public struct ChannelCanvasView: View {
    public let channelId: String
    public let onClose: () -> Void

    @State private var checklistItems: [TaskChecklistItem] = [
        TaskChecklistItem(id: "c1", title: "STT Finalization Watchdog Fix", status: .done),
        TaskChecklistItem(id: "c2", title: "Centralized Slack Theme System", status: .done),
        TaskChecklistItem(id: "c3", title: "Human-Agent Voice Huddles", status: .done),
        TaskChecklistItem(id: "c4", title: "Quick Switcher & Channel Canvas", status: .inProgress)
    ]

    public init(channelId: String, onClose: @escaping () -> Void) {
        self.channelId = channelId
        self.onClose = onClose
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Canvas Header
            HStack {
                Label("Channel Canvas", systemImage: "doc.richtext")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.speakBone)

                Spacer()

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11))
                        .foregroundColor(.speakMica)
                }
                .buttonStyle(.plain)
            }

            Divider()
                .overlay(Color.speakCardBorder)

            // Pinned Project Topic & Architecture
            VStack(alignment: .leading, spacing: 6) {
                Text("PINNED SPECIFICATION")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.speakMica)

                Text("Channel: #\(channelId)")
                    .font(.speakMonoCaption)
                    .foregroundColor(.speakHumanAmber)

                Text("Local-first Human-Agent Workspace operating manual. Zero cloud audio egress, Apple-native execution, SQLite persistence.")
                    .font(.system(size: 11))
                    .foregroundColor(.speakBone)
            }
            .padding(10)
            .background(Color.speakInk2)
            .cornerRadius(8)

            Divider()
                .overlay(Color.speakCardBorder)

            // Dynamic Task Checklist
            VStack(alignment: .leading, spacing: 8) {
                Text("LIVE TASK CHECKLIST")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.speakMica)

                ForEach(checklistItems) { item in
                    HStack(spacing: 8) {
                        Image(systemName: item.status == .done ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 12))
                            .foregroundColor(item.status == .done ? .speakDelivered : .speakMica)

                        Text(item.title)
                            .font(.speakMonoCaption)
                            .foregroundColor(item.status == .done ? .speakMica : .speakBone)
                            .strikethrough(item.status == .done)

                        Spacer()
                    }
                }
            }

            Divider()
                .overlay(Color.speakCardBorder)

            // Quick Action Shortcuts
            VStack(alignment: .leading, spacing: 8) {
                Text("ACTION SHORTCUTS")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.speakMica)

                HStack(spacing: 8) {
                    Button("Run Tests") {}
                        .buttonStyle(.bordered)
                        .tint(.speakAgentViolet)

                    Button("Moat Audit") {}
                        .buttonStyle(.bordered)
                        .tint(.speakHumanAmber)
                }
            }

            Spacer()
        }
        .padding(14)
        .frame(width: 250)
        .background(Color.speakSidebarBg)
        .overlay(
            Rectangle()
                .frame(width: 1)
                .foregroundColor(.speakCardBorder),
            alignment: .leading
        )
    }
}
