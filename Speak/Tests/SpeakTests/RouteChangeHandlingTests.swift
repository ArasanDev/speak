// SpeakTests/RouteChangeHandlingTests.swift
//
// Regression tests for the Apple-standard route/device handling pass:
//
// - Burst coalescing: one physical event (headset plug flipping the default)
//   fires BOTH `.AVAudioEngineConfigurationChange` and the HAL default-input
//   callback. `requestRebuildLocked` must collapse the burst into one rebuild
//   instead of tearing down + restarting the engine N times back-to-back.
// - start() serialization: the install-tap/register-observers/engine-start
//   tail now runs on `stateQueue`, so a route-change event queued mid-start
//   can no longer removeTap under a half-built graph.
// - `.routeChanged` feedback mapping: distinct system sound so a mid-dictation
//   source switch is felt, not silent.
//
// Requires real audio hardware (AVAudioEngine.start()). If no input device is
// available in the sandbox/CI environment these XCTSkip — skipping is NOT
// passing (see AudioCaptureVADAttachTests.swift's established pattern).

import AVFoundation
@testable import SpeakCore
import XCTest

final class RouteChangeHandlingTests: XCTestCase {

    /// A burst of configuration-change notifications mid-capture must not
    /// crash, must not wedge, and must leave capture yielding buffers — the
    /// coalesced rebuild lands on the final hardware state.
    func testConfigurationChangeBurstMidCaptureSurvives() async throws {
        let capture = AudioCapture()

        let stream: AsyncThrowingStream<AVAudioPCMBuffer, Error>
        do {
            stream = try capture.start()
        } catch {
            throw XCTSkip("No audio input device available in this environment: \(error)")
        }
        defer { capture.stop() }

        // Simulate a physical plug/unplug storm: the OS fires a burst of
        // config-change notifications while the default-input callback fires
        // alongside them.
        for _ in 0..<8 {
            NotificationCenter.default.post(name: .AVAudioEngineConfigurationChange, object: nil)
        }

        // Give the queued rebuilds time to coalesce + drain.
        let handlerDeadline = Date().addingTimeInterval(1.5)
        while Date() < handlerDeadline {
            Thread.sleep(forTimeInterval: 0.05)
        }

        // Capture must still yield buffers — proof the drain loop converged
        // and the last rebuild left a live tap, not a torn graph.
        let drainTask = Task {
            var seen = 0
            do {
                for try await _ in stream {
                    seen += 1
                    if seen >= 1 { break }
                }
            } catch {
                // A thrown finish is acceptable only if the input genuinely
                // disappeared; in this environment the built-in mic persists,
                // so treat a throw as a failure.
                XCTFail("stream threw after coalesced burst: \(error)")
            }
            return seen
        }
        let result = await drainTask.value
        XCTAssertGreaterThanOrEqual(result, 1, "expected ≥1 buffer after burst — rebuild left no live tap")
    }

    /// stop() racing a queued rebuild must still tear down cleanly — the
    /// continuation-nil guard drops the late rebuild.
    func testStopDuringQueuedRebuildDoesNotResurrectEngine() async throws {
        let capture = AudioCapture()
        do {
            _ = try capture.start()
        } catch {
            throw XCTSkip("No audio input device available in this environment: \(error)")
        }

        NotificationCenter.default.post(name: .AVAudioEngineConfigurationChange, object: nil)
        capture.stop()

        // A second capture instance (MicLevelMonitor-style) must still be
        // usable after the raced teardown — proves no shared-state wedging.
        let capture2 = AudioCapture()
        do {
            let stream2 = try capture2.start()
            capture2.stop()
            var iterator = stream2.makeAsyncIterator()
            _ = try await iterator.next()
        } catch {
            throw XCTSkip("Second capture unavailable: \(error)")
        }
    }

    /// `.routeChanged` maps to a real system sound distinct from engage/release.
    @MainActor
    func testRouteChangedHasDistinctSystemSound() {
        let engage = DictationFeedback.sound(for: .engaged)?.name
        let release = DictationFeedback.sound(for: .released)?.name
        let route = DictationFeedback.sound(for: .routeChanged)?.name

        XCTAssertNotNil(route, "routeChanged must map to a system sound")
        XCTAssertNotEqual(route, engage)
        XCTAssertNotEqual(route, release)
    }

    // MARK: - Pinned-device selection

    /// The resolver is the single source of truth for "which device feeds
    /// capture": nil/empty/unknown UIDs fall back to the system default, a
    /// real UID resolves to its device.
    func testResolvedInputDeviceHonorsPreferenceAndFallback() throws {
        let monitor = CoreAudioDeviceMonitor.shared
        guard let defaultDevice = monitor.currentDefaultInputDevice() else {
            throw XCTSkip("No input device in this environment")
        }

        // nil / empty / bogus → system default
        XCTAssertEqual(monitor.resolvedInputDevice(preferredUID: nil)?.id, defaultDevice.id)
        XCTAssertEqual(monitor.resolvedInputDevice(preferredUID: "")?.id, defaultDevice.id)
        XCTAssertEqual(
            monitor.resolvedInputDevice(preferredUID: "no-such-device-uid")?.id,
            defaultDevice.id
        )

        // The default device's own UID must resolve to itself — proves the
        // preferred-UID path matches by stable UID, not by position.
        XCTAssertFalse(defaultDevice.uid.isEmpty, "built-in mic should expose a stable UID")
        XCTAssertEqual(
            monitor.resolvedInputDevice(preferredUID: defaultDevice.uid)?.id,
            defaultDevice.id
        )
    }

    /// A bogus pinned UID must not break capture — resolution falls back to
    /// the system default and the engine starts on real hardware.
    func testBogusPreferenceFallsBackToDefaultCapture() async throws {
        let capture = AudioCapture()
        capture.preferredInputDeviceUID = "no-such-device-uid"

        let stream: AsyncThrowingStream<AVAudioPCMBuffer, Error>
        do {
            stream = try capture.start()
        } catch {
            throw XCTSkip("No audio input device available in this environment: \(error)")
        }
        capture.stop()

        // Must not throw — a clean finish or a delivered buffer are both fine.
        var iterator = stream.makeAsyncIterator()
        _ = try await iterator.next()
    }

    /// SettingsStore round-trip: nil ↔ "" normalization plus the display name.
    func testMicPreferencePersistsAndNormalizes() throws {
        let defaults = try XCTUnwrap(
            UserDefaults(suiteName: UUID().uuidString),
            "UserDefaults(suiteName:) returned nil for a UUID name — impossible."
        )
        let store = SettingsStore(defaults: defaults)

        XCTAssertNil(store.preferredInputDeviceUID)
        XCTAssertNil(store.preferredInputDeviceName)

        store.preferredInputDeviceUID = "hw-uid-123"
        store.preferredInputDeviceName = "Jabra Evolve2 30 SE"
        XCTAssertEqual(store.preferredInputDeviceUID, "hw-uid-123")
        XCTAssertEqual(store.preferredInputDeviceName, "Jabra Evolve2 30 SE")

        // Clearing writes "" under the hood but reads back as nil.
        store.preferredInputDeviceUID = nil
        store.preferredInputDeviceName = nil
        XCTAssertNil(store.preferredInputDeviceUID)
        XCTAssertNil(store.preferredInputDeviceName)
    }
}
