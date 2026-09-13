// App/Privacy/PrivacyPaneView.swift
//
// The Privacy pane — speak's trust-building centerpiece. This is where users
// understand the core moat: 100% local, no cloud, no account, no telemetry.
//
// Layout:
//   Headline: "Nothing Leaves Your Device"
//   Visual Guarantees: 5 rows in one grouped card (mic, transcripts, cleanup,
//     hotkey, offline)
//   [Verify Moat] button → sheet with audit results
//   Trust Links: source code, license, report concern
//   Comparison: cloud competitors vs. speak (factual, not marketing)
//
// Design contract: speakCard/speakInset surfaces, speakBody chrome, mono for
// data. Colors are semantic — `speakOK` for local guarantees, `speakError`
// for what we don't do. The comparison's red/green contrast is intentional:
// it IS the data (design-contract exception), expressed through the themed
// error/ok roles so it still repaints with the active theme.

import AppKit
import SpeakCore
import SwiftUI

// MARK: - PrivacyPaneView

struct PrivacyPaneView: View {
    let context: DashboardContext

    @State private var showMoatResults = false
    @State private var moatResults: [MoatCheckResult] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SpeakSpacing.lg) {
                headline

                guaranteesCard

                verifyButton

                hairline

                trustLinks

                hairline

                comparisonSection
            }
            .padding(.horizontal, SpeakSpacing.lg)
            .padding(.vertical, SpeakSpacing.md)
        }
        .sheet(isPresented: $showMoatResults) {
            MoatResultsSheet(results: moatResults)
        }
    }

    /// Theme-aware hairline — the same tint `SettingsRowSeparator` uses.
    private var hairline: some View {
        Divider()
            .overlay(Color.speakCardBorder.opacity(0.6))
            .padding(.vertical, SpeakSpacing.xs)
    }

    // MARK: - Headline

    private var headline: some View {
        HStack(spacing: SpeakSpacing.md) {
            ZStack {
                Circle()
                    .fill(Color.speakOK.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.speakOK)
            }

            VStack(alignment: .leading, spacing: SpeakSpacing.xs) {
                Text("Nothing Leaves Your Device")
                    .font(.speakDisplay(.title))
                    .foregroundStyle(Color.speakBone)
                Text("100% local architecture. Zero cloud APIs, zero telemetry, zero accounts.")
                    .font(.speakBody(.caption))
                    .foregroundStyle(Color.speakMica)
            }

            Spacer(minLength: 0)
        }
        .padding(SpeakSpacing.md)
        .speakCard()
    }

    // MARK: - Guarantee rows

    private var guaranteesCard: some View {
        VStack(spacing: 0) {
            guaranteeRow(
                icon: "mic.slash.fill",
                title: "Microphone: processed locally",
                detail: "Audio is transcribed on-device and deleted immediately — never uploaded."
            )
            rowSeparator
            guaranteeRow(
                icon: "doc.text.magnifyingglass",
                title: "Transcripts: stored locally",
                detail: "A searchable archive that lives on your Mac only."
            )
            rowSeparator
            guaranteeRow(
                icon: "brain.head.profile",
                title: "Cleanup: on-device only",
                detail: "Apple Foundation Models run locally — no API calls, no account."
            )
            rowSeparator
            guaranteeRow(
                icon: "keyboard",
                title: "Hotkey: global, not tracked",
                detail: "No analytics, no telemetry — just listening for your gesture."
            )
            rowSeparator
            guaranteeRow(
                icon: "wifi.slash",
                title: "Offline: works 100%",
                detail: "Zero internet required — dictation is always ready."
            )
        }
        .speakCard()
    }

    private var rowSeparator: some View {
        Divider()
            .overlay(Color.speakCardBorder.opacity(0.6))
            .padding(.leading, SpeakSpacing.md + 20 + SpeakSpacing.md)
    }

    private func guaranteeRow(icon: String, title: String, detail: String) -> some View {
        HStack(spacing: SpeakSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.speakOK)
                .frame(width: 20, alignment: .center)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.speakBody(.base, semibold: true))
                    .foregroundStyle(Color.speakBone)
                Text(detail)
                    .font(.speakBody(.caption))
                    .foregroundStyle(Color.speakMica)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, SpeakSpacing.md)
        .padding(.vertical, SpeakSpacing.sm + 4)
    }

    // MARK: - Verify moat button

    private var verifyButton: some View {
        Button(
            action: {
                moatResults = MoatAuditor.runAudit()
                showMoatResults = true
            },
            label: {
                HStack(spacing: SpeakSpacing.sm) {
                    Image(systemName: "shield.checkmark.fill")
                    Text("Verify Privacy & Security Moat")
                        .font(.speakBody(.base, semibold: true))
                }
                .frame(maxWidth: .infinity)
            }
        )
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(.speakUIAccent)
    }

    // MARK: - Trust links

    private var trustLinks: some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.sm) {
            Text("Transparency & Open Source")
                .font(.speakBody(.base, semibold: true))
                .foregroundStyle(Color.speakBone)

            HStack(spacing: SpeakSpacing.md) {
                trustLinkCard(
                    "Source Code", "github.com",
                    "https://github.com/ArasanDev/speak",
                    icon: "chevron.left.forwardslash.chevron.right"
                )
                trustLinkCard(
                    "MIT License", "Open source",
                    "https://github.com/ArasanDev/speak/blob/main/LICENSE",
                    icon: "doc.text"
                )
                trustLinkCard(
                    "Report Concern", "GitHub Issues",
                    "https://github.com/ArasanDev/speak/issues",
                    icon: "exclamationmark.bubble"
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func trustLinkCard(_ title: String, _ subtitle: String, _ url: String, icon: String) -> some View {
        Button(
            action: { openURL(url) },
            label: {
                VStack(alignment: .leading, spacing: SpeakSpacing.xs) {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.speakUIAccent)
                    Text(title)
                        .font(.speakBody(.caption, semibold: true))
                        .foregroundStyle(Color.speakBone)
                    Text(subtitle)
                        .font(.speakBody(.caption))
                        .foregroundStyle(Color.speakMica)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(SpeakSpacing.sm + 2)
                .speakCard(cornerRadius: 8)
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        )
        .buttonStyle(.plain)
    }

    // MARK: - Comparison section
    //
    // The red/green contrast here is intentional and load-bearing — it IS the
    // data (design-contract exception). Expressed through the themed
    // `speakError` / `speakOK` roles so the comparison still repaints with
    // the active theme instead of pinning raw system colors.

    private var comparisonSection: some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.md) {
            Text("Architecture Comparison")
                .font(.speakBody(.base, semibold: true))
                .foregroundStyle(Color.speakBone)

            HStack(alignment: .top, spacing: SpeakSpacing.md) {
                comparisonColumn(
                    title: "Cloud Competitors",
                    tint: .speakError,
                    items: [
                        ("Cloud upload", "Audio sent to third-party servers"),
                        ("Account required", "Login & tracking tied to email"),
                        ("Subscription tiers", "Word limits & monthly fees")
                    ]
                )

                comparisonColumn(
                    title: "speak Architecture",
                    tint: .speakOK,
                    items: [
                        ("100% local on-device", "SpeechAnalyzer on Apple Silicon"),
                        ("Zero account needed", "Instant open-source dictation"),
                        ("100% free forever", "Unlimited dictation & neat-writing")
                    ]
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func comparisonColumn(
        title: String,
        tint: Color,
        items: [(String, String)]
    ) -> some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.sm) {
            Text(title)
                .font(.speakBody(.caption, semibold: true))
                .foregroundStyle(tint)

            ForEach(items, id: \.0) { label, description in
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.speakBody(.caption, semibold: true))
                        .foregroundStyle(Color.speakBone)
                    Text(description)
                        .font(.speakBody(.caption))
                        .foregroundStyle(Color.speakMica)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(SpeakSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(tint.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(tint.opacity(0.15), lineWidth: 1)
        )
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
