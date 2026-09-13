// App/Dashboard/Panes/InferenceToolsViews.swift
//
// Two of the Inference pane's cards: the model registry (discovered backends)
// and the quick-test console. Split out of `InferencePaneView.swift` so every
// file in the pane stays under the 400-line file_length budget.
//
// These types are internal (not `private`) because `private` does not cross
// files and `InferencePaneView` composes them.
//
// TYPE RULE: SF Pro for chrome/labels; Monaco for data (model IDs, endpoints,
// prompt echo, model output).

import Foundation
import SpeakCore
import SpeakLLM
import SwiftUI

// MARK: - ModelRegistryCard

/// Discovered inference backends, one row each. Rows are the pane's only list,
/// so they carry the list conventions: a status dot, a name, quiet metadata,
/// and a right-aligned status word.
struct ModelRegistryCard: View {
    @ObservedObject var viewModel: InferenceViewModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        InferenceCard(
            systemImage: "square.stack.3d.up.fill",
            title: "Model Registry",
            subtitle: subtitleText,
            tint: .speakAgentViolet,
            accessory: { refreshButton },
            content: { registryBody }
        )
    }

    @ViewBuilder
    private var registryBody: some View {
        if viewModel.backends.isEmpty {
            InferenceEmptyState(
                systemImage: "square.stack.3d.up.slash",
                headline: viewModel.isDiscovering ? "Scanning…" : "No backends yet",
                message: "speak probes Apple Intelligence and any local\nOpenAI-compatible server on loopback."
            ) {
                if !viewModel.isDiscovering {
                    InferenceButton(
                        title: "Scan for backends",
                        systemImage: "sparkle.magnifyingglass",
                        tint: .speakAgentViolet,
                        emphasis: .tinted
                    ) {
                        viewModel.discoverBackends()
                    }
                }
            }
        } else {
            VStack(spacing: 0) {
                ForEach(viewModel.backends) { backend in
                    BackendRow(backend: backend)
                    if backend.id != viewModel.backends.last?.id {
                        Rectangle()
                            .fill(Color.speakCardBorder)
                            .frame(height: InferenceMetrics.hairline)
                            .opacity(0.4)
                    }
                }
            }
            .animation(SpeakMotion.state(reduceMotion: reduceMotion), value: viewModel.backends.count)
        }
    }

    private var subtitleText: String {
        if viewModel.backends.isEmpty { return "Nothing discovered yet" }
        let available = viewModel.backends.filter { $0.status != .offline }.count
        return "\(available) of \(viewModel.backends.count) reachable"
    }

    private var refreshButton: some View {
        InferenceButton(
            title: viewModel.isDiscovering ? "Scanning" : "Refresh",
            systemImage: "arrow.clockwise",
            tint: .speakAgentViolet,
            emphasis: .quiet,
            isBusy: viewModel.isDiscovering
        ) {
            viewModel.discoverBackends()
        }
        .disabled(viewModel.isDiscovering)
    }
}

// MARK: - BackendRow

/// A single backend row: status dot, name, model ID + endpoint, owner badge.
struct BackendRow: View {
    let backend: BackendInfo

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: SpeakSpacing.sm) {
            Circle()
                .fill(statusColor)
                .frame(width: InferenceMetrics.statusDot, height: InferenceMetrics.statusDot)

            VStack(alignment: .leading, spacing: 2) {
                Text(backend.name)
                    .font(.speakBody(.base, semibold: true))
                    .foregroundStyle(Color.speakBone)
                    .lineLimit(1)

                HStack(spacing: SpeakSpacing.xs) {
                    Text(backend.id)
                        .font(.speakMonoFace(.caption))
                        .foregroundStyle(Color.speakMica)
                        .lineLimit(1)

                    if let endpoint = backend.endpoint {
                        Text("·")
                            .foregroundStyle(Color.speakMica)
                        Text(endpoint)
                            .font(.speakMonoFace(.caption))
                            .foregroundStyle(Color.speakMica)
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: SpeakSpacing.sm)

            ownerBadge

            Text(backend.status.rawValue)
                .font(.speakBody(.caption, semibold: true))
                .foregroundStyle(statusColor)
                .frame(width: 62, alignment: .trailing)
        }
        .padding(.horizontal, SpeakSpacing.sm)
        .padding(.vertical, SpeakSpacing.sm + 2)
        .background(
            RoundedRectangle(cornerRadius: InferenceMetrics.controlRadius, style: .continuous)
                .fill(Color.speakBone.opacity(isHovering ? 0.04 : 0))
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(SpeakMotion.micro(reduceMotion: reduceMotion)) { isHovering = hovering }
        }
    }

    private var ownerBadge: some View {
        Text(backend.ownedBy)
            .font(.speakBody(.caption))
            .foregroundStyle(Color.speakAgentViolet)
            .padding(.horizontal, SpeakSpacing.xs + 2)
            .padding(.vertical, 2)
            .background(
                Capsule().fill(Color.speakAgentViolet.opacity(0.15))
            )
    }

    private var statusColor: Color {
        switch backend.status {
        case .available:
            return Color.speakOK

        case .reachable:
            return Color.speakOK

        case .offline:
            return Color.speakError

        case .unknown:
            return Color.speakWarning
        }
    }
}

