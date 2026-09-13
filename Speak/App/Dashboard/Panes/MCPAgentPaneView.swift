// App/Dashboard/Panes/MCPAgentPaneView.swift
//
// The MCP & Agent Integration Pane — Developer hub for stdio MCP server registration,
// active agent session management, tool capabilities inspection, and dynamic @tag agent adapters.

import Foundation
import SpeakCore
import SwiftUI

// MARK: - MCPAgentTab

private enum MCPAgentTab: String, CaseIterable, Identifiable {
    case mcpConfig = "MCP Server Config"
    case agentSessions = "Active Sessions & Tools"
    case tagAdapters = "Spoken @tag Adapters"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .mcpConfig:     return "terminal"
        case .agentSessions: return "network"
        case .tagAdapters:   return "tag"
        }
    }
}

// MARK: - MCPAgentPaneView

@MainActor
struct MCPAgentPaneView: View {
    let context: DashboardContext

    @State private var selectedTab: MCPAgentTab = .mcpConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: SpeakSpacing.md) {
                Picker("MCP View", selection: $selectedTab) {
                    ForEach(MCPAgentTab.allCases) { tab in
                        Label(tab.rawValue, systemImage: tab.icon)
                            .foregroundStyle(.speakBone)
                            .tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, SpeakSpacing.lg)
                .padding(.top, SpeakSpacing.md)

                ScrollView {
                    VStack(alignment: .leading, spacing: SpeakSpacing.lg) {
                        switch selectedTab {
                        case .mcpConfig:
                            MCPServerConfigSection()
                        case .agentSessions:
                            ActiveAgentSessionsSection(
                                context: context,
                                onShowSetup: { selectedTab = .mcpConfig }
                            )
                        case .tagAdapters:
                            TagAgentAdaptersSection()
                        }
                    }
                    .padding(SpeakSpacing.lg)
                }
            }

            Spacer(minLength: 0)
        }
    }
}

// MARK: - MCPServerConfigSection

private struct MCPServerConfigSection: View {
    /// Where `make install-mcp-user` places the relocatable bridge
    /// (`MCP_USER_DIR` in the Makefile). Checked on appear so the status pill
    /// is a real signal, not a sticker.
    private static let installedBinaryPath =
        "~/Library/Application Support/speak/mcp/bin/speak-mcp"

    @State private var isInstalled = false

    /// One-step registration across detected agent CLIs (idempotent — see
    /// `scripts/register-mcp.sh`). Pair with `installCommand`.
    private let installCommand = "make install-mcp-user"
    private let registerCommand = "make register-mcp-apply"

    /// The manual client config — mirrors README §"Manual Configuration".
    /// `/bin/zsh -lc` is required: the path contains a space and is not on PATH.
    private let jsonSnippet = """
    {
      "mcpServers": {
        "speak-app": {
          "command": "/bin/zsh",
          "args": ["-lc", "exec \\"$HOME/Library/Application Support/speak/mcp/bin/speak-mcp\\""]
        }
      }
    }
    """

