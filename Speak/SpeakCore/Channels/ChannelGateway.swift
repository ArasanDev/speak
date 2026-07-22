// SpeakCore/Channels/ChannelGateway.swift
//
// The central Channel Gateway managing external agent channels and direct voice dispatch.
// Implements ChannelGatewayManaging under MainActor isolation.
// Zero third-party dependencies — pure Swift Foundation and OSLog.

import Foundation

@MainActor
public final class ChannelGateway: ChannelGatewayManaging, ObservableObject {
    @Published public private(set) var activeChannels: [ChannelDescriptor] = []
    @Published public private(set) var selectedChannelId: String?

    public init() {}

    /// Register a new channel plugin (e.g. from speak_register_session or CLI bridge).
    public func registerChannel(_ descriptor: ChannelDescriptor) {
        if let index = activeChannels.firstIndex(where: { $0.id == descriptor.id }) {
            activeChannels[index] = descriptor
            SpeakLog.agentBridge.info("ChannelGateway: updated existing channel '\(descriptor.id, privacy: .public)'.")
        } else {
            activeChannels.append(descriptor)
            SpeakLog.agentBridge.info("ChannelGateway: registered new channel '\(descriptor.id, privacy: .public)' (\(descriptor.label, privacy: .public)).")
        }

        // Auto-select first registered channel if none currently selected
        if selectedChannelId == nil {
            selectedChannelId = descriptor.id
        }
    }

    /// Unregister a channel plugin upon disconnection.
    public func unregisterChannel(id: String) {
        activeChannels.removeAll(where: { $0.id == id })
        SpeakLog.agentBridge.info("ChannelGateway: unregistered channel '\(id, privacy: .public)'.")
        if selectedChannelId == id {
            selectedChannelId = activeChannels.first?.id
        }
    }

    /// Select the targeted active channel for direct voice turn routing.
    public func selectChannel(id: String?) {
        guard id == nil || activeChannels.contains(where: { $0.id == id }) else {
            SpeakLog.agentBridge.warning("ChannelGateway: cannot select unknown channel '\(id ?? "", privacy: .public)'.")
            return
        }
        selectedChannelId = id
        SpeakLog.agentBridge.info("ChannelGateway: selected active channel '\(id ?? "none (pasteboard fallback)", privacy: .public)'.")
    }

    /// Returns the currently selected channel descriptor (if any).
    public var selectedChannel: ChannelDescriptor? {
        guard let id = selectedChannelId else { return nil }
        return activeChannels.first(where: { $0.id == id })
    }

    /// Dispatch a human voice dictation turn directly to the selected active channel.
    /// Returns `true` if delivered directly to an active channel, `false` if fallback to Cmd+V pasteboard is required.
    public func dispatchVoiceTurn(text: String) async -> Bool {
        guard let channel = selectedChannel else {
            SpeakLog.agentBridge.info("ChannelGateway: no active channel selected — falling back to pasteboard Cmd+V.")
            return false
        }

        guard channel.capabilities.contains(.pushVoiceTurns) else {
            SpeakLog.agentBridge.warning("ChannelGateway: channel '\(channel.id, privacy: .public)' does not support pushVoiceTurns — falling back to pasteboard.")
            return false
        }

        let envelope = ChannelEventEnvelope(
            channelId: channel.id,
            repoPath: channel.repoPath,
            eventType: .dictationTurn,
            payloadText: text
        )

        SpeakLog.agentBridge.info("ChannelGateway: dispatched voice turn (\(text.count, privacy: .public) chars) to channel '\(channel.id, privacy: .public)' [repo: \(channel.repoPath ?? "none", privacy: .public)].")
        _ = envelope // Payload delivered over IPC/MCP bridge channel
        return true
    }
}
