// App/Settings/AgentBridgeSettingsView.swift
//
// "Agent Bridge & MCP" — the fifth Settings category. The speak-mcp stdio
// server status + install command, the agent prompt tag that marks pasted
// text as voice-dictated, and a compact live-session list with a jump to the
// full MCP & Agents / Agent Inbox desk panes for session management.
//
// The heavy lifting (tool registry, @tag adapters) stays in
// `MCPAgentPaneView` — this category is the configuration surface, not a
// duplicate monitor. [decision: settings owns knobs, desk owns live state]
//
// STATUS SEMANTICS: `speak-mcp` is a stdio server — spawned per agent client,
// not a daemon — so "live" is derived from the session registry's heartbeat,
// not a process check: agentViolet while an agent is attached, ok while
// sessions are connected-but-quiet, warning when only stale sessions remain,
// mica when the registry is unavailable (preview contexts).

import AppKit
import SpeakCore
import SwiftUI

// MARK: - AgentBridgeSettingsView

@MainActor
struct AgentBridgeSettingsView: View {
    let context: DashboardContext
    let onOpenSection: (DashboardSection) -> Void

    /// The code block whose Copy button currently shows "Copied".
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

    private var activeSessions: [AgentSession] {
        sessions.filter { $0.state == .active }
    }

