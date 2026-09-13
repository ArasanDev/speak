// App/Settings/AboutSettingsTab.swift
//
// The "About" tab of Settings. Split out of SettingsView.swift to keep that
// file under SwiftLint's file_length cap — same pattern as HUDStyleSection.

import SpeakCore
import SwiftUI

// MARK: - AboutSettingsTab

struct AboutSettingsTab: View {

    // Static URL constants — compile-time literals guaranteed non-nil, but
    // URL(string:) returns Optional so we store as URL? and map at the call site
    // rather than force-unwrap. [decision: P11-c — no force-unwrap rule]
    fileprivate static let githubURL = URL(string: "https://github.com/ArasanDev/speak")
    fileprivate static let issuesURL = URL(string: "https://github.com/ArasanDev/speak/issues")
    fileprivate static let changelogURL = URL(string: "https://github.com/ArasanDev/speak/blob/main/CHANGELOG.md")

    // Version string from the bundle — zero magic strings. [decision: P11-c]
    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        return [version, build.map { "(\($0))" }]
            .compactMap { $0 }
            .joined(separator: " ")
    }

    // Build configuration — compile-time introspection, matches Xcode/CI.
    private var buildConfiguration: String {
        #if DEBUG
        return "Debug"
        #else
        return "Release"
        #endif
    }

    // "macOS 26.5 · Apple Silicon" — the environment this build is running on.
    // [verified: ProcessInfo.operatingSystemVersion tuple; #if arch(arm64)]
    private var systemSummary: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        #if arch(arm64)
        let arch = "Apple Silicon"
        #else
        let arch = "Intel"
        #endif
        return "macOS \(version.majorVersion).\(version.minorVersion) · \(arch) · \(buildConfiguration)"
    }

    var body: some View {
        VStack(spacing: SpeakSpacing.lg) {
            Spacer()

            // Brand mark: the amber waveform — the human channel is the brand
            // (intentional brand color, kept across themes). App name in the
            // display face; version/build metadata in the mono data face.
            VStack(spacing: SpeakSpacing.sm) {
                Image(systemName: "waveform")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.speakHumanAmber)
                Text("speak")
                    .font(.speakDisplay())
                    .foregroundStyle(Color.speakBone)
                if !appVersion.isEmpty {
                    Text("v\(appVersion)")
                        .font(.speakMonoFace(.caption))
                        .foregroundStyle(Color.speakMica)
                }
                Text(systemSummary)
                    .font(.speakMonoFace(.caption))
                    .foregroundStyle(Color.speakMica)
                Text("Free · Open-source · MIT")
                    .font(.speakBody(.caption))
                    .foregroundStyle(Color.speakMica)
            }

            Divider()
                .overlay(Color.speakCardBorder.opacity(0.6))
                .frame(maxWidth: 200)  // [decision: short decorative divider, visual balance]

            // Links — URL(string:) with compile-time literals always succeeds, but
            // force-unwrap is banned by the hard rules. Use static lets so the
            // compiler can prove the optionality at the call site. [decision: P11-c]
            VStack(spacing: SpeakSpacing.sm) {
                AboutSettingsTab.githubURL.map { url in
                    Link("View on GitHub", destination: url)
                        .font(.speakBody(.caption))
                }
                AboutSettingsTab.changelogURL.map { url in
                    Link("What's new", destination: url)
                        .font(.speakBody(.caption))
                }
                AboutSettingsTab.issuesURL.map { url in
                    Link("Report an issue", destination: url)
                        .font(.speakBody(.caption))
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(SpeakSpacing.lg)
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Settings — About") {
    AboutSettingsTab()
        .frame(minWidth: 760, minHeight: 520)
}
#endif

/// A single privacy guarantee row: icon + title + detail. Shared by the
/// Settings ▸ Privacy "On-Device Moat" card. The `speakOK` tint is semantic —
/// these are healthy/nominal guarantees, not a decorated brand green.
struct PrivacyGuaranteeRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: SpeakSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(Color.speakOK)
                .frame(width: 24)  // [decision: 24pt icon column width = 3× SpeakSpacing.sm]
            VStack(alignment: .leading, spacing: SpeakSpacing.xs) {
                Text(title)
                    .font(.speakBody(.base))
                    .foregroundStyle(Color.speakBone)
                Text(detail)
                    .font(.speakBody(.caption))
                    .foregroundStyle(Color.speakMica)
            }
        }
    }
}
