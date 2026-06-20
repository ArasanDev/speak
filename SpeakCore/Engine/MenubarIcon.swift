// SpeakCore/Engine/MenubarIcon.swift
//
// Pure, unit-testable mapping from `CaptureSession.State` to a menubar icon
// identity. Lives in SpeakCore so `SpeakTests` can import it without depending
// on the App target (which is an executable and cannot be @testable imported).
//
// `systemImage` (the SF Symbol name) lives in the App layer (presentation);
// only the semantic enum + its initialiser from `CaptureSession.State` live here.
//
// Exhaustive switch — no `default` — so a future `State` case is a compile error
// rather than a silent fallback.

import Foundation

/// The semantic icon state shown in the menubar.
///
/// Each case corresponds to a distinct visual intent that the App layer maps to
/// an SF Symbol. The mapping is pure and tested in `SpeakTests/MenubarIconTests.swift`.
public enum MenubarIcon: Equatable, Sendable {
    case idle
    case listening
    case processing
    case done
    case error
}

extension MenubarIcon {
    /// Derive the menubar icon from a `CaptureSession.State`.
    ///
    /// - Parameter state: The current capture-session state.
    /// - Returns: The corresponding `MenubarIcon` case.
    ///
    /// This mapping is `[verified]` by `MenubarIconTests` — it is the only
    /// headlessly-verifiable piece of the app-shell wiring (the live dictation
    /// behavior is human-gated).
    public init(for state: CaptureSession.State) {
        switch state {
        case .idle:
            self = .idle
        case .listening:
            self = .listening
        case .processing:
            self = .processing
        case .done:
            self = .done
        case .error:
            self = .error
        }
    }
}
