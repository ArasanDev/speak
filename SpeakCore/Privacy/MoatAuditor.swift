// SpeakCore/Privacy/MoatAuditor.swift
//
// Computes the rows shown by the Privacy pane's "Verify Moat" sheet
// (App/Privacy/PrivacyPaneView.swift). Previously that sheet hardcoded all
// seven rows to "✅ PASS" regardless of any real state — theater on the one
// screen whose entire purpose is proving speak is trustworthy. This type
// replaces that with results that are honest about what kind of verification
// each guarantee actually represents.
//
// TWO KINDS OF GUARANTEE (`MoatVerificationKind`):
//
//   .runtime   — computed live, this launch, from real, currently-observable
//                process/bundle state.
//   .buildTime — a static property of the *source tree* (no networking code,
//                no auth code, no force-unwraps, no bare-print logging,
//                write-only pasteboard) enforced by tooling — SwiftLint,
//                `scripts/verify-moat.sh`, `SpeakTests/MoatAuditTests.swift` —
//                at build/CI time. A running app cannot re-derive "does my own
//                source talk to the network" about itself, so we do not
//                pretend to re-scan it on every button tap; we say plainly
//                that it's a build-time guarantee.
//
// [decision] speak is NOT App-Sandboxed in v0 — there is no `.entitlements`
// file anywhere in the project (confirmed by repo-wide grep at implementation
// time). That means there is no `com.apple.security.network.client`
// entitlement to check: that key is only meaningful *under* App Sandbox — its
// absence in a non-sandboxed app proves nothing about network access, because
// the OS does not enforce it either way. So "No cloud upload" cannot honestly
// be presented as an OS-enforced runtime fact here; it is a source-code
// guarantee (no networking symbols anywhere in SpeakCore/App/CLI), which is
// exactly what `scripts/verify-moat.sh` already checks in CI. We say so.
//
// The one row with a genuine, non-fake *live* signal available to a running,
// non-sandboxed macOS app is "No third-party deps": the actual contents of
// its own `Contents/Frameworks/` directory, checked against the allowlist
// implied by `project.yml` (only `SpeakCore.framework` is embedded). That is
// real runtime evidence about the binary that's actually running, not a
// restatement of a source-tree fact.
//
// TAGS: benchmark.md §3; AGENTS.md §2; quality.md §9

import Foundation

// MARK: - MoatVerificationKind

/// How a `MoatCheckResult` was actually established.
public enum MoatVerificationKind: String, Sendable, Equatable {
    /// Computed live, this launch, from real process/bundle state.
    case runtime
    /// A static fact about the source tree, enforced by build/CI tooling —
    /// not re-derived when the user taps "Verify Moat".
    case buildTime
}

// MARK: - MoatStatus

/// Outcome of one moat guarantee row.
public enum MoatStatus: String, Sendable, Equatable {
    case pass
    case fail
}

// MARK: - MoatCheckResult

/// One row of the Verify Moat sheet.
public struct MoatCheckResult: Equatable, Sendable, Identifiable {
    public var id: String { guarantee }

    public let guarantee: String
    public let status: MoatStatus
    public let detail: String
    public let kind: MoatVerificationKind

    public init(guarantee: String, status: MoatStatus, detail: String, kind: MoatVerificationKind) {
        self.guarantee = guarantee
        self.status = status
        self.detail = detail
        self.kind = kind
    }
}

// MARK: - MoatAuditor

/// Computes the Privacy pane's moat-audit rows.
public enum MoatAuditor {

    /// Names allowed inside the running app's `Contents/Frameworks/`
    /// directory. Per `project.yml`, only `SpeakCore` is embedded
    /// (`embed: true`) — every other Apple framework speak links
    /// (AVFoundation, Speech, FoundationModels, …) is system-provided and is
    /// never copied into the app bundle, so nothing else should ever appear
    /// here.
    static let allowedEmbeddedFrameworks: Set<String> = ["SpeakCore.framework"]

    // MARK: Runtime check — embedded frameworks

