// SpeakCore/Audio/SpeechSynthesizerStream.swift
//
// Streaming text-to-speech engine wrapper around AVSpeechSynthesizer with sub-100ms
// cancellation (`stopImmediately()`) and progress/playback state streaming.
//
// Part of Layer 1 of the Bidirectional Voice Architecture.

import AVFoundation
import Foundation
import os

/// Playback state for SpeechSynthesizerStream.
public enum SpeechPlaybackState: Equatable, Sendable {
    case idle
    case speaking(text: String)
    case paused
    case stopped
}

/// Progress event emitted during speech playback.
public struct SpeechProgress: Equatable, Sendable {
    /// Text of the active utterance.
    public let utteranceText: String
    /// Character range in `utteranceText` being spoken.
    public let characterRange: NSRange
    /// The specific word string being spoken, if available.
    public let word: String?
    /// Whether the utterance has completed playback.
    public let isComplete: Bool

    public init(
        utteranceText: String,
        characterRange: NSRange,
        word: String? = nil,
        isComplete: Bool = false
    ) {
        self.utteranceText = utteranceText
        self.characterRange = characterRange
        self.word = word
        self.isComplete = isComplete
    }
}

/// Configuration settings for streaming speech synthesis.
public struct SpeechStreamConfiguration: Sendable {
    public var voiceIdentifier: String?
    public var rate: Float
    public var pitch: Float
    public var volume: Float
    public var locale: Locale

    public init(
        voiceIdentifier: String? = nil,
        rate: Float = AVSpeechUtteranceDefaultSpeechRate,
        pitch: Float = 1.0,
        volume: Float = 1.0,
        locale: Locale = Locale(identifier: "en-US")
    ) {
        self.voiceIdentifier = voiceIdentifier
        self.rate = rate
        self.pitch = pitch
        self.volume = volume
        self.locale = locale
    }
}

// MARK: - Delegate Bridge

private final class SpeechSynthesizerStreamDelegateBridge: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    var onStart: (@Sendable (AVSpeechUtterance) -> Void)?
    var onFinish: (@Sendable (AVSpeechUtterance) -> Void)?
    var onCancel: (@Sendable (AVSpeechUtterance) -> Void)?
    var onPause: (@Sendable (AVSpeechUtterance) -> Void)?
    var onContinue: (@Sendable (AVSpeechUtterance) -> Void)?
    var onWillSpeakRange: (@Sendable (NSRange, AVSpeechUtterance) -> Void)?

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        onStart?(utterance)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        onFinish?(utterance)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        onCancel?(utterance)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance) {
        onPause?(utterance)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didContinue utterance: AVSpeechUtterance) {
        onContinue?(utterance)
    }

    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        willSpeakRangeOfSpeechString characterRange: NSRange,
        utterance: AVSpeechUtterance
    ) {
        onWillSpeakRange?(characterRange, utterance)
    }
}

// MARK: - SpeechSynthesizerStream

public final class SpeechSynthesizerStream: @unchecked Sendable {

    private let lock = NSLock()
    private let synthesizer = AVSpeechSynthesizer()
    private let delegateBridge = SpeechSynthesizerStreamDelegateBridge()

    private var playbackState: SpeechPlaybackState = .idle
    private var pendingQueue: [AVSpeechUtterance] = []
    private var currentConfiguration: SpeechStreamConfiguration
    private var streamTask: Task<Void, Never>?

    private var stateContinuation: AsyncStream<SpeechPlaybackState>.Continuation?
    private var progressContinuation: AsyncStream<SpeechProgress>.Continuation?

    public let stateStream: AsyncStream<SpeechPlaybackState>
    public let progressStream: AsyncStream<SpeechProgress>

