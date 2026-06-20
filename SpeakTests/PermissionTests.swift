// SpeakTests/PermissionTests.swift
//
// Deterministic tests for the permission layer. The live microphone PROMPT and
// AVAudioEngine capture are hardware/TCC-dependent and verified by a live run
// (P2 done-when), not here — these cover the parts that are pure logic.

import Testing
import Foundation
@testable import SpeakCore

@Test @MainActor
func inputMonitoringIsNotDeterminedUntilP5() {
    let manager = PermissionManager()
    // Wired at P5; until then it must not claim a definite state.
    #expect(manager.status(.inputMonitoring) == .notDetermined)
}

@Test @MainActor
func statusResolvesForEveryKindWithoutHanging() {
    let manager = PermissionManager()
    for kind in PermissionKind.allCases {
        _ = manager.status(kind)   // must return synchronously, never prompt
    }
    #expect(PermissionKind.allCases.count == 3)
}
