// App/Dashboard/Panes/AgentPlaygroundView.swift
//
// The Agent Playground — a document-style streaming interface for local
// inference. Not a chatbot clone: the mental model is "an agent co-authoring
// in my buffer." User instructions are dimmed command lines; model output is
// full-width composed text with deliberate streaming cadence.
//
// Design principles:
// - Document, not chat. Full-width text flow, no bubbles.
// - Provenance visible. Every response carries its wine-label colophon.
// - Engine room. Backend health is always at a glance.
// - Streaming as craft. Cadence-paced delivery, pulsing cursor, ink arrival.

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
    @Published var lastProvenance: ProvenanceReceipt?
    @Published var provenanceLog: [String: ProvenanceReceipt] = [:]
    @Published var backends: [BackendInfo] = []
    @Published var contextTokenEstimate = 0

    // MARK: - Dependencies

    private let client = StreamingChatClient()
    private let server = LocalInferenceServer()
    private let registry = ModelRegistry()
    private var store: (any ConversationStoring)?
    private var streamTask: Task<Void, Never>?
    private let logger = Logger(subsystem: "com.speak.app", category: "Playground")

    /// Approximate context window size for the progress bar.
    private let contextWindowLimit = 4096

    // MARK: - Init

    init(store: (any ConversationStoring)?) {
        self.store = store
    }

    // MARK: - Lifecycle

    func onAppear() {
        Task {
            await ensureServerRunning()
            await fetchAPIKey()
            await loadConversations()
            discoverBackends()
        }
    }

    // MARK: - Context progress

    var contextProgress: Double {
        min(Double(contextTokenEstimate) / Double(contextWindowLimit), 1.0)
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
            let msg = ChatMessage(
                id: UUID().uuidString,
                conversationId: activeConversation?.id ?? "",
                role: "assistant",
                content: partial + " [stopped]",
                createdAt: Date()
            )
            messages.append(msg)
        }
    }

    func newConversation() {
        activeConversation = nil
        messages = []
        streamingText = ""
        errorMessage = nil
        lastProvenance = nil
        provenanceLog = [:]
        contextTokenEstimate = 0
    }

    func loadConversation(_ conversation: Conversation) {
        activeConversation = conversation
        selectedModel = conversation.model
        systemPrompt = conversation.systemPrompt ?? ""
        errorMessage = nil
        lastProvenance = nil

        Task {
            do {
                messages = try await store?.messages(conversationId: conversation.id) ?? []
                recalculateContextEstimate()
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

    func discoverBackends() {
        Task {
            await registry.discover()
            backends = await registry.backends
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
        contextTokenEstimate += text.count / 4

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
        lastProvenance = nil

        let convId = conversation?.id
        let result = client.streamChat(
            messages: wireMessages,
            model: selectedModel,
            port: serverPort,
            apiKey: apiKey
        )

        streamTask = Task { [weak self] in
            guard let self else { return }

            do {
                for try await chunk in result.tokens {
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
                contextTokenEstimate += finalText.count / 4

                if let convId {
                    _ = try? await store?.appendMessage(conversationId: convId, role: "assistant", content: finalText)
                }

                for await receipt in result.provenance {
                    lastProvenance = receipt
                    provenanceLog[assistantMessage.id] = receipt
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

    private func ensureServerRunning() async {
        guard await !server.isRunning else { return }
        do {
            try await server.start()
            logger.info("Playground auto-started inference server")
        } catch {
            errorMessage = "Could not start inference server: \(error.localizedDescription)"
            logger.error("Server auto-start failed: \(error.localizedDescription)")
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

    private func recalculateContextEstimate() {
        var total = systemPrompt.count / 4
        for msg in messages {
            total += msg.content.count / 4
        }
        contextTokenEstimate = total
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
            PaneHeader(title: "Playground", subtitle: "Local inference · streaming · multi-backend")

            EngineRoomStrip(viewModel: viewModel)

            Divider()

            DocumentArea(viewModel: viewModel)
        }
        .onAppear { viewModel.onAppear() }
    }
}

// MARK: - EngineRoomStrip

private struct EngineRoomStrip: View {
    @ObservedObject var viewModel: PlaygroundViewModel

    var body: some View {
        HStack(spacing: SpeakSpacing.md) {
            ForEach(viewModel.backends) { backend in
                EngineNode(backend: backend, isSelected: viewModel.selectedModel == backend.id)
            }

            if viewModel.backends.isEmpty {
                HStack(spacing: SpeakSpacing.sm) {
                    EngineNodePlaceholder(name: "Foundation Models", status: " probing...")
                    EngineNodePlaceholder(name: "Ollama", status: " probing...")
                    EngineNodePlaceholder(name: "MLX", status: " probing...")
                }
            }

            Spacer(minLength: 0)

            Button(action: { viewModel.discoverBackends() }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help("Refresh backends")
        }
        .padding(.horizontal, SpeakSpacing.lg)
        .padding(.vertical, SpeakSpacing.sm)
        .background(Color.speakSurface.opacity(0.3))
    }
}

private struct EngineNode: View {
    let backend: BackendInfo
    let isSelected: Bool

    var body: some View {
        HStack(spacing: SpeakSpacing.xs) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)
                .shadow(color: statusColor.opacity(0.6), radius: isSelected ? 3 : 1)

            Text(backend.name)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(isSelected ? .primary : .secondary)

            Text(backend.status.rawValue)
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(statusColor.opacity(0.8))
        }
        .padding(.horizontal, SpeakSpacing.sm)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(isSelected ? Color.speakAgentViolet.opacity(0.08) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(isSelected ? Color.speakAgentViolet.opacity(0.3) : Color.clear, lineWidth: 0.5)
        )
    }

    private var statusColor: Color {
        switch backend.status {
        case .available, .reachable:
            return Color.speakDelivered
        case .offline:
            return Color(nsColor: .systemRed)
        case .unknown:
            return Color(nsColor: .systemYellow)
        }
    }
}

private struct EngineNodePlaceholder: View {
    let name: String
    let status: String

    var body: some View {
        HStack(spacing: SpeakSpacing.xs) {
            Circle()
                .fill(Color.speakMica.opacity(0.4))
                .frame(width: 6, height: 6)

            Text(name)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)

            Text(status)
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, SpeakSpacing.sm)
        .padding(.vertical, 3)
    }
}

// MARK: - DocumentArea

private struct DocumentArea: View {
    @ObservedObject var viewModel: PlaygroundViewModel

    var body: some View {
        VStack(spacing: 0) {
            DocumentToolbar(viewModel: viewModel)

            Divider()

            DocumentScrollView(viewModel: viewModel)

            Divider()

            CommandBar(viewModel: viewModel)
        }
    }
}

// MARK: - DocumentToolbar

private struct DocumentToolbar: View {
    @ObservedObject var viewModel: PlaygroundViewModel

    var body: some View {
        HStack(spacing: SpeakSpacing.sm) {
            Picker("Model", selection: $viewModel.selectedModel) {
                if viewModel.backends.isEmpty {
                    Text("speak-default").tag("speak-default")
                } else {
                    ForEach(viewModel.backends) { backend in
                        Text(backend.name).tag(backend.id)
                    }
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 180)

            Spacer(minLength: 0)

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color(nsColor: .systemRed))
                    .lineLimit(1)
            }

            Button(action: { viewModel.showSystemPrompt.toggle() }) {
                HStack(spacing: 4) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 10))
                    Text("persona")
                        .font(.system(size: 10, design: .monospaced))
                }
                .padding(.horizontal, SpeakSpacing.sm)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(viewModel.systemPrompt.isEmpty
                            ? Color.speakSurface
                            : Color.speakAgentViolet.opacity(0.12))
                )
                .foregroundStyle(viewModel.systemPrompt.isEmpty ? Color.speakMica : Color.speakAgentViolet)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $viewModel.showSystemPrompt, arrowEdge: .bottom) {
                PersonaEditor(viewModel: viewModel)
            }
        }
        .padding(.horizontal, SpeakSpacing.md)
        .padding(.vertical, SpeakSpacing.xs)
    }
}

// MARK: - PersonaEditor

private struct PersonaEditor: View {
    @ObservedObject var viewModel: PlaygroundViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.sm) {
            Text("System Persona")
                .font(.system(size: 12, weight: .medium, design: .monospaced))

            Text("Prepended to every request. Defines the agent's voice and constraints.")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)

            TextEditor(text: $viewModel.systemPrompt)
                .font(.system(size: 12, design: .monospaced))
                .frame(width: 340, height: 120)
                .scrollContentBackground(.hidden)
                .padding(SpeakSpacing.xs)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.speakSurface)
                )

            HStack {
                Spacer()
                Button("Clear") { viewModel.systemPrompt = "" }
                    .font(.system(size: 10, design: .monospaced))
                Button("Done") { viewModel.showSystemPrompt = false }
                    .font(.system(size: 10, design: .monospaced))
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(SpeakSpacing.md)
    }
}

