// App/Dashboard/Panes/AgentInboxPaneView.swift
//
// AVB-7 (specs/avb7-durable-calls-design.md): the Agent Inbox pane — lists
// non-terminal `AgentCall`s (prompt, urgency, elapsed time, mode, expiry).
// Per card: Answer by voice (routes through the SAME capture path
// `speak_request_input` uses), Decline, Dismiss.
//
// SEMANTICS (the pane's reason to exist):
//   - agentViolet — the agent channel: a call "waiting on you", mode tags.
//   - humanAmber — the human channel: the mic is the answer path, so the
//     primary action ("Answer by voice") is amber, not violet.
//   - warning — urgency hints and calls nearing `expiresAt`.
//   - delivered — reserved: this pane shows only non-terminal calls, so nothing
//     here earns the terminal-success color.
//
// Chrome is SF Pro; data (timestamps, session IDs, choices) is SF Mono.
// Cards use the shared `speakCard` surface; wells use `speakInset`.

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
            if let errorMessage {
                AgentInboxErrorStrip(
                    message: errorMessage,
                    onRetry: { Task { await refresh() } },
                    onDismiss: { self.errorMessage = nil }
                )
                .padding(.top, SpeakSpacing.sm)
                .padding(.horizontal, SpeakSpacing.lg)
            }

            if calls.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: SpeakSpacing.sm) {
                        headerRow

                        ForEach(calls) { call in
                            AgentCallCard(
                                call: call,
                                isBusy: busyCallId == call.id,
                                canAnswer: context.answerAgentCallByVoice != nil,
                                onAnswerByVoice: { await answerByVoice(call) },
                                onDecline: { await decline(call) },
                                onDismiss: { await dismiss(call) }
                            )
                        }
                    }
                    .padding(.horizontal, SpeakSpacing.lg)
                    .padding(.top, SpeakSpacing.sm)
                    .padding(.bottom, SpeakSpacing.lg)
                }
            }
        }
        .task { await refresh() }
        .onAppear { startPolling() }
        .onDisappear {
            refreshTask?.cancel()
            refreshTask = nil
        }
    }

    // MARK: - Header & empty state

    /// A one-line ledger over the list — how many calls are waiting and that
    /// the pane self-refreshes. Chrome, not a section header: the desk header
    /// already owns the pane title.
    private var headerRow: some View {
        HStack(spacing: SpeakSpacing.xs) {
            Text(calls.count == 1 ? "1 call waiting" : "\(calls.count) calls waiting")
                .font(.speakBody(.caption))
                .foregroundStyle(Color.speakAgentViolet)
            Text("· refreshes automatically")
                .font(.speakBody(.caption))
                .foregroundStyle(Color.speakMica)
            Spacer(minLength: 0)
            Button {
                Task { await refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.speakMica)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Refresh now")
        }
    }

    /// The empty inbox is the pane's *resting* state — calls arrive only when
    /// an agent asks, so the empty state explains where they come from rather
    /// than apologizing. A missing store (previews, unwired contexts) gets its
    /// own honest message instead of pretending the inbox is just empty.
    private var emptyState: some View {
        VStack(spacing: SpeakSpacing.sm) {
            Image(systemName: context.agentCallStore == nil ? "exclamationmark.triangle" : "tray")
                .font(.system(size: 30))
                .foregroundStyle(context.agentCallStore == nil ? Color.speakWarning : Color.speakMica.opacity(0.7))
            Text(context.agentCallStore == nil ? "Inbox unavailable" : "No pending agent calls")
                .font(.speakBody(.base, semibold: true))
                .foregroundStyle(Color.speakBone)
            Text(context.agentCallStore == nil
                 ? "The durable call store is not wired into this context."
                 : "Durable calls an agent submits via speak_submit_call\nwait here for your spoken answer.")
                .font(.speakBody(.caption))
                .foregroundStyle(Color.speakMica)
                .multilineTextAlignment(.center)
            if context.agentCallStore != nil {
                Button {
                    Task { await refresh() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .font(.speakBody(.caption, semibold: true))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.speakAgentViolet)
                .padding(.top, SpeakSpacing.xs)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(SpeakSpacing.xl)
    }

    // MARK: - Actions

    private func refresh() async {
        guard let store = context.agentCallStore else { return }
        do {
            // A refresh doubles as an expiry sweep so calls that outlived
            // their `expiresAt` while the pane sat open disappear on schedule.
            try await store.expireOverdue(now: Date())
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
        busyCallId = call.id
        await context.declineAgentCall?(call.id)
        busyCallId = nil
        await refresh()
    }

    private func dismiss(_ call: AgentCall) async {
        busyCallId = call.id
        await context.dismissAgentCall?(call.id)
        busyCallId = nil
        await refresh()
    }
}

// MARK: - AgentCallCard

/// One durable call. The header is the agent's envelope (mode, urgency,
/// timing, expiry); the prompt is the body; the actions are the human's
/// answer paths.
private struct AgentCallCard: View {
    let call: AgentCall
    let isBusy: Bool
    let canAnswer: Bool
    let onAnswerByVoice: () async -> Void
    let onDecline: () async -> Void
    let onDismiss: () async -> Void

    /// An `expiresAt` inside this window reads as "expiring soon" and earns
    /// the warning tint. [decision: 30 min — long enough to be actionable.]
    private static let expiringSoonWindow: TimeInterval = 30 * 60

    var body: some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.sm) {
            envelopeRow
            promptBlock
            choicesBlock
            consequenceBlock
            actionRow
        }
        .padding(SpeakSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .speakCard()
    }

    // MARK: - Envelope

    /// Mode · urgency · age · expiry — the metadata an agent attached, read at
    /// a glance before the prompt itself.
    private var envelopeRow: some View {
        HStack(spacing: SpeakSpacing.xs) {
            InboxPill(
                title: call.state == .presented ? "Waiting on you" : "Queued",
                tint: call.state == .presented ? .speakAgentViolet : .speakMica
            )

            Text(call.mode.rawValue.capitalized)
                .font(.speakBody(.caption, semibold: true))
                .foregroundStyle(Color.speakAgentViolet)

            switch call.urgency {
            case .high:
                InboxPill(title: "High priority", tint: .speakWarning)
            case .low:
                InboxPill(title: "Low", tint: .speakMica)
            case .normal:
                EmptyView()
            }

            Spacer(minLength: SpeakSpacing.sm)

            Text(call.createdAt, style: .relative)
                .font(.speakMonoFace(.caption))
                .foregroundStyle(Color.speakMica)
                .help("Submitted \(call.createdAt.formatted(date: .abbreviated, time: .shortened))")
        }
    }

    // MARK: - Body

    private var promptBlock: some View {
        Text(call.prompt)
            .font(.speakBody(.body))
            .foregroundStyle(Color.speakBone)
            .lineSpacing(3)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var choicesBlock: some View {
        if call.mode == .choice && !call.choices.isEmpty {
            VStack(alignment: .leading, spacing: SpeakSpacing.xs) {
                Text("Speak one of:")
                    .font(.speakBody(.caption))
                    .foregroundStyle(Color.speakMica)
                HStack(spacing: SpeakSpacing.xs) {
                    ForEach(call.choices, id: \.self) { choice in
                        Text(choice)
                            .font(.speakMonoFace(.caption))
                            .foregroundStyle(Color.speakBone)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(
                                Capsule().fill(Color.speakAgentViolet.opacity(0.12))
                            )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var consequenceBlock: some View {
        if let consequence = call.consequence, !consequence.isEmpty {
            HStack(alignment: .top, spacing: SpeakSpacing.xs) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 10))
                Text(consequence)
                    .font(.speakBody(.caption))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(Color.speakWarning)
        }
    }

    // MARK: - Actions

    private var actionRow: some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.sm) {
            HStack(spacing: SpeakSpacing.sm) {
                Button {
                    Task { await onAnswerByVoice() }
                } label: {
                    Label("Answer by voice", systemImage: "mic.fill")
                        .font(.speakBody(.caption, semibold: true))
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.speakHumanAmber)
                .disabled(isBusy || !canAnswer)
                .help(canAnswer
                      ? "Dictate the answer — same capture path as speak_request_input"
                      : "Voice answering is unavailable in this context")

                Button("Decline") {
                    Task { await onDecline() }
                }
                .buttonStyle(.bordered)
                .disabled(isBusy)

                Button("Dismiss") {
                    Task { await onDismiss() }
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.speakMica)
                .disabled(isBusy)

                if isBusy {
                    ProgressView().controlSize(.small)
                }

                Spacer(minLength: 0)
            }

            expiryLine
        }
    }

    @ViewBuilder
    private var expiryLine: some View {
        if let expiresAt = call.expiresAt {
            let expiringSoon = expiresAt.timeIntervalSinceNow < Self.expiringSoonWindow
            HStack(spacing: 4) {
                Image(systemName: "clock")
                    .font(.system(size: 9))
                Text("Expires \(expiresAt, style: .relative)")
                    .font(.speakMonoFace(.caption))
                if let sessionId = call.sessionId {
                    Text("·")
                    Text("session \(sessionId.prefix(8))")
                        .font(.speakMonoFace(.caption))
                        .lineLimit(1)
                }
            }
            .foregroundStyle(expiringSoon ? Color.speakWarning : Color.speakMica)
            .help("The call resolves to .expired past this point if unanswered.")
        } else if let sessionId = call.sessionId {
            Text("session \(sessionId.prefix(8))")
                .font(.speakMonoFace(.caption))
                .foregroundStyle(Color.speakMica)
                .lineLimit(1)
        }
    }
}

// MARK: - InboxPill

/// The pane's one status pill — caption-semibold on a tint capsule.
/// `agentViolet` marks agent-active; `warning` marks attention; `mica` is
/// neutral metadata.
private struct InboxPill: View {
    let title: String
    let tint: Color

    var body: some View {
        Text(title)
            .font(.speakBody(.caption, semibold: true))
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(tint.opacity(0.15)))
    }
}

// MARK: - AgentInboxErrorStrip

/// A load failure is a strip above the list, not a modal — retry and dismiss.
private struct AgentInboxErrorStrip: View {
    let message: String
    let onRetry: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: SpeakSpacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))

            Text(message)
                .font(.speakBody(.caption))
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

            Spacer(minLength: SpeakSpacing.sm)

            Button("Retry", action: onRetry)
                .font(.speakBody(.caption, semibold: true))
                .buttonStyle(.plain)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
            }
            .buttonStyle(.plain)
            .help("Dismiss")
        }
        .foregroundStyle(Color.speakError)
        .padding(SpeakSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.speakError.opacity(0.08))
        )
    }
}
