// App/Dashboard/Panes/AgentInboxPaneView.swift
//
// AVB-7 (specs/avb7-durable-calls-design.md): the Agent Inbox pane — lists
// non-terminal `AgentCall`s (prompt, urgency, elapsed time, mode). Per row:
// Answer by voice (routes through the SAME capture path `speak_request_input`
// uses), Decline, Dismiss.
// Styled with centralized design system tokens (`Color.speak*`, `Font.speakMono*`).

import SpeakCore
import SwiftUI

// MARK: - AgentInboxPaneView

struct AgentInboxPaneView: View {
    let context: DashboardContext

    @State private var calls: [AgentCall] = []
    @State private var busyCallId: UUID?
    @State private var errorMessage: String?
    @State private var refreshTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaneHeader(title: "Agent Inbox", subtitle: "Questions submitted by AI agents, waiting for your approval.")

            if let errorMessage {
                Text(errorMessage)
                    .font(.speakMonoCaption)
                    .foregroundColor(.speakOnAir)
                    .padding(.horizontal)
            }

            if calls.isEmpty {
                PanePlaceholder(
                    systemImage: "tray",
                    message: "No pending agent questions."
                )
            } else {
                List(calls) { call in
                    AgentCallRow(
                        call: call,
                        isBusy: busyCallId == call.id,
                        onAnswerByVoice: { await answerByVoice(call) },
                        onDecline: { await decline(call) },
                        onDismiss: { await dismiss(call) }
                    )
                }
                .listStyle(.plain)
            }
        }
        .task { await refresh() }
        .onAppear { startPolling() }
        .onDisappear {
            refreshTask?.cancel()
            refreshTask = nil
        }
    }

    // MARK: - Actions

    private func refresh() async {
        guard let store = context.agentCallStore else { return }
        do {
            calls = try await store.pendingAndPresented()
            errorMessage = nil
        } catch {
            errorMessage = "Could not load the inbox: \(error.localizedDescription)"
        }
    }

    private func startPolling() {
        refreshTask?.cancel()
        refreshTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard !Task.isCancelled else { break }
                await refresh()
            }
        }
    }

    private func answerByVoice(_ call: AgentCall) async {
        guard let action = context.answerAgentCallByVoice else { return }
        busyCallId = call.id
        _ = await action(call)
        busyCallId = nil
        await refresh()
    }

    private func decline(_ call: AgentCall) async {
        await context.declineAgentCall?(call.id)
        await refresh()
    }

    private func dismiss(_ call: AgentCall) async {
        await context.dismissAgentCall?(call.id)
        await refresh()
    }
}

// MARK: - AgentCallRow

private struct AgentCallRow: View {
    let call: AgentCall
    let isBusy: Bool
    let onAnswerByVoice: () async -> Void
    let onDecline: () async -> Void
    let onDismiss: () async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(call.prompt)
                    .font(.speakMonoBody)
                    .foregroundColor(.speakBone)
                    .lineLimit(2)
                Spacer()
                urgencyBadge
            }

            HStack(spacing: 8) {
                Text(call.mode.rawValue.capitalized)
                    .font(.speakMonoCaption)
                    .foregroundColor(.speakAgentViolet)

                Text("·")
                    .foregroundColor(.speakMica)

                Text(call.createdAt, style: .relative)
                    .font(.speakMonoCaption)
                    .foregroundColor(.speakMica)
            }

            HStack(spacing: 10) {
                Button(action: { Task { await onAnswerByVoice() } }) {
                    Label("Answer by voice", systemImage: "mic.fill")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(.speakHumanAmber)
                .disabled(isBusy)

                Button("Decline") {
                    Task { await onDecline() }
                }
                .buttonStyle(.bordered)
                .tint(.speakOnAir)
                .disabled(isBusy)

                Button("Dismiss") {
                    Task { await onDismiss() }
                }
                .buttonStyle(.plain)
                .foregroundColor(.speakMica)
                .disabled(isBusy)

                if isBusy {
                    ProgressView().controlSize(.small)
                }
            }
        }
        .padding(10)
        .background(Color.speakInk2)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.speakCardBorder, lineWidth: 1)
        )
        .padding(.vertical, 4)
    }

    private var urgencyBadge: some View {
        Text(call.urgency.rawValue.capitalized)
            .font(.speakMonoCaption)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(call.urgency == .high ? Color.speakOnAir.opacity(0.2) : Color.speakAgentViolet.opacity(0.15))
            .foregroundColor(call.urgency == .high ? .speakOnAir : .speakAgentViolet)
            .clipShape(Capsule())
    }
}