    var body: some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.sm) {
            HStack(spacing: SpeakSpacing.xs) {
                Text("speak-mcp Stdio Server")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.speakBone)
                MCPStatusPill(
                    title: isInstalled ? "Installed" : "Not installed",
                    tint: isInstalled ? .speakOK : .speakWarning
                )
                Spacer()
            }

            VStack(alignment: .leading, spacing: SpeakSpacing.md) {
                Text("Standard input/output Model Context Protocol server bridging LLM agents to Speak's local voice interface.")
                    .font(.speakBody(.caption))
                    .foregroundStyle(.speakMica)

                // Info Grid
                Grid(alignment: .leading, horizontalSpacing: SpeakSpacing.lg, verticalSpacing: SpeakSpacing.xs) {
                    GridRow {
                        Text("Binary").font(.speakBody(.caption)).foregroundStyle(.speakMica)
                        Text(Self.installedBinaryPath)
                            .font(.speakMonoFace(.caption))
                            .foregroundStyle(.speakBone)
                            .textSelection(.enabled)
                    }
                    GridRow {
                        Text("Protocol").font(.speakBody(.caption)).foregroundStyle(.speakMica)
                        Text("MCP 2025-11-25 · JSON-RPC 2.0 · stdio").font(.speakMonoFace(.caption)).foregroundStyle(.speakBone)
                    }
                    GridRow {
                        Text("Tools").font(.speakBody(.caption)).foregroundStyle(.speakMica)
                        Text("speak_notify, speak_request_input, speak_say, …").font(.speakMonoFace(.caption)).foregroundStyle(.speakBone)
                    }
                }

                if !isInstalled {
                    MCNoticeStrip(
                        systemImage: "exclamationmark.triangle",
                        tint: .speakWarning,
                        message: "The bridge binary is not installed yet — run the install command below from the speak repo."
                    )
                }

                MCPHairline()

                // User Installation Command
                MCPCodeWell(
                    label: "Install the bridge",
                    code: installCommand,
                    copyLabel: "Copy command"
                )

                MCPCodeWell(
                    label: "Register with detected agent CLIs",
                    code: registerCommand,
                    copyLabel: "Copy command"
                )

                MCPHairline()

                // Client Config JSON
                MCPCodeWell(
                    label: "Manual client config (Claude / Cursor / Windsurf)",
                    code: jsonSnippet,
                    copyLabel: "Copy JSON"
                )
            }
            .padding(SpeakSpacing.md)
            .speakCard()
            .onAppear { refreshInstallStatus() }
        }
    }

    private func refreshInstallStatus() {
        let path = (Self.installedBinaryPath as NSString).expandingTildeInPath
        isInstalled = FileManager.default.isExecutableFile(atPath: path)
    }
}

// MARK: - ActiveAgentSessionsSection

private struct ActiveAgentSessionsSection: View {
    let context: DashboardContext
    /// Jumps back to the config tab — the empty state's "set up the bridge" action.
    let onShowSetup: () -> Void

    @State private var sessions: [AgentSession] = []

