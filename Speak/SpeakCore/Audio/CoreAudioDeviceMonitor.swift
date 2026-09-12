// SpeakCore/Audio/CoreAudioDeviceMonitor.swift
//
// Monitors macOS CoreAudio HAL default input device changes and hardware topology.
// Operates 24/7 (both during active capture and when idle).
// Uses AudioObjectPropertyListenerBlock on kAudioObjectSystemObject.

import AudioToolbox
import CoreAudio
import Foundation
import os

/// Monitors the system-wide default audio input device using CoreAudio HAL.
public final class CoreAudioDeviceMonitor: @unchecked Sendable {
    public static let shared = CoreAudioDeviceMonitor()

    public struct DeviceInfo: Equatable, Sendable {
        public let id: AudioDeviceID
        public let name: String
        public let sampleRate: Double
        public let channelCount: Int

        public init(id: AudioDeviceID, name: String, sampleRate: Double, channelCount: Int) {
            self.id = id
            self.name = name
            self.sampleRate = sampleRate
            self.channelCount = channelCount
        }
    }

    private let queue = DispatchQueue(label: "com.speak.audiodevicemonitor", qos: .userInitiated)
    private var isListening = false
    private let lock = NSLock()
    private var callbacks: [UUID: @Sendable (DeviceInfo) -> Void] = [:]
    /// Notified on ANY device plug/unplug — carries the full input roster,
    /// not just the default. Used by UI that lists devices; capture rebuilds
    /// must keep subscribing to `registerCallback` (default-only).
    private var topologyCallbacks: [UUID: @Sendable ([DeviceInfo]) -> Void] = [:]
    /// The exact block passed to `AudioObjectAddPropertyListenerBlock`.
    /// `AudioObjectRemovePropertyListenerBlock` identifies the listener BY
    /// BLOCK IDENTITY — passing a fresh closure to it removes nothing, which
    /// is what the previous `stopMonitoring` did (double-registration on any
    /// re-start). [fix: audit — listener identity]
    private var listenerBlock: AudioObjectPropertyListenerBlock?

    private var defaultInputAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultInputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    /// Fires on ANY device plug/unplug — including a mic that connects without
    /// becoming the default. [fix: audit — topology listener]
    private var deviceListAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    /// The same block registered for the device-list property — removal by
    /// identity covers both addresses.
    private var deviceListBlock: AudioObjectPropertyListenerBlock?

    private init() {
        startMonitoring()
    }

    deinit {
        stopMonitoring()
    }

