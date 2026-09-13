// SpeakTests/EdgeFlowBorderColorTests.swift
//
// Regression guard for the 2026-09-14 launch crash (Speak-*.ips):
//
//   NSInvalidArgumentException — "-getHue:saturation:brightness:alpha: not
//   valid for the NSColor Catalog color: #$customDynamic; need to first
//   convert colorspace." thrown inside EdgeFlowBorder.interpolateColor during
//   NSHostingView.layout → _crashOnException → SIGTRAP.
//
// Root cause: theme-resolved tokens (speakOnAir, speakAgentViolet, …) are
// Color(nsColor: NSColor(name:nil){appearance in…}) — dynamic catalog colors.
// getHue throws on them. The fix converts through .usingColorSpace(.sRGB)
// first and falls back on nil. These tests pin that conversion against the
// exact inputs that killed the app.
//
// If the conversion regresses, the first test CRASHES this suite with the
// same ObjC exception — a loud signal, which is the point.

import AppKit
@testable import Speak   // App-shell view under test requires TEST_HOST=Speak
import SpeakCore
import SwiftUI
import XCTest

@MainActor
final class EdgeFlowBorderColorTests: XCTestCase {

    private func makeBorder() -> EdgeFlowBorder<Capsule> {
        EdgeFlowBorder(
            shape: Capsule(),
            state: .listening,
            level: 0.5,
            speed: .medium,
            count: 1,
            reduceMotion: false
        )
    }

    /// The exact killer input: a theme-resolved dynamic catalog color.
    /// Before the fix this threw NSInvalidArgumentException (uncatchable).
    func testHSBComponentsConvertsThemedDynamicColor() {
        let border = makeBorder()
        XCTAssertNotNil(
            border.hsbComponents(of: .speakOnAir),
            "speakOnAir is a dynamic catalog NSColor — hsbComponents must convert it via sRGB, not throw."
        )
        XCTAssertNotNil(border.hsbComponents(of: .speakAgentViolet))
        XCTAssertNotNil(border.hsbComponents(of: .speakHumanAmber))
        XCTAssertNotNil(border.hsbComponents(of: .speakDelivered))
        XCTAssertNotNil(border.hsbComponents(of: .speakError))
    }

    /// Fixed RGB colors must keep converting too (no over-guard).
    func testHSBComponentsConvertsFixedColor() {
        let border = makeBorder()
        let hsb = border.hsbComponents(of: .speakVoiceBlue)
        XCTAssertNotNil(hsb, "speakVoiceBlue is a fixed RGB color — conversion must succeed.")
        XCTAssertEqual(hsb?.b ?? 0, 0.95, accuracy: 0.01)
    }

    /// Every state's palette must convert end-to-end — the crash wasn't
    /// listening-specific; all spectra carry themed endpoints.
    func testEveryStatePaletteConverts() {
        for state: OverlayState in [.listening, .processing, .done, .error] {
            let border = EdgeFlowBorder(
                shape: Capsule(), state: state, level: 0.5,
                speed: .medium, count: 1, reduceMotion: false
            )
            for color in border.paletteForTesting {
                XCTAssertNotNil(
                    border.hsbComponents(of: color),
                    "Palette color for state \(state) failed sRGB conversion."
                )
            }
        }
    }
}
