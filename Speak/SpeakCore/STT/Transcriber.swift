// SpeakCore/STT/Transcriber.swift
//
// The speech-to-text seam. Every STT engine (Apple SpeechAnalyzer in v0,
// WhisperKit/whisper.cpp later) conforms to `Transcribing`, so the engine is
// pluggable. Signatures are verbatim from `docs/architecture.md` §6.

import Foundation

public protocol Transcribing: Sendable {
    var id: String { get }
    func startStream(locale: Locale) -> AsyncThrowingStream<TranscriptChunk, Error>
    func stop() async
}

public struct TranscriptChunk: Sendable {
    public let text: String
    public let isFinal: Bool
    public let timestamp: Date

    public init(text: String, isFinal: Bool, timestamp: Date) {
        self.text = text
        self.isFinal = isFinal
        self.timestamp = timestamp
    }
}
