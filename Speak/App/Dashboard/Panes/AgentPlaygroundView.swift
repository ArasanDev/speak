// App/Dashboard/Panes/AgentPlaygroundView.swift
//
// The Agent Playground — a multi-turn streaming chat interface for the local
// inference server. Users pick a model, set a system prompt, and converse with
// local LLMs via SSE streaming. Conversations persist to SQLite.
//
// This is the product surface for speak's "local human interface for software
// agents" vision (product.md §6c). Phase 1: conversational chat. Phase 2:
// tool calls and voice integration.

import Foundation
import os
import SpeakCore
import SpeakLLM
import SwiftUI

// MARK: - PlaygroundViewModel

@MainActor
final class PlaygroundViewModel: ObservableObject {

    // MARK: - Published state

    @Published var messages: [ChatMessage] = []
    @Published var streamingText = ""
    @Published var isStreaming = false
    @Published var inputText = ""
    @Published var selectedModel = "speak-default"
    @Published var systemPrompt = ""
    @Published var conversations: [Conversation] = []
    @Published var activeConversation: Conversation?
    @Published var showSystemPrompt = false
    @Published var errorMessage: String?
    @Published var serverPort: UInt16 = LocalInferenceServer.defaultPort
    @Published var apiKey = ""

    // MARK: - Dependencies

    private let client = StreamingChatClient()
    private let server = LocalInferenceServer()
    private var store: (any ConversationStoring)?
    private var streamTask: Task<Void, Never>?
    private let logger = Logger(subsystem: "com.speak.app", category: "Playground")

    // MARK: - Init

    init(store: (any ConversationStoring)?) {
        self.store = store
    }

    // MARK: - Lifecycle

    func onAppear() {
        Task {
            await fetchAPIKey()
            await loadConversations()
        }
    }

    // MARK: - Actions

    func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isStreaming else { return }

        inputText = ""
        errorMessage = nil

        Task {
            await performSend(text: text)
        }
    }

    func cancelStream() {
        streamTask?.cancel()
        streamTask = nil
        isStreaming = false

        if !streamingText.isEmpty {
            let partial = streamingText
            streamingText = ""
            messages.append(ChatMessage(
                id: UUID().uuidString,
                conversationId: activeConversation?.id ?? "",
                role: "assistant",
                content: partial + " [cancelled]",
                createdAt: Date()
            ))
        }
    }

    func newConversation() {
        activeConversation = nil
        messages = []
        streamingText = ""
        errorMessage = nil
    }

    func loadConversation(_ conversation: Conversation) {
        activeConversation = conversation
        selectedModel = conversation.model
        systemPrompt = conversation.systemPrompt ?? ""
        errorMessage = nil

        Task {
            do {
                messages = try await store?.messages(conversationId: conversation.id) ?? []
            } catch {
                logger.error("Failed to load messages: \(error.localizedDescription)")
                errorMessage = "Failed to load conversation"
            }
        }
    }

    func deleteConversation(_ conversation: Conversation) {
        Task {
            try? await store?.deleteConversation(id: conversation.id)
            if activeConversation?.id == conversation.id {
                newConversation()
            }
            await loadConversations()
        }
    }

    // MARK: - Private

    private func performSend(text: String) async {
        var conversation = activeConversation

        if conversation == nil {
            let title = String(text.prefix(50)) + (text.count > 50 ? "..." : "")
            do {
                conversation = try await store?.createConversation(
                    title: title,
                    model: selectedModel,
                    systemPrompt: systemPrompt.isEmpty ? nil : systemPrompt
                )
                activeConversation = conversation
                await loadConversations()
            } catch {
                logger.error("Failed to create conversation: \(error.localizedDescription)")
            }
        }

        let userMessage = ChatMessage(
            id: UUID().uuidString,
            conversationId: conversation?.id ?? "",
            role: "user",
            content: text,
            createdAt: Date()
        )
        messages.append(userMessage)

        if let convId = conversation?.id {
            _ = try? await store?.appendMessage(conversationId: convId, role: "user", content: text)
        }

        var wireMessages: [ChatWireMessage] = []
        if !systemPrompt.isEmpty {
            wireMessages.append(ChatWireMessage(role: "system", content: systemPrompt))
        }
        for msg in messages {
            wireMessages.append(ChatWireMessage(role: msg.role, content: msg.content))
        }

        isStreaming = true
        streamingText = ""

        let convId = conversation?.id
        streamTask = Task { [weak self] in
            guard let self else { return }

            do {
                let stream = client.streamChat(
                    messages: wireMessages,
                    model: selectedModel,
                    port: serverPort,
                    apiKey: apiKey
                )

                for try await chunk in stream {
                    if Task.isCancelled { return }
                    streamingText += chunk
                }

                let finalText = streamingText
                streamingText = ""
                isStreaming = false

                let assistantMessage = ChatMessage(
                    id: UUID().uuidString,
                    conversationId: convId ?? "",
                    role: "assistant",
                    content: finalText,
                    createdAt: Date()
                )
                messages.append(assistantMessage)

                if let convId {
                    _ = try? await store?.appendMessage(conversationId: convId, role: "assistant", content: finalText)
                }
            } catch {
                streamingText = ""
                isStreaming = false
                if !Task.isCancelled {
                    errorMessage = error.localizedDescription
                    logger.error("Stream failed: \(error.localizedDescription)")
                }
            }
        }
    }

    private func fetchAPIKey() async {
        apiKey = await server.getAPIKey()
    }

    private func loadConversations() async {
        do {
            conversations = try await store?.listConversations(limit: 50) ?? []
        } catch {
            logger.error("Failed to load conversations: \(error.localizedDescription)")
        }
    }
}

