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

    private var defaultInputAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultInputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

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

        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultInputAddress,
            queue
        ) { [weak self] _, _ in
            self?.handleDeviceChange()
        }

        if status == noErr {
            isListening = true
            SpeakLog.audio.info("CoreAudioDeviceMonitor: listening to kAudioHardwarePropertyDefaultInputDevice.")
        } else {
            SpeakLog.audio.error("CoreAudioDeviceMonitor: failed to add listener (\(status, privacy: .public)).")
        }
    }

    public func stopMonitoring() {
        lock.lock()
        defer { lock.unlock() }
        guard isListening else { return }

        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultInputAddress,
            queue
        ) { _, _ in }
        isListening = false
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
        lock.unlock()
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