// MARK: - DocumentScrollView

private struct DocumentScrollView: View {
    @ObservedObject var viewModel: PlaygroundViewModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if viewModel.messages.isEmpty && !viewModel.isStreaming {
                        DocumentEmptyState()
                    }

                    ForEach(viewModel.messages) { message in
                        DocumentSection(
                            message: message,
                            provenance: viewModel.provenanceLog[message.id]
                        )
                        .id(message.id)
                    }

                    if viewModel.isStreaming {
                        StreamingSection(text: viewModel.streamingText)
                            .id("streaming")
                    }
                }
                .padding(.horizontal, SpeakSpacing.lg)
                .padding(.vertical, SpeakSpacing.md)
            }
            .onChange(of: viewModel.messages.count) {
                if let lastId = viewModel.messages.last?.id {
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(lastId, anchor: .bottom)
                    }
                }
            }
            .onChange(of: viewModel.streamingText) {
                withAnimation(.easeOut(duration: 0.08)) {
                    proxy.scrollTo("streaming", anchor: .bottom)
                }
            }
        }
    }
}

// MARK: - DocumentEmptyState

private struct DocumentEmptyState: View {
    var body: some View {
        VStack(spacing: SpeakSpacing.md) {
            Spacer().frame(height: 60)

            Image(systemName: "text.cursor")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)

            Text("The agent writes here.")
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(.secondary)

            Text("Type a command below. Responses stream in real-time from your local inference server.")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - DocumentSection

private struct DocumentSection: View {
    let message: ChatMessage
    let provenance: ProvenanceReceipt?

    private var isUser: Bool { message.role == "user" }

    var body: some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.xs) {
            if isUser {
                HStack(alignment: .top, spacing: SpeakSpacing.sm) {
                    Text(">")
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.speakHumanAmber.opacity(0.7))

                    Text(message.content)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(Color.speakMica)
                        .textSelection(.enabled)
                }
                .padding(.top, SpeakSpacing.md)
            } else {
                VStack(alignment: .leading, spacing: SpeakSpacing.xs) {
                    Text(message.content)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(Color.speakBone)
                        .textSelection(.enabled)
                        .lineSpacing(3)

                    if let receipt = provenance {
                        ProvenanceColophon(receipt: receipt)
                    }
                }
                .padding(.top, SpeakSpacing.sm)
                .padding(.bottom, SpeakSpacing.xs)
            }
        }
    }
}

