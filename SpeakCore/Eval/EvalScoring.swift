// SpeakCore/Eval/EvalScoring.swift
//
// Pure scoring functions for the small-models eval harness (roadmap SM-0).
// All functions are deterministic and have no side effects — suitable for both
// mock and live evaluation paths without modification.

import Foundation

// MARK: - Correctness Metric

/// Compute the correctness score of an output against the expected text.
///
/// Metric: normalized Jaccard similarity over lowercased, whitespace-tokenized words.
/// Jaccard(A,B) = |A ∩ B| / |A ∪ B|, where A = output tokens, B = expected tokens.
///
/// [decision 2026-06-29] Jaccard over tokens is simple, language-agnostic, and
/// handles prose well. Limitations: punctuation is folded into words (e.g. "text." ≠ "text");
/// this is acceptable for small-model quality gates. Exact matches (e.g. CLI commands)
/// should use `equalsExpected` formatCheck instead.
///
/// - Parameters:
///   - output: The actual cleaned text from the model.
///   - expected: The reference text to measure against.
/// - Returns: A Double in [0, 1] where 1.0 is perfect match and 0.0 is no overlap.
public func correctness(output: String, expected: String) -> Double {
    let outputTokens = Set(output.lowercased().split(separator: " ").map(String.init))
    let expectedTokens = Set(expected.lowercased().split(separator: " ").map(String.init))

    let intersection = outputTokens.intersection(expectedTokens).count
    let union = outputTokens.union(expectedTokens).count

    guard union > 0 else {
        // Both empty → perfect match.
        return 1.0
    }

    return Double(intersection) / Double(union)
}

// MARK: - Format Checks

/// Describes a single format check that a fixture's output must satisfy.
///
/// Fixtures can declare multiple checks (e.g. `["startsWithCapital", "noTrailingPeriod"]`).
/// A fixture passes format checks iff ALL its checks pass.
public struct FormatCheck {
    public let name: String
    public let predicate: (String) -> Bool

    public init(_ name: String, check: @escaping (String) -> Bool) {
        self.name = name
        self.predicate = check
    }
}

/// Registry of built-in format checks referenced by name in fixture definitions.
public enum BuiltInFormatChecks {
    private static let all: [String: FormatCheck] = [
        "startsWithCapital": FormatCheck("startsWithCapital") { text in
            guard let first = text.first else { return true } // Empty → passes
            return first.isUppercase
        },
        "noTrailingPeriod": FormatCheck("noTrailingPeriod") { text in
            !text.hasSuffix(".")
        },
        "equalsExpected": FormatCheck("equalsExpected") { _ in
            // This check is evaluated specially in the caller — it compares
            // output == expected directly, not via a single-string predicate.
            // The predicate here is a placeholder; the harness interprets
            // "equalsExpected" as a flag to do exact comparison instead of Jaccard.
            true
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
