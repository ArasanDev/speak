// App/Dashboard/Panes/InferencePaneView.swift
//
// The Inference pane — developer visibility into the local inference server.
// Shows server status, API key management, discovered model backends, a quick
// test console, and copy-paste integration snippets for popular dev tools.
//
// The inference server (SpeakLLM/InferenceServer/) is a loopback-only HTTP
// gateway that exposes Apple Intelligence and local LLMs via standard OpenAI
// and Anthropic API protocols. This pane is its control surface.
//
// LAYOUT (this file): the pane scaffold + the two identity cards — server
// status and API key. The registry, quick-test console and tool snippets live
// in `InferenceToolsViews.swift`; the shared card/button/copy chrome lives in
// `InferenceComponents.swift`; the view model in `InferenceViewModel.swift`.
//
// TYPE RULE (see InferenceComponents.swift header): SF Pro for chrome, labels
// and controls; Monaco (`Font.speakMono*`) ONLY for data the user would copy or
// verify — URLs, keys, model IDs, endpoints, numerals, code.
//
// All server interactions are async (actor isolation). Copy buttons use
// NSPasteboard write-only (AGENTS.md §2.6). No print — os.Logger only.

import AppKit
import Foundation
import SpeakCore
import SpeakLLM
import SwiftUI

// MARK: - InferencePaneView

/// The Inference dashboard pane — developer visibility into the local
/// inference server. Follows the standard pane pattern: takes a
/// `DashboardContext`, renders content in a ScrollView.
struct InferencePaneView: View {
    let context: DashboardContext

    @StateObject private var viewModel: InferenceViewModel

    init(context: DashboardContext) {
        self.context = context
        // The shared server — same instance the Agent Playground uses, so both
        // surfaces report and control one listener instead of two. The pane's
        // Start/Stop now genuinely controls THE app server. [fix: single-server]
        _viewModel = StateObject(wrappedValue: InferenceViewModel(server: context.inferenceServer))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: SpeakSpacing.md) {
                    ServerStatusCard(viewModel: viewModel)
                    APIKeyCard(viewModel: viewModel)
                    ModelRegistryCard(viewModel: viewModel)
                    QuickTestConsole(viewModel: viewModel, context: context)
                    ConnectToolsCard(viewModel: viewModel)
                    settingsHint
                }
                .padding(.top, SpeakSpacing.sm)
                .padding(.horizontal, SpeakSpacing.lg)
                .padding(.bottom, SpeakSpacing.lg)
            }
        }
        .task {
            viewModel.loadAPIKey()
            viewModel.discoverBackends()
            viewModel.startPolling()
        }
        .onDisappear {
            viewModel.stopPolling()
        }
    }

    /// This pane CONSUMES what Settings › Intelligence configures — the pane
    /// can't deep-link into a Settings category (the navigation channel only
    /// carries `DashboardSection`), so the pointer is a caption, not a button
    /// that would lie about where it lands.
    private var settingsHint: some View {
        HStack(spacing: SpeakSpacing.xs) {
            Image(systemName: "gearshape")
                .font(.system(size: 10))
            Text("Engines, providers, and neat-writing are configured in Settings › Intelligence.")
                .font(.speakBody(.caption))
        }
        .foregroundStyle(Color.speakMica)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, SpeakSpacing.xs)
    }
}

// MARK: - ServerStatusCard

