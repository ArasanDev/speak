// App/Dashboard/Panes/MCPAgentPaneView.swift
//
// The MCP & Agent Integration Pane — Developer hub for stdio MCP server registration,
// active agent session management, tool capabilities inspection, and dynamic @tag agent adapters.

import AppKit
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
            PaneHeader(
                title: "MCP & Agent Integration",
                subtitle: "Register local stdio MCP servers, inspect active connected agent sessions, and configure dynamic @tag agent adapters."
            )

            VStack(alignment: .leading, spacing: SpeakSpacing.md) {
                Picker("MCP View", selection: $selectedTab) {
                    ForEach(MCPAgentTab.allCases) { tab in
                        Label(tab.rawValue, systemImage: tab.icon).tag(tab)
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
                            ActiveAgentSessionsSection()
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
    @State private var showCopiedNotification = false
    @State private var copiedItemName = ""

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

    private let installCommand = "make install-mcp-user"

    var body: some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.md) {
            // Header card
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: SpeakSpacing.xs) {
                        Text("speak-mcp Stdio Server")
                            .font(.speakBody(.base, semibold: true))
                        Text("READY")
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.speakDelivered.opacity(0.2))
                            .foregroundColor(.speakDelivered)
                            .clipShape(Capsule())
                    }
                    Text("Standard input/output Model Context Protocol server bridging LLM agents to Speak's local voice interface.")
                        .font(.speakBody(.caption))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            VStack(alignment: .leading, spacing: SpeakSpacing.md) {
                // Info Grid
                Grid(alignment: .leading, horizontalSpacing: SpeakSpacing.lg, verticalSpacing: SpeakSpacing.xs) {
                    GridRow {
                        Text("Binary Name:").font(.speakBody(.caption)).foregroundStyle(.secondary)
                        Text("speak-mcp (~/.local/bin/speak-mcp)").font(.speakMonoFace(.caption))
                    }
                    GridRow {
                        Text("Protocol Version:").font(.speakBody(.caption)).foregroundStyle(.secondary)
                        Text("2025-11-25 (JSON-RPC 2.0 via Stdio)").font(.speakMonoFace(.caption))
                    }
                    GridRow {
                        Text("Capabilities:").font(.speakBody(.caption)).foregroundStyle(.secondary)
                        Text("tools (speak_notify, speak_request_input, speak_say, …)").font(.speakMonoFace(.caption))
                    }
                }

                Divider()

                // User Installation Command
                VStack(alignment: .leading, spacing: SpeakSpacing.xs) {
                    HStack {
                        Text("1-Click Stdio Install Command").font(.speakBody(.caption, semibold: true))
                        Spacer()
                        Button(action: { copyToClipboard(installCommand, name: "Install Command") }) {
                            Label("Copy Command", systemImage: "doc.on.doc")
                                .font(.speakBody(.caption))
                        }
                    }

                    Text(installCommand)
                        .font(.speakMonoFace(.base))
                        .padding(SpeakSpacing.sm)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .speakInset(cornerRadius: 8)
                }

                Divider()

                // Client Config JSON
                VStack(alignment: .leading, spacing: SpeakSpacing.xs) {
                    HStack {
                        Text("Client Configuration Snippet (Claude / Cursor / Antigravity)").font(.speakBody(.caption, semibold: true))
                        Spacer()
                        Button(action: { copyToClipboard(jsonSnippet, name: "JSON Config") }) {
                            Label("Copy JSON Config", systemImage: "doc.on.doc")
                                .font(.speakBody(.caption))
                        }
                    }

                    Text(jsonSnippet)
                        .font(.speakMonoFace(.base))
                        .padding(SpeakSpacing.sm)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .speakInset(cornerRadius: 8)
                }

                if showCopiedNotification {
                    HStack(spacing: SpeakSpacing.xs) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.speakDelivered)
                        Text("\(copiedItemName) copied to clipboard.")
                            .font(.speakBody(.caption))
                            .foregroundStyle(Color.speakDelivered)
                    }
                    .padding(.top, SpeakSpacing.xs)
                    .transition(.opacity)
                }
            }
            .padding(SpeakSpacing.md)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.speakSurface))
        }
    }

    private func copyToClipboard(_ text: String, name: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copiedItemName = name
        withAnimation {
            showCopiedNotification = true
        }
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            withAnimation {
                showCopiedNotification = false
            }
        }
    }
}

