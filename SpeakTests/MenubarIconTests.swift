// SpeakTests/MenubarIconTests.swift
//
// Unit tests for the pure `MenubarIcon(for: CaptureSession.State)` mapping.
//
// This is the ONLY headlessly-verifiable piece of the P5/P8 keystone wiring.
// The end-to-end behavior (double-tap Fn, paste, live icon) is deferred to
// human verification (docs/human-verification.md).
//
// Coverage: every `CaptureSession.State` case maps to the expected `MenubarIcon`.
// An exhaustive switch in `MenubarIcon.init(for:)` (no `default`) guarantees
// this test suite fails to compile — not just fails — if a new State case is
// added without a corresponding MenubarIcon mapping. [verified]

import Testing
@testable import SpeakCore

@Suite("MenubarIcon")
struct MenubarIconTests {
    @Test("maps CaptureSession.State correctly", arguments: [
        (CaptureSession.State.idle,       MenubarIcon.idle),
        (.listening,  .listening),
        (.processing, .processing),
        (.done,       .done),
        (.error(.sessionCancelled), .error),
    ])
    func iconMapping(state: CaptureSession.State, expected: MenubarIcon) {
        #expect(MenubarIcon(for: state) == expected)
    }
}
