// App/Privacy/PrivacyPaneView.swift
//
// The Privacy pane — speak's trust-building centerpiece. This is where users
// understand the core moat: 100% local, no cloud, no account, no telemetry.
//
// Layout:
//   Headline: "Nothing Leaves Your Device"
//   Visual Guarantees: 5 rows (microphone, transcripts, cleanup, hotkey, offline)
//   [Verify Moat] button → sheet with audit results
//   Trust Links: source code, license, report concern
//   Comparison: Wispr vs. speak (factual, not marketing)
//
// Chrome uses system font; content uses Monaco where appropriate. Colors are
// semantic: green for local guarantees, red for what we don't do.

import SpeakCore
import SwiftUI

// MARK: - PrivacyPaneView

struct PrivacyPaneView: View {
    let context: DashboardContext

    @State private var showMoatResults = false
    @State private var moatResults: [MoatCheckResult] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: SpeakSpacing.lg) {
                    headline

                    VStack(alignment: .leading, spacing: SpeakSpacing.sm) {
                        guaranteeRow("Microphone: Processed Locally", "Deleted immediately, never uploaded")
                        guaranteeRow("Transcripts: Stored Locally", "Searchable archive, your Mac only")
                        guaranteeRow("Cleanup: On-Device Only", "Foundation Models run locally, no API calls")
                        guaranteeRow("Hotkey: Global, Not Tracked", "No analytics, no telemetry, just listening")
                        guaranteeRow("Offline: Works 100%", "Zero internet required, always ready")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    verifyButton

                    Divider()
                        .padding(.vertical, SpeakSpacing.sm)

                    trustLinks

                    Divider()
                        .padding(.vertical, SpeakSpacing.sm)

                    comparisonSection
                }
                .padding(.horizontal, SpeakSpacing.lg)
                .padding(.vertical, SpeakSpacing.md)
            }
        }
        .sheet(isPresented: $showMoatResults) {
            MoatResultsSheet(results: moatResults)
        }
    }

    // MARK: - Headline

    private var headline: some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.xs) {
            HStack(spacing: SpeakSpacing.sm) {
                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.15))
                        .frame(width: 32, height: 32)
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.green)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Nothing Leaves Your Device")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Color.speakBone)
                    Text("100% local architecture. Zero cloud APIs, zero telemetry, zero accounts.")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.speakMica)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(SpeakSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.speakSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.speakCardBorder, lineWidth: 1)
        )
    }

    // MARK: - Guarantee Rows

    private func guaranteeRow(_ title: String, _ description: String) -> some View {
        HStack(spacing: SpeakSpacing.md) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.green)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.speakBone)
                Text(description)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.speakMica)
            }
            Spacer(minLength: 0)
        }
        .padding(SpeakSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.speakSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.speakCardBorder, lineWidth: 1)
        )
    }

    // MARK: - Verify Moat Button

    private var verifyButton: some View {
        Button(action: {
            moatResults = MoatAuditor.runAudit()
            showMoatResults = true
        }) {
            HStack(spacing: SpeakSpacing.sm) {
                Image(systemName: "shield.checkmark.fill")
                    .font(.system(size: 14, weight: .semibold))
                Text("Verify Privacy & Security Moat")
                    .font(.system(size: 13, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .background(
                LinearGradient(
                    colors: [Color.speakUIAccent.opacity(0.9), Color.speakUIAccent],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .foregroundStyle(Color.speakOnAccent)
            .cornerRadius(8)
            .shadow(color: Color.speakUIAccent.opacity(0.3), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Trust Links

    private var trustLinks: some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.sm) {
            Text("Transparency & Open Source")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.speakBone)

            HStack(spacing: SpeakSpacing.md) {
                trustLinkCard("Source Code", "github.com", "https://github.com/tamilarasanraja14/speak", icon: "code")
                trustLinkCard("MIT License", "Open Source", "https://github.com/tamilarasanraja14/speak/blob/main/LICENSE", icon: "doc.text")
                trustLinkCard("Report Concern", "GitHub Issues", "https://github.com/tamilarasanraja14/speak/issues", icon: "exclamationmark.bubble")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func trustLinkCard(_ title: String, _ subtitle: String, _ url: String, icon: String) -> some View {
        Button(action: { openURL(url) }) {
            VStack(alignment: .leading, spacing: SpeakSpacing.xs) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.speakUIAccent)
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.speakBone)
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.speakMica)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(SpeakSpacing.sm + 2)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.speakSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.speakCardBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Comparison Section

    private var comparisonSection: some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.md) {
            Text("Architecture Comparison")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.speakBone)

            HStack(alignment: .top, spacing: SpeakSpacing.md) {
                VStack(alignment: .leading, spacing: SpeakSpacing.xs) {
                    Text("Cloud Competitors")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.red.opacity(0.9))

                    comparisonItem("Cloud Upload", "Audio sent to third-party servers")
                    comparisonItem("Account Required", "Login & tracking tied to email")
                    comparisonItem("Subscription Tiers", "Word limits & monthly subscriptions")
                }
                .padding(SpeakSpacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.red.opacity(0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.red.opacity(0.15), lineWidth: 1)
                )

                VStack(alignment: .leading, spacing: SpeakSpacing.xs) {
                    Text("speak Architecture")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.green.opacity(0.9))

                    comparisonItem("100% Local On-Device", "SpeechAnalyzer & Apple Silicon")
                    comparisonItem("Zero Account Needed", "Instant open-source dictation")
                    comparisonItem("100% Free Forever", "Unlimited dictation & neat-writing")
                }
                .padding(SpeakSpacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.green.opacity(0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.green.opacity(0.15), lineWidth: 1)
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func comparisonItem(_ label: String, _ description: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Color.speakBone)
            Text(description)
                .font(.system(size: 11))
                .foregroundStyle(Color.speakMica)
                .padding(.leading, 16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Helpers

    private func openURL(_ urlString: String) {
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Privacy") {
    PrivacyPaneView(context: DashboardContext(
        settingsStore: SettingsStore(),
        historyStore: PreviewNullHistoryStore(),
        hotkeyCombo: ["Fn", "Fn"]
    ))
    .frame(width: 620, height: 600)
}
#endif