// MARK: - AgentPlaygroundView

struct AgentPlaygroundView: View {
    let context: DashboardContext
    @StateObject private var viewModel: PlaygroundViewModel

    init(context: DashboardContext) {
        self.context = context
        _viewModel = StateObject(wrappedValue: PlaygroundViewModel(store: context.conversationStore))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaneHeader(title: "Playground", subtitle: "Chat with local models via the inference server")

            HStack(spacing: 0) {
                ConversationSidebar(viewModel: viewModel)
                    .frame(width: 220)

                Divider()

                ChatArea(viewModel: viewModel)
            }
        }
        .onAppear { viewModel.onAppear() }
    }
}

// MARK: - ConversationSidebar

private struct ConversationSidebar: View {
    @ObservedObject var viewModel: PlaygroundViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Conversations")
                    .font(.speakMonoCaption)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                Button(action: { viewModel.newConversation() }) {
                    Image(systemName: "plus.message")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.speakAgentViolet)
                }
                .buttonStyle(.plain)
                .help("New conversation")
            }
            .padding(SpeakSpacing.sm)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(viewModel.conversations) { conversation in
                        ConversationRow(
                            conversation: conversation,
                            isActive: viewModel.activeConversation?.id == conversation.id,
                            onSelect: { viewModel.loadConversation(conversation) },
                            onDelete: { viewModel.deleteConversation(conversation) }
                        )
                    }
                }
                .padding(SpeakSpacing.xs)
            }
        }
        .background(Color.speakSurface.opacity(0.5))
    }
}

// MARK: - ConversationRow

private struct ConversationRow: View {
    let conversation: Conversation
    let isActive: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: SpeakSpacing.xs) {
            Button(action: onSelect) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(conversation.title)
                        .font(.speakMonoCaption)
                        .lineLimit(1)
                        .foregroundStyle(isActive ? Color.speakAgentViolet : .primary)

                    Text(conversation.model)
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, SpeakSpacing.sm)
                .padding(.vertical, SpeakSpacing.xs)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isActive ? Color.speakAgentViolet.opacity(0.12) : Color.clear)
                )
            }
            .buttonStyle(.plain)

            if isHovering {
                Button(action: onDelete) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .onHover { isHovering = $0 }
    }
}

// MARK: - ChatArea

private struct ChatArea: View {
    @ObservedObject var viewModel: PlaygroundViewModel

    var body: some View {
        VStack(spacing: 0) {
            ChatToolbar(viewModel: viewModel)

            Divider()

            ChatScrollView(viewModel: viewModel)

            Divider()

            InputBar(viewModel: viewModel)
        }
        .flowBorder(
            colors: Color.speakFlowAgent,
            cornerRadius: 0,
            isActive: viewModel.isStreaming
        )
    }
}

// MARK: - ChatToolbar

private struct ChatToolbar: View {
    @ObservedObject var viewModel: PlaygroundViewModel

    var body: some View {
        HStack(spacing: SpeakSpacing.sm) {
            Picker("Model", selection: $viewModel.selectedModel) {
                Text("speak-default").tag("speak-default")
                Text("apple-intelligence").tag("apple-intelligence")
                Text("ollama/qwen3").tag("ollama/qwen3")
                Text("ollama/gemma3").tag("ollama/gemma3")
                Text("mlx/llama-3.2").tag("mlx/llama-3.2")
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 200)

            Spacer(minLength: 0)

            Button(action: { viewModel.showSystemPrompt.toggle() }) {
                HStack(spacing: SpeakSpacing.xs) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 11))
                    Text("System Prompt")
                        .font(.speakMonoCaption)
                }
                .padding(.horizontal, SpeakSpacing.sm)
                .padding(.vertical, SpeakSpacing.xs)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(viewModel.systemPrompt.isEmpty ? Color.speakSurface : Color.speakAgentViolet.opacity(0.15))
                )
                .foregroundStyle(viewModel.systemPrompt.isEmpty ? .secondary : Color.speakAgentViolet)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $viewModel.showSystemPrompt, arrowEdge: .bottom) {
                SystemPromptEditor(viewModel: viewModel)
            }

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.speakMonoCaption)
                    .foregroundStyle(Color(nsColor: .systemRed))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, SpeakSpacing.md)
        .padding(.vertical, SpeakSpacing.sm)
    }
}

// MARK: - SystemPromptEditor