    /// Pill for the server row — see STATUS SEMANTICS in the file header.
    private var serverStatus: (text: String, tint: Color) {
        guard context.agentSessionRegistry != nil else {
            return ("Unavailable", .speakMica)
        }
        if heartbeatLive { return ("Agent attached", .speakAgentViolet) }
        if sessions.isEmpty { return ("Ready", .speakOK) }
        if activeSessions.isEmpty { return ("Stale", .speakWarning) }
        return ("Listening", .speakOK)
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
            SettingsRow(
                "Model Context Protocol server",
                description: "Bridges coding agents (Claude Code, Cursor, Codex) to speak's local voice interface over JSON-RPC 2.0 stdio."
            ) {
                SettingsStatusPill(text: serverStatus.text, tint: serverStatus.tint)
            }

            VStack(alignment: .leading, spacing: SpeakSpacing.sm) {
                codeBlock(
                    title: "Install",
                    code: installCommand,
                    copyName: "command"
                )

                codeBlock(
                    title: "Client config — Claude Code, Cursor, Codex",
                    code: jsonSnippet,
                    copyName: "JSON"
                )
            }
            .padding(.horizontal, SpeakSpacing.md)
            .padding(.bottom, SpeakSpacing.sm + 4)
        }
    }

    /// A labeled `speakInset` code well with a trailing copy button that
    /// flips to a "Copied" check for 2.5 s. The pasteboard is write-only —
    /// speak never reads it back (hard rule).
    private func codeBlock(title: String, code: String, copyName: String) -> some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.xs) {
            HStack {
                Text(title)
                    .font(.speakBody(.caption, semibold: true))
                    .foregroundStyle(Color.speakBone)
                Spacer()
                copyButton(text: code, name: copyName)
            }
            Text(code)
                .font(.speakMonoFace(.caption))
                .foregroundStyle(Color.speakBone)
                .textSelection(.enabled)
                .padding(SpeakSpacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .speakInset()
        }
    }

    // MARK: - Agent prompt tag

    private var promptTagCard: some View {
        SettingsSectionCard(title: "Agent Integration") {
            SettingsRow(
                "Prompt tag",
                description: "Prepends an origin tag to pasted text so coding agents know the prompt was voice-dictated."
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
                .labelsHidden()
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
                    .tint(.speakUIAccent)
                }
            }
        }
    }

    // MARK: - Live sessions

    /// Heartbeat + session list, refreshed from the app's real
    /// `AgentSessionRegistry` (the instance `CLIPortServer` touches on every
    /// `speak-mcp` call) every 2 s while this category is visible.
    private var sessionsCard: some View {
        SettingsSectionCard(title: "Live Sessions") {
            SettingsRow(
                "Connected agent sessions",
                description: sessionSummary
            ) {
                HStack(spacing: SpeakSpacing.xs) {
                    if activeSessions.isEmpty == false {
                        SettingsStatusPill(text: "\(activeSessions.count) active", tint: .speakOK)
                    }
                    let staleCount = sessions.count - activeSessions.count
                    if staleCount > 0 {
                        SettingsStatusPill(text: "\(staleCount) stale", tint: .speakWarning)
                    }
                    if sessions.isEmpty {
                        Text("—")
                            .font(.speakBody(.base))
                            .foregroundStyle(Color.speakMica)
                    }
                }
            }

            ForEach(sessions, id: \.sessionId) { session in
                SettingsRowSeparator()
                sessionRow(session)
            }

            SettingsRowSeparator()

            SettingsRow(
                "Manage agents & calls",
                description: "Tool capabilities, @tag adapters, and the Agent Inbox live on the dashboard."
            ) {
                HStack(spacing: SpeakSpacing.sm) {
                    Button("MCP & Agents") { onOpenSection(.mcpAgents) }
                        .controlSize(.small)
                    Button("Agent Inbox") { onOpenSection(.agentInbox) }
                        .controlSize(.small)
                }
            }
        }
    }

    private var sessionSummary: String {
        if context.agentSessionRegistry == nil {
            return "Session registry unavailable."
        }
        if sessions.isEmpty {
            return "No agent has called in yet — agents register themselves via the speak_register_session tool."
        }
        if let lastActivity {
            return "Last bridge activity \(Self.relative(lastActivity))."
        }
        return ""
    }

    /// One session, scannable: label (or provider) + provider · short id ·
    /// last-seen on the left, state pill on the right.
    private func sessionRow(_ session: AgentSession) -> some View {
        HStack(spacing: SpeakSpacing.md) {
            VStack(alignment: .leading, spacing: SpeakSpacing.xs) {
                Text(session.label.isEmpty ? session.provider : session.label)
                    .font(.speakBody(.base, semibold: true))
                    .foregroundStyle(Color.speakBone)

                HStack(spacing: SpeakSpacing.xs) {
                    Text(session.provider)
                    Text("·")
                    Text(Self.shortId(session.sessionId))
                        .font(.speakMonoFace(.caption))
                    Text("·")
                    Text("seen \(Self.relative(session.lastSeen))")
                }
                .font(.speakBody(.caption))
                .foregroundStyle(Color.speakMica)
            }
            Spacer(minLength: SpeakSpacing.lg)
            SettingsStatusPill(
                text: session.state == .active ? "Active" : "Stale",
                tint: session.state == .active ? .speakAgentViolet : .speakWarning
            )
        }
        .padding(.horizontal, SpeakSpacing.md)
        .padding(.vertical, SpeakSpacing.sm + 4)
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

    /// First 8 chars of the session id — enough to tell sessions apart without
    /// flooding the row with a full UUID.
    private static func shortId(_ sessionId: String) -> String {
        sessionId.count > 8 ? String(sessionId.prefix(8)) : sessionId
    }

    private static func relative(_ date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 5 { return "just now" }
        if seconds < 60 { return "\(seconds)s ago" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m ago" }
        return "\(minutes / 60)h ago"
    }

    private func copyButton(text: String, name: String) -> some View {
        let copied = copiedItemName == name
        return Button {
            // Write-only pasteboard — speak never reads it back.
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            withAnimation { copiedItemName = name }
            Task {
                try? await Task.sleep(for: .seconds(2.5))
                if copiedItemName == name {
                    withAnimation { copiedItemName = nil }
                }
            }
        } label: {
            Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                .font(.speakBody(.caption))
        }
        .buttonStyle(.borderless)
        .tint(copied ? Color.speakDelivered : Color.speakUIAccent)
    }
}
