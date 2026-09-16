// SpeakTests/InferenceServerSharingTests.swift
//
// Regression coverage for the single-inference-server fix.
//
// The flaw: the Inference pane (`InferenceViewModel`) and the Agent Playground
// (`PlaygroundViewModel`) each constructed their own `LocalInferenceServer` —
// two listeners contending for loopback port 11235 with no coordination; the
// second to start failed or silently shadowed the first.
//
// The fix: `DictationController` owns ONE instance (composition root),
// `DashboardContext` transports it, and both pane view models receive that
// same instance by injection.
//
// Covered seams:
//   - DashboardContext carries the injected server by reference.
//   - InferenceViewModel + PlaygroundViewModel store the injected instance —
//     same identity, not a copy (the server is an actor: reference type).
//   - LocalInferenceServer.start() is idempotent: a second start() is a no-op
//     that keeps the original port — defense-in-depth so a missed call site
//     degrades to a warning log instead of a second bind attempt.
//
// [decision: a real listener bind is used for the idempotency test on an
//  uncommon high port — start()/stop() mutate state synchronously on the
//  actor, so the assertions are deterministic even though listener readiness
//  is asynchronous.]

@testable import Speak
@testable import SpeakCore
@testable import SpeakLLM
import XCTest

// MARK: - InferenceServerSharingTests

@MainActor
final class InferenceServerSharingTests: XCTestCase {

    // MARK: - Helpers

    /// Minimal `HistoryStoring` so a `DashboardContext` can be built without a
    /// real SQLite file — same pattern as WindowPresenterTests' null store.
    private final class NullHistoryStore: HistoryStoring, @unchecked Sendable {
        func save(_ entry: HistoryEntry) throws {}
        func recent(limit: Int) throws -> [HistoryEntry] { [] }
        func search(_ substring: String) throws -> [HistoryEntry] { [] }
        func clear() throws {}
        func export() throws -> String { "[]" }
    }

    private func makeContext(server: LocalInferenceServer) -> DashboardContext {
        DashboardContext(
            settingsStore: SettingsStore(),
            historyStore: NullHistoryStore(),
            hotkeyCombo: ["Fn", "Fn"],
            inferenceServer: server
        )
    }

    // MARK: - Context transport

    /// `DashboardContext` must carry the injected server instance unchanged —
    /// this is the channel through which both panes receive the shared server.
    func testDashboardContextCarriesInjectedServerByReference() {
        let server = LocalInferenceServer()
        let context = makeContext(server: server)
        XCTAssertTrue(
            context.inferenceServer === server,
            "DashboardContext must hold the injected LocalInferenceServer by reference."
        )
    }

    // MARK: - Both consumers share one instance

    /// The regression itself: both pane view models, built from one context,
    /// must end up holding the SAME server — previously each created its own
    /// and the second listener collided on port 11235.
    func testBothPaneViewModelsShareTheInjectedServer() {
        let server = LocalInferenceServer()
        let context = makeContext(server: server)

        let inferenceVM = InferenceViewModel(server: context.inferenceServer)
        let playgroundVM = PlaygroundViewModel(store: nil, server: context.inferenceServer)

        XCTAssertTrue(
            inferenceVM.server === server,
            "InferenceViewModel must store the injected server, not construct its own."
        )
        XCTAssertTrue(
            playgroundVM.server === server,
            "PlaygroundViewModel must store the injected server, not construct its own."
        )
        XCTAssertTrue(
            inferenceVM.server === playgroundVM.server,
            "Both panes must drive one shared LocalInferenceServer instance."
        )
    }

    // MARK: - start() idempotency (defense-in-depth)

    /// A second `start()` must be a no-op that keeps the originally bound port,
    /// so even a missed call site cannot trigger a second bind.
    /// [decision: port 12871 — uncommon high port, distinct from the app's
    ///  default 11235, so the real bind here collides with nothing in dev.]
    func testSecondStartIsANoOpKeepingOriginalPort() async throws {
        let server = LocalInferenceServer()
        let testPort: UInt16 = 12871

        try await server.start(port: testPort)
        // Second start on a DIFFERENT port — must be ignored entirely.
        try await server.start(port: testPort + 1)

        let running = await server.isRunning
        let boundPort = await server.port
        await server.stop()

        XCTAssertTrue(running, "server must be running after a successful start()")
        XCTAssertEqual(
            boundPort, testPort,
            "second start() must be a no-op — the listener keeps the first port."
        )
        let stoppedRunning = await server.isRunning
        XCTAssertFalse(stoppedRunning, "stop() must release the listener.")
    }
}
