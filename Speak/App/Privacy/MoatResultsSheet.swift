// App/Privacy/MoatResultsSheet.swift
//
// The "Verify Moat" results sheet — extracted from PrivacyPaneView so both the
// dashboard Privacy pane and the Settings "Privacy & System Health" category
// present one audit surface. Renders the `[MoatCheckResult]` array produced by
// `MoatAuditor.runAudit()`.

import SpeakCore
import SwiftUI

// MARK: - MoatResultsSheet

struct MoatResultsSheet: View {
    let results: [MoatCheckResult]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.lg) {
            HStack(spacing: SpeakSpacing.sm) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.green)
                Text("Moat Audit Results")
                    .font(.system(size: 17, weight: .semibold))
                Spacer()
                Button(
                    action: { dismiss() },
                    label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                )
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ScrollView {
                VStack(alignment: .leading, spacing: SpeakSpacing.md) {
                    ForEach(results) { result in
                        MoatResultRow(result: result)
                    }

                    Divider()
                        .padding(.vertical, SpeakSpacing.sm)

                    Text(
                        "\"Runtime\" rows were just measured against this running app. \"Build-time\" rows are "
                            + "static source-tree guarantees enforced by SwiftLint and scripts/verify-moat.sh in "
                            + "CI — they are not re-scanned by this button."
                    )
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(SpeakSpacing.md)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .controlBackgroundColor)))
                }
            }

            Button(
                action: { dismiss() },
                label: {
                    Text("Close")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .foregroundStyle(.primary)
                        .cornerRadius(6)
                }
            )
            .buttonStyle(.plain)

            Spacer(minLength: 0)
        }
        .padding(SpeakSpacing.lg)
        .frame(minWidth: 400, minHeight: 500)
    }
}

// MARK: - MoatResultRow

private struct MoatResultRow: View {
    let result: MoatCheckResult

    var body: some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.xs) {
            HStack(spacing: SpeakSpacing.sm) {
                Text(result.guarantee)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer(minLength: SpeakSpacing.sm)
                Text(result.status == .pass ? "PASS" : "FAIL")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(result.status == .pass ? .green : .red)
            }

            Text(kindLabel(result.kind))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color(nsColor: .separatorColor).opacity(0.3)))

            Text(result.detail)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(SpeakSpacing.md)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .controlBackgroundColor)))
    }

    private func kindLabel(_ kind: MoatVerificationKind) -> String {
        switch kind {
        case .runtime:
            return "LIVE — checked just now"

        case .buildTime:
            return "BUILD-TIME — enforced by CI, not a live scan"
        }
    }
}