private struct SystemPromptEditor: View {
    @ObservedObject var viewModel: PlaygroundViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.sm) {
            Text("System Prompt")
                .font(.speakMonoBody)

            Text("Sets the agent's persona and behavior for this conversation.")
                .font(.speakMonoCaption)
                .foregroundStyle(.secondary)

            TextEditor(text: $viewModel.systemPrompt)
                .font(.speakMonoBody)
                .frame(width: 360, height: 140)
                .scrollContentBackground(.hidden)
                .padding(SpeakSpacing.xs)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.speakSurface)
                )

            HStack {
                Spacer()
                Button("Clear") { viewModel.systemPrompt = "" }
                    .font(.speakMonoCaption)
                Button("Done") { viewModel.showSystemPrompt = false }
                    .font(.speakMonoCaption)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(SpeakSpacing.md)
    }
}

// MARK: - ChatScrollView

private struct ChatScrollView: View {
    @ObservedObject var viewModel: PlaygroundViewModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: SpeakSpacing.md) {
                    if viewModel.messages.isEmpty && !viewModel.isStreaming {
                        EmptyChatState()
                    }

                    ForEach(viewModel.messages) { message in
                        ChatBubble(message: message)
                            .id(message.id)
                    }

                    if viewModel.isStreaming {
                        StreamingBubble(text: viewModel.streamingText)
                            .id("streaming")
                    }
                }
                .padding(SpeakSpacing.lg)
            }
            .onChange(of: viewModel.messages.count) {
                if let lastId = viewModel.messages.last?.id {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(lastId, anchor: .bottom)
                    }
                }
            }
            .onChange(of: viewModel.streamingText) {
                withAnimation(.easeOut(duration: 0.1)) {
                    proxy.scrollTo("streaming", anchor: .bottom)
                }
            }
        }
    }
}

// MARK: - EmptyChatState

private struct EmptyChatState: View {
    var body: some View {
        VStack(spacing: SpeakSpacing.md) {
            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.system(size: 34))
                .foregroundStyle(.tertiary)

            Text("Start a conversation")
                .font(.speakMonoBody)
                .foregroundStyle(.secondary)

            Text("Messages stream in real-time from your local inference server.")
                .font(.speakMonoCaption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, SpeakSpacing.xl)
    }
}

// MARK: - ChatBubble

private struct ChatBubble: View {
    let message: ChatMessage

    private var isUser: Bool { message.role == "user" }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 60) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: SpeakSpacing.xs) {
                Text(message.role == "user" ? "You" : "Assistant")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(isUser ? Color.speakHumanAmber : Color.speakAgentViolet)

                Text(message.content)
                    .font(.speakMonoBody)
                    .textSelection(.enabled)
                    .padding(SpeakSpacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(isUser
                                ? Color.speakHumanAmber.opacity(0.08)
                                : Color.speakAgentViolet.opacity(0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(
                                isUser
                                    ? Color.speakHumanAmber.opacity(0.2)
                                    : Color.speakAgentViolet.opacity(0.15),
                                lineWidth: 0.5
                            )
                    )
            }

            if !isUser { Spacer(minLength: 60) }
        }
    }
}

// MARK: - StreamingBubble

private struct StreamingBubble: View {
    let text: String
    @State private var cursorVisible = true

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: SpeakSpacing.xs) {
                Text("Assistant")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Color.speakAgentViolet)

                HStack(alignment: .bottom, spacing: 1) {
                    Text(text.isEmpty ? " " : text)
                        .font(.speakMonoBody)

                    Text("\u{258F}")
                        .font(.speakMonoBody)
                        .foregroundStyle(Color.speakAgentViolet)
                        .opacity(cursorVisible ? 1 : 0)
                }
                .padding(SpeakSpacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.speakAgentViolet.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.speakAgentViolet.opacity(0.25), lineWidth: 0.5)
                )
            }

            Spacer(minLength: 60)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                cursorVisible = false
            }
        }
    }
}

// MARK: - InputBar

private struct InputBar: View {
    @ObservedObject var viewModel: PlaygroundViewModel
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: SpeakSpacing.sm) {
            TextField("Message the agent...", text: $viewModel.inputText, axis: .vertical)
                .font(.speakMonoBody)
                .textFieldStyle(.plain)
                .lineLimit(1...6)
                .padding(SpeakSpacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.speakSurface)
                )
                .focused($isFocused)
                .onSubmit {
                    if !NSEvent.modifierFlags.contains(.shift) {
                        viewModel.sendMessage()
                    }
                }

            if viewModel.isStreaming {
                Button(action: { viewModel.cancelStream() }) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Color(nsColor: .systemRed))
                        .frame(width: 32, height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color(nsColor: .systemRed).opacity(0.1))
                        )
                }
                .buttonStyle(.plain)
                .help("Stop generation")
            } else {
                Button(action: { viewModel.sendMessage() }) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(
                            viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? Color.speakMica
                                : Color.speakAgentViolet
                        )
                }
                .buttonStyle(.plain)
                .disabled(viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .help("Send message")
            }
        }
        .padding(SpeakSpacing.md)
        .onAppear { isFocused = true }
    }
}