// MARK: - ProvenanceColophon

private struct ProvenanceColophon: View {
    let receipt: ProvenanceReceipt

    var body: some View {
        HStack(spacing: SpeakSpacing.sm) {
            Text(receipt.backendID)
                .foregroundStyle(Color.speakAgentViolet.opacity(0.7))

            Text("·")
                .foregroundStyle(.tertiary)

            Text("\(receipt.latencyMS)ms")
                .foregroundStyle(.tertiary)

            Text("·")
                .foregroundStyle(.tertiary)

            Text("\(receipt.promptTokens + receipt.completionTokens) tok")
                .foregroundStyle(.tertiary)

            if receipt.fellBack {
                Text("·")
                    .foregroundStyle(.tertiary)
                Text("fallback")
                    .foregroundStyle(Color(nsColor: .systemYellow).opacity(0.8))
            }
        }
        .font(.system(size: 9, design: .monospaced))
        .padding(.top, 2)
    }
}

// MARK: - StreamingSection

private struct StreamingSection: View {
    let text: String
    @State private var cursorOpacity: Double = 1.0

    var body: some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.xs) {
            HStack(alignment: .bottom, spacing: 0) {
                Text(text.isEmpty ? " " : text)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(Color.speakBone)
                    .lineSpacing(3)

                Rectangle()
                    .fill(Color.speakAgentViolet)
                    .frame(width: 2, height: 15)
                    .opacity(cursorOpacity)
                    .padding(.leading, 1)
            }
        }
        .padding(.top, SpeakSpacing.sm)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                cursorOpacity = 0.0
            }
        }
    }
}

// MARK: - CommandBar

private struct CommandBar: View {
    @ObservedObject var viewModel: PlaygroundViewModel
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ContextProgressBar(progress: viewModel.contextProgress)

            HStack(alignment: .bottom, spacing: SpeakSpacing.sm) {
                Text(">")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.speakHumanAmber.opacity(0.6))
                    .padding(.bottom, 8)

                TextField("instruct the agent...", text: $viewModel.inputText, axis: .vertical)
                    .font(.system(size: 13, design: .monospaced))
                    .textFieldStyle(.plain)
                    .lineLimit(1...6)
                    .focused($isFocused)
                    .onSubmit {
                        if !NSEvent.modifierFlags.contains(.shift) {
                            viewModel.sendMessage()
                        }
                    }

                if viewModel.isStreaming {
                    Button(action: { viewModel.cancelStream() }) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Color(nsColor: .systemRed))
                            .frame(width: 28, height: 28)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Color(nsColor: .systemRed).opacity(0.08))
                            )
                    }
                    .buttonStyle(.plain)
                    .help("Stop generation")
                } else {
                    Button(action: { viewModel.sendMessage() }) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(
                                viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    ? Color.speakMica.opacity(0.4)
                                    : Color.speakAgentViolet
                            )
                            .frame(width: 28, height: 28)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Color.speakAgentViolet.opacity(
                                        viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.04 : 0.12
                                    ))
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .help("Send (Enter)")
                }
            }
            .padding(.horizontal, SpeakSpacing.md)
            .padding(.vertical, SpeakSpacing.sm)
        }
        .onAppear { isFocused = true }
    }
}

// MARK: - ContextProgressBar

private struct ContextProgressBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.speakSurface)
                    .frame(height: 2)

                Rectangle()
                    .fill(barColor)
                    .frame(width: geo.size.width * progress, height: 2)
            }
        }
        .frame(height: 2)
    }

    private var barColor: Color {
        if progress > 0.85 {
            return Color(nsColor: .systemRed).opacity(0.7)
        } else if progress > 0.6 {
            return Color(nsColor: .systemYellow).opacity(0.7)
        }
        return Color.speakAgentViolet.opacity(0.5)
    }
}
