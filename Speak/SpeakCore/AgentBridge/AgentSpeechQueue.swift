// SpeakCore/AgentBridge/AgentSpeechQueue.swift
//
// Serial, actor-owned attention queue for agent-originated speech. The shared
// SpeechSynthesizing conformer intentionally interrupts overlapping direct calls;
// this layer gives the MCP `interrupt` hint real enqueue-vs-replace semantics.

import Foundation

public actor AgentSpeechQueue {
    private struct Item: Sendable {
        let id: UUID
        let text: String
        let locale: Locale
    }

    private let synthesizer: any SpeechSynthesizing
    private var pending: [Item] = []
    private var activeID: UUID?
    private var activeTask: Task<Void, Never>?
    /// Invalidates delegate/task completions belonging to speech interrupted by
    /// a newer request or by human input. [decision: monotonic local generation]
    private var generation: UInt64 = 0

    public init(synthesizer: any SpeechSynthesizing) {
        self.synthesizer = synthesizer
    }

    /// Queue an agent notification. `interrupt == true` discards pending agent
    /// speech and immediately replaces the active utterance. Otherwise the item
    /// waits its turn. Returns after acceptance, not after playback.
    public func submit(text: String, locale: Locale, interrupt: Bool) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let item = Item(id: UUID(), text: trimmed, locale: locale)

        if interrupt {
            generation &+= 1
            let replacementGeneration = generation
            pending.removeAll()
            activeTask?.cancel()
            await synthesizer.stop()
            guard generation == replacementGeneration else { return }
            activeID = nil
            activeTask = nil
            start(item)
        } else if activeID == nil {
            start(item)
        } else {
            pending.append(item)
        }
    }

    /// Human input always wins: stop active agent speech and discard its queue.
    public func cancelAll() async {
        generation &+= 1
        pending.removeAll()
        activeTask?.cancel()
        activeTask = nil
        activeID = nil
        await synthesizer.stop()
    }

    public var queuedCount: Int {
        pending.count + (activeID == nil ? 0 : 1)
    }

    private func start(_ item: Item) {
        activeID = item.id
        let itemGeneration = generation
        activeTask = Task { [weak self, synthesizer] in
            guard !Task.isCancelled else { return }
            await synthesizer.speak(item.text, locale: item.locale)
            await self?.didFinish(id: item.id, generation: itemGeneration)
        }
    }

    private func didFinish(id: UUID, generation itemGeneration: UInt64) {
        guard itemGeneration == generation, activeID == id else { return }
        activeID = nil
        activeTask = nil
        guard !pending.isEmpty else { return }
        start(pending.removeFirst())
    }
}
