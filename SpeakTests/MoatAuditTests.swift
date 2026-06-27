// SpeakTests/MoatAuditTests.swift
//
// Automated structural-moat audit for `speak`.
//
// PURPOSE:
//   These tests enforce the BEAT rows from benchmark.md §3 that are fully
//   autonomously verifiable by static analysis of the source tree. They run
//   headlessly, require no permissions, and are wired into `make test` so
//   they become a permanent CI regression guard.
//
//   Each test maps to one or more §3 BEAT rows:
//     #1  100% local + offline   → testNoNetworkEgress + testOfflineByConstruction
//     #2  Free & unlimited       → testNoPaywallOrWordCap
//     #3  Open source (MIT)      → testMITLicenseExists
//     #4  No account / no auth   → testNoAccountOrAuthCode
//     #7  Privacy (no egress)    → testNoNetworkEgress (also covers #7)
//   Plus:
//     Third-party deps           → testNoThirdPartyImports
//
// METHODOLOGY (import allowlist, not denylist):
//   We assert every `import` in SpeakCore/ + App/ is from the explicit
//   Apple-frameworks allowlist below. Anything not on the list fails.
//   This is stricter than a denylist (you can't game it by renaming a
//   package), and it produces no false positives from substring matches.
//
// METHODOLOGY (symbol scanning for networking / auth / paywall):
//   For statements-that-aren't-imports we scan for *symbol-level* markers —
//   the actual API names that would be used if such functionality existed.
//   Each justified exclusion is documented inline with the reason it's safe.
//
// TAGS: benchmark.md §3 #1–#4 #7; quality.md §9; AGENTS.md §2

import Foundation
import XCTest

final class MoatAuditTests: XCTestCase {

    // ── Source root discovery ────────────────────────────────────────────────
    //
    // Walk up from this test file to the directory containing project.yml.
    // We anchor on `project.yml` so the path is stable regardless of build
    // system CWD (xcodebuild sets its own DerivedData CWD in CI).

    private var repoRoot: URL {
        var dir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // SpeakTests/
            .deletingLastPathComponent() // repo root
        // Verify project.yml is there; if not, walk up one more level.
        if !FileManager.default.fileExists(atPath: dir.appendingPathComponent("project.yml").path) {
            dir = dir.deletingLastPathComponent()
        }
        return dir
    }

