// App/Dashboard/Panes/AgentInboxPaneView.swift
//
// AVB-7 (specs/avb7-durable-calls-design.md): the Agent Inbox pane — lists
// non-terminal `AgentCall`s (prompt, urgency, elapsed time, mode). Per row:
// Answer by voice (routes through the SAME capture path `speak_request_input`
// uses), Decline, Dismiss.
//
// [decision: AVB-7 cut line] Minimal, plain styling — `Speak/App/DesignSystem/`
// does not exist on master yet (FE-3 is building the token system in a
// worktree). This pane intentionally does NOT create or depend on those
// tokens; FE-3 restyles it once merged. Poll-on-appear + a coarse timer is
// the whole refresh story this slice needs (no push-style live updates,
// per the design doc's deferral list).

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
            PaneHeader(title: "Agent Inbox", subtitle: "Questions submitted by AI agents, waiting for you.")

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
            // Coarse timer — no push-style live updates in this slice.
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
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(call.prompt)
                    .font(.body)
                    .lineLimit(2)
                Spacer()
                urgencyBadge
            }
            HStack(spacing: 8) {
                Text(call.mode.rawValue.capitalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("·")
                    .foregroundStyle(.secondary)
                Text(call.createdAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Button("Answer by voice") {
                    Task { await onAnswerByVoice() }
                }
                .disabled(isBusy)
                Button("Decline") {
                    Task { await onDecline() }
                }
                .disabled(isBusy)
                Button("Dismiss") {
                    Task { await onDismiss() }
                }
                .disabled(isBusy)
                if isBusy {
                    ProgressView().controlSize(.small)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var urgencyBadge: some View {
        Text(call.urgency.rawValue.capitalized)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.secondary.opacity(0.15))
            .clipShape(Capsule())
    }
}
