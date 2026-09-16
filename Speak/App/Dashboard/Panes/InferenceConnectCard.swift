// App/Dashboard/Panes/InferenceConnectCard.swift
//
// The Inference pane's "Connect Your Tools" card: copy-paste integration
// snippets rendered with the live port and API key.
//
// [decision: the old card stacked SIX code blocks vertically the moment it was
//  expanded — ~120 lines of monospace no one reads. The redesign keeps the same
//  six snippets but shows ONE at a time behind a chip selector, so the card is
//  a chooser ("which tool are you wiring up?") instead of a wall. The expansion
//  flag is still `viewModel.showToolsCard` — the view model is untouched.]
//
// Pasteboard is write-only (AGENTS.md §2.6). No print — os.Logger only.

import Foundation
import SwiftUI

// MARK: - InferenceSnippet

/// One tool integration: a chip label, an icon, and a code generator.
struct InferenceSnippet: Identifiable, Hashable {
    let id: String
    let label: String
    let systemImage: String
    /// A short line telling the user where the code goes.
    let hint: String

    static let all: [InferenceSnippet] = [
        .init(id: "python-openai", label: "OpenAI SDK", systemImage: "chevron.left.forwardslash.chevron.right",
              hint: "Python · pip install openai"),
        .init(id: "python-anthropic", label: "Anthropic SDK", systemImage: "chevron.left.forwardslash.chevron.right",
              hint: "Python · pip install anthropic"),
        .init(id: "curl", label: "cURL", systemImage: "terminal", hint: "Paste into any shell"),
        .init(id: "cursor", label: "Cursor", systemImage: "cursorarrow.rays", hint: "Cursor · settings.json"),
        .init(id: "claude-code", label: "Claude Code", systemImage: "sparkles", hint: "Claude Code · settings.json"),
        .init(id: "env", label: "Env vars", systemImage: "gearshape.2", hint: "Append to ~/.zshrc")
    ]
}

// MARK: - ConnectToolsCard

/// Collapsible card showing copy-paste integration snippets for popular
/// developer tools. Each snippet uses the actual port and API key.
struct ConnectToolsCard: View {
    var viewModel: InferenceViewModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selection: String = InferenceSnippet.all[0].id

    var body: some View {
        InferenceCard(
            systemImage: "cable.connector",
            title: "Connect Your Tools",
            subtitle: "Point any OpenAI- or Anthropic-compatible client at speak",
            tint: .speakUIAccent,
            accessory: { disclosureButton },
            content: { body(for: viewModel.showToolsCard) }
        )
    }

    @ViewBuilder
    private func body(for expanded: Bool) -> some View {
        if expanded {
            VStack(alignment: .leading, spacing: SpeakSpacing.sm) {
                chipRow
                if let snippet = InferenceSnippet.all.first(where: { $0.id == selection }) {
                    InferenceCodeBlock(hint: snippet.hint, code: code(for: snippet))
                }
            }
            .transition(.opacity)
        } else {
            Text(InferenceSnippet.all.map(\.label).joined(separator: " · "))
                .font(.speakBody(.caption))
                .foregroundStyle(Color.speakMica)
        }
    }

