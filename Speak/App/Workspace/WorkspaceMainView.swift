// Speak/App/Workspace/WorkspaceMainView.swift
//
// Main Slack-Replacement Workspace View.
// Renders the Channel Sidebar, Spoken Thread Canvas, and Rich Evidence Cards.

import SpeakCore
import SwiftUI

public struct WorkspaceMainView: View {
    @State private var selectedChannelId: String = "general"
    @State private var inputText: String = ""
    @State private var channels: [Channel] = [
        Channel(id: "general", name: "general", topic: "Default workspace channel"),
        Channel(id: "core-engine", name: "core-engine", topic: "Engine & Audio Core development"),
        Channel(id: "qa-regressions", name: "qa-regressions", topic: "Test suites & moat privacy audits")
    ]
    @State private var messages: [WorkspaceMessage] = []
    @State private var mockEvidences: [UUID: EvidencePayload] = [:]

    public init() {}

    public var body: some View {
        HSplitView {
            // Left Sidebar: Channels & Agent Roster
            sidebarView
                .frame(minWidth: 200, maxWidth: 260)

            // Main Canvas: Thread Feed & Input
            canvasView
                .frame(minWidth: 400)
        }
        .onAppear {
            loadInitialData()
        }
    }

    // MARK: - Sidebar

    private var sidebarView: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Channels Header
            VStack(alignment: .leading, spacing: 8) {
                Text("CHANNELS")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.secondary)

                ForEach(channels) { channel in
                    Button(action: { selectedChannelId = channel.id }) {
                        HStack {
                            Image(systemName: "number")
                                .font(.system(size: 12))
                            Text(channel.name)
                                .font(.system(size: 13, weight: selectedChannelId == channel.id ? .semibold : .regular))
                            Spacer()
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .background(selectedChannelId == channel.id ? Color.accentColor.opacity(0.15) : Color.clear)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()

            // Spoken Plugins as Tags
            VStack(alignment: .leading, spacing: 8) {
                Text("PLUGINS (@TAGS)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.secondary)

                pluginRow(tag: "@terminal", icon: "terminal.fill", label: "Terminal Execution")
                pluginRow(tag: "@github", icon: "arrow.triangle.pull", label: "GitHub Integration")
                pluginRow(tag: "@xcode", icon: "hammer.fill", label: "Xcode Automation")
            }

            Divider()

            // Agent Roster
            VStack(alignment: .leading, spacing: 8) {
                Text("AGENT ROSTER")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.secondary)

                agentRow(tag: "@Claude", status: "Active (Claude Code)", isOnline: true)
                agentRow(tag: "@codex", status: "Idle", isOnline: true)
                agentRow(tag: "@builder-qa", status: "Running Moat Audit", isOnline: true)
            }

            Spacer()
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private func pluginRow(tag: String, icon: String, label: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            Text(tag)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(.accentColor)
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
    }

    private func agentRow(tag: String, status: String, isOnline: Bool) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isOnline ? Color.green : Color.gray)
                .frame(width: 6, height: 6)
            Text(tag)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
            Spacer()
            Text(status)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
    }

    // MARK: - Canvas

    private var canvasView: some View {
        VStack(spacing: 0) {
            // Channel Header
            HStack {
                Text("# \(selectedChannelId)")
                    .font(.system(size: 15, weight: .bold))
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Message / Thread Scroll
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(messages) { msg in
                        messageRow(msg)
                    }
                }
                .padding(16)
            }

            Divider()

            // Spoken Turn Input Bar
            HStack(spacing: 10) {
                Button(action: handleVoiceRecord) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                        .padding(8)
                        .background(Color.accentColor)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                TextField("Type or speak a message... (e.g. Tag @Claude check tap guard)", text: $inputText)
                    .textFieldStyle(.plain)
                    .padding(8)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)
                    .onSubmit {
                        sendMessage()
                    }

                Button("Send", action: sendMessage)
                    .buttonStyle(.borderedProminent)
            }
            .padding(12)
            .background(Color(NSColor.windowBackgroundColor))
        }
    }

    private func messageRow(_ msg: WorkspaceMessage) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(msg.senderTag)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(msg.senderTag.hasPrefix("@") && msg.senderTag != "@tamil" ? .accentColor : .primary)

                Text(msg.createdAt, style: .time)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)

                Spacer()
            }

            Text(msg.text)
                .font(.system(size: 13))

            // Evidence Card if present
            if let evidence = mockEvidences[msg.id] {
                EvidenceCardView(payload: evidence)
                    .padding(.top, 4)
            }
        }
    }

    // MARK: - Actions

    private func loadInitialData() {
        let id1 = UUID()
        let id2 = UUID()

        messages = [
            WorkspaceMessage(id: id1, channelId: "general", senderTag: "@tamil", text: "Tag @Claude review AudioCapture tap safety and tag @terminal run make test"),
            WorkspaceMessage(id: id2, channelId: "general", senderTag: "@Claude", text: "Inspected AudioCapture.swift. Added input.removeTap guard and verified with test suite.")
        ]

        mockEvidences[id2] = EvidencePayload(
            summary: "AudioCapture tap safety patch applied & verified.",
            checklist: [
                TaskChecklistItem(id: "t1", title: "Inspect AudioCapture.swift line 89", status: .done),
                TaskChecklistItem(id: "t2", title: "Add removeTap(onBus: bus) guard", status: .done),
                TaskChecklistItem(id: "t3", title: "Run XCTest & verify-moat audit", status: .done)
            ],
            diffs: [
                CodeDiffBlock(file: "AudioCapture.swift", patch: "+ input.removeTap(onBus: bus)\n  input.installTap(onBus: bus...)")
            ]
        )
    }

    private func sendMessage() {
        guard !inputText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let newMsg = WorkspaceMessage(channelId: selectedChannelId, senderTag: "@tamil", text: inputText)
        messages.append(newMsg)
        let textToSend = inputText
        inputText = ""

        // Extract tags and simulate dynamic agent response
        let extractedTags = VoiceCommandParser.extractTags(from: textToSend)
        if !extractedTags.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                let targetTag = extractedTags[0].tag
                let replyId = UUID()
                let reply = WorkspaceMessage(
                    id: replyId,
                    channelId: selectedChannelId,
                    senderTag: targetTag,
                    text: "Received turn for \(targetTag). Executing requested task..."
                )
                messages.append(reply)
                mockEvidences[replyId] = EvidencePayload(
                    summary: "Executed action for \(targetTag).",
                    checklist: [
                        TaskChecklistItem(id: "c1", title: "Parsed turn parameters", status: .done),
                        TaskChecklistItem(id: "c2", title: "Executing plugin task...", status: .inProgress)
                    ]
                )
            }
        }
    }

    private func handleVoiceRecord() {
        // Triggers voice dictation input into the text field
        inputText = "Tag @Claude check tap safety"
    }
}
