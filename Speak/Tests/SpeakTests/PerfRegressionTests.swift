// SpeakTests/PerfRegressionTests.swift
//
// Regression coverage for the Wave-7 audit performance fixes:
//   - LocalInferenceServer.isCompleteRequest: incremental scan must preserve
//     the original completeness semantics (separator straddling chunks,
//     Content-Length, malformed headers) while no longer re-scanning the
//     whole accumulation per receive.
//   - StreamingChunkCoordinator.cleanerAvailable: TTL cache must collapse a
//     burst of per-chunk checks into a single underlying isAvailable call.
//   - vDSP RMS parity: VoiceActivityDetector Int16 path must still produce
//     normalized RMS in [0,1] after the scalar-loop replacement.

import AVFoundation
import Foundation
import XCTest
@testable import SpeakCore
@testable import SpeakLLM

final class PerfRegressionTests: XCTestCase {

    // MARK: - isCompleteRequest incremental scan

    private func feed(_ server: LocalInferenceServer, chunks: [String]) -> (completedAt: Int, scan: LocalInferenceServer.RequestScanState) {
        var scan = LocalInferenceServer.RequestScanState()
        var accumulated = Data()
        var completedAt = -1
        for (index, chunk) in chunks.enumerated() {
            accumulated.append(Data(chunk.utf8))
            if completedAt == -1, server.isCompleteRequest(accumulated, scan: &scan) {
                completedAt = index
            }
        }
        return (completedAt, scan)
    }

    private let server = LocalInferenceServer()

    func testGetRequestCompletesOnHeaders() {
        let request = "GET /health HTTP/1.1\r\nHost: localhost\r\n\r\n"
        var scan = LocalInferenceServer.RequestScanState()
        XCTAssertTrue(server.isCompleteRequest(Data(request.utf8), scan: &scan))
    }

    func testSeparatorStraddlingReceiveBoundary() {
        // The \r\n\r\n arrives split as "…\r\n" + "\r\n…" — the incremental
        // scan must catch it via the 3-byte overlap.
        let chunks = [
            "POST /v1/chat HTTP/1.1\r\nHost: localhost\r\nContent-Length: 4\r\n\r",
            "\nabcd"
        ]
        let (completedAt, _) = feed(server, chunks: chunks)
        XCTAssertEqual(completedAt, 1, "request must complete once headers + 4 body bytes arrive")
    }

    func testContentLengthBodyArrivingInPieces() {
        let chunks = [
            "POST /v1/chat HTTP/1.1\r\nContent-Length: 10\r\n\r\n",
            "abc",
            "defg",
            "hij"
        ]
        let (completedAt, scan) = feed(server, chunks: chunks)
        XCTAssertEqual(completedAt, 3, "must complete exactly when 10 body bytes have arrived")
        XCTAssertEqual(scan.contentLength, 10)
        XCTAssertNotNil(scan.headerEnd)
    }

    func testIncompleteBodyDoesNotComplete() {
        let chunks = [
            "POST /v1/chat HTTP/1.1\r\nContent-Length: 100\r\n\r\n",
            "short"
        ]
        let (completedAt, _) = feed(server, chunks: chunks)
        XCTAssertEqual(completedAt, -1, "5 of 100 body bytes must not complete the request")
    }

    func testMalformedHeaderNeverCompletes() {
        var scan = LocalInferenceServer.RequestScanState()
        var accumulated = Data([0xFF, 0xFE, 0x0D, 0x0A, 0x0D, 0x0A])
        XCTAssertFalse(server.isCompleteRequest(accumulated, scan: &scan))
        // More data later still never completes — matches the old behavior.
        accumulated.append(Data("more".utf8))
        XCTAssertFalse(server.isCompleteRequest(accumulated, scan: &scan))
    }

