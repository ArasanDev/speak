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
    @State private var sessionCount: Int?

    private var store: SettingsStore { context.settingsStore }

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
        .task { await refreshSessionCount() }
    }

    // MARK: - speak-mcp server

    private var serverCard: some View {
        SettingsSectionCard(title: "speak-mcp Stdio Server", systemImage: "terminal") {
            VStack(alignment: .leading, spacing: SpeakSpacing.sm) {
                SettingsRow(
                    "Model Context Protocol server",
                    description: "Bridges LLM agents (Claude Code, Cursor, Codex) to speak's local voice interface over JSON-RPC 2.0 stdio."
                ) {
                    SettingsStatusPill(text: "Ready")
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
                        .font(.speakMonoCaption)
                        .padding(SpeakSpacing.sm)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.black.opacity(0.2))
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
                        .font(.speakMonoCaption)
                        .padding(SpeakSpacing.sm)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.black.opacity(0.2))
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
        SettingsSectionCard(title: "Agent Integration", systemImage: "tag") {
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

    // MARK: - Live state jump

    private var sessionsCard: some View {
        SettingsSectionCard(title: "Live State", systemImage: "network") {
            SettingsRow(
                "Connected agent sessions",
                description: "Agents registered via speak_register_session."
            ) {
                Text(sessionCount.map { "\($0)" } ?? "—")
                    .font(.speakMonoBody)
                    .foregroundStyle(.secondary)
            }

            SettingsRowSeparator()

            SettingsRow(
                "Manage agents & calls",
                description: "Live sessions, tool capabilities, @tag adapters, and the Agent Inbox live on the dashboard."
            ) {
                HStack(spacing: SpeakSpacing.sm) {
                    Button("MCP & Agents") { onOpenSection(.mcpAgents) }
                    Button("Agent Inbox") { onOpenSection(.agentInbox) }
                }
            }
        }
    }

    // MARK: - Helpers

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

    private func refreshSessionCount() async {
        let registry = AgentSessionRegistry()
        sessionCount = registry.list().count
    }
}
