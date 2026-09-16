// SpeakCore/Eval/EvalScoring.swift
//
// Pure scoring functions for the small-models eval harness (roadmap SM-0).
// All functions are deterministic and have no side effects — suitable for both
// mock and live evaluation paths without modification.
//
// `#if DEBUG`: the eval harness is only consumed by SpeakTests (EvalHarnessTests,
// HistoryCleaningEvalTests, EvalScoringMetricRedesignTests), which always builds
// SpeakCore in Debug. Gating keeps the FM-scoring surface out of release binaries
// [audit fix — release-shipping dead code].
#if DEBUG

import Foundation

// MARK: - Tokenization

/// Punctuation stripped from the EDGES of a token before Jaccard comparison.
/// [decision 2026-07-04, adopted from SM-2 Phase0b live A/B research] Edge-trimming
/// sentence punctuation and quotes makes `tomorrow,` == `tomorrow.` == `tomorrow` for
/// prose overlap — confirmed empirically to fix false failures purely from trailing
/// punctuation (a real fixture scored 0.75, under the 0.80 pass threshold, on a
/// period-only mismatch before this fix). Exact matches (code/shell) bypass this via
/// the `equalsExpected` sentinel and never tokenize, so meaning-bearing punctuation
/// there is unaffected. We trim only the edges (internal `logger.info` stays one token).
private let jaccardEdgePunctuation = CharacterSet(charactersIn: ".,;:!?\"'`()[]{}…")

private func jaccardTokens(_ text: String) -> Set<String> {
    var tokens = Set<String>()
    for raw in text.lowercased().split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" || $0 == "\r" }) {
        let trimmed = String(raw).trimmingCharacters(in: jaccardEdgePunctuation)
        if !trimmed.isEmpty {
            tokens.insert(trimmed)
        }
    }
    return tokens
}

// MARK: - Correctness Metric

/// Compute the correctness score of an output against the expected text.
///
/// Metric: normalized Jaccard similarity over lowercased, edge-punctuation-normalized
/// word tokens. Jaccard(A,B) = |A ∩ B| / |A ∪ B|, where A = output tokens, B = expected tokens.
///
/// - Parameters:
///   - output: The actual cleaned text from the model.
///   - expected: The reference text to measure against.
/// - Returns: A Double in [0, 1] where 1.0 is perfect match and 0.0 is no overlap.
public func correctness(output: String, expected: String) -> Double {
    let outputTokens = jaccardTokens(output)
    let expectedTokens = jaccardTokens(expected)

    let intersection = outputTokens.intersection(expectedTokens).count
    let union = outputTokens.union(expectedTokens).count

    guard union > 0 else {
        // Both empty → perfect match.
        return 1.0
    }

    return Double(intersection) / Double(union)
}

/// Correctness against a SET of acceptable references — the max Jaccard over the set.
/// [decision 2026-07-04, adopted from SM-2 Phase0b] A generative fixture may have
/// several equally valid phrasings (e.g. an imperative AND a report form of a `fix`);
/// scoring against only one reference imposes a "single-phrasing ceiling" that fails
/// otherwise-correct paraphrases. Confirmed empirically: a valid fix-fragment output
/// scored 0.56 (below the 0.80 threshold) against one reference phrasing, 1.0 once the
/// accepted alternate phrasing was included.
///
/// - Parameters:
///   - output: The actual cleaned text from the model.
///   - references: One or more acceptable reference phrasings.
/// - Returns: The maximum Jaccard score across all references, or 0.0 if `references` is empty.
public func correctness(output: String, references: [String]) -> Double {
    guard !references.isEmpty else { return 0.0 }
    return references.map { correctness(output: output, expected: $0) }.max() ?? 0.0
}

// MARK: - Anti-hallucination guard

/// Heuristically extract identifier-like tokens from text: file paths, dotted paths,
/// camelCase / PascalCase symbols, snake_case, call expressions (`foo()`), and tokens
/// with a source-file extension.
/// [decision 2026-07-04, adopted from SM-2 Phase0b] Conservative by design — plain
/// prose words (no internal capital hump, no `/ _ . ()`) are never identifiers, so
/// generic English is not flagged.
func identifierCandidates(in text: String) -> [String] {
    let codeExtensions = ["swift", "py", "js", "ts", "md", "json", "txt", "log", "sh", "rb", "go", "rs", "c", "h", "m"]
    var result: [String] = []
    for raw in text.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" || $0 == "\r" }) {
        let token = String(raw).trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?\"'`"))
        if token.isEmpty { continue }
        let hasPathOrUnderscore = token.contains("/") || token.contains("_")
        let hasCall = token.contains("(")
        let hasCamelHump = token.range(of: "[a-z][A-Z]", options: .regularExpression) != nil
        let hasCodeExtension = codeExtensions.contains { token.lowercased().contains(".\($0)") }
        if hasPathOrUnderscore || hasCall || hasCamelHump || hasCodeExtension {
            result.append(token)
        }
    }
    return result
}