    /// Pure logic: given the actual directory listing of the running app's
    /// `Contents/Frameworks/`, is every entry on the allowlist? Separated from
    /// bundle/file-system access so it's unit-testable without a real `.app`.
    static func checkEmbeddedFrameworks(contents: [String]) -> MoatCheckResult {
        let unexpected = contents.filter { !allowedEmbeddedFrameworks.contains($0) }
        if unexpected.isEmpty {
            let found = contents.isEmpty ? "(directory absent or empty)" : contents.joined(separator: ", ")
            return MoatCheckResult(
                guarantee: "No third-party deps",
                status: .pass,
                detail: "Live scan of this running app's Contents/Frameworks/ just now: \(found). "
                    + "Apple frameworks are system-provided and never embedded, so SpeakCore.framework "
                    + "is the only expected entry.",
                kind: .runtime
            )
        } else {
            return MoatCheckResult(
                guarantee: "No third-party deps",
                status: .fail,
                detail: "Live scan of this running app's Contents/Frameworks/ just now found unexpected "
                    + "item(s) not on the allowlist: \(unexpected.joined(separator: ", ")).",
                kind: .runtime
            )
        }
    }

    /// Reads the real `Contents/Frameworks/` directory of `bundle` and runs
    /// the check above. Defaults to `Bundle.main` / `FileManager.default` for
    /// production use; both are injectable for tests.
    static func embeddedFrameworksCheck(bundle: Bundle, fileManager: FileManager) -> MoatCheckResult {
        guard let frameworksURL = bundle.privateFrameworksURL,
              let contents = try? fileManager.contentsOfDirectory(atPath: frameworksURL.path) else {
            // No Frameworks directory at all is itself a valid pass — nothing embedded.
            return checkEmbeddedFrameworks(contents: [])
        }
        return checkEmbeddedFrameworks(contents: contents)
    }

    // MARK: Build-time guarantees

    /// Static facts about the source tree, enforced by SwiftLint /
    /// `scripts/verify-moat.sh` / `MoatAuditTests.swift` rather than observed
    /// live. These never change within a single build, so they're plain data,
    /// not a function of runtime state.
    static let noCloudUpload = MoatCheckResult(
        guarantee: "No cloud upload",
        status: .pass,
        detail: "No networking code of any kind appears anywhere in source. "
            + "speak is not App-Sandboxed in v0 (no .entitlements file), so this is not OS-enforced by "
            + "entitlements — it's a source-code guarantee, continuously checked by scripts/verify-moat.sh "
            + "in CI. Not re-scanned on this tap.",
        kind: .buildTime
    )

    static let noTelemetry = MoatCheckResult(
        guarantee: "No telemetry",
        status: .pass,
        detail: "No analytics/telemetry frameworks or symbols in source — every import in SpeakCore/App/CLI "
            + "is checked against an Apple-only allowlist by scripts/verify-moat.sh in CI. Not a live scan.",
        kind: .buildTime
    )

    static let noAccounts = MoatCheckResult(
        guarantee: "No accounts",
        status: .pass,
        detail: "No login/auth code path exists — no Sign in with Apple, identity provider, or "
            + "credential storage anywhere in source. Enforced by scripts/verify-moat.sh in CI. Not a live scan.",
        kind: .buildTime
    )

    static let noForceUnwrap = MoatCheckResult(
        guarantee: "No force-unwrap",
        status: .pass,
        detail: "SwiftLint's force_unwrapping rule is severity: error (.swiftlint.yml) — every build fails if "
            + "one is introduced into production code. Not re-scanned on this tap.",
        kind: .buildTime
    )

    static let noPasteboardRead = MoatCheckResult(
        guarantee: "No pasteboard-read",
        status: .pass,
        detail: "PasteboardWriter only ever writes to the system pasteboard — it never reads back existing "
            + "clipboard contents. Enforced by scripts/verify-moat.sh symbol scan in CI. Not a live scan.",
        kind: .buildTime
    )

    static let noPrintStatements = MoatCheckResult(
        guarantee: "No print statements",
        status: .pass,
        detail: "Production code logs exclusively through os.Logger (SpeakLog). Enforced by "
            + "scripts/verify-moat.sh source grep in CI. Not a live scan.",
        kind: .buildTime
    )

    // MARK: - Full audit

    /// Full ordered set of rows shown by the Verify Moat sheet: six build-time
    /// guarantees plus the one genuine runtime check, in the pane's original
    /// display order.
    public static func runAudit(bundle: Bundle = .main, fileManager: FileManager = .default) -> [MoatCheckResult] {
        [
            noCloudUpload,
            noTelemetry,
            noAccounts,
            noForceUnwrap,
            embeddedFrameworksCheck(bundle: bundle, fileManager: fileManager),
            noPasteboardRead,
            noPrintStatements
        ]
    }
}