    var body: some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.lg) {
            // Sessions Section
            VStack(alignment: .leading, spacing: SpeakSpacing.sm) {
                HStack {
                    Text("Connected Agent Sessions")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.speakBone)
                    Spacer()
                    Button(action: refreshSessions) {
                        Label("Refresh", systemImage: "arrow.clockwise")
                            .font(.speakBody(.caption))
                            .foregroundStyle(.speakBone)
                    }
                }

                VStack(alignment: .leading, spacing: SpeakSpacing.md) {
                    Text("Live agent pings negotiated through the speak_register_session tool.")
                        .font(.speakBody(.caption))
                        .foregroundStyle(.speakMica)

                    if sessions.isEmpty {
                        InferenceEmptyState(
                            systemImage: "network.badge.shield.half.filled",
                            headline: "No agent sessions",
                            message: "Agents that call speak_register_session appear here live."
                        ) {
                            Button("Set up the bridge", action: onShowSetup)
                                .font(.speakBody(.caption, semibold: true))
                                .foregroundStyle(Color.speakAgentViolet)
                                .buttonStyle(.plain)
                        }
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(sessions.enumerated()), id: \.element.sessionId) { index, session in
                                AgentSessionRow(session: session)
                                if index < sessions.count - 1 {
                                    MCPHairline()
                                }
                            }
                        }
                    }
                }
                .padding(SpeakSpacing.md)
                .speakCard()
            }
            .task {
                refreshSessions()
            }

            // MCP Tool Capability Registry Section
            VStack(alignment: .leading, spacing: SpeakSpacing.sm) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Exposed MCP Tools")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.speakBone)
                    Text("Tool interfaces available to connected stdio agents.")
                        .font(.speakBody(.caption))
                        .foregroundStyle(.speakMica)
                }

                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(Self.toolCatalog.enumerated()), id: \.element.name) { index, tool in
                        toolRow(tool)
                        if index < Self.toolCatalog.count - 1 {
                            MCPHairline()
                        }
                    }
                }
                .padding(.vertical, SpeakSpacing.xs)
                .padding(.horizontal, SpeakSpacing.md)
                .speakCard()
            }
        }
    }

    /// The compiled-in tool surface (AgentBridgeServer) — static because the
    /// tools ship with the binary, not discovered at runtime.
    private static let toolCatalog: [(name: String, summary: String, params: String)] = [
        ("speak_notify", "Spoken or banner notifications", "summary, kind, interrupt"),
        ("speak_request_input", "Human-in-the-loop interactive prompts", "requestId, prompt, mode, choices"),
        ("speak_say", "Vocalize text aloud via on-device TTS", "text, interrupt"),
        ("speak_ask", "Ask question by voice and dictation response", "question, timeout"),
        ("speak_confirm", "Yes/No voice confirmation prompt", "question"),
        ("speak_status", "Check dictation engine state and hotkey", "sessionId"),
        ("speak_register_session", "Negotiate agent capabilities and session", "provider, label, cwd, capabilities"),
        ("speak_submit_call", "Submit durable agent call to Agent Inbox", "requestId, prompt, mode, urgency"),
        ("speak_get_call", "Poll a durable call's state and response", "callId"),
    ]

    private func refreshSessions() {
        // The LIVE registry — the same instance CLIPortServer/AgentBridgeServer
        // mutate on every speak-mcp call. (The old code listed a freshly built
        // registry, which is empty by construction.) Nil in previews.
        sessions = context.agentSessionRegistry?.list() ?? []
    }

    private func toolRow(_ tool: (name: String, summary: String, params: String)) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: SpeakSpacing.sm) {
            Text(tool.name)
                .font(.speakMonoFace(.caption, semibold: true))
                .foregroundStyle(Color.speakAgentViolet)
                .frame(width: 168, alignment: .leading)

            VStack(alignment: .leading, spacing: 1) {
                Text(tool.summary)
                    .font(.speakBody(.caption))
                    .foregroundStyle(.speakBone)
                Text(tool.params)
                    .font(.speakMonoFace(.caption))
                    .foregroundStyle(.speakMica)
            }

            Spacer(minLength: SpeakSpacing.sm)

            MCPStatusPill(title: "Active", tint: .speakOK)
        }
        .padding(.vertical, SpeakSpacing.xs + 2)
    }
}

// MARK: - AgentSessionRow

private struct AgentSessionRow: View {
    let session: AgentSession

    private var isActive: Bool { session.state == .active }

    var body: some View {
        HStack(alignment: .top, spacing: SpeakSpacing.sm + 2) {
            InferenceGlyph(systemImage: "network", tint: .speakAgentViolet)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: SpeakSpacing.xs) {
                    Text(session.label)
                        .font(.speakBody(.base, semibold: true))
                        .foregroundStyle(.speakBone)
                    Text(session.provider)
                        .font(.speakMonoFace(.caption))
                        .foregroundStyle(Color.speakAgentViolet)
                }

                Text(session.sessionId)
                    .font(.speakMonoFace(.caption))
                    .foregroundStyle(.speakMica)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if let cwd = session.workingDirectory {
                    Text(cwd)
                        .font(.speakMonoFace(.caption))
                        .foregroundStyle(.speakMica)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: SpeakSpacing.sm)

            VStack(alignment: .trailing, spacing: SpeakSpacing.xs) {
                MCPStatusPill(
                    title: isActive ? "Active" : "Stale",
                    tint: isActive ? .speakOK : .speakWarning
                )

                Text(session.lastSeen, style: .relative)
                    .font(.speakMonoFace(.caption))
                    .foregroundStyle(.speakMica)

                if !session.capabilities.isEmpty {
                    Text(session.capabilities.joined(separator: " · "))
                        .font(.speakBody(.caption))
                        .foregroundStyle(.speakMica)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, SpeakSpacing.sm)
    }
}

// MARK: - TagAgentAdaptersSection

private struct TagAgentAdaptersSection: View {
    @State private var tags: [TagMetadata] = []
    @State private var showingAddModal = false