    public init(configuration: SpeechStreamConfiguration = SpeechStreamConfiguration()) {
        self.currentConfiguration = configuration

        // Bounded: only the latest playback state/progress matters to a
        // consumer — never backlog unboundedly. [fix: audit — unbounded AsyncStream]
        let (sStream, sContinuation) = AsyncStream<SpeechPlaybackState>.makeStream(
            bufferingPolicy: .bufferingNewest(8)
        )
        let (pStream, pContinuation) = AsyncStream<SpeechProgress>.makeStream(
            bufferingPolicy: .bufferingNewest(8)
        )

        self.stateStream = sStream
        self.stateContinuation = sContinuation
        self.progressStream = pStream
        self.progressContinuation = pContinuation

        setupDelegateBridge()
    }

    deinit {
        stopImmediately()
        stateContinuation?.finish()
        progressContinuation?.finish()
    }

    // MARK: - Properties

    /// Current playback state of the synthesizer stream.
    public var currentState: SpeechPlaybackState {
        lock.lock()
        defer { lock.unlock() }
        return playbackState
    }

    /// Whether speech is active or queued.
    public var isSpeaking: Bool {
        lock.lock()
        defer { lock.unlock() }
        switch playbackState {
        case .speaking:
            return true

        case .idle, .paused, .stopped:
            return synthesizer.isSpeaking
        }
    }

    /// Active configuration settings.
    public var configuration: SpeechStreamConfiguration {
        get {
            lock.lock()
            defer { lock.unlock() }
            return currentConfiguration
        }
        set {
            lock.lock()
            currentConfiguration = newValue
            lock.unlock()
        }
    }

    // MARK: - Speech Control Methods

