// Speak/App/Workspace/WorkspaceMainView.swift
//
// Main Slack-Replacement Workspace View.
// Renders Channel Sidebar, Spoken Thread Canvas, Voice Huddles, and Rich Evidence Cards.
// Reactively wired to WorkspaceStore (SQLite) and TagRegistry.
// Styled with centralized design system tokens (`Color.speak*`, `Font.speakMono*`).

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
    @State private var registeredTags: [TagMetadata] = []
    @State private var store: WorkspaceStore?
    @State private var isHuddleActive: Bool = false
    @State private var activeReadingMsgId: UUID?

    private let speechSynthesizer = AppleSpeechSynthesizer()

    public init() {}

    public var body: some View {
        HSplitView {
            // Left Sidebar: Channels & Agent Roster
            sidebarView
                .frame(minWidth: 210, maxWidth: 260)

            // Main Canvas: Thread Feed & Input
            canvasView
                .frame(minWidth: 440)
        }
        .task {
            await loadInitialData()
        }
        .onChange(of: selectedChannelId) { newChannelId in
            Task {
                await reloadMessages(for: newChannelId)
            }
        }
    }

    // MARK: - Sidebar

    private var sidebarView: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Channels Header
            VStack(alignment: .leading, spacing: 8) {
                Text("CHANNELS")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.speakMica)

                ForEach(channels) { channel in
                    Button(action: { selectedChannelId = channel.id }) {
                        HStack {
                            Image(systemName: "number")
                                .font(.system(size: 12))
                                .foregroundColor(.speakMica)
                            Text(channel.name)
                                .font(.system(size: 13, weight: selectedChannelId == channel.id ? .semibold : .regular))
                                .foregroundColor(.speakBone)
                            Spacer()
                        }
                        .padding(.vertical, 5)
                        .padding(.horizontal, 10)
                        .background(selectedChannelId == channel.id ? Color.speakSidebarActiveBg : Color.clear)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()
                .overlay(Color.speakCardBorder)

            // Spoken Plugins as Tags
            VStack(alignment: .leading, spacing: 8) {
                Text("PLUGINS (@TAGS)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.speakMica)

                let pluginTags = registeredTags.filter { $0.tagKind == .plugin }
                if pluginTags.isEmpty {
                    pluginRow(tag: "@terminal", icon: "terminal.fill", label: "Terminal Execution")
                    pluginRow(tag: "@github", icon: "arrow.triangle.pull", label: "GitHub Integration")
                } else {
                    ForEach(pluginTags) { tagMeta in
                        pluginRow(tag: tagMeta.tagName, icon: iconForKind(tagMeta.tagKind), label: tagMeta.description)
                    }
                }
            }

            Divider()
                .overlay(Color.speakCardBorder)

            // Agent Roster
            VStack(alignment: .leading, spacing: 8) {
                Text("AGENT ROSTER")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.speakMica)

                let agentTags = registeredTags.filter { $0.tagKind == .agent }
                if agentTags.isEmpty {
                    agentRow(tag: "@Claude", status: "Active (Claude Code)", isOnline: true)
                    agentRow(tag: "@builder-qa", status: "Running Moat Audit", isOnline: true)
                } else {
                    ForEach(agentTags) { tagMeta in
                        agentRow(tag: tagMeta.tagName, status: tagMeta.description, isOnline: true)
                    }
                }
            }

            Spacer()
        }
        .padding(12)
        .background(Color.speakSidebarBg)
    }

    private func iconForKind(_ kind: TagKind) -> String {
        switch kind {
        case .agent: return "person.badge.shield.checkmark.fill"
        case .plugin: return "terminal.fill"
        case .team: return "person.3.fill"
        case .scope: return "globe"
        }
    }

    private func pluginRow(tag: String, icon: String, label: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(.speakMica)
            Text(tag)
                .font(.speakMonoCaption)
                .foregroundColor(.speakTagBadgeFg)
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
    }

    private func agentRow(tag: String, status: String, isOnline: Bool) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isOnline ? Color.speakDelivered : Color.speakMica)
                .frame(width: 6, height: 6)
            Text(tag)
                .font(.speakMonoCaption)
                .foregroundColor(.speakBone)
            Spacer()
            Text(status)
                .font(.system(size: 10))
                .foregroundColor(.speakMica)
                .lineLimit(1)
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
                    .foregroundColor(.speakBone)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.speakInk)

            Divider()
                .overlay(Color.speakCardBorder)

            // Voice Huddle Header Bar
            huddleHeaderBar

            // Message / Thread Scroll
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(messages) { msg in
                        messageRow(msg)
                    }
                }
                .padding(16)
            }
            .background(Color.speakInk)

            Divider()
                .overlay(Color.speakCardBorder)

            // Spoken Turn Input Bar
            HStack(spacing: 10) {
                Button(action: handleVoiceRecord) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.black)
                        .padding(8)
                        .background(isHuddleActive ? Color.speakOnAir : Color.speakHumanAmber)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                TextField("Type or speak a message... (e.g. Tag @Claude check tap guard)", text: $inputText)
                    .textFieldStyle(.plain)
                    .padding(8)
                    .background(Color.speakInk2)
                    .cornerRadius(8)
                    .onSubmit {
                        sendMessage()
                    }

                Button("Send", action: sendMessage)
                    .buttonStyle(.borderedProminent)
                    .tint(.speakAgentViolet)
            }
            .padding(12)
            .background(Color.speakInk)
        }
    }

    // MARK: - Voice Huddle Header Bar

    private var huddleHeaderBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Circle()
                    .fill(isHuddleActive ? Color.speakOnAir : Color.speakHumanAmber)
                    .frame(width: 8, height: 8)

                Text(isHuddleActive ? "LIVE HUDDLE" : "VOICE HUDDLE")
                    .font(.speakMonoCaption)
                    .foregroundColor(isHuddleActive ? .speakOnAir : .speakHumanAmber)
            }

            if isHuddleActive {
                HStack(spacing: 6) {
                    Text("Participants:")
                        .font(.system(size: 11))
                        .foregroundColor(.speakMica)

                    Text("👤 @tamil")
                        .font(.speakMonoCaption)
                        .foregroundColor(.speakHumanAmber)

                    Text("🤖 @Claude")
                        .font(.speakMonoCaption)
                        .foregroundColor(.speakAgentViolet)

                    Text("🤖 @builder-qa")
                        .font(.speakMonoCaption)
                        .foregroundColor(.speakAgentViolet)
                }
            }

            Spacer()

            Button(action: toggleHuddle) {
                HStack(spacing: 6) {
                    Image(systemName: isHuddleActive ? "phone.down.fill" : "waveform.circle.fill")
                    Text(isHuddleActive ? "Leave Huddle" : "Join Huddle")
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(isHuddleActive ? .white : .black)
                .padding(.vertical, 4)
                .padding(.horizontal, 10)
                .background(isHuddleActive ? Color.speakOnAir : Color.speakHumanAmber)
                .cornerRadius(12)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.speakInk2.opacity(0.8))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(.speakCardBorder),
            alignment: .bottom
        )
    }

    private func messageRow(_ msg: WorkspaceMessage) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(msg.senderTag)
                    .font(.speakMonoCaption)
                    .foregroundColor(msg.senderTag.hasPrefix("@") && msg.senderTag != "@tamil" ? .speakAgentViolet : .speakHumanAmber)

                Text(msg.createdAt, style: .time)
                    .font(.system(size: 10))
                    .foregroundColor(.speakMica)

                Spacer()

                // Audio Readback Button for individual message
                Button(action: { readbackMessage(msg) }) {
                    Image(systemName: activeReadingMsgId == msg.id ? "speaker.wave.3.fill" : "speaker.wave.1")
                        .font(.system(size: 11))
                        .foregroundColor(activeReadingMsgId == msg.id ? .speakAgentViolet : .speakMica)
                }
                .buttonStyle(.plain)
            }

            Text(msg.text)
                .font(.speakMonoBody)
                .foregroundColor(.speakBone)

            // Evidence Card if present
            if let evidence = mockEvidences[msg.id] {
                EvidenceCardView(payload: evidence)
                    .padding(.top, 4)
            }
        }
    }

    // MARK: - Actions

    private func toggleHuddle() {
        isHuddleActive.toggle()
        if !isHuddleActive {
            Task {
                await speechSynthesizer.stop()
            }
        }
    }

    private func readbackMessage(_ msg: WorkspaceMessage) {
        let msgId = msg.id
        let text = msg.text
        Task {
            if await speechSynthesizer.isSpeaking {
                await speechSynthesizer.stop()
                activeReadingMsgId = nil
            } else {
                activeReadingMsgId = msgId
                await speechSynthesizer.speak(text, locale: Locale(identifier: "en-US"))
                activeReadingMsgId = nil
            }
        }
    }

    private func loadInitialData() async {
        await TagRegistry.shared.registerDefaults()
        registeredTags = await TagRegistry.shared.allTags()

        do {
            let dbStore = try WorkspaceStore.makeProductionStore()
            self.store = dbStore
            let fetchedChannels = try await dbStore.fetchChannels()
            if !fetchedChannels.isEmpty {
                self.channels = fetchedChannels
            }
            await reloadMessages(for: selectedChannelId)
        } catch {
            // Fallback seed data if database is initialized for the first time
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
    }

    private func reloadMessages(for channelId: String) async {
        guard let dbStore = store else { return }
        do {
            let msgs = try await dbStore.fetchMessages(channelId: channelId)
            if !msgs.isEmpty {
                self.messages = msgs
            }
        } catch {
            // Keep current in-memory messages on error
        }
    }

    private func sendMessage() {
        let textToSend = inputText.trimmingCharacters(in: .whitespaces)
        guard !textToSend.isEmpty else { return }

        let newMsg = WorkspaceMessage(channelId: selectedChannelId, senderTag: "@tamil", text: textToSend)
        messages.append(newMsg)
        inputText = ""

        Task {
            if let dbStore = store {
                try? await dbStore.postMessage(newMsg)
            }

            // Extract tags and execute matching adapter
            let extractedTags = VoiceCommandParser.extractTags(from: textToSend)
            for tagMention in extractedTags {
                if let adapter = await TagRegistry.shared.lookup(tagName: tagMention.tag) {
                    do {
                        let outcome = try await adapter.handleTurn(prompt: textToSend, sessionId: nil)
                        await handleAdapterOutcome(outcome, targetTag: tagMention.tag)
                    } catch {
                        let replyId = UUID()
                        let errReply = WorkspaceMessage(
                            id: replyId,
                            channelId: selectedChannelId,
                            senderTag: tagMention.tag,
                            text: "Execution failed: \(error.localizedDescription)"
                        )
                        messages.append(errReply)
                        if let dbStore = store {
                            try? await dbStore.postMessage(errReply)
                        }
                    }
                }
            }
        }
    }

    private func handleAdapterOutcome(_ outcome: TagTurnOutcome, targetTag: String) async {
        let replyId = UUID()
        switch outcome {
        case .completed(let summary, let evidence):
            let reply = WorkspaceMessage(
                id: replyId,
                channelId: selectedChannelId,
                senderTag: targetTag,
                text: summary
            )
            messages.append(reply)
            if let evidence = evidence {
                mockEvidences[replyId] = evidence
            }
            if let dbStore = store {
                try? await dbStore.postMessage(reply)
            }

            // In Huddle mode: automatically speak agent response aloud!
            if isHuddleActive {
                await speechSynthesizer.speak(summary, locale: Locale(identifier: "en-US"))
            }

        case .inProgress(let summary, let checklist):
            let reply = WorkspaceMessage(
                id: replyId,
                channelId: selectedChannelId,
                senderTag: targetTag,
                text: summary
            )
            messages.append(reply)
            mockEvidences[replyId] = EvidencePayload(summary: summary, checklist: checklist)
            if let dbStore = store {
                try? await dbStore.postMessage(reply)
            }

            if isHuddleActive {
                await speechSynthesizer.speak(summary, locale: Locale(identifier: "en-US"))
            }

        case .needsApproval(let prompt, _):
            let reply = WorkspaceMessage(
                id: replyId,
                channelId: selectedChannelId,
                senderTag: targetTag,
                text: "Approval requested: \(prompt)"
            )
            messages.append(reply)
            if let dbStore = store {
                try? await dbStore.postMessage(reply)
            }

        case .failed(let errorMsg):
            let reply = WorkspaceMessage(
                id: replyId,
                channelId: selectedChannelId,
                senderTag: targetTag,
                text: "Failed: \(errorMsg)"
            )
            messages.append(reply)
            if let dbStore = store {
                try? await dbStore.postMessage(reply)
            }
        }
    }

    private func handleVoiceRecord() {
        // Triggers voice dictation input into the text field
        inputText = "Tag @Claude check tap safety"
    }
}