    public func startMonitoring() {
        lock.lock()
        defer { lock.unlock() }
        guard !isListening else { return }

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.handleDeviceChange()
        }
        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultInputAddress,
            queue,
            block
        )

        if status == noErr {
            listenerBlock = block
            isListening = true
            SpeakLog.audio.info("CoreAudioDeviceMonitor: listening to kAudioHardwarePropertyDefaultInputDevice.")
        } else {
            SpeakLog.audio.error("CoreAudioDeviceMonitor: failed to add listener (\(status, privacy: .public)).")
        }

        // Second listener: device topology — a USB mic plugging in does not
        // always become the default input, and without this the app never
        // notices it exists. Same removal-by-identity rules apply.
        // [fix: audit — detect external mics]
        let topoBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.handleTopologyChange()
        }
        let topoStatus = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &deviceListAddress,
            queue,
            topoBlock
        )
        if topoStatus == noErr {
            deviceListBlock = topoBlock
        } else {
            SpeakLog.audio.error("CoreAudioDeviceMonitor: failed to add device-list listener (\(topoStatus, privacy: .public)).")
        }
    }

    public func stopMonitoring() {
        lock.lock()
        defer { lock.unlock() }
        guard isListening, let block = listenerBlock else { return }

        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultInputAddress,
            queue,
            block
        )
        listenerBlock = nil
        isListening = false

        if let topoBlock = deviceListBlock {
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &deviceListAddress,
                queue,
                topoBlock
            )
            deviceListBlock = nil
        }
    }

    @discardableResult
    public func registerCallback(_ callback: @escaping @Sendable (DeviceInfo) -> Void) -> UUID {
        let id = UUID()
        lock.lock()
        callbacks[id] = callback
        lock.unlock()
        return id
    }

    public func unregisterCallback(_ id: UUID) {
        lock.lock()
        callbacks.removeValue(forKey: id)
        topologyCallbacks.removeValue(forKey: id)
        lock.unlock()
    }

    /// Subscribe to device topology changes (plug/unplug of ANY device).
    /// The callback receives the current input-capable device roster.
    @discardableResult
    public func registerTopologyCallback(_ callback: @escaping @Sendable ([DeviceInfo]) -> Void) -> UUID {
        let id = UUID()
        lock.lock()
        topologyCallbacks[id] = callback
        lock.unlock()
        return id
    }

    public func currentDefaultInputDevice() -> DeviceInfo? {
        var deviceID: AudioDeviceID = kAudioDeviceUnknown
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultInputAddress,
            0,
            nil,
            &size,
            &deviceID
        )

        guard status == noErr, deviceID != kAudioDeviceUnknown else {
            return nil
        }

        let name = queryDeviceName(deviceID: deviceID)
        let rate = queryDeviceSampleRate(deviceID: deviceID)
        let channels = queryDeviceChannelCount(deviceID: deviceID)

        return DeviceInfo(id: deviceID, name: name, sampleRate: rate, channelCount: channels)
    }

    private func handleDeviceChange() {
        guard let info = currentDefaultInputDevice() else { return }
        SpeakLog.audio.info(
            "CoreAudioDeviceMonitor: default device changed to [\(info.id, privacy: .public)] \(info.name, privacy: .public)"
        )

        lock.lock()
        let notifyList = Array(callbacks.values)
        lock.unlock()

        for callback in notifyList {
            callback(info)
        }
    }

    /// Enumerates every device that has at least one input channel.
    /// Pure HAL query — safe to call from any thread.
    public func listInputDevices() -> [DeviceInfo] {
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &deviceListAddress,
            0,
            nil,
            &size
        ) == noErr, size > 0 else { return [] }

        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &deviceListAddress,
            0,
            nil,
            &size,
            &ids
        ) == noErr else { return [] }

        return ids.compactMap { id in
            let channels = queryDeviceChannelCount(deviceID: id)
            guard channels > 0 else { return nil }
            return DeviceInfo(
                id: id,
                name: queryDeviceName(deviceID: id),
                sampleRate: queryDeviceSampleRate(deviceID: id),
                channelCount: channels
            )
        }
    }

    /// Device plug/unplug arrived. Log the current input roster so a newly
    /// connected mic is visible in `make logs` even when it isn't the default,
    /// and notify topology subscribers. Deliberately does NOT fan out to the
    /// capture callbacks — only a *default* change needs a tap rebuild.
    /// [decision: topology = observability + UI roster, not a rebuild trigger]
    private func handleTopologyChange() {
        let inputs = listInputDevices()
        let names = inputs.map { "\($0.name) (\($0.channelCount)ch)" }.joined(separator: ", ")
        SpeakLog.audio.info(
            "CoreAudioDeviceMonitor: device topology changed — input devices now: \(names, privacy: .public)"
        )

        lock.lock()
        let notifyList = Array(topologyCallbacks.values)
        lock.unlock()

        for callback in notifyList {
            callback(inputs)
        }
    }

    private func queryDeviceName(deviceID: AudioDeviceID) -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &name)
        if status == noErr, let name = name {
            return name.takeRetainedValue() as String
        }
        return "Unknown Device"
    }

    private func queryDeviceSampleRate(deviceID: AudioDeviceID) -> Double {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var rate: Float64 = 0
        var size = UInt32(MemoryLayout<Float64>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &rate)
        return status == noErr ? Double(rate) : 0.0
    }

    private func queryDeviceChannelCount(deviceID: AudioDeviceID) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr, size > 0 else {
            return 1
        }
        let bufferListPointer = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: Int(size))
        defer { bufferListPointer.deallocate() }

        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, bufferListPointer) == noErr else {
            return 1
        }
        let buffers = UnsafeMutableAudioBufferListPointer(bufferListPointer)
        var channels = 0
        for buf in buffers {
            channels += Int(buf.mNumberChannels)
        }
        return max(channels, 1)
    }
}
