// Speak/SpeakCore/AgentBridge/EvidencePayload.swift
//
// Standardized JSON-Codable domain model for Rich Media Evidence Cards returned by
// tagged agents and plugins (@Claude, @github, @terminal, @builder-qa).
//
// Holds checklists, image/video attachment paths, patch diffs, and audio readback paths.

import Foundation

/// Status of an individual task inside an agent checklist.
public enum TaskChecklistStatus: String, Codable, Sendable, Equatable {
    case pending
    case inProgress = "in_progress"
    case done
    case blocked
    case failed
}

/// An individual item in a live agent task checklist.
public struct TaskChecklistItem: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public var status: TaskChecklistStatus

    public init(id: String, title: String, status: TaskChecklistStatus = .pending) {
        self.id = id
        self.title = title
        self.status = status
    }
}

/// A code patch diff block attached to an evidence card.
public struct CodeDiffBlock: Codable, Sendable, Equatable {
    public let file: String
    public let patch: String

    public init(file: String, patch: String) {
        self.file = file
        self.patch = patch
    }
}

/// Standardized Rich Evidence Card payload emitted by agents and plugins.
public struct EvidencePayload: Codable, Sendable, Equatable {
    public var summary: String
    public var checklist: [TaskChecklistItem]
    public var images: [String]
    public var videos: [String]
    public var diffs: [CodeDiffBlock]
    public var audioPath: String?

    public init(
        summary: String,
        checklist: [TaskChecklistItem] = [],
        images: [String] = [],
        videos: [String] = [],
        diffs: [CodeDiffBlock] = [],
        audioPath: String? = nil
    ) {
        self.summary = summary
        self.checklist = checklist
        self.images = images
        self.videos = videos
        self.diffs = diffs
        self.audioPath = audioPath
    }
}
