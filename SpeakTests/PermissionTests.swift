// SpeakTests/PermissionTests.swift
//
// Deterministic tests for the permission layer. The live microphone PROMPT and
// AVAudioEngine capture are hardware/TCC-dependent and verified by a live run
// (P2 done-when), not here — these cover the parts that are pure logic.
//
// P7 note: `inputMonitoring` is now wired via IOHIDCheckAccess
// (kIOHIDRequestTypeListenEvent). The prior test asserting `.notDetermined`
// is removed because the real value is environment-dependent (CI vs a Mac
// with TCC grants). We test only that the call returns without hanging and
// returns a valid state, not the *exact* value. Live correctness is
// [deferred — human-verification.md §4.4].

import Testing
import Foundation
@testable import SpeakCore

@Test @MainActor
func inputMonitoringStatusResolvesWithoutHanging() {
    let manager = PermissionManager()
    let state = manager.status(.inputMonitoring)
    // Must be a valid PermissionState — granted, denied, or notDetermined.
    // The exact value is TCC-environment-dependent; we do not assert it.
    let validStates: Set<PermissionState> = [.granted, .denied, .notDetermined]
    #expect(validStates.contains(state))
}

@Test @MainActor
func statusResolvesForEveryKindWithoutHanging() {
    let manager = PermissionManager()
    for kind in PermissionKind.allCases {
        _ = manager.status(kind)   // must return synchronously, never prompt
    }
    #expect(PermissionKind.allCases.count == 3)
}