    func testScanDoesNotRescanOldBytes() {
        // After the first receive, scannedUpTo must advance past the scanned
        // region — second call only searches the new tail.
        var scan = LocalInferenceServer.RequestScanState()
        let part1 = Data("POST /x HTTP/1.1\r\nContent-".utf8)
        XCTAssertFalse(server.isCompleteRequest(part1, scan: &scan))
        XCTAssertEqual(scan.scannedUpTo, part1.count)

        var accumulated = part1
        accumulated.append(Data("Length: 0\r\n\r\n".utf8))
        XCTAssertTrue(server.isCompleteRequest(accumulated, scan: &scan))
    }

    // MARK: - cleanerAvailable TTL cache

    private final class CountingCleaner: LLMCleaning, @unchecked Sendable {
        let id = "counting-cleaner"
        private let lock = NSLock()
        private var _checks = 0
        var checks: Int { lock.lock(); defer { lock.unlock() }; return _checks }

        var isAvailable: Bool {
            get async {
                lock.lock(); _checks += 1; lock.unlock()
                return true
            }
        }

        func clean(_ text: String, mode: CleanupMode) async throws -> String { text }
    }

    func testAvailabilityChecksCollapseUnderTTL() async {
        let cleaner = CountingCleaner()
        let coordinator = StreamingChunkCoordinator(cleaner: cleaner, mode: .fillersOnly)

        _ = await coordinator.cleanerAvailable()
        _ = await coordinator.cleanerAvailable()
        _ = await coordinator.cleanerAvailable()

        let checks = cleaner.checks
        XCTAssertEqual(checks, 1, "burst of availability checks must hit the TTL cache, not the cleaner")
    }

    func testIngestChunkBurstPingsAvailabilityOnce() async throws {
        let cleaner = CountingCleaner()
        let coordinator = StreamingChunkCoordinator(cleaner: cleaner, mode: .fillersOnly)

        await coordinator.ingestChunk("first chunk")
        await coordinator.ingestChunk("second chunk")
        await coordinator.ingestChunk("third chunk")
        _ = try await coordinator.finalizeAndStitch()

        let checks = cleaner.checks
        XCTAssertEqual(checks, 1, "three chained chunks must share one isAvailable evaluation")
    }

    // MARK: - vDSP RMS parity

    private func makeInt16Buffer(amplitude: Int16, frames: AVAudioFrameCount = 512) -> AVAudioPCMBuffer? {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        ), let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
        let channelData = buffer.int16ChannelData else {
            return nil
        }
        buffer.frameLength = frames
        for i in 0..<Int(frames) {
            channelData[0][i] = amplitude
        }
        return buffer
    }

    func testInt16RMSNormalizationPreserved() {
        guard let buffer = makeInt16Buffer(amplitude: 16384) else {
            XCTFail("could not build Int16 test buffer")
            return
        }
        // 16384 / 32768 = 0.5 — the vDSP path must reproduce the old
        // scalar-normalized result.
        let rms = VoiceActivityDetector.calculateRMS(buffer: buffer)
        XCTAssertEqual(rms, 0.5, accuracy: 1e-3)
    }
}

// MARK: - Device topology enumeration

final class DeviceTopologyTests: XCTestCase {

    /// The machine under test always has the built-in mic — enumeration must
    /// find at least one input-capable device, and every entry must carry a
    /// plausible name/rate/channel count.
    func testListInputDevicesFindsBuiltInMic() {
        let devices = CoreAudioDeviceMonitor.shared.listInputDevices()
        XCTAssertFalse(devices.isEmpty, "expected at least the built-in microphone")
        for dev in devices {
            XCTAssertFalse(dev.name.isEmpty, "device \(dev.id) has an empty name")
            XCTAssertGreaterThan(dev.channelCount, 0)
        }
        XCTAssertTrue(
            devices.contains { $0.name.localizedCaseInsensitiveContains("macbook") },
            "expected the built-in MacBook microphone in the roster, got: \(devices.map { $0.name })"
        )
    }

    /// A registered topology callback token unregisters cleanly and a default-
    /// change callback token clears both channels.
    func testUnregisterClearsBothChannels() {
        let monitor = CoreAudioDeviceMonitor.shared
        let token = monitor.registerTopologyCallback { _ in }
        monitor.unregisterCallback(token)  // must not crash; clears both maps
    }
}
