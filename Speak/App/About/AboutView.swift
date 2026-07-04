// App/About/AboutView.swift
//
// The About pane — app identity, version, system info, and links to the community.
//
// DESIGN (W3.1):
//   Headline + tagline establish the product voice. Version and build info are
//   auto-detected from the bundle, macOS version from ProcessInfo, and architecture
//   from compile-time introspection (#if arch). Links are compile-time URL literals
//   with the no-force-unwrap pattern (`map` guard). All text uses Monaco for the
//   content voice per SpeakTheme; system font for labels (per existing pattern).
//
// THREADING:
//   All SwiftUI view bodies are implicitly @MainActor.
//   System version and architecture detection are O(1) at view init time.
//
// DESIGN LANGUAGE:
//   Monaco for headlines, data, and credits. System font for labels.
//   SpeakTheme colors (accent, surface) and SpeakSpacing grid.
//   No force-unwrap, no magic strings. [decision: W3.1]

import SpeakCore
import SwiftUI

// MARK: - AboutView

struct AboutView: View {

    // MARK: - URL constants (compile-time literals, mapped at call site)

    fileprivate static let githubURL = URL(string: "https://github.com/tamilarasanraja/speak")
    fileprivate static let issuesURL = URL(string: "https://github.com/tamilarasanraja/speak/issues")
    fileprivate static let contributingURL = URL(string: "https://github.com/tamilarasanraja/speak/blob/main/CONTRIBUTING.md")
    fileprivate static let changelogURL = URL(string: "https://github.com/tamilarasanraja/speak/blob/main/CHANGELOG.md")

    // MARK: - Version & build detection