/// Decompose an identifier into its lowercased sub-words by splitting on path/dot/
/// underscore/paren separators AND camelCase boundaries. `PasteboardWriter.swift`
/// → {pasteboard, writer, swift}; `src/auth/token` → {src, auth, token}.
/// [decision 2026-07-04, adopted from SM-2 Phase0b] Sub-word decomposition lets
/// `noUnspokenIdentifiers` accept legitimate identifier-ization — "capture session"
/// (spoken) → "CaptureSession" (output) — while still catching a wholly invented
/// `AuthService.swift`.
func identifierSubwords(_ identifier: String) -> Set<String> {
    let separated = identifier.unicodeScalars.map { scalar -> Character in
        CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : " "
    }
    let coarse = String(separated).split(separator: " ").map(String.init)
    var subwords = Set<String>()
    for piece in coarse {
        let camelSplit = piece.replacingOccurrences(
            of: "([a-z0-9])([A-Z])",
            with: "$1 $2",
            options: .regularExpression
        )
        for word in camelSplit.split(separator: " ") {
            let lower = word.lowercased()
            if !lower.isEmpty { subwords.insert(lower) }
        }
    }
    return subwords
}

/// True iff EVERY identifier-like token in `output` is grounded in `spoken`: each of its
/// sub-words must appear among the spoken text's words. A violation = a hallucinated
/// path / symbol / error string the speaker never uttered — this feeds false context to
/// a downstream coding agent if it leaks.
/// [decision 2026-07-04, adopted from SM-2 Phase0b] Master had no anti-hallucination
/// guard prior to this; this closes that gap.
func noUnspokenIdentifiers(output: String, spoken: String) -> Bool {
    var spokenWords = Set<String>()
    for raw in spoken.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }) {
        spokenWords.insert(String(raw))
    }
    for ident in identifierCandidates(in: spoken) {
        spokenWords.formUnion(identifierSubwords(ident))
    }
    for ident in identifierCandidates(in: output) {
        let subwords = identifierSubwords(ident)
        for sub in subwords where !spokenWords.contains(sub) {
            return false
        }
    }
    return true
}

// MARK: - Format Checks

/// Describes a single format check that a fixture's output must satisfy.
///
/// Fixtures can declare multiple checks (e.g. `["startsWithCapital", "noTrailingPeriod"]`).
/// A fixture passes format checks iff ALL its checks pass.
public struct FormatCheck: Sendable {
    public let name: String
    public let predicate: @Sendable (String) -> Bool

    public init(_ name: String, check: @escaping @Sendable (String) -> Bool) {
        self.name = name
        self.predicate = check
    }
}

/// Registry of built-in format checks referenced by name in fixture definitions.
public enum BuiltInFormatChecks {
    private static let imperativeVerbs: Set<String> = [
        "Fix", "Add", "Build", "Refactor", "Explore", "Create", "Update", "Remove",
        "Write", "Set", "Break", "Optimize", "Implement", "Design", "Handle"
    ]

    private static let all: [String: FormatCheck] = [
        "startsWithCapital": FormatCheck("startsWithCapital") { text in
            guard let first = text.first else { return true } // Empty → passes
            return first.isUppercase
        },
        "noTrailingPeriod": FormatCheck("noTrailingPeriod") { text in
            !text.hasSuffix(".")
        },
        "equalsExpected": FormatCheck("equalsExpected") { _ in
            // Evaluated specially in the caller — placeholder predicate.
            true
        },
        "noFiller": FormatCheck("noFiller") { text in
            let lower = text.lowercased()
            let fillers = ["um", "uh", "basically", "you know", "i mean", "so i", "i think", "like"]
            return !fillers.contains { lower.contains($0) }
        },
        "imperativeStart": FormatCheck("imperativeStart") { text in
            guard let firstWord = text.split(separator: " ").first.map(String.init) else { return false }
            let stripped = firstWord.trimmingCharacters(in: .punctuationCharacters)
            return imperativeVerbs.contains(stripped)
        },
        "endsWithQuestion": FormatCheck("endsWithQuestion") { text in
            text.hasSuffix("?")
        },
        "noMarkdown": FormatCheck("noMarkdown") { text in
            !text.contains("```") && !text.contains("**") && !text.hasPrefix("#")
        },
        "conventionalCommitsFormat": FormatCheck("conventionalCommitsFormat") { text in
            let pattern = "^(feat|fix|docs|refactor|test|chore|style|perf|ci|build): .+"
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
            let range = NSRange(text.startIndex..., in: text)
            return regex.firstMatch(in: text, range: range) != nil
        }
    ]

