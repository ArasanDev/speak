// SpeakCore/Channels/ChannelDomain.swift
//
// Clean specification and data domain for Agent Channel Plugins.
// Universal Channel transport contracts for external coding agents & tools
// (Claude Code, Hermes, Open-Interpreter, Cursor, custom CLI scripts).
// Zero third-party dependencies — pure Swift Foundation.

import Foundation

// MARK: - Channel Capability & Descriptor

/// The capabilities supported by a registered Agent Channel.
public struct ChannelCapabilities: OptionSet, Codable, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    /// Can receive direct push voice turn events (dictation without Cmd+V pasteboard).
    public static let pushVoiceTurns        = ChannelCapabilities(rawValue: 1 << 0)
    /// Can process structured interactive questions & approvals (speak_request_input).
    public static let interactivePrompts    = ChannelCapabilities(rawValue: 1 << 1)
    /// Can receive outbound audio status notifications (speak_notify / speak_say).
    public static let spokenAudioOut        = ChannelCapabilities(rawValue: 1 << 2)
    /// Workspace repo aware (carries repoPath / workspace root context).
    public static let repoAware             = ChannelCapabilities(rawValue: 1 << 3)

    public static let all: ChannelCapabilities = [
        .pushVoiceTurns, .interactivePrompts, .spokenAudioOut, .repoAware
    ]
}

/// A descriptor representing an active external Channel connection.
public struct ChannelDescriptor: Identifiable, Codable, Sendable, Equatable {
    /// Unique identifier for the channel (e.g., "com.speak.channel.claude-code").
    public let id: String
    /// Human-readable label (e.g. "Claude Code (deepvoice)").
    public let label: String
    /// Absolute path to the Git repository or workspace root associated with this channel.
    public let repoPath: String?
    /// Transport medium used by this channel.
    public let transportType: TransportType
    /// Supported channel capabilities.
    public let capabilities: ChannelCapabilities

    public enum TransportType: String, Codable, Sendable {
        case mcpStdio
        case cfMessagePort
        case unixSocket
    }

    public init(
        id: String,
        label: String,
        repoPath: String?,
        transportType: TransportType,
        capabilities: ChannelCapabilities
    ) {
        self.id = id
        self.label = label
        self.repoPath = repoPath
        self.transportType = transportType
        self.capabilities = capabilities
    }
}

// MARK: - Channel Event Envelope

/// An envelope wrapping an event traversing a Channel.
public struct ChannelEventEnvelope: Identifiable, Codable, Sendable {
    public let id: UUID
    public let channelId: String
    public let repoPath: String?
    public let eventType: EventType
    public let payloadText: String
    public let timestamp: Date

    public enum EventType: String, Codable, Sendable {
        case dictationTurn     // Human spoken voice turn -> Agent
        case agentRequest      // Agent question/approval request -> Human (HUD)
        case agentResponse     // Agent answer/status -> Human (VoiceOut)
        case systemNotification// Channel alert or status update
    }

    public init(
        id: UUID = UUID(),
        channelId: String,
        repoPath: String?,
        eventType: EventType,
        payloadText: String,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.channelId = channelId
        self.repoPath = repoPath
        self.eventType = eventType
        self.payloadText = payloadText
        self.timestamp = timestamp
    }
}

// MARK: - Channel Gateway Contract

/// Protocol for the Channel Gateway managing active agent channel plugins.
@MainActor
public protocol ChannelGatewayManaging: AnyObject {
    /// List all currently registered active agent channels.
    var activeChannels: [ChannelDescriptor] { get }
    /// Currently selected active target channel for direct voice turn dispatch.
    var selectedChannelId: String? { get }

    /// Register a new external agent channel plugin.
    func registerChannel(_ descriptor: ChannelDescriptor)
    /// Unregister an agent channel plugin when it disconnects.
    func unregisterChannel(id: String)
    /// Select the active channel target for dictation turn routing.
    func selectChannel(id: String?)
    /// Dispatch a human voice turn directly to the selected channel (bypassing Cmd+V).
    func dispatchVoiceTurn(text: String) async -> Bool
}