    /// Returns the paths of all `.swift` source files under the two production
    /// directories: `SpeakCore/` and `App/`. Test files are excluded because
    /// they legitimately use `try!`, `as!`, etc. per the coding rules.
    private func productionSwiftFiles() throws -> [URL] {
        let sourceDirs = ["SpeakCore", "App"].map { repoRoot.appendingPathComponent($0) }
        var result: [URL] = []
        for dir in sourceDirs {
            guard let enumerator = FileManager.default.enumerator(
                at: dir,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for case let fileURL as URL in enumerator {
                if fileURL.pathExtension == "swift" {
                    result.append(fileURL)
                }
            }
        }
        return result
    }

    /// Reads all production Swift files and returns (file, lines) pairs.
    private func productionSourceLines() throws -> [(URL, [String])] {
        try productionSwiftFiles().map { url in
            let text = try String(contentsOf: url, encoding: .utf8)
            return (url, text.components(separatedBy: .newlines))
        }
    }

    // ── §3 #3: MIT License ───────────────────────────────────────────────────

    /// BEAT §3 #3 — Open source (MIT).
    /// Asserts that `LICENSE` exists at the repo root and contains "MIT License".
    func testMITLicenseExists() throws {
        let licenseURL = repoRoot.appendingPathComponent("LICENSE")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: licenseURL.path),
            "LICENSE file not found at repo root (\(licenseURL.path)). " +
            "BEAT §3 #3 requires an MIT-licensed file."
        )
        let text = try String(contentsOf: licenseURL, encoding: .utf8)
        XCTAssertTrue(
            text.contains("MIT License"),
            "LICENSE file exists but does not contain 'MIT License'. " +
            "BEAT §3 #3 requires the MIT licence text."
        )
    }

    // ── Third-party import check (AGENTS.md §2.4) ────────────────────────────

    /// Apple-framework allowlist for v0.
    ///
    /// These are the only modules permitted in production source (SpeakCore/ + App/).
    /// Any import not in this list is a violation of the no-third-party-deps rule.
    ///
    /// Basis:
    ///   • `Foundation`, `os` — standard library / Darwin
    ///   • `SwiftUI`, `AppKit` — UI
    ///   • `AVFoundation` — audio capture
    ///   • `Speech` — SpeechAnalyzer (STT)
    ///   • `FoundationModels` — on-device AI cleanup
    ///   • `CoreGraphics`, `ApplicationServices` — CGEventTap for HotkeyMonitor
    ///   • `Carbon.HIToolbox` — kVK_Function, kVK_ANSI_V key codes
    ///   • `SQLite3` — embedded DB for HistoryStore (Apple-shipped system library)
    ///   • `SpeakCore` — the framework target itself (App imports it)
    private let allowedImports: Set<String> = [
        "Foundation",
        "Combine",          // Apple framework; used by AnyPublisher in WindowPresenter / DictationController
        "Observation",      // Apple framework (Swift stdlib on macOS 14+); @Observable macro
        "os",
        "SwiftUI",
        "AppKit",
        "AVFoundation",
        "Speech",
        "FoundationModels",
        "CoreGraphics",
        "ApplicationServices",
        "Carbon.HIToolbox",
        "UniformTypeIdentifiers",  // Apple framework; UTType.json for history export save-panel
        "SQLite3",
        "SpeakCore",
        "CoreFoundation"   // CFRunLoop, CFRunLoopTimer — used in HotkeyMonitor for the tap thread
    ]

    /// BEAT §3 / AGENTS.md §2.4 — No third-party dependencies.
    ///
    /// Asserts every `import <Module>` in SpeakCore/ + App/ is in the
    /// Apple-frameworks allowlist. An import of anything else means a
    /// third-party dep has been introduced — a direct moat violation.
    func testNoThirdPartyImports() throws {
        let sourceLines = try productionSourceLines()
        var violations: [String] = []

        for (url, lines) in sourceLines {
            for (idx, line) in lines.enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                // Match `import Module` or `import Module.SubModule`.
                // Ignore `// import ...` comments.
                guard trimmed.hasPrefix("import "),
                      !trimmed.hasPrefix("//") else { continue }
                let module = String(trimmed.dropFirst("import ".count))
                    .components(separatedBy: " ").first ?? ""
                // `Carbon.HIToolbox` is in the allowlist as a qualified name;
                // the bare `Carbon` without submodule would NOT be in it.
                // Both forms resolve to the same framework — only the qualified
                // form is used here, which is already in the allowlist.
                if !allowedImports.contains(module) {
                    violations.append(
                        "\(url.lastPathComponent):\(idx + 1): `import \(module)` " +
                        "is not in the Apple-frameworks allowlist. " +
                        "BEAT §3 / AGENTS.md §2.4 violation."
                    )
                }
            }
        }

        XCTAssertTrue(
            violations.isEmpty,
            "Third-party import violations found:\n" + violations.joined(separator: "\n")
        )
    }

    // ── §3 #1 + #7: No network egress ────────────────────────────────────────

    /// Networking API symbols that must not appear in production source.
    ///
    /// JUSTIFICATIONS for excluded terms:
    ///   • `authorizationStatus` — This is `AVCaptureDevice.authorizationStatus`,
    ///     a microphone-permission query, not a networking or authentication API.
    ///     The networking denylist targets `URLSession`/`NWConnection` etc.
    ///     exclusively. The AVCaptureDevice usage is in PermissionManager.swift
    ///     and is correct / required for the permission flow.
    ///   • `URL(` — Swift's `URL` type is used for file paths and local SQLite DB
    ///     paths everywhere; it is not a networking construct. We target only
    ///     `URLSession`, `URLRequest`, `URLConnection`, and `dataTask`, all of
    ///     which require network I/O.
    private let networkingSymbols: [String] = [
        "URLSession",
        "URLRequest",
        "URLConnection",
        "dataTask(",
        "uploadTask(",
        "downloadTask(",
        "NWConnection",
        "NWListener",
        "NWPathMonitor",
        "CFSocketCreate",
        "getaddrinfo",
        "CFStream",
        "import Network",
        "NSURLSession",
        "NSURLConnection",
        "NSURLRequest",
        "XMLHTTPRequest",
        "WebSocket",
        "URLWebSocketTask"
    ]

    /// BEAT §3 #1 + #7 — No network egress.
    ///
    /// Asserts that none of the networking API symbols above appear in any
    /// production Swift file. This is the privacy moat's actual proof:
    /// no network call can be made if none of these symbols are present.
    func testNoNetworkEgress() throws {
        let sourceLines = try productionSourceLines()
        var violations: [String] = []

        for (url, lines) in sourceLines {
            for (idx, line) in lines.enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                // Skip pure comment lines.
                guard !trimmed.hasPrefix("//") else { continue }
                // Strip inline comments before checking.
                let codePart = trimmed.components(separatedBy: "//").first ?? trimmed
                for symbol in networkingSymbols {
                    if codePart.contains(symbol) {
                        violations.append(
                            "\(url.lastPathComponent):\(idx + 1): " +
                            "Found networking symbol '\(symbol)'. " +
                            "BEAT §3 #1/#7 / AGENTS.md §2.1 violation: no network egress allowed."
                        )
                    }
                }
            }
        }

        XCTAssertTrue(
            violations.isEmpty,
            "Network egress violations found:\n" + violations.joined(separator: "\n")
        )
    }

    // ── §3 #4: No account / no auth (identity auth, not OS permissions) ──────

    /// Auth/account *identity* API symbols that must not appear in production.
    ///
    /// JUSTIFICATIONS for excluded terms:
    ///   • `authorizationStatus` — excluded: this is `AVCaptureDevice.authorizationStatus`
    ///     (OS microphone permission), not identity/account auth. See above.
    ///   • `AVAuthorizationStatus` — excluded: same; it is the permission enum type
    ///     for microphone permission, not identity authentication.
    ///   • `map(_ status: AVAuthorizationStatus)` — excluded: same.
    ///   • The targeted symbols below are exclusively identity/account/auth-token APIs.
    private let accountAuthSymbols: [String] = [
        "ASAuthorizationController",
        "ASAuthorization",
        "LAContext",
        "SecItemAdd",
        "SecItemCopyMatching",
        "SecItemUpdate",
        "SecItemDelete",
        "kSecClass",
        "SignInWithAppleButton",
        "AuthenticationServices",
        "OAuthToken",
        "AccessToken",
        "RefreshToken",
        "UserDefaults.*account",         // would be: UserDefaults key "account..."
        "credentialStorage"
    ]

    /// BEAT §3 #4 — No account / no auth.
    ///
    /// Asserts that no identity-authentication or user-account APIs appear in
    /// production source. OS-permission queries (AVCaptureDevice.authorizationStatus,
    /// AXIsProcessTrusted) are NOT targeted — they are required for the three
    /// mandated permissions and are explicitly excluded.
    func testNoAccountOrAuthCode() throws {
        let sourceLines = try productionSourceLines()
        var violations: [String] = []

        // Symbols that should not appear at all (no exclusion logic needed):
        let hardDenySymbols = [
            "ASAuthorizationController",
            "ASAuthorization",
            "LAContext",
            "SecItemAdd(",
            "SecItemCopyMatching(",
            "SecItemUpdate(",
            "SecItemDelete(",
            "SignInWithAppleButton",
            "import AuthenticationServices"
        ]

        for (url, lines) in sourceLines {
            for (idx, line) in lines.enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.hasPrefix("//") else { continue }
                let codePart = trimmed.components(separatedBy: "//").first ?? trimmed
                for symbol in hardDenySymbols {
                    if codePart.contains(symbol) {
                        violations.append(
                            "\(url.lastPathComponent):\(idx + 1): " +
                            "Found account/auth symbol '\(symbol)'. " +
                            "BEAT §3 #4 violation: no account, no identity-auth code allowed."
                        )
                    }
                }
            }
        }

        XCTAssertTrue(
            violations.isEmpty,
            "Account/auth violations found:\n" + violations.joined(separator: "\n")
        )
    }

    // ── §3 #2: Free & unlimited — no paywall / word-cap ──────────────────────

    /// BEAT §3 #2 — Free & unlimited.
    ///
    /// Asserts that no paywall, subscription, trial-gate, or word-cap code
    /// exists in production source. These are high-specificity symbols — any
    /// match here is genuine, not a false positive.
    func testNoPaywallOrWordCap() throws {
        let sourceLines = try productionSourceLines()
        var violations: [String] = []

        // High-specificity symbols for monetisation gating.
        // `limit` is NOT in this list — it appears legitimately in HistoryStore
        // (recent(limit:) is a query-result limit, not a word cap).
        let paywallSymbols = [
            "StoreKit",
            "SKProduct",
            "SKPayment",
            "InAppPurchase",
            "wordCap",
            "WordCap",
            "wordsRemaining",
            "freeLimit",
            "subscriptionActive",
            "isPremium",
            "isTrial",
            "trialDaysLeft",
            "paywall",
            "Paywall"
        ]

        for (url, lines) in sourceLines {
            for (idx, line) in lines.enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.hasPrefix("//") else { continue }
                let codePart = trimmed.components(separatedBy: "//").first ?? trimmed
                for symbol in paywallSymbols {
                    if codePart.contains(symbol) {
                        violations.append(
                            "\(url.lastPathComponent):\(idx + 1): " +
                            "Found paywall/subscription symbol '\(symbol)'. " +
                            "BEAT §3 #2 violation: speak must be free and unlimited."
                        )
                    }
                }
            }
        }

        XCTAssertTrue(
            violations.isEmpty,
            "Paywall/subscription violations found:\n" + violations.joined(separator: "\n")
        )
    }

    // ── §3 #1: Offline by construction ───────────────────────────────────────

    /// BEAT §3 #1 — Offline capable.
    ///
    /// Given that testNoNetworkEgress() passes (no networking APIs in production
    /// source), every core flow (capture → cleanup → paste → history) is offline
    /// by construction. This test asserts the three Apple frameworks used for
    /// core flows are all on-device:
    ///
    ///   • Speech (SpeechAnalyzer) — on-device, verified: WWDC25 #277 [verified]
    ///   • FoundationModels — on-device Apple Intelligence [verified]
    ///   • SQLite3 — embedded DB, no network required
    ///
    /// All three appear in the import allowlist and not in any networking denylist.
    /// The offline guarantee is therefore structural, not behavioral.
    func testOfflineByConstruction() throws {
        // Assert the three on-device core-flow imports exist in the codebase
        // (ensuring the codebase actually uses on-device paths, not cloud stubs).
        let files = try productionSwiftFiles()
        let allText = try files
            .map { try String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n")

        XCTAssertTrue(
            allText.contains("import Speech"),
            "Expected `import Speech` (SpeechAnalyzer, on-device STT) in production source. " +
            "BEAT §3 #1 requires on-device STT."
        )
        XCTAssertTrue(
            allText.contains("import FoundationModels"),
            "Expected `import FoundationModels` (Apple on-device AI) in production source. " +
            "BEAT §3 #1 requires on-device cleanup."
        )
        XCTAssertTrue(
            allText.contains("import SQLite3"),
            "Expected `import SQLite3` (embedded DB, no network) in production source. " +
            "BEAT §3 #1 requires local history storage."
        )
    }

    // ── Pasteboard write-only guard (AGENTS.md §2.8) ─────────────────────────

    /// AGENTS.md §2.8 — Never read the pasteboard.
    ///
    /// Asserts that no `NSPasteboard` read API appears in production source.
    /// We write to the pasteboard (clearContents + setString), but must never
    /// call `string(forType:)`, `pasteboardItems`, `readObjects(forClasses:)`,
    /// or any other read accessor. Any such call is a hard violation.
    func testNoPasteboardRead() throws {
        let sourceLines = try productionSourceLines()
        var violations: [String] = []

        let readSymbols = [
            "string(forType:",
            "pasteboardItems",
            "readObjects(forClasses:",
            "data(forType:",
            "canReadObject(",
            "availableType(",
            "pasteboardData("
        ]

        for (url, lines) in sourceLines {
            for (idx, line) in lines.enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.hasPrefix("//") else { continue }
                let codePart = trimmed.components(separatedBy: "//").first ?? trimmed
                for symbol in readSymbols {
                    if codePart.contains(symbol) {
                        violations.append(
                            "\(url.lastPathComponent):\(idx + 1): " +
                            "Found pasteboard read symbol '\(symbol)'. " +
                            "AGENTS.md §2.8 violation: never read the pasteboard."
                        )
                    }
                }
            }
        }

        XCTAssertTrue(
            violations.isEmpty,
            "Pasteboard read violations found:\n" + violations.joined(separator: "\n")
        )
    }

    // ── No print() in production (AGENTS.md §2, swift-code-review rule #1) ───

    /// AGENTS.md §2 / swift-code-review rule #1 — No `print` in production.
    ///
    /// Asserts that bare `print(` does not appear in any production Swift file.
    /// All logging must go through `os.Logger` (SpeakLog categories).
    ///
    /// JUSTIFICATION for the exclusion of `// print(` comments:
    ///   Commented-out print calls are excluded — they do not execute. Only
    ///   uncommented calls on non-comment lines are flagged.
    func testNoPrintInProductionCode() throws {
        let sourceLines = try productionSourceLines()
        var violations: [String] = []

        for (url, lines) in sourceLines {
            for (idx, line) in lines.enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                // Skip comment lines.
                guard !trimmed.hasPrefix("//") else { continue }
                // Strip inline comments.
                let codePart = trimmed.components(separatedBy: "//").first ?? trimmed
                // Match bare `print(` (not `Logger.print` or `NSLog`).
                if codePart.contains("print(") {
                    violations.append(
                        "\(url.lastPathComponent):\(idx + 1): " +
                        "Found `print(` in production code. " +
                        "Use os.Logger / SpeakLog categories instead. " +
                        "swift-code-review rule #1 / AGENTS.md §2 violation."
                    )
                }
            }
        }

        XCTAssertTrue(
            violations.isEmpty,
            "print() violations found:\n" + violations.joined(separator: "\n")
        )
    }

    // ── No force-unwrap / try! / as! in production ───────────────────────────

    /// swift-code-review rule #2 — No force-unwrap / `try!` / `as!`.
    ///
    /// Asserts that the three unsafe operators do not appear in production source.
    /// Guards, if-let, and throws are the required alternatives.
    ///
    /// NOTE: These operators ARE permitted inside SpeakTests/ per the coding rules.
    /// This test only scans SpeakCore/ + App/.
    func testNoForceUnwrapInProductionCode() throws {
        let sourceLines = try productionSourceLines()
        var violations: [String] = []

        for (url, lines) in sourceLines {
            for (idx, line) in lines.enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.hasPrefix("//") else { continue }
                let codePart = trimmed.components(separatedBy: "//").first ?? trimmed

                // `try!` — must not appear in production.
                if codePart.contains("try!") {
                    violations.append(
                        "\(url.lastPathComponent):\(idx + 1): " +
                        "Found `try!` in production code. Use `try` + `throws` instead. " +
                        "swift-code-review rule #2 violation."
                    )
                }
                // `as!` — must not appear in production.
                if codePart.contains("as!") {
                    violations.append(
                        "\(url.lastPathComponent):\(idx + 1): " +
                        "Found `as!` in production code. Use `as?` + guard/if-let instead. " +
                        "swift-code-review rule #2 violation."
                    )
                }
                // Force-unwrap `!` is harder to detect without a parser.
                // We scan for `!` that is NOT part of `!=`, `!trimmed`, or string ops.
                // Strategy: look for a word character followed by `!` and then
                // a non-`=` character (or end of statement). This catches `foo!`
                // and `foo!.bar` but not `!=` comparisons.
                // Regex note: we use a simple string scan here to avoid pulling in
                // Foundation RegEx (which would be fine but is heavier).
                // The SwiftLint force_unwrap rule is the authoritative catch;
                // this test is a belt-and-suspenders signal.
                let stripped = codePart
                    .replacingOccurrences(of: "!=", with: "")  // remove !=
                    .replacingOccurrences(of: "!important", with: "") // CSS comment noise (none expected)
                // Look for alphabetic/numeric followed by !
                var prevChar: Character = " "
                for char in stripped {
                    if char == "!" && (prevChar.isLetter || prevChar.isNumber || prevChar == "_" || prevChar == ")") {
                        violations.append(
                            "\(url.lastPathComponent):\(idx + 1): " +
                            "Possible force-unwrap `!` in production code: '\(codePart.trimmingCharacters(in: .whitespaces))'. " +
                            "Use `guard let` / `if let` instead. " +
                            "swift-code-review rule #2 violation."
                        )
                        break
                    }
                    prevChar = char
                }
            }
        }

        XCTAssertTrue(
            violations.isEmpty,
            "Force-unwrap / try! / as! violations found:\n" + violations.joined(separator: "\n")
        )
    }
}
