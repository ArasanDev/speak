// SpeakTests/EngineCoreTests.swift
//
// Proves the framework-agnostic engine core compiles and the pluggable seams
// (`Transcribing`, `LLMCleaning`) are usable from another module with mock
// engines. This is the verification that the SwiftPM harness is green before
// the framework-bound engines (SpeechAnalyzer, Foundation Models) arrive.
//
// Uses swift-testing (`import Testing`) rather than XCTest: XCTest ships only
// inside full Xcode, whereas swift-testing is part of the Swift toolchain, so
// these run under Command Line Tools alone. When the Xcode `SpeakTests` target
// is created, swift-testing is equally supported there.

import Foundation
@testable import SpeakCore
import Testing

// MARK: SpeakError

@Test
func recoverySuggestionsAreUserFacing() {
    #expect(SpeakError.microphoneDenied.recoverySuggestion.contains("Microphone"))
    #expect(SpeakError.accessibilityDenied.recoverySuggestion.contains("Accessibility"))
    #expect(SpeakError.sessionCancelled.recoverySuggestion == "Session cancelled.")
    #expect(SpeakError.llmCleanupFailed("boom").recoverySuggestion.contains("boom"))
}

// MARK: Transcribing seam

@Test
func mockTranscriberStreamsPartialsThenFinal() async throws {
    let transcriber = MockTranscriber(script: ["hel", "hello", "hello world"])
    #expect(transcriber.id == "mock-stt")

    var chunks: [TranscriptChunk] = []
    for try await chunk in transcriber.startStream(locale: Locale(identifier: "en-US")) {
        chunks.append(chunk)
    }

    #expect(chunks.count == 3)
    #expect(chunks[0].isFinal == false)
    #expect(chunks[1].isFinal == false)
    #expect(chunks[2].isFinal == true)
    #expect(chunks.last?.text == "hello world")
}

// MARK: LLMCleaning seam

@Test
func mockCleanerIsAvailableAndRemovesFillers() async throws {
    let cleaner = MockCleaner()
    #expect(await cleaner.isAvailable)

    let cleaned = try await cleaner.clean("um hello uh world", mode: .punctuation)
    #expect(cleaned == "hello world")
}

// MARK: TranscriptionResult shape

@Test
func transcriptionResultCarriesProvenance() {
    let now = Date()
    let result = TranscriptionResult(
        rawText: "hello world",
        cleanedText: "Hello, world.",
        duration: 1.2,
        engineId: "mock-stt",
        createdAt: now
    )
    #expect(result.rawText == "hello world")
    #expect(result.cleanedText == "Hello, world.")
    #expect(result.engineId == "mock-stt")
    #expect(result.createdAt == now)
}

// MARK: - Mocks

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
