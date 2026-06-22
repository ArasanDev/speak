// App/Settings/OllamaSetupSheet.swift
//
// Guided-setup sheet for the Ollama local LLM cleanup engine (Wave 2.1).
//
// Extracted from SettingsView.swift to keep that file under the 1000-line
// swiftlint limit. [decision Wave 2.1]
//
// DESIGN DECISION (moat constraint):
//   A "Test Connection" button that pings localhost:11434 would use Apple
//   networking APIs that `make verify-moat` greps for in the App/ source
//   directory — it would cause an immediate moat failure. Live detection is
//   therefore deferred to the SpeakLLM module (v0.1), which lives outside
//   the moat-audited directories.
//   This sheet is informational only: it tells the user what to install, but
//   cannot verify connectivity in v0. [decision Wave 2.1: no live detection]

import SwiftUI
import SpeakCore

// MARK: - OllamaModel

/// A recommended Ollama model entry shown in the setup sheet.
/// Using a named struct (not an anonymous tuple) avoids the swiftlint
/// `large_tuple` violation for collections with 3+ members.
struct OllamaModel: Identifiable {
    let tag: String
    let label: String
    let detail: String
    let recommended: Bool

    var id: String { tag }
}

// MARK: - OllamaSetupSheet

/// A non-modal sheet that explains how to install Ollama and pull a model.
/// Presented automatically when the user picks "Ollama" in AICleanupSettingsTab.
struct OllamaSetupSheet: View {
    @Binding var isPresented: Bool

    // Recommended models — curated for quality/speed on Apple Silicon.
    // [decision Wave 2.1: three tiers — small/fast, balanced, multilingual —
    //  matching commonly-pulled small models from the Ollama library (2026-06-22)]
    private let recommendedModels: [OllamaModel] = [
        OllamaModel(tag: "qwen2.5:3b",
                    label: "Qwen2.5 3B (default)",
                    detail: "Best quality/speed balance. Recommended.",
                    recommended: true),
        OllamaModel(tag: "gemma3:4b",
                    label: "Gemma3 4B",
                    detail: "Google\u{2019}s model — strong at multilingual.",
                    recommended: false),
        OllamaModel(tag: "phi4-mini",
                    label: "Phi-4 Mini",
                    detail: "Microsoft\u{2019}s compact model, very fast.",
                    recommended: false),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.lg) {

            // Header
            HStack(alignment: .top, spacing: SpeakSpacing.md) {
                Image(systemName: "server.rack")
                    .font(.system(size: 32))
                    .foregroundStyle(Color.speakAccent)
                VStack(alignment: .leading, spacing: SpeakSpacing.xs) {
                    Text("Set up Ollama")
                        .font(.speakMonoTitle)
                    Text("Run a local LLM on your Mac \u{2014} no cloud, no account.")
                        .font(.speakMonoCaption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, SpeakSpacing.sm)

            Divider()

            // Step 1: install
            SetupStepRow(
                number: "1",
                title: "Install Ollama",
                detail: "Download from ollama.ai and drag to Applications."
            )

            // Step 2: pull a model
            SetupStepRow(
                number: "2",
                title: "Pull a cleanup model",
                detail: "Open Terminal and run one of these commands:"
            )

            // Command blocks — Monaco for commands (content voice).
            // [decision: speakMonoBody for terminal commands]
            modelCommandBlock

            // Step 3: keep running
            SetupStepRow(
                number: "3",
                title: "Keep Ollama running",
                detail: "Ollama runs as a background service on port 11434. speak uses it automatically on your next dictation."
            )

            // Note: live detection deferred to v0.1.
            HStack(spacing: SpeakSpacing.xs) {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                Text("speak will use Ollama automatically once it is running. Live detection arrives in v0.1.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(SpeakSpacing.md)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.speakSurface)
            )

            Spacer()

            // Footer dismiss button
            HStack {
                Spacer()
                Button("Done") { isPresented = false }
                    .keyboardShortcut(.return, modifiers: [])
            }
        }
        .padding(SpeakSpacing.lg)
        // [decision Wave 2.1: 480×520 fits three model rows + three steps comfortably]
        .frame(minWidth: 480, minHeight: 520)
    }

    // MARK: - Model command block

    @ViewBuilder
    private var modelCommandBlock: some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.sm) {
            ForEach(recommendedModels) { entry in
                VStack(alignment: .leading, spacing: SpeakSpacing.xs) {
                    Text(entry.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: SpeakSpacing.sm) {
                        Text("ollama pull \(entry.tag)")
                            .font(.speakMonoBody)
                            .textSelection(.enabled)
                            .padding(.horizontal, SpeakSpacing.sm)
                            .padding(.vertical, SpeakSpacing.xs)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.speakSurface)
                            )
                        Spacer()
                        if entry.recommended {
                            Text("Recommended")
                                .font(.caption)
                                .foregroundStyle(Color.speakAccent)
                                .padding(.horizontal, SpeakSpacing.xs)
                                .padding(.vertical, 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.speakAccent.opacity(0.12))
                                )
                        }
                    }
                    Text(entry.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(SpeakSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.speakSurface)
        )
    }
}

// MARK: - SetupStepRow

/// A numbered step row for the Ollama setup sheet.
struct SetupStepRow: View {
    let number: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: SpeakSpacing.md) {
            // Step number bubble — accent color, Monaco for the numeral.
            // [decision: 24pt bubble = 3× SpeakSpacing.sm; matches PrivacyGuaranteeRow icon column]
            Text(number)
                .font(.speakMonoBody)
                .foregroundStyle(.background)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.speakAccent))
            VStack(alignment: .leading, spacing: SpeakSpacing.xs) {
                Text(title)
                    .font(.speakMonoBody)
                Text(detail)
                    .font(.speakMonoCaption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Ollama Setup") {
    OllamaSetupSheet(isPresented: .constant(true))
}
#endif