    // Version string from the bundle: "0.0.1" from CFBundleShortVersionString.
    // [verified: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String]
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    }

    // Build number from the bundle: "1" from CFBundleVersion.
    // [verified: Bundle.main.infoDictionary?["CFBundleVersion"] as? String]
    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
    }

    // Build configuration: "Debug" or "Release" based on compilation flags.
    // [decision: #if DEBUG is the platform-standard introspection; matches Xcode and CI]
    private var buildConfiguration: String {
        #if DEBUG
        return "Debug"
        #else
        return "Release"
        #endif
    }

    // macOS version: e.g., "macOS 26.5" or "macOS unknown" if detection fails.
    // [verified: ProcessInfo.processInfo.operatingSystemVersion is the standard way
    //  to read the kernel version tuple on macOS; Foundation.OperatingSystemVersion
    //  has `majorVersion`, `minorVersion`, `patchVersion` fields]
    private var macOSVersion: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(version.majorVersion).\(version.minorVersion)"
    }

    // Architecture string: "Apple Silicon" (ARM64) or "Intel" (x86_64).
    // [decision: #if arch(arm64) is compile-time introspection; resolved at build time.
    //  This view is shipped for Apple Silicon only per AGENTS.md, so "Apple Silicon"
    //  is the only result in practice, but the clause is transparent and portable.]
    private var architecture: String {
        #if arch(arm64)
        return "Apple Silicon"
        #else
        return "Intel"
        #endif
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SpeakSpacing.lg) {

                // MARK: - Headline block

                VStack(alignment: .center, spacing: SpeakSpacing.md) {
                    // Icon
                    Image(systemName: "waveform")
                        .font(.system(size: 48))
                        .foregroundStyle(Color.speakAccent)

                    // Headline: "speak v0.0.1"
                    HStack(spacing: SpeakSpacing.xs) {
                        Text("speak")
                            .font(.speakMonoTitle)
                        Text("v\(appVersion)")
                            .font(.speakMonoCaption)
                            .foregroundStyle(.secondary)
                    }

                    // Tagline
                    Text("Speech → text → clean writing, 100% on your device")
                        .font(.speakMonoCaption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                .frame(maxWidth: .infinity)
                .padding(SpeakSpacing.md)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.speakSurface)
                )

                // MARK: - System info

                VStack(alignment: .leading, spacing: SpeakSpacing.md) {
                    SystemInfoRow(label: "Version", value: appVersion)
                    Divider()
                    SystemInfoRow(label: "Build", value: "\(buildNumber) (\(buildConfiguration))")
                    Divider()
                    SystemInfoRow(label: "macOS", value: macOSVersion)
                    Divider()
                    SystemInfoRow(label: "Architecture", value: architecture)
                }
                .padding(SpeakSpacing.lg)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.speakSurface)
                )

                // MARK: - Quick links

                VStack(alignment: .leading, spacing: SpeakSpacing.sm) {
                    Text("Quick Links")
                        .font(.speakMonoBody)
                        .foregroundStyle(.primary)
                        .padding(.bottom, SpeakSpacing.xs)

                    // GitHub repo
                    AboutView.githubURL.map { url in
                        Link(destination: url) {
                            HStack {
                                Image(systemName: "link")
                                    .foregroundStyle(.secondary)
                                Text("View on GitHub")
                                    .font(.speakMonoCaption)
                                    .foregroundStyle(Color.speakAccent)
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, SpeakSpacing.sm)
                        }
                    }

                    // Issues / bug reports
                    AboutView.issuesURL.map { url in
                        Link(destination: url) {
                            HStack {
                                Image(systemName: "exclamationmark.circle")
                                    .foregroundStyle(.secondary)
                                Text("Report an issue")
                                    .font(.speakMonoCaption)
                                    .foregroundStyle(Color.speakAccent)
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, SpeakSpacing.sm)
                        }
                    }

                    // Contributing guide
                    AboutView.contributingURL.map { url in
                        Link(destination: url) {
                            HStack {
                                Image(systemName: "person.badge.plus")
                                    .foregroundStyle(.secondary)
                                Text("Learn how to contribute")
                                    .font(.speakMonoCaption)
                                    .foregroundStyle(Color.speakAccent)
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, SpeakSpacing.sm)
                        }
                    }

                    // Changelog
                    AboutView.changelogURL.map { url in
                        Link(destination: url) {
                            HStack {
                                Image(systemName: "list.bullet.clipboard")
                                    .foregroundStyle(.secondary)
                                Text("What's new")
                                    .font(.speakMonoCaption)
                                    .foregroundStyle(Color.speakAccent)
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, SpeakSpacing.sm)
                        }
                    }
                }
                .padding(SpeakSpacing.lg)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.speakSurface)
                )

                // MARK: - Credits

                VStack(alignment: .leading, spacing: SpeakSpacing.md) {
                    Text("Credits")
                        .font(.speakMonoBody)
                        .foregroundStyle(.primary)

                    VStack(alignment: .leading, spacing: SpeakSpacing.sm) {
                        CreditRow(
                            icon: "bolt.circle",
                            title: "Speech Recognition",
                            detail: "Apple SpeechAnalyzer"
                        )

                        CreditRow(
                            icon: "brain.head.profile",
                            title: "AI Neat-Writing",
                            detail: "Apple Foundation Models"
                        )

                        CreditRow(
                            icon: "lock.open",
                            title: "License",
                            detail: "MIT — free, forever"
                        )
                    }
                }
                .padding(SpeakSpacing.lg)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.speakSurface)
                )

                Spacer()
                    .frame(height: SpeakSpacing.md)
            }
            .padding(SpeakSpacing.lg)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - SystemInfoRow

/// A single system info row: label + value in Monaco.
private struct SystemInfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
            Spacer()
            Text(value)
                .font(.speakMonoCaption)
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
    }
}

// MARK: - CreditRow

/// A single credit row: icon + title + detail.
private struct CreditRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: SpeakSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(Color.speakAccent)
                .frame(width: 24, alignment: .center)

            VStack(alignment: .leading, spacing: SpeakSpacing.xs) {
                Text(title)
                    .font(.speakMonoCaption)
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("About") {
    AboutView()
}
#endif