    /// Parse and instantiate a format check from a string descriptor.
    ///
    /// - Parameters:
    ///   - descriptor: A check name or a parameterized check like `"maxWords:10"`.
    /// - Returns: A FormatCheck, or nil if the descriptor is unknown.
    public static func parse(_ descriptor: String) -> FormatCheck? {
        // Handle parameterized checks: "maxWords:N"
        if descriptor.hasPrefix("maxWords:") {
            let parts = descriptor.split(separator: ":", maxSplits: 1)
            guard parts.count == 2, let maxWords = Int(parts[1]) else {
                return nil
            }
            return FormatCheck("maxWords:\(maxWords)") { text in
                let wordCount = text.split(separator: " ").count
                return wordCount <= maxWords
            }
        }

        // Parameterized: "preservesTerms:X,Y,Z" — each term must appear in output (lowercased)
        if descriptor.hasPrefix("preservesTerms:") {
            let parts = descriptor.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { return nil }
            let terms = parts[1].split(separator: ",").map { $0.lowercased() }
            return FormatCheck(descriptor) { text in
                let lower = text.lowercased()
                return terms.allSatisfy { lower.contains($0) }
            }
        }

        // Parameterized: "maxSentences:N" — sentence count (split on ". ", ".\n", "?", "!") <= N
        if descriptor.hasPrefix("maxSentences:") {
            let parts = descriptor.split(separator: ":", maxSplits: 1)
            guard parts.count == 2, let maxSentences = Int(parts[1]) else { return nil }
            return FormatCheck(descriptor) { text in
                var count = 1
                var idx = text.startIndex
                while idx < text.endIndex {
                    let c = text[idx]
                    if c == "?" || c == "!" {
                        count += 1
                    } else if c == "." {
                        let next = text.index(after: idx)
                        if next < text.endIndex && (text[next] == " " || text[next] == "\n") {
                            count += 1
                        }
                    }
                    idx = text.index(after: idx)
                }
                return count <= maxSentences
            }
        }

        // Built-in checks
        return all[descriptor]
    }

    /// Evaluate a list of format check descriptors against the given text.
    ///
    /// - Parameters:
    ///   - descriptors: Array of check names (e.g. `["startsWithCapital", "maxWords:20"]`).
    ///   - text: The text to evaluate.
    /// - Returns: `(passed: Bool, failed: [String])` — passed is true iff all checks pass;
    ///   failed lists the names of checks that did not pass.
    public static func evaluateAll(_ descriptors: [String], against text: String) -> (passed: Bool, failed: [String]) {
        var failedChecks: [String] = []

        for descriptor in descriptors {
            // "equalsExpected" is a sentinel — it is handled by the harness separately
            // (compared against the expected text, not just the output in isolation).
            // Skip it here and let the caller decide.
            if descriptor == "equalsExpected" {
                continue
            }

            guard let check = parse(descriptor) else {
                // Unknown check — treat as a failure.
                failedChecks.append(descriptor)
                continue
            }

            if !check.predicate(text) {
                failedChecks.append(descriptor)
            }
        }

        return (failedChecks.isEmpty, failedChecks)
    }
}

// MARK: - Fixture Evaluation

/// Result of evaluating a single fixture.
public struct FixtureResult: Equatable {
    /// `true` if the fixture passed (correctness >= threshold AND all format checks pass).
    public let passed: Bool

    /// Correctness score in [0, 1].
    public let correctnessScore: Double

    /// List of format checks that failed. Empty if all passed.
    public let formatChecksFailed: [String]

    /// Latency in seconds (wall-clock). Zero for mock cleaner.
    public let latencySeconds: Double