// MARK: - ActiveAgentSessionsSection

private struct ActiveAgentSessionsSection: View {
    @State private var sessions: [AgentSession] = []
    @State private var isLoading = false

    var body: some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.lg) {
            // Sessions Card
            VStack(alignment: .leading, spacing: SpeakSpacing.md) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Connected Agent Sessions")
                            .font(.speakBody(.base, semibold: true))
                        Text("Active agent pings negotiated via speak_register_session tool calls.")
                            .font(.speakBody(.caption))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(action: { Task { await refreshSessions() } }) {
                        Label(isLoading ? "Refreshing..." : "Refresh Sessions", systemImage: "arrow.clockwise")
                            .font(.speakBody(.caption))
                    }
                    .disabled(isLoading)
                }

                if sessions.isEmpty {
                    VStack(spacing: SpeakSpacing.sm) {
                        Image(systemName: "network.badge.shield.half.filled")
                            .font(.system(size: 28))
                            .foregroundStyle(.tertiary)
                        Text("No external agent sessions currently registered.")
                            .font(.speakBody(.caption))
                            .foregroundStyle(.secondary)
                        Text("Agents registering via speak_register_session will appear here live.")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, SpeakSpacing.lg)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.1)))
                } else {
                    VStack(spacing: SpeakSpacing.sm) {
                        ForEach(sessions, id: \.sessionId) { session in
                            AgentSessionRow(session: session)
                        }
                    }
                }
            }
            .padding(SpeakSpacing.md)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.speakSurface))
            .task {
                await refreshSessions()
            }

            Divider()

            // MCP Tool Capability Registry Card
            VStack(alignment: .leading, spacing: SpeakSpacing.md) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Exposed MCP Tools & Capability Status")
                        .font(.speakBody(.base, semibold: true))
                    Text("Registered tool interfaces available to connected stdio agents.")
                        .font(.speakBody(.caption))
                        .foregroundStyle(.secondary)
                }

                Grid(alignment: .leading, horizontalSpacing: SpeakSpacing.md, verticalSpacing: SpeakSpacing.sm) {
                    toolRow(
                        name: "speak_notify",
                        summary: "Spoken or banner notifications",
                        params: "summary, kind, interrupt",
                        status: "Active"
                    )
                    toolRow(
                        name: "speak_request_input",
                        summary: "Human-in-the-loop interactive prompts",
                        params: "requestId, prompt, mode, choices",
                        status: "Active"
                    )
                    toolRow(
                        name: "speak_say",
                        summary: "Vocalize text aloud via on-device TTS",
                        params: "text, interrupt",
                        status: "Active"
                    )
                    toolRow(
                        name: "speak_ask",
                        summary: "Ask question by voice and dictation response",
                        params: "question, timeout",
                        status: "Active"
                    )
                    toolRow(
                        name: "speak_confirm",
                        summary: "Yes/No voice confirmation prompt",
                        params: "question",
                        status: "Active"
                    )
                    toolRow(
                        name: "speak_status",
                        summary: "Check dictation engine state and hotkey",
                        params: "sessionId",
                        status: "Active"
                    )
                    toolRow(
                        name: "speak_register_session",
                        summary: "Negotiate agent capabilities and session",
                        params: "provider, label, cwd, capabilities",
                        status: "Active"
                    )
                    toolRow(
                        name: "speak_submit_call",
                        summary: "Submit durable agent call to Agent Inbox",
                        params: "requestId, prompt, mode, urgency",
                        status: "Active"
                    )
                }
            }
            .padding(SpeakSpacing.md)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.speakSurface))
        }
    }

    private func refreshSessions() async {
        isLoading = true
        let registry = AgentSessionRegistry()
        sessions = registry.list()
        isLoading = false
    }

    private func toolRow(name: String, summary: String, params: String, status: String) -> some View {
        GridRow {
            Text(name)
                .font(.speakMonoFace(.base, semibold: true))
                .foregroundStyle(Color.speakAccent)
            Text(summary)
                .font(.speakBody(.caption))
            Text("(\(params))")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            Spacer()
            Text(status)
                .font(.system(size: 9, weight: .bold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.speakDelivered.opacity(0.15))
                .foregroundColor(.speakDelivered)
                .clipShape(Capsule())
        }
    }
}

