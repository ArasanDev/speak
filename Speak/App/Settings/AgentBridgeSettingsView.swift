// App/Settings/AgentBridgeSettingsView.swift
//
// "Agent Bridge & MCP" — the fifth Settings category. The speak-mcp stdio
// server status + install command, the agent prompt tag that marks pasted
// text as voice-dictated, and a jump to the full MCP & Agents / Agent Inbox
// desk panes for live session management.
//
// The heavy lifting (session list, tool registry, @tag adapters) stays in
// `MCPAgentPaneView` — this category is the configuration surface, not a
// duplicate monitor. [decision: settings owns knobs, desk owns live state]

import AppKit
import SpeakCore
import SwiftUI

// MARK: - AgentBridgeSettingsView

@MainActor
struct AgentBridgeSettingsView: View {
    let context: DashboardContext
    let onOpenSection: (DashboardSection) -> Void

    @State private var copiedItemName: String?
    @State private var sessions: [AgentSession] = []

    private var store: SettingsStore { context.settingsStore }

    /// A session touched within this window reads as a live heartbeat.
    /// [decision: 60 s — well under the registry's 30-min stale threshold; an
    ///  agent that pinged a tool in the last minute is genuinely attached]
    private static let heartbeatWindow: TimeInterval = 60

    private var lastActivity: Date? {
        sessions.map(\.lastSeen).max()
    }

    private var heartbeatLive: Bool {
        guard let lastActivity else { return false }
        return Date().timeIntervalSince(lastActivity) < Self.heartbeatWindow
    }

    private let installCommand = "make install-mcp-user"
    private let jsonSnippet = """
    {
      "mcpServers": {
        "speak": {
          "command": "speak-mcp",
          "args": []
        }
      }
    }
    """

