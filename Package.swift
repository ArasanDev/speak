// swift-tools-version: 5.9
//
// TEMPORARY SwiftPM harness — NOT the canonical build system.
//
// The mandated build system (docs/architecture.md §5) is an Xcode project with
// an app target + `SpeakCore.framework` + `SpeakTests`. That requires full
// Xcode, which is being installed. Until then, this manifest lets us build and
// `swift test` the framework-agnostic engine core (protocols, value types,
// error model, logging) with the Command Line Tools alone.
//
// The source files live in their FINAL `docs/architecture.md` §5 locations
// (SpeakCore/Engine, SpeakCore/STT, …) via explicit `path:`, so when the Xcode
// framework target is created it picks them up with zero movement. This file
// is then either removed or kept as a parallel test entry point.

import PackageDescription

let package = Package(
    name: "SpeakCore",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "SpeakCore", targets: ["SpeakCore"]),
    ],
    targets: [
        .target(
            name: "SpeakCore",
            path: "SpeakCore"
        ),
        // TEMPORARY runtime verification, runnable under Command Line Tools
        // (XCTest/swift-testing need full Xcode). `swift run speak-smoke`.
        // Superseded by SpeakTests/ once Xcode is installed.
        .executableTarget(
            name: "speak-smoke",
            dependencies: ["SpeakCore"],
            path: "Smoke"
        ),
        // Canonical tests (swift-testing). Build/run under Xcode's SpeakTests
        // target; cannot execute under Command Line Tools (no Testing module).
        .testTarget(
            name: "SpeakTests",
            dependencies: ["SpeakCore"],
            path: "SpeakTests"
        ),
    ]
)