/// The pane's hero: running/stopped state, the base URL as the one thing worth
/// copying, live metrics, and a single primary Start/Stop affordance.
///
/// [decision: the old card wore a perpetually rotating `flowBorder` while
///  running. A forever-animating gradient on a persistent settings card is the
///  opposite of premium — it reads as a screensaver and it competes with the
///  overlay, where the flow border actually means something. Liveness now comes
///  from a single breathing status dot (one signal, one animation) plus a
///  statically tinted card border.]
private struct ServerStatusCard: View {
    @ObservedObject var viewModel: InferenceViewModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        InferenceCard(
            systemImage: "server.rack",
            title: "Inference Server",
            subtitle: viewModel.isServerRunning
                ? "Accepting connections on loopback"
                : "Not accepting connections",
            tint: statusTint,
            isEmphasized: viewModel.isServerRunning,
            accessory: { toggleButton },
            content: { cardBody }
        )
        .animation(SpeakMotion.state(reduceMotion: reduceMotion), value: viewModel.isServerRunning)
    }

    // MARK: - Body

    private var cardBody: some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.md) {
            statusRow
            Rectangle()
                .fill(Color.speakCardBorder)
                .frame(height: InferenceMetrics.hairline)
                .opacity(0.5)
            metricsRow

            if let error = viewModel.errorMessage {
                errorRow(error)
            }
        }
    }

    /// State line + the base URL, the pane's most-copied string.
    private var statusRow: some View {
        HStack(spacing: SpeakSpacing.sm) {
            InferenceStatusDot(color: statusTint, isLive: viewModel.isServerRunning)

            VStack(alignment: .leading, spacing: 1) {
                Text(viewModel.isServerRunning ? "Running" : "Stopped")
                    .font(.speakBody(.body, semibold: true))
                    .foregroundStyle(viewModel.isServerRunning ? statusTint : Color.speakMica)

                Text("http://localhost:\(viewModel.serverPort)")
                    .font(.speakMonoFace(.caption))
                    .foregroundStyle(Color.speakMica)
                    .textSelection(.enabled)
            }

            Spacer(minLength: 0)

            InferenceCopyButton(text: "http://localhost:\(viewModel.serverPort)", label: "Base URL")
        }
    }

    /// Three tabular metrics separated by hairlines — a readout, not a paragraph.
    private var metricsRow: some View {
        HStack(alignment: .center, spacing: 0) {
            metric(
                value: viewModel.isServerRunning ? "\(viewModel.activeConnections)" : "—",
                label: "Connections"
            )
            metricDivider
            metric(
                value: viewModel.isServerRunning ? formatUptime(viewModel.uptimeSeconds) : "—",
                label: "Uptime"
            )
            metricDivider
            metric(
                value: viewModel.isServerRunning ? "127.0.0.1" : "—",
                label: "Bound to"
            )
        }
    }

    private var metricDivider: some View {
        Rectangle()
            .fill(Color.speakCardBorder)
            .frame(width: InferenceMetrics.hairline, height: 26)
            // sm, not md: at the 480pt dashboard floor the three metrics share
            // ~350pt, and 32pt of gutter (not 64) keeps "127.0.0.1" un-truncated.
            .padding(.horizontal, SpeakSpacing.sm)
    }

    private func metric(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.speakMonoFace(.body))
                .foregroundStyle(viewModel.isServerRunning ? Color.speakBone : Color.speakMica)
                .lineLimit(1)
            Text(label)
                .font(.speakBody(.caption))
                .foregroundStyle(Color.speakMica)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func errorRow(_ error: String) -> some View {
        HStack(alignment: .top, spacing: SpeakSpacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
            Text(error)
                .font(.speakBody(.caption))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button {
                viewModel.errorMessage = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
            }
            .buttonStyle(.plain)
            .help("Dismiss")
        }
        .foregroundStyle(Color.speakError)
        .padding(SpeakSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: InferenceMetrics.controlRadius, style: .continuous)
                .fill(Color.speakError.opacity(0.08))
        )
        .transition(.opacity)
    }

    // MARK: - Controls

    private var toggleButton: some View {
        InferenceButton(
            title: viewModel.isServerRunning ? "Stop" : "Start Server",
            systemImage: viewModel.isServerRunning ? "stop.fill" : "play.fill",
            tint: viewModel.isServerRunning ? Color.speakError : Color.speakOK,
            emphasis: viewModel.isServerRunning ? .tinted : .filled,
            isBusy: viewModel.isTogglingServer
        ) {
            viewModel.toggleServer()
        }
        .disabled(viewModel.isTogglingServer)
    }

    // MARK: - Derived values

    /// [decision: `speakOnAir` is reserved by hard rule for the mic tally.
    ///  Stopped is the pane's *default* state, not a failure — the dot and the
    ///  "Stopped" word stay `mica` (off), and `error` red is spent only on the
    ///  error strip, where it means something actually went wrong.]
    private var statusTint: Color {
        viewModel.isServerRunning ? Color.speakOK : Color.speakMica
    }

    private func formatUptime(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else if minutes > 0 {
            return "\(minutes)m \(secs)s"
        }
        return "\(secs)s"
    }
}

// MARK: - APIKeyCard

/// The masked API key on a code-like field, with copy and regenerate.
private struct APIKeyCard: View {
    @ObservedObject var viewModel: InferenceViewModel

    var body: some View {
        InferenceCard(
            systemImage: "key.fill",
            title: "API Key",
            subtitle: "Bearer token for every request · stored in the macOS Keychain",
            tint: .speakAgentViolet,
            accessory: { regenerateButton },
            content: { keyField }
        )
        .confirmationDialog(
            "Regenerate API Key?",
            isPresented: $viewModel.showRegenerateConfirmation,
            titleVisibility: .visible
        ) {
            Button("Regenerate", role: .destructive) {
                viewModel.regenerateAPIKey()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All existing tool integrations using the old key will receive 401 until reconfigured.")
        }
    }

    private var keyField: some View {
        HStack(spacing: SpeakSpacing.sm) {
            Text(maskedKey(viewModel.apiKey))
                .font(.speakMonoFace(.base))
                .foregroundStyle(viewModel.apiKey.isEmpty ? Color.speakMica : Color.speakBone)
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: SpeakSpacing.sm)

            InferenceCopyButton(text: viewModel.apiKey, label: "Copy")
                .disabled(viewModel.apiKey.isEmpty)
        }
        .padding(.horizontal, SpeakSpacing.sm + 2)
        .padding(.vertical, SpeakSpacing.sm)
        .speakInset(cornerRadius: InferenceMetrics.codeRadius)
    }

    private var regenerateButton: some View {
        InferenceButton(
            title: "Regenerate",
            systemImage: "arrow.triangle.2.circlepath",
            tint: .speakAgentViolet,
            emphasis: .quiet
        ) {
            viewModel.showRegenerateConfirmation = true
        }
    }

    /// Masks the API key for display: shows prefix and last 4 chars.
    private func maskedKey(_ key: String) -> String {
        guard key.count > 16 else { return key.isEmpty ? "sk-speak-****" : key }
        let prefix = String(key.prefix(10))
        let suffix = String(key.suffix(4))
        return "\(prefix)••••••••\(suffix)"
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Inference") {
    InferencePaneView(context: DashboardContext(
        settingsStore: SettingsStore(),
        historyStore: PreviewNullHistoryStore(),
        hotkeyCombo: ["Fn", "Fn"]
    ))
    .frame(width: 900, height: 700)
}
#endif
