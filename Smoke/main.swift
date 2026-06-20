// Smoke/main.swift
//
// TEMPORARY runtime verification for the framework-agnostic engine core,
// runnable under Command Line Tools alone (XCTest/swift-testing require full
// Xcode). Mirrors SpeakTests/EngineCoreTests.swift; exits non-zero on the first
// failed check. Delete once Xcode is installed and `SpeakTests` runs natively.

import Foundation
import SpeakCore

// MARK: Mocks (mirror the canonical test fixtures)

private struct MockTranscriber: Transcribing {
    let id = "mock-stt"
    let script: [String]

    func startStream(locale: Locale) -> AsyncThrowingStream<TranscriptChunk, Error> {
        AsyncThrowingStream { continuation in
            for (index, text) in script.enumerated() {
                let isFinal = index == script.count - 1
                continuation.yield(TranscriptChunk(text: text, isFinal: isFinal, timestamp: Date()))
            }
            continuation.finish()
        }
    }

    func stop() async {}
}

private struct MockCleaner: LLMCleaning {
    let id = "mock-cleaner"
    var isAvailable: Bool { get async { true } }

    func clean(_ text: String, mode: CleanupMode) async throws -> String {
        let fillers: Set<String> = ["um", "uh", "er", "ah"]
        return text
            .split(separator: " ")
            .filter { !fillers.contains($0.lowercased()) }
            .joined(separator: " ")
    }
}

// MARK: Checks

@MainActor
func run() async {
    var failures = 0
    func check(_ condition: Bool, _ label: String) {
        if condition {
            print("  ok    \(label)")
        } else {
            FileHandle.standardError.write(Data("  FAIL  \(label)\n".utf8))
            failures += 1
        }
    }

    // SpeakError
    check(SpeakError.microphoneDenied.recoverySuggestion.contains("Microphone"), "SpeakError.microphoneDenied suggestion")
    check(SpeakError.accessibilityDenied.recoverySuggestion.contains("Accessibility"), "SpeakError.accessibilityDenied suggestion")
    check(SpeakError.inputMonitoringDenied.recoverySuggestion.contains("Input Monitoring"), "SpeakError.inputMonitoringDenied suggestion")
    check(SpeakError.sessionCancelled.recoverySuggestion == "Session cancelled.", "SpeakError.sessionCancelled suggestion")
    check(SpeakError.llmCleanupFailed("boom").recoverySuggestion.contains("boom"), "SpeakError.llmCleanupFailed carries detail")

    // Transcribing seam
    let transcriber = MockTranscriber(script: ["hel", "hello", "hello world"])
    check(transcriber.id == "mock-stt", "Transcriber id")
    var chunks: [TranscriptChunk] = []
    do {
        for try await chunk in transcriber.startStream(locale: Locale(identifier: "en-US")) {
            chunks.append(chunk)
        }
    } catch {
        check(false, "Transcriber stream threw: \(error)")
    }
    check(chunks.count == 3, "Transcriber yields 3 chunks")
    check(chunks.first?.isFinal == false, "First chunk is partial")
    check(chunks.last?.isFinal == true, "Last chunk is final")
    check(chunks.last?.text == "hello world", "Final chunk text")

    // LLMCleaning seam
    let cleaner = MockCleaner()
    let available = await cleaner.isAvailable
    check(available, "Cleaner reports available")
    do {
        let cleaned = try await cleaner.clean("um hello uh world", mode: .punctuation)
        check(cleaned == "hello world", "Cleaner removes fillers")
    } catch {
        check(false, "Cleaner threw: \(error)")
    }

    // TranscriptionResult shape
    let now = Date()
    let result = TranscriptionResult(rawText: "hello world",
                                     cleanedText: "Hello, world.",
                                     duration: 1.2,
                                     engineId: "mock-stt",
                                     createdAt: now)
    check(result.rawText == "hello world", "Result rawText")
    check(result.cleanedText == "Hello, world.", "Result cleanedText")
    check(result.engineId == "mock-stt", "Result engineId")
    check(result.createdAt == now, "Result createdAt")

    // Logging compiles + emits (no assertion — just exercise the path)
    SpeakLog.engine.debug("smoke: engine-core verification run")

    if failures == 0 {
        print("\nAll engine-core smoke checks passed.")
    } else {
        FileHandle.standardError.write(Data("\n\(failures) check(s) FAILED.\n".utf8))
        exit(1)
    }
}

await run()
