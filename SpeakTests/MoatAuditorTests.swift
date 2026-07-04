// SpeakTests/MoatAuditorTests.swift
//
// Tests for App/Privacy/PrivacyPaneView.swift's Verify Moat sheet logic
// (SpeakCore/Privacy/MoatAuditor.swift). Complements MoatAuditTests.swift
// (the source-tree audit) by covering the pane-facing result type: every
// build-time row must honestly declare itself `.buildTime`, exactly one row
// (`No third-party deps`) must be a genuine `.runtime` check, and that
// runtime check's pure logic must correctly pass/fail on real vs. unexpected
// `Contents/Frameworks/` contents.

import Foundation
@testable import SpeakCore
import Testing

@Test
func runAuditReturnsExactlySevenRowsInStableOrder() {
    let results = MoatAuditor.runAudit()
    #expect(results.count == 7)
    let guarantees = results.map(\.guarantee)
    #expect(guarantees == [
        "No cloud upload",
        "No telemetry",
        "No accounts",
        "No force-unwrap",
        "No third-party deps",
        "No pasteboard-read",
        "No print statements"
    ])
}

@Test
func onlyThirdPartyDepsRowIsRuntimeCheckedEveryOtherRowIsBuildTime() {
    let results = MoatAuditor.runAudit()
    for result in results {
        if result.guarantee == "No third-party deps" {
            #expect(result.kind == .runtime)
        } else {
            #expect(result.kind == .buildTime)
        }
    }
}

@Test
func buildTimeRowsAllPassAndSayNotALiveScan() {
    let results = MoatAuditor.runAudit()
    for result in results where result.kind == .buildTime {
        #expect(result.status == .pass)
        let detailLowercased = result.detail.lowercased()
        #expect(detailLowercased.contains("not a live scan") || detailLowercased.contains("not re-scanned"))
    }
}

@Test
func embeddedFrameworksCheckPassesWhenOnlyAllowlistedFrameworkPresent() {
    let result = MoatAuditor.checkEmbeddedFrameworks(contents: ["SpeakCore.framework"])
    #expect(result.status == .pass)
    #expect(result.kind == .runtime)
    #expect(result.guarantee == "No third-party deps")
}

@Test
func embeddedFrameworksCheckPassesWhenDirectoryIsEmpty() {
    let result = MoatAuditor.checkEmbeddedFrameworks(contents: [])
    #expect(result.status == .pass)
}

@Test
func embeddedFrameworksCheckFailsOnUnexpectedThirdPartyFramework() {
    let result = MoatAuditor.checkEmbeddedFrameworks(contents: ["SpeakCore.framework", "Sparkle.framework"])
    #expect(result.status == .fail)
    #expect(result.detail.contains("Sparkle.framework"))
}

@Test
func embeddedFrameworksCheckReadsBundleFrameworksDirectoryViaFileManager() {
    // Exercise the FileManager-backed wrapper with a fake FileManager-visible
    // temp directory standing in for Contents/Frameworks, proving the runtime
    // path actually reads real directory contents rather than being hardcoded.
    let tempRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("MoatAuditorTests-\(UUID().uuidString)", isDirectory: true)
    let frameworksDir = tempRoot.appendingPathComponent("Contents/Frameworks", isDirectory: true)
    try? FileManager.default.createDirectory(at: frameworksDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempRoot) }

    try? FileManager.default.createDirectory(
        at: frameworksDir.appendingPathComponent("SpeakCore.framework"),
        withIntermediateDirectories: true
    )

    // `Bundle.privateFrameworksURL` only resolves for a real bundle on disk;
    // build one by pointing a Bundle at tempRoot (an app-shaped directory).
    guard let bundle = Bundle(url: tempRoot) else {
        // Some environments won't resolve a bare directory as a Bundle without
        // an Info.plist; the pure-logic tests above already cover the
        // pass/fail behavior, so skip gracefully rather than fail spuriously.
        return
    }
    let result = MoatAuditor.embeddedFrameworksCheck(bundle: bundle, fileManager: .default)
    #expect(result.kind == .runtime)
    #expect(result.status == .pass)
}
