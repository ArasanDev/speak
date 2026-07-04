// SpeakCore/Profiles/Profile.swift
//
// The Profile — the single unit of customization for the Profile Engine
// (specs/profile-engine.md §2). A profile is, at heart, "a name + a system
// prompt + a few rules." Every overlay chip, every user customization, Agent
// Mode, code-aware mode — all are instances of this ONE type. There is one
// engine; profiles are its configuration.
//
// PE-0 SCOPE (task #39): this is the DATA MODEL ONLY. Profile resolution (which
// profile applies to a dictation), AI Studio (authoring UI), and the overlay
// control surface are LATER tasks. Nothing here is wired into the live dictation
// flow yet — it is purely additive and must not affect the verified v0 base.
//
// Designed for a very small (~3B) on-device model (profile-engine.md §6): the
// `systemPrompt` is short + imperative, and `examples` (few-shot pairs) are the
// strongest steering lever for a small model.

import Foundation

// MARK: - Profile

/// One configuration of the text engine: a name, a system prompt, and a few
/// structured rules. Built-ins ship as defaults (resettable, not deletable);
/// users may create their own.
public struct Profile: Codable, Identifiable, Sendable, Equatable {

    /// Stable identity for SwiftUI lists + persistence. Built-ins use fixed ids
    /// (see `DefaultProfiles`) so "reset to default" can find them across launches.
    public let id: UUID

    /// Display name shown on the overlay chip and in AI Studio ("Clean", "Code", …).
    public var name: String

    /// SF Symbol name used as the overlay chip glyph.
    public var icon: String

    /// `true` for shipped defaults: customizable + resettable, but not deletable.
    public var isBuiltIn: Bool

    // ── The heart: the customization point ──────────────────────────────────

    /// The system prompt — the editable heart of the profile. Shipped with a
    /// default; fully user-editable. For `.raw` this is empty (pure passthrough).
    public var systemPrompt: String

    /// Few-shot `spoken → written` pairs. The strongest lever for steering a
    /// small model (profile-engine.md §6 rule 2).
    public var examples: [Example]

    // ── Structured knobs (compile into prompt clauses via PromptBuilder) ─────

    public var format: OutputFormat
    public var tone: Tone
    public var length: LengthBias
    public var contextInputs: Set<ContextInput>

    // ── Routing & delivery ──────────────────────────────────────────────────

    /// Bundle IDs (or host strings) that auto-activate this profile when frontmost.
    public var targetApps: [String]

    /// Simulate Return after paste (for agent terminals). PE-0 stores it only.
    public var autoSubmit: Bool

    /// Which model runs the profile. `.raw` is the base-core bypass.
    public var model: ModelChoice

    public init(
        id: UUID = UUID(),
        name: String,
        icon: String,
        isBuiltIn: Bool = false,
        systemPrompt: String,
        examples: [Example] = [],
        format: OutputFormat = .asIs,
        tone: Tone = .neutral,
        length: LengthBias = .preserve,
        contextInputs: Set<ContextInput> = [],
        targetApps: [String] = [],
        autoSubmit: Bool = false,
        model: ModelChoice = .foundationModels
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.isBuiltIn = isBuiltIn
        self.systemPrompt = systemPrompt
        self.examples = examples
        self.format = format
        self.tone = tone
        self.length = length
        self.contextInputs = contextInputs
        self.targetApps = targetApps
        self.autoSubmit = autoSubmit
        self.model = model
    }
}

// MARK: - Example

/// A few-shot pair: raw dictation → desired output. Doubles as the first golden
/// fixture for the small-models eval harness (profile-system-prompts.md §Eval).
public struct Example: Codable, Sendable, Equatable, Hashable {
    public var spoken: String
    public var written: String

    public init(spoken: String, written: String) {
        self.spoken = spoken
        self.written = written
    }
}

// MARK: - Structured knobs

/// Output shape. `asIs` adds no formatting instruction (the system prompt rules).
public enum OutputFormat: String, Codable, Sendable, CaseIterable {
    case asIs, paragraph, bullets, numbered, codeBlock, verbatim
}

/// Voice. `neutral` adds no tone instruction.
public enum Tone: String, Codable, Sendable, CaseIterable {
    case neutral, terse, formal, casual
}

/// Length bias. `preserve` adds no length instruction.
public enum LengthBias: String, Codable, Sendable, CaseIterable {
    case preserve, condense, expand
}

/// Extra context a profile may attach to the prompt at build time. PE-0 defines
/// the cases; the values are supplied by the caller (later tasks wire the sources).
public enum ContextInput: String, Codable, Sendable, CaseIterable {
    case selection, clipboard, currentFile, appName
}

// MARK: - ModelChoice

/// Which model runs a profile. Codable is synthesized for this enum-with-payload.
public enum ModelChoice: Codable, Sendable, Equatable {
    /// Base-core passthrough — no model. The raw transcript is delivered untouched.
    case raw
    /// The default on-device model (Apple Foundation Models).
    case foundationModels
    /// A pluggable engine (MLX / OpenAI-compatible), v0.1+. Identified by id.
    case pluggable(engineID: String)
}