    var body: some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.lg) {
            serverCard
            promptTagCard
            sessionsCard
        }
        .task { await pollSessions() }
    }

    // MARK: - speak-mcp server

    private var serverCard: some View {
        SettingsSectionCard(title: "speak-mcp Stdio Server") {
            VStack(alignment: .leading, spacing: SpeakSpacing.sm) {
                SettingsRow(
                    "Model Context Protocol server",
                    description: "Bridges LLM agents (Claude Code, Cursor, Codex) to speak's local voice interface over JSON-RPC 2.0 stdio."
                ) {
                    HStack(spacing: SpeakSpacing.xs) {
                        Circle()
                            .fill(heartbeatLive ? Color.speakDelivered : Color.secondary.opacity(0.4))
                            .frame(width: 7, height: 7)
                        SettingsStatusPill(
                            text: heartbeatLive ? "Agent attached" : "Listening",
                            tint: heartbeatLive ? .speakDelivered : .secondary.opacity(0.4)
                        )
                    }
                }

                SettingsRowSeparator()

                VStack(alignment: .leading, spacing: SpeakSpacing.xs) {
                    HStack {
                        Text("Install")
                            .font(.speakBody(.caption, semibold: true))
                        Spacer()
                        copyButton("Copy Command", text: installCommand, name: "Install command")
                    }
                    Text(installCommand)
                        .font(.speakMonoFace(.caption))
                        .padding(SpeakSpacing.sm)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.speakWindowCanvas)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.speakCardBorder, lineWidth: 1))
                        .cornerRadius(6)
                }

                VStack(alignment: .leading, spacing: SpeakSpacing.xs) {
                    HStack {
                        Text("Client config (Claude / Cursor / Codex)")
                            .font(.speakBody(.caption, semibold: true))
                        Spacer()
                        copyButton("Copy JSON", text: jsonSnippet, name: "JSON config")
                    }
                    Text(jsonSnippet)
                        .font(.speakMonoFace(.caption))
                        .padding(SpeakSpacing.sm)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.speakWindowCanvas)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.speakCardBorder, lineWidth: 1))
                        .cornerRadius(6)
                }

                if let copiedItemName {
                    HStack(spacing: SpeakSpacing.xs) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.speakDelivered)
                        Text("\(copiedItemName) copied to clipboard.")
                            .font(.speakBody(.caption))
                            .foregroundStyle(Color.speakDelivered)
                    }
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, SpeakSpacing.md)
            .padding(.vertical, SpeakSpacing.sm + 4)
        }
    }

    // MARK: - Agent prompt tag

    private var promptTagCard: some View {
        SettingsSectionCard(title: "Agent Integration") {
            SettingsRow(
                "Prompt tag",
                description: "Prepends an STT origin tag to pasted text so coding agents know the prompt was voice-dictated."
            ) {
                Picker("", selection: Binding(
                    get: { store.agentPrefixStyle },
                    set: { store.agentPrefixStyle = $0 }
                )) {
                    ForEach(AgentPrefixStyle.allCases, id: \.self) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .pickerStyle(.menu)
                .fixedSize()
            }

            if store.agentPrefixStyle != .none {
                SettingsRowSeparator()
                SettingsRow(
                    "Include transcript state",
                    description: "Appends ':clean' or ':raw' to signal whether AI cleanup polished the text."
                ) {
                    Toggle("", isOn: Binding(
                        get: { store.agentPrefixIncludeState },
                        set: { store.agentPrefixIncludeState = $0 }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }
            }
        }
    }

    // MARK: - Live state

    /// Heartbeat + session list, refreshed from the app's real
    /// `AgentSessionRegistry` (the instance `CLIPortServer` touches on every
    /// `speak-mcp` call) every 2 s while this category is visible.
    private var sessionsCard: some View {
        SettingsSectionCard(title: "Live Sessions") {
            VStack(alignment: .leading, spacing: 0) {
                SettingsRow(
                    "Connected agent sessions",
                    description: lastActivity.map { "Last bridge activity \(Self.relative($0))." }
                        ?? "No agent has called in yet — register via speak_register_session."
                ) {
                    Text("\(sessions.filter { $0.state == .active }.count)")
                        .font(.speakBody(.base))
                        .foregroundStyle(.secondary)
                }

                ForEach(sessions, id: \.sessionId) { session in
                    SettingsRowSeparator()
                    SettingsRow(
                        session.label.isEmpty ? session.provider : session.label,
                        description: "\(session.provider) · seen \(Self.relative(session.lastSeen))"
                    ) {
                        SettingsStatusPill(
                            text: session.state == .active ? "Active" : "Stale",
                            tint: session.state == .active ? .speakDelivered : .orange
                        )
                    }
                }

                SettingsRowSeparator()

                SettingsRow(
                    "Manage agents & calls",
                    description: "Tool capabilities, @tag adapters, and the Agent Inbox live on the dashboard."
                ) {
                    HStack(spacing: SpeakSpacing.sm) {
                        Button("MCP & Agents") { onOpenSection(.mcpAgents) }
                        Button("Agent Inbox") { onOpenSection(.agentInbox) }
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    /// Poll the shared registry while visible. `AgentSessionRegistry` is
    /// `@MainActor` — `list()` is a synchronous read once on the actor.
    private func pollSessions() async {
        while !Task.isCancelled {
            sessions = context.agentSessionRegistry?.list()
                .sorted { $0.lastSeen > $1.lastSeen } ?? []
            try? await Task.sleep(for: .seconds(2))
        }
    }

    private static func relative(_ date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 5 { return "just now" }
        if seconds < 60 { return "\(seconds)s ago" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m ago" }
        return "\(minutes / 60)h ago"
    }

    private func copyButton(_ label: String, text: String, name: String) -> some View {
        Button(label) {
            // Write-only pasteboard — speak never reads it back.
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            withAnimation { copiedItemName = name }
            Task {
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                withAnimation { copiedItemName = nil }
            }
        }
        .font(.speakBody(.caption))
        .buttonStyle(.borderless)
    }
}
