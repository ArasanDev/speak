// SpeakTests/PermissionTests.swift
//
// Deterministic tests for the permission layer. The live microphone PROMPT and
// AVAudioEngine capture are hardware/TCC-dependent and verified by a live run
// (P2 done-when), not here — these cover the parts that are pure logic.
//
// Input Monitoring was removed from v0: the CGEventTap uses .defaultTap and is
// gated on Accessibility alone. PermissionKind now has 2 cases (mic + AX).

import Foundation
@testable import SpeakCore
import Testing

@Test @MainActor
func statusResolvesForEveryKindWithoutHanging() {
    let manager = PermissionManager()
    for kind in PermissionKind.allCases {
        _ = manager.status(kind)   // must return synchronously, never prompt
    }
    #expect(PermissionKind.allCases.count == 2)
}
