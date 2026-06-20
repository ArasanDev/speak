// App/MicTestController.swift
//
// TEMPORARY P2 verification affordance: a menubar toggle that requests mic
// permission, starts AudioCapture, and logs PCM buffer stats. This proves the
// P2 done-when (permission prompt + buffer stats + clean stop) until the real
// hotkey-driven capture flow lands at P5. Replaced then.

import Foundation
import SwiftUI
import SpeakCore

@MainActor
final class MicTestController: ObservableObject {

    @Published private(set) var isCapturing = false

    private let permissions = PermissionManager()
    private let capture = AudioCapture()
    private var consumer: Task<Void, Never>?

    func toggle() {
        if isCapturing {
            stop()
        } else {
            Task { await start() }
        }
    }

    private func start() async {
        let state = await permissions.requestMicrophone()
        guard state == .granted else {
            SpeakLog.audio.error("mic test aborted: permission \(String(describing: state), privacy: .public)")
            return
        }
        do {
            let stream = try capture.start()
            isCapturing = true
            consumer = Task.detached(priority: .utility) {
                var count = 0
                var frames = 0
                for await buffer in stream {
                    count += 1
                    frames += Int(buffer.frameLength)
                    // Throttle logging to every 20th buffer to avoid log spam. [decision]
                    if count % 20 == 0 {
                        SpeakLog.audio.debug("""
                            pcm buffers=\(count, privacy: .public) \
                            lastFrames=\(buffer.frameLength, privacy: .public) \
                            rate=\(buffer.format.sampleRate, privacy: .public) \
                            totalFrames=\(frames, privacy: .public)
                            """)
                    }
                }
                SpeakLog.audio.info("mic test stream ended after \(count, privacy: .public) buffers")
            }
        } catch {
            SpeakLog.audio.error("mic test start failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func stop() {
        capture.stop()
        consumer?.cancel()
        consumer = nil
        isCapturing = false
    }
}