// MARK: - QuickTestConsole

/// A prompt input + model picker + run button + output display for testing the
/// local inference server directly from the dashboard. When the server is
/// stopped the whole console reads as blocked rather than merely disabled.
struct QuickTestConsole: View {
    @ObservedObject var viewModel: InferenceViewModel
    let context: DashboardContext

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        InferenceCard(
            systemImage: "bolt.horizontal.fill",
            title: "Quick Test",
            subtitle: "Send one chat completion through the local gateway",
            tint: .speakHumanAmber,
            accessory: { modelPicker },
            content: { consoleBody }
        )
    }

    @ViewBuilder
    private var consoleBody: some View {
        if viewModel.isServerRunning {
            VStack(alignment: .leading, spacing: SpeakSpacing.sm) {
                promptField
                actionRow
                if !viewModel.testOutput.isEmpty {
                    outputView
                }
            }
            .animation(SpeakMotion.state(reduceMotion: reduceMotion), value: viewModel.testOutput.isEmpty)
        } else {
            InferenceEmptyState(
                systemImage: "bolt.slash",
                headline: "Server is stopped",
                message: "Start the inference server above to run a test prompt."
            )
        }
    }

    private var modelPicker: some View {
        Picker("Model", selection: $viewModel.selectedModelID) {
            if viewModel.backends.isEmpty {
                Text("speak-default").tag("speak-default")
            } else {
                ForEach(viewModel.backends) { backend in
                    Text(backend.name).tag(backend.id)
                }
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .controlSize(.small)
        .font(.speakBody(.caption))
        .frame(maxWidth: 200)
    }

    private var promptField: some View {
        TextField("Ask the local model something…", text: $viewModel.testPrompt, axis: .vertical)
            .font(.speakBody(.base))
            .textFieldStyle(.plain)
            .lineLimit(1...4)
            .padding(.horizontal, SpeakSpacing.sm + 2)
            .padding(.vertical, SpeakSpacing.sm)
            .background(
                RoundedRectangle(cornerRadius: InferenceMetrics.codeRadius, style: .continuous)
                    .fill(Color.speakBone.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: InferenceMetrics.codeRadius, style: .continuous)
                    .strokeBorder(Color.speakCardBorder, lineWidth: InferenceMetrics.hairline)
            )
            .onSubmit { viewModel.runTest() }
    }

    private var actionRow: some View {
        HStack(spacing: SpeakSpacing.sm) {
            InferenceButton(
                title: viewModel.isTesting ? "Running" : "Run",
                systemImage: "play.fill",
                tint: .speakAgentViolet,
                emphasis: .filled,
                isBusy: viewModel.isTesting
            ) {
                viewModel.runTest()
            }
            .disabled(viewModel.testPrompt.isEmpty || viewModel.isTesting)

            if let engine = context.speakEngine {
                InferenceButton(
                    title: "Dictate",
                    systemImage: "mic.fill",
                    tint: .speakHumanAmber,
                    emphasis: .tinted
                ) {
                    Task {
                        // Dictation start failures are logged by the engine.
                        _ = try? await engine.beginDictation()
                    }
                }
            }

            Spacer(minLength: 0)

            if !viewModel.testOutput.isEmpty {
                InferenceCopyButton(text: viewModel.testOutput, label: "Copy result")
            }
        }
    }

    private var outputView: some View {
        ScrollView {
            Text(viewModel.testOutput)
                .font(.speakMonoFace(.caption))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(SpeakSpacing.sm)
        }
        .frame(maxHeight: 200)
        .speakInset(cornerRadius: InferenceMetrics.codeRadius)
        .transition(.opacity)
    }
}
