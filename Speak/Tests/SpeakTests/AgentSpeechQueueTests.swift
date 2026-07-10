@testable import SpeakCore
import XCTest

private actor QueueTestSynthesizer: SpeechSynthesizing {
    private var calls: [String] = []
    private var continuation: CheckedContinuation<Void, Never>?
    private var speaking = false

    var isSpeaking: Bool { speaking }

    func speak(_ text: String, locale: Locale) async {
        calls.append(text)
        speaking = true
        await withCheckedContinuation { continuation = $0 }
    }

    func stop() async {
        finishCurrent()
    }

    func finishCurrent() {
        speaking = false
        continuation?.resume()
        continuation = nil
    }

    func snapshot() -> [String] { calls }
}

final class AgentSpeechQueueTests: XCTestCase {
    private func waitForCalls(_ count: Int, synthesizer: QueueTestSynthesizer) async -> [String] {
        for _ in 0 ..< 200 {
            let calls = await synthesizer.snapshot()
            if calls.count >= count { return calls }
            await Task.yield()
        }
        return await synthesizer.snapshot()
    }

    private func waitForQueuedCount(_ count: Int, queue: AgentSpeechQueue) async -> Int {
        for _ in 0 ..< 200 {
            let queued = await queue.queuedCount
            if queued == count { return queued }
            await Task.yield()
        }
        return await queue.queuedCount
    }

    private func waitForLastCall(_ text: String, synthesizer: QueueTestSynthesizer) async -> [String] {
        for _ in 0 ..< 200 {
            let calls = await synthesizer.snapshot()
            if calls.last == text { return calls }
            await Task.yield()
        }
        return await synthesizer.snapshot()
    }

    func testNonInterruptingNotificationsPlaySerially() async {
        let synthesizer = QueueTestSynthesizer()
        let queue = AgentSpeechQueue(synthesizer: synthesizer)
        let locale = Locale(identifier: "en-US")

        await queue.submit(text: "first", locale: locale, interrupt: false)
        await queue.submit(text: "second", locale: locale, interrupt: false)
        let firstSnapshot = await waitForCalls(1, synthesizer: synthesizer)
        let initiallyQueued = await queue.queuedCount
        XCTAssertEqual(firstSnapshot, ["first"])
        XCTAssertEqual(initiallyQueued, 2)

        await synthesizer.finishCurrent()
        let serialCalls = await waitForCalls(2, synthesizer: synthesizer)
        XCTAssertEqual(serialCalls, ["first", "second"])
        await synthesizer.finishCurrent()
        let remaining = await waitForQueuedCount(0, queue: queue)
        XCTAssertEqual(remaining, 0)
    }

    func testInterruptReplacesActiveAndPendingSpeech() async {
        let synthesizer = QueueTestSynthesizer()
        let queue = AgentSpeechQueue(synthesizer: synthesizer)
        let locale = Locale(identifier: "en-US")

        await queue.submit(text: "active", locale: locale, interrupt: false)
        await queue.submit(text: "stale pending", locale: locale, interrupt: false)
        await queue.submit(text: "urgent", locale: locale, interrupt: true)

        let calls = await waitForLastCall("urgent", synthesizer: synthesizer)
        XCTAssertEqual(calls.last, "urgent")
        XCTAssertFalse(calls.contains("stale pending"))
        let queued = await queue.queuedCount
        XCTAssertEqual(queued, 1)
        await synthesizer.finishCurrent()
    }

    func testCancelAllPreventsQueuedSpeechFromResuming() async {
        let synthesizer = QueueTestSynthesizer()
        let queue = AgentSpeechQueue(synthesizer: synthesizer)
        let locale = Locale(identifier: "en-US")

        await queue.submit(text: "active", locale: locale, interrupt: false)
        await queue.submit(text: "pending", locale: locale, interrupt: false)
        await queue.cancelAll()
        for _ in 0 ..< 20 { await Task.yield() }

        let calls = await synthesizer.snapshot()
        let queued = await queue.queuedCount
        XCTAssertFalse(calls.contains("pending"))
        XCTAssertEqual(queued, 0)
    }
}
