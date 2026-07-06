// App/Settings/AboutSettingsTab.swift
//
// The "About" tab of Settings. Split out of SettingsView.swift to keep that
// file under SwiftLint's file_length cap — same pattern as HUDStyleSection.

import SpeakCore
import SwiftUI

// MARK: - 6. About

struct AboutSettingsTab: View {

    // Static URL constants — compile-time literals guaranteed non-nil, but
    // URL(string:) returns Optional so we store as URL? and map at the call site
    // rather than force-unwrap. [decision: P11-c — no force-unwrap rule]
    fileprivate static let githubURL = URL(string: "https://github.com/tamilarasanraja/speak")
    fileprivate static let issuesURL = URL(string: "https://github.com/tamilarasanraja/speak/issues")

    // Version string from the bundle — zero magic strings. [decision: P11-c]
    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        return [version, build.map { "(\($0))" }]
            .compactMap { $0 }
            .joined(separator: " ")
    }

    var body: some View {
        VStack(spacing: SpeakSpacing.lg) {
            Spacer()

            // App name + version in Monaco — content voice, not chrome.
            VStack(spacing: SpeakSpacing.sm) {
                Image(systemName: "waveform")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.speakAccent)
                Text("speak")
                    .font(.speakMonoTitle)
                if !appVersion.isEmpty {
                    Text("v\(appVersion)")
                        .font(.speakMonoCaption)
                        .foregroundStyle(.secondary)
                }
                Text("Free · Open-source · MIT")
                    .font(.speakMonoCaption)
                    .foregroundStyle(.secondary)
            }

            Divider()
                .frame(maxWidth: 200)  // [decision: short decorative divider, visual balance]

            // Links — URL(string:) with compile-time literals always succeeds, but
            // force-unwrap is banned by the hard rules. Use static lets so the
            // compiler can prove the optionality at the call site. [decision: P11-c]
            VStack(spacing: SpeakSpacing.sm) {
                AboutSettingsTab.githubURL.map { url in
                    Link("View on GitHub", destination: url)
                        .font(.speakMonoCaption)
                }
                AboutSettingsTab.issuesURL.map { url in
                    Link("Report an issue", destination: url)
                        .font(.speakMonoCaption)
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(SpeakSpacing.lg)
    }
}