    // New tag form fields
    @State private var newTagName = ""
    @State private var newDisplayName = ""
    @State private var newDescription = ""
    @State private var newShellCommand = ""
    @State private var newSystemPrompt = ""
    @State private var newIsLocalMCP = false

    var body: some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.sm) {
            HStack {
                Text("Spoken @tag Agent Adapters")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.speakBone)
                Spacer()
                Button(action: { showingAddModal = true }) {
                    Label("Register @tag Adapter", systemImage: "plus")
                        .font(.speakBody(.caption, semibold: true))
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.speakAgentViolet)
            }

            VStack(alignment: .leading, spacing: SpeakSpacing.md) {
                Text("Register, inspect, and invoke dynamic agent adapters using spoken @tag references.")
                    .font(.speakBody(.caption))
                    .foregroundStyle(.speakMica)

                if tags.isEmpty {
                    InferenceEmptyState(
                        systemImage: "tag",
                        headline: "No @tag adapters",
                        message: "Built-in adapters load on appear; register a custom adapter to extend the set."
                    )
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(tags.enumerated()), id: \.element.id) { index, tag in
                            TagRow(tag: tag, onRemove: { Task { await removeTag(tag.tagName) } })
                            if index < tags.count - 1 {
                                MCPHairline()
                            }
                        }
                    }
                }
            }
            .padding(SpeakSpacing.md)
            .speakCard()
            .task {
                await loadTags()
            }
            .sheet(isPresented: $showingAddModal) {
                addTagSheet
            }
        }
    }

    private var addTagSheet: some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.md) {
            Text("Register Custom @tag Agent Adapter")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.speakBone)

            Form {
                Section {
                    TextField("Tag Name (e.g. @speak-mcp or @my-agent)", text: $newTagName)
                        .foregroundStyle(.speakBone)
                    TextField("Display Name (e.g. Speak MCP Agent)", text: $newDisplayName)
                        .foregroundStyle(.speakBone)
                    TextField("Description", text: $newDescription)
                        .foregroundStyle(.speakBone)
                } header: {
                    Text("Agent Metadata")
                        .font(.speakBody(.base, semibold: true))
                        .foregroundStyle(.speakBone)
                }

                Section {
                    TextField("Shell Command (e.g. /usr/local/bin/agent)", text: $newShellCommand)
                        .foregroundStyle(.speakBone)
                    TextField("System Prompt", text: $newSystemPrompt)
                        .foregroundStyle(.speakBone)
                    Toggle(isOn: $newIsLocalMCP) {
                        Text("Is Local MCP Server")
                            .font(.speakBody(.base))
                            .foregroundStyle(.speakBone)
                    }
                } header: {
                    Text("Execution & Prompt (Optional)")
                        .font(.speakBody(.base, semibold: true))
                        .foregroundStyle(.speakBone)
                }
            }
            .formStyle(.grouped)

            HStack {
                Button {
                    showingAddModal = false
                } label: {
                    Text("Cancel")
                        .font(.speakBody(.base))
                        .foregroundStyle(.speakBone)
                }
                .buttonStyle(.plain)
                Spacer()
                Button("Register Adapter") {
                    Task { await addTag() }
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.speakAgentViolet)
                .disabled(newTagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(SpeakSpacing.lg)
        .frame(minWidth: 460, minHeight: 380)
    }

    private func loadTags() async {
        await TagRegistry.shared.registerDefaults()
        tags = await TagRegistry.shared.allTags()
    }

    private func addTag() async {
        let def = CustomAgentDefinition(
            tagName: newTagName,
            displayName: newDisplayName.isEmpty ? newTagName : newDisplayName,
            description: newDescription.isEmpty ? "Developer custom agent adapter" : newDescription,
            systemPrompt: newSystemPrompt.isEmpty ? nil : newSystemPrompt,
            shellCommand: newShellCommand.isEmpty ? nil : newShellCommand,
            isLocalMCP: newIsLocalMCP
        )
        await TagRegistry.shared.registerCustomAgent(def)
        showingAddModal = false
        // Reset form
        newTagName = ""
        newDisplayName = ""
        newDescription = ""
        newShellCommand = ""
        newSystemPrompt = ""
        newIsLocalMCP = false
        // Reload list
        tags = await TagRegistry.shared.allTags()
    }

    private func removeTag(_ tagName: String) async {
        await TagRegistry.shared.unregister(tagName: tagName)
        tags = await TagRegistry.shared.allTags()
    }
}