    /// Speak a single block of text aloud.
    public func speak(_ text: String, configuration: SpeechStreamConfiguration? = nil) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            SpeakLog.voiceOut.info("SpeechSynthesizerStream: speak() skipped — empty text.")
            return
        }

        let config = configuration ?? self.configuration
        let utterance = createUtterance(from: trimmed, configuration: config)

        lock.lock()
        pendingQueue.append(utterance)
        let wasIdle = (playbackState == .idle || playbackState == .stopped)
        if wasIdle {
            updateStateLocked(.speaking(text: trimmed))
        }
        lock.unlock()

        synthesizer.speak(utterance)
        SpeakLog.voiceOut.info("SpeechSynthesizerStream: queued utterance (\(trimmed.count, privacy: .public) chars)")
    }

    /// Enqueue a text chunk into the streaming TTS queue.
    public func enqueue(_ chunk: String, configuration: SpeechStreamConfiguration? = nil) {
        speak(chunk, configuration: configuration)
    }

    /// Stream chunks of text from an `AsyncStream<String>`.
    public func speakStream(_ stream: AsyncStream<String>, configuration: SpeechStreamConfiguration? = nil) {
        let config = configuration ?? self.configuration

        lock.lock()
        streamTask?.cancel()
        let task = Task { [weak self] in
            for await chunk in stream {
                guard let self else { break }
                if Task.isCancelled { break }
                let trimmed = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                self.enqueue(trimmed, configuration: config)
            }
        }
        self.streamTask = task
        lock.unlock()
    }

    /// Immediately cancels all active and queued speech readbacks.
    /// Designed for sub-100ms barge-in interruption.
    @discardableResult
    public func stopImmediately() -> Double {
        let startTime = CFAbsoluteTimeGetCurrent()

        lock.lock()
        streamTask?.cancel()
        streamTask = nil
        pendingQueue.removeAll()

        let wasSpeakingOrPaused = synthesizer.isSpeaking || synthesizer.isPaused
        updateStateLocked(.stopped)
        lock.unlock()

        // Call synthesizer.stopSpeaking OUTSIDE the lock to prevent re-entrant
        // deadlock when delegate callbacks fire synchronously on the same thread.
        if wasSpeakingOrPaused {
            synthesizer.stopSpeaking(at: .immediate)
        }

        let elapsedTimeMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0
        SpeakLog.voiceOut.info("SpeechSynthesizerStream: stopImmediately() executed in \(elapsedTimeMs, privacy: .public) ms")
        return elapsedTimeMs
    }

    /// Pause speech playback.
    public func pause() {
        lock.lock()
        if synthesizer.isSpeaking {
            synthesizer.pauseSpeaking(at: .immediate)
            updateStateLocked(.paused)
        }
        lock.unlock()
    }

    /// Resume paused speech playback.
    public func continueSpeaking() {
        lock.lock()
        if synthesizer.isPaused {
            synthesizer.continueSpeaking()
            if let activeText = pendingQueue.first?.speechString {
                updateStateLocked(.speaking(text: activeText))
            } else {
                updateStateLocked(.idle)
            }
        }
        lock.unlock()
    }

    // MARK: - Private Setup & Delegate Routing

    private func setupDelegateBridge() {
        synthesizer.delegate = delegateBridge
        bindUtteranceLifecycleCallbacks()
        bindProgressCallbacks()
    }

    private func bindUtteranceLifecycleCallbacks() {
        delegateBridge.onStart = { [weak self] utterance in
            guard let self else { return }
            self.lock.lock()
            let text = utterance.speechString
            self.updateStateLocked(.speaking(text: text))
            self.lock.unlock()
            SpeakLog.voiceOut.info("SpeechSynthesizerStream: didStart utterance")
        }

        delegateBridge.onFinish = { [weak self] utterance in
            guard let self else { return }
            self.handleUtteranceFinished(utterance)
        }

        delegateBridge.onCancel = { [weak self] _ in
            guard let self else { return }
            self.lock.lock()
            self.pendingQueue.removeAll()
            self.updateStateLocked(.stopped)
            self.lock.unlock()
            SpeakLog.voiceOut.info("SpeechSynthesizerStream: didCancel utterance")
        }
    }

    private func handleUtteranceFinished(_ utterance: AVSpeechUtterance) {
        lock.lock()
        if let idx = pendingQueue.firstIndex(of: utterance) {
            pendingQueue.remove(at: idx)
        }
        let text = utterance.speechString
        let progress = SpeechProgress(
            utteranceText: text,
            characterRange: NSRange(location: 0, length: text.utf16.count),
            word: nil,
            isComplete: true
        )
        progressContinuation?.yield(progress)

        if let nextUtterance = pendingQueue.first {
            updateStateLocked(.speaking(text: nextUtterance.speechString))
        } else if !synthesizer.isSpeaking {
            updateStateLocked(.idle)
        }
        lock.unlock()
        SpeakLog.voiceOut.info("SpeechSynthesizerStream: didFinish utterance")
    }

    private func bindProgressCallbacks() {
        delegateBridge.onWillSpeakRange = { [weak self] range, utterance in
            guard let self else { return }
            let text = utterance.speechString
            var word: String?
            if let swiftRange = Range(range, in: text) {
                word = String(text[swiftRange])
            }
            let progress = SpeechProgress(
                utteranceText: text,
                characterRange: range,
                word: word,
                isComplete: false
            )
            self.progressContinuation?.yield(progress)
        }
    }

    private func createUtterance(from text: String, configuration: SpeechStreamConfiguration) -> AVSpeechUtterance {
        let utterance = AVSpeechUtterance(string: text)
        if let voiceId = configuration.voiceIdentifier, !voiceId.isEmpty,
           let voice = AVSpeechSynthesisVoice(identifier: voiceId) {
            utterance.voice = voice
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: configuration.locale.identifier)
                ?? AVSpeechSynthesisVoice(language: "en-US")
        }
        utterance.rate = configuration.rate
        utterance.pitchMultiplier = configuration.pitch
        utterance.volume = configuration.volume
        return utterance
    }

    private func updateStateLocked(_ newState: SpeechPlaybackState) {
        playbackState = newState
        stateContinuation?.yield(newState)
    }
}
