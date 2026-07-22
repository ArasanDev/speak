// SpeakTests/ChannelGatewayTests.swift
//
// Test suite for ChannelDomain and ChannelGateway.
// Verifies channel registration, auto-selection, unregistration, capability filtering,
// and direct voice turn dispatch logic.

import Foundation
import Testing
@testable import SpeakCore

struct ChannelGatewayTests {

    @Test
    @MainActor
    func testChannelRegistrationAndAutoSelection() {
        let gateway = ChannelGateway()
        #expect(gateway.activeChannels.isEmpty)
        #expect(gateway.selectedChannelId == nil)

        let descriptor = ChannelDescriptor(
            id: "com.speak.channel.claude",
            label: "Claude Code (deepvoice)",
            repoPath: "/Users/tamil/Developers/deepvoice",
            transportType: .mcpStdio,
            capabilities: [.pushVoiceTurns, .interactivePrompts, .repoAware]
        )

        gateway.registerChannel(descriptor)

        #expect(gateway.activeChannels.count == 1)
        #expect(gateway.selectedChannelId == "com.speak.channel.claude")
        #expect(gateway.selectedChannel?.label == "Claude Code (deepvoice)")
    }

    @Test
    @MainActor
    func testChannelSelectionAndUnregistration() {
        let gateway = ChannelGateway()

        let c1 = ChannelDescriptor(
            id: "channel-1",
            label: "Channel 1",
            repoPath: "/path/1",
            transportType: .mcpStdio,
            capabilities: .all
        )
        let c2 = ChannelDescriptor(
            id: "channel-2",
            label: "Channel 2",
            repoPath: "/path/2",
            transportType: .cfMessagePort,
            capabilities: .all
        )

        gateway.registerChannel(c1)
        gateway.registerChannel(c2)

        #expect(gateway.activeChannels.count == 2)
        #expect(gateway.selectedChannelId == "channel-1")

        gateway.selectChannel(id: "channel-2")
        #expect(gateway.selectedChannelId == "channel-2")

        gateway.unregisterChannel(id: "channel-2")
        #expect(gateway.activeChannels.count == 1)
        #expect(gateway.selectedChannelId == "channel-1")
    }

    @Test
    @MainActor
    func testDirectVoiceTurnDispatchSuccess() async {
        let gateway = ChannelGateway()
        let descriptor = ChannelDescriptor(
            id: "channel-voice",
            label: "Voice Channel",
            repoPath: "/repo",
            transportType: .mcpStdio,
            capabilities: [.pushVoiceTurns, .repoAware]
        )
        gateway.registerChannel(descriptor)

        let delivered = await gateway.dispatchVoiceTurn(text: "Refactor AudioCapture to support 48kHz mono")
        #expect(delivered == true)
    }

    @Test
    @MainActor
    func testDirectVoiceTurnDispatchFallbackWhenNoChannelSelected() async {
        let gateway = ChannelGateway()
        let delivered = await gateway.dispatchVoiceTurn(text: "Hello world")
        #expect(delivered == false)
    }

    @Test
    @MainActor
    func testDirectVoiceTurnDispatchFallbackWhenChannelLacksCapability() async {
        let gateway = ChannelGateway()
        let descriptor = ChannelDescriptor(
            id: "channel-audio-only",
            label: "Audio Only Channel",
            repoPath: "/repo",
            transportType: .mcpStdio,
            capabilities: [.spokenAudioOut] // Missing .pushVoiceTurns
        )
        gateway.registerChannel(descriptor)

        let delivered = await gateway.dispatchVoiceTurn(text: "Testing capability check")
        #expect(delivered == false)
    }
}