    public init(
        passed: Bool,
        correctnessScore: Double,
        formatChecksFailed: [String] = [],
        latencySeconds: Double = 0.0
    ) {
        self.passed = passed
        self.correctnessScore = correctnessScore
        self.formatChecksFailed = formatChecksFailed
        self.latencySeconds = latencySeconds
    }
}

/// Evaluate a single fixture against expected output using the correctness metric
/// and format checks.
///
/// - Parameters:
///   - output: The actual cleaned text from the model.
///   - expected: The reference text to measure against.
///   - formatCheckDescriptors: Array of format check names (e.g., `["startsWithCapital"]`).
///     Special handling: if `"equalsExpected"` is present, it forces correctness == 1.0
///     to pass (i.e., the output must exactly match expected). Otherwise, correctness
///     is evaluated via Jaccard. [decision 2026-06-29]
///   - correctnessThreshold: Pass threshold for Jaccard score. Defaults to 0.80.
///   - latencySeconds: Wall-clock latency (for logging/stats). Defaults to 0.
/// - Returns: A FixtureResult capturing whether the fixture passed and diagnostic details.
public func evaluateFixture(
    output: String,
    expected: String,
    formatCheckDescriptors: [String] = [],
    correctnessThreshold: Double = 0.80,
    latencySeconds: Double = 0.0
) -> FixtureResult {
    // Special case: if "equalsExpected" is specified, require exact match.
    if formatCheckDescriptors.contains("equalsExpected") {
        let passed = output == expected
        return FixtureResult(
            passed: passed,
            correctnessScore: passed ? 1.0 : 0.0,
            formatChecksFailed: passed ? [] : ["equalsExpected"],
            latencySeconds: latencySeconds
        )
    }

    // Standard path: Jaccard correctness + format checks.
    let score = correctness(output: output, expected: expected)
    let (formatsPassed, formatsFailed) = BuiltInFormatChecks.evaluateAll(formatCheckDescriptors, against: output)

    let passed = (score >= correctnessThreshold) && formatsPassed

    return FixtureResult(
        passed: passed,
        correctnessScore: score,
        formatChecksFailed: formatsFailed,
        latencySeconds: latencySeconds
    )
}

/// Evaluate a single fixture using rubric scoring: score = fraction of checks passing.
///
/// Use this when a fixture defines a `checks[]` array instead of (or in addition to) an
/// `expected` string. All checks must pass for `passed` to be true.
///
/// - Parameters:
///   - output: The actual cleaned text from the model.
///   - checks: Array of format check descriptors (same syntax as `BuiltInFormatChecks.parse`).
///   - latencySeconds: Wall-clock latency. Defaults to 0.
/// - Returns: A FixtureResult where `correctnessScore` is the fraction of checks that passed.
public func evaluateFixtureRubric(
    output: String,
    checks: [String],
    latencySeconds: Double = 0.0
) -> FixtureResult {
    let (passed, failed) = BuiltInFormatChecks.evaluateAll(checks, against: output)
    let passedCount = checks.count - failed.count
    let score = checks.isEmpty ? 1.0 : Double(passedCount) / Double(checks.count)
    return FixtureResult(
        passed: passed,
        correctnessScore: score,
        formatChecksFailed: failed,
        latencySeconds: latencySeconds
    )
}

// MARK: - Percentile Computation

/// Compute the p50 (median) of a list of latencies using nearest-rank method.
///
/// [decision 2026-06-29] Nearest-rank percentile is simple and works for n >= 1.
/// For n == 1, returns the single value; for n == 2, returns the lower value for p50.
///
/// - Parameters:
///   - latencies: Array of latency values in seconds. Must not be empty.
/// - Returns: The p50 (median) latency, or 0 if the array is empty (defensive).
public func percentile50(_ latencies: [Double]) -> Double {
    guard !latencies.isEmpty else { return 0.0 }

    let sorted = latencies.sorted()
    let index = max(0, (sorted.count + 1) / 2 - 1)  // Nearest-rank for p50
    return sorted[index]
}

/// Compute the p95 of a list of latencies using nearest-rank method.
///
/// - Parameters:
///   - latencies: Array of latency values in seconds. Must not be empty.
/// - Returns: The p95 latency, or 0 if the array is empty (defensive).
public func percentile95(_ latencies: [Double]) -> Double {
    guard !latencies.isEmpty else { return 0.0 }

    let sorted = latencies.sorted()
    let index = max(0, (Int(Double(sorted.count) * 0.95) + 1) - 1)  // Nearest-rank for p95
    return sorted[min(index, sorted.count - 1)]
}

#endif