// MARK: - AgentSessionRow

private struct AgentSessionRow: View {
    let session: AgentSession

    var body: some View {
        HStack(spacing: SpeakSpacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: SpeakSpacing.xs) {
                    Text(session.label)
                        .font(.speakMonoFace(.base, semibold: true))
                    Text("[\(session.provider)]")
                        .font(.speakMonoFace(.caption))
                        .foregroundStyle(.secondary)
                }
                if let cwd = session.workingDirectory {
                    Text("CWD: \(cwd)")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(session.state == .active ? "Active" : "Stale")
                    .font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(session.state == .active ? Color.speakDelivered.opacity(0.2) : Color.orange.opacity(0.2))
                    .foregroundColor(session.state == .active ? .speakDelivered : .orange)
                    .clipShape(Capsule())

                Text("Capabilities: \(session.capabilities.joined(separator: ", "))")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(SpeakSpacing.sm)
        .background(Color.black.opacity(0.15))
        .cornerRadius(6)
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
        VStack(alignment: .leading, spacing: SpeakSpacing.md) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Spoken @tag Agent Adapters")
                        .font(.speakBody(.base, semibold: true))
                    Text("Register, inspect, and invoke dynamic agent adapters using spoken @tag references.")
                        .font(.speakBody(.caption))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: { showingAddModal = true }) {
                    Label("Register @tag Adapter", systemImage: "plus")
                        .font(.speakBody(.caption))
                }
                .buttonStyle(.borderedProminent)
            }

            VStack(spacing: SpeakSpacing.sm) {
                ForEach(tags) { tag in
                    TagRow(tag: tag, onRemove: { Task { await removeTag(tag.tagName) } })
                }
            }
            .padding(SpeakSpacing.md)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.speakSurface))
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
                .font(.system(size: 16, weight: .bold))

            Form {
                Section("Agent Metadata") {
                    TextField("Tag Name (e.g. @speak-mcp or @my-agent)", text: $newTagName)
                    TextField("Display Name (e.g. Speak MCP Agent)", text: $newDisplayName)
                    TextField("Description", text: $newDescription)
                }

                Section("Execution & Prompt (Optional)") {
                    TextField("Shell Command (e.g. /usr/local/bin/agent)", text: $newShellCommand)
                    TextField("System Prompt", text: $newSystemPrompt)
                    Toggle("Is Local MCP Server", isOn: $newIsLocalMCP)
                }
            }
            .formStyle(.grouped)

            HStack {
                Button("Cancel") {
                    showingAddModal = false
                }
                Spacer()
                Button("Register Adapter") {
                    Task { await addTag() }
                }
                .buttonStyle(.borderedProminent)
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
        HStack(spacing: SpeakSpacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: SpeakSpacing.xs) {
                    Text(tag.tagName)
                        .font(.speakMonoFace(.base, semibold: true))
                        .foregroundStyle(Color.speakAccent)

                    Text(tag.tagKind.rawValue.capitalized)
                        .font(.system(size: 9, weight: .semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.08))
                        .cornerRadius(4)
                }

                Text(tag.description)
                    .font(.speakBody(.caption))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: SpeakSpacing.xs) {
                ForEach(tag.capabilities, id: \.self) { cap in
                    Text(cap.rawValue)
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.black.opacity(0.2))
                        .cornerRadius(3)
                }
            }

            if !isBuiltIn {
                Button(action: onRemove) {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundStyle(.red.opacity(0.8))
                }
                .buttonStyle(.plain)
                .help("Remove custom @tag adapter")
            }
        }
        .padding(SpeakSpacing.sm)
        .background(Color.black.opacity(0.12))
        .cornerRadius(6)
    }
}