// MARK: - TagRow

private struct TagRow: View {
    let tag: TagMetadata
    let onRemove: () -> Void

    private var isBuiltIn: Bool {
        ["@claude", "@terminal", "@builder-qa", "@github"].contains(tag.tagName.lowercased())
    }

    var body: some View {
        HStack(alignment: .top, spacing: SpeakSpacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: SpeakSpacing.xs) {
                    Text(tag.tagName)
                        .font(.speakMonoFace(.base, semibold: true))
                        .foregroundStyle(Color.speakAgentViolet)

                    MCPStatusPill(title: tag.tagKind.rawValue.capitalized, tint: .speakMica)
                }

                Text(tag.description)
                    .font(.speakBody(.caption))
                    .foregroundStyle(.speakMica)
            }

            Spacer(minLength: SpeakSpacing.sm)

            HStack(spacing: SpeakSpacing.xs) {
                ForEach(tag.capabilities, id: \.self) { cap in
                    Text(cap.rawValue)
                        .font(.speakBody(.caption))
                        .foregroundStyle(.speakBone)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(Color.speakAgentViolet.opacity(0.12))
                        )
                }
            }

            if !isBuiltIn {
                Button(action: onRemove) {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.speakError.opacity(0.8))
                }
                .buttonStyle(.plain)
                .help("Remove custom @tag adapter")
            }
        }
        .padding(.vertical, SpeakSpacing.sm)
    }
}

// MARK: - Shared chrome (pane-local)

/// The pane's one status pill: caption-semibold text on a 14% tint capsule.
/// Semantics follow the palette contract — `ok` live/healthy, `warning`
/// stale/attention, `error` down/failed, `agentViolet` agent-active.
private struct MCPStatusPill: View {
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

/// A hairline that uses the themed card border — `Divider()` picks up a system
/// gray that fights the two-temperature palette.
private struct MCPHairline: View {
    var body: some View {
        Rectangle()
            .fill(Color.speakCardBorder)
            .frame(height: 1)
            .opacity(0.5)
    }
}

/// A recessed code/command well: mono face, selectable, with a copy affordance
/// in the label row. Pasteboard is write-only (AGENTS.md §2.6).
private struct MCPCodeWell: View {
    let label: String
    let code: String
    var copyLabel: String = "Copy"

    var body: some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.xs) {
            HStack {
                Text(label)
                    .font(.speakBody(.caption, semibold: true))
                    .foregroundStyle(.speakBone)
                Spacer()
                InferenceCopyButton(text: code, label: copyLabel)
            }

            Text(code)
                .font(.speakMonoFace(.caption))
                .foregroundStyle(.speakBone)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(SpeakSpacing.sm)
                .speakInset(cornerRadius: 8)
        }
    }
}

/// A one-line tinted notice strip — caution or failure callouts inside a card.
private struct MCNoticeStrip: View {
    let systemImage: String
    let tint: Color
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: SpeakSpacing.sm) {
            Image(systemName: systemImage)
                .font(.system(size: 11))
            Text(message)
                .font(.speakBody(.caption))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(tint)
        .padding(SpeakSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(tint.opacity(0.08))
        )
    }
}