    private var chipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: SpeakSpacing.xs + 2) {
                ForEach(InferenceSnippet.all) { snippet in
                    InferenceChip(
                        label: snippet.label,
                        systemImage: snippet.systemImage,
                        isSelected: snippet.id == selection
                    ) {
                        withAnimation(SpeakMotion.micro(reduceMotion: reduceMotion)) {
                            selection = snippet.id
                        }
                    }
                }
            }
            .padding(.vertical, 1)
        }
    }

    private var disclosureButton: some View {
        InferenceButton(
            title: viewModel.showToolsCard ? "Hide" : "Show snippets",
            systemImage: viewModel.showToolsCard ? "chevron.up" : "chevron.down",
            tint: .speakUIAccent,
            emphasis: .quiet
        ) {
            withAnimation(SpeakMotion.state(reduceMotion: reduceMotion)) {
                viewModel.showToolsCard.toggle()
            }
        }
    }

    // MARK: - Snippet generation

    private func code(for snippet: InferenceSnippet) -> String {
        let baseURL = "http://localhost:\(viewModel.serverPort)/v1"
        let key = viewModel.apiKey.isEmpty ? "sk-speak-<your-key>" : viewModel.apiKey

        switch snippet.id {
        case "python-openai", "python-anthropic":
            return pythonCode(id: snippet.id, baseURL: baseURL, key: key)

        case "curl":
            return """
            curl \(baseURL)/chat/completions \\
              -H "Content-Type: application/json" \\
              -H "Authorization: Bearer \(key)" \\
              -d '{"model": "speak-default", "messages": [{"role": "user", "content": "Hello"}]}'
            """

        case "cursor":
            return """
            {
              "openai.apiKey": "\(key)",
              "openai.apiBaseUrl": "\(baseURL)",
              "openai.model": "speak-default"
            }
            """

        case "claude-code":
            return """
            {
              "apiBaseUrl": "\(baseURL)",
              "apiKey": "\(key)",
              "model": "speak-default"
            }
            """

        default:
            return """
            export OPENAI_BASE_URL="\(baseURL)"
            export OPENAI_API_KEY="\(key)"
            export ANTHROPIC_BASE_URL="\(baseURL)"
            export ANTHROPIC_API_KEY="\(key)"
            """
        }
    }

    private func pythonCode(id: String, baseURL: String, key: String) -> String {
        if id == "python-anthropic" {
            return """
            from anthropic import Anthropic
            client = Anthropic(base_url="\(baseURL)", api_key="\(key)")
            message = client.messages.create(
                model="speak-default", max_tokens=1024,
                messages=[{"role": "user", "content": "Hello from speak"}]
            )
            result = message.content[0].text
            """
        }
        return """
        from openai import OpenAI
        client = OpenAI(base_url="\(baseURL)", api_key="\(key)")
        response = client.chat.completions.create(
            model="speak-default",
            messages=[{"role": "user", "content": "Hello from speak"}]
        )
        result = response.choices[0].message.content
        """
    }
}

// MARK: - InferenceChip

/// A selectable tool chip. Selected state is a filled capsule; the rest are
/// hairline outlines that warm on hover.
struct InferenceChip: View {
    let label: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: SpeakSpacing.xs) {
                Image(systemName: systemImage)
                    .font(.system(size: 9, weight: .semibold))
                Text(label)
                    .font(.speakBody(.caption, semibold: isSelected))
            }
            .padding(.horizontal, SpeakSpacing.sm + 2)
            .padding(.vertical, 5)
            .foregroundStyle(isSelected ? Color.speakUIAccent : Color.speakMica)
            .background(
                Capsule().fill(
                    isSelected
                        ? Color.speakUIAccent.opacity(0.16)
                        : Color.speakBone.opacity(isHovering ? 0.06 : 0.02)
                )
            )
            .overlay(
                Capsule().strokeBorder(
                    isSelected ? Color.speakUIAccent.opacity(0.35) : Color.speakCardBorder,
                    lineWidth: InferenceMetrics.hairline
                )
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(SpeakMotion.micro(reduceMotion: reduceMotion)) { isHovering = hovering }
        }
    }
}

// MARK: - InferenceCodeBlock

/// A code surface with a where-does-this-go hint and a copy affordance.
struct InferenceCodeBlock: View {
    let hint: String
    let code: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: SpeakSpacing.sm) {
                Text(hint)
                    .font(.speakBody(.caption))
                    .foregroundStyle(Color.speakMica)
                Spacer(minLength: 0)
                InferenceCopyButton(text: code, label: "Copy")
            }
            .padding(.horizontal, SpeakSpacing.sm + 2)
            .padding(.vertical, SpeakSpacing.xs + 2)
            .background(Color.speakBone.opacity(0.03))

            Rectangle()
                .fill(Color.speakCardBorder)
                .frame(height: InferenceMetrics.hairline)
                .opacity(0.4)

            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.speakMonoFace(.caption))
                    .foregroundStyle(Color.speakBone)
                    .textSelection(.enabled)
                    .padding(SpeakSpacing.sm + 2)
            }
        }
        .speakInset(cornerRadius: InferenceMetrics.codeRadius)
    }
}
