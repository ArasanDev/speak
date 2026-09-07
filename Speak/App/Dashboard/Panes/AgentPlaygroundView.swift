// App/Dashboard/Panes/AgentPlaygroundView.swift
//
// The Agent Playground — a document-style streaming interface for local
// inference. Not a chatbot clone: the mental model is "an agent co-authoring
// in my buffer." User instructions are dimmed command lines; model output is
// full-width composed text with deliberate streaming cadence.
//
// Design principles:
// - Document, not chat. One reading measure, full-width text flow, no bubbles.
// - Provenance visible. Every response carries its wine-label colophon.
// - Engine room. Backend health is always at a glance — and is the model picker.
// - Streaming as craft. Cadence-paced delivery that converges, never pops.
//
// This file owns the view model and the pane's spine. The surfaces live in
// `AgentPlaygroundSurfaces.swift` (masthead, engine room, document, turns,
// colophon, empty state) and `AgentPlaygroundComposer.swift` (composer, footer,
// context meter, persona editor). See the header of AgentPlaygroundSurfaces for
// the full design thesis.

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

/// The pane's spine: masthead, buffer, composer. Three bands on one measure.
struct AgentPlaygroundView: View {
    let context: DashboardContext
    @StateObject private var viewModel: PlaygroundViewModel

    init(context: DashboardContext) {
        self.context = context
        _viewModel = StateObject(wrappedValue: PlaygroundViewModel(store: context.conversationStore))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PlaygroundMasthead(viewModel: viewModel)

            PlaygroundDocument(viewModel: viewModel)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            PlaygroundComposer(viewModel: viewModel)
        }
        .background(Color.speakWindowCanvas)
        .onAppear { viewModel.onAppear() }
    }
}
