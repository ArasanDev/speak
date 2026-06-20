// SpeakCore/Logging/SpeakLog.swift
//
// Centralized OSLog categories. Per `AGENTS.md` §3, logging is `os.Logger`
// only — never `print`. Every subsystem logs through one of these so Console
// filtering by category works out of the box.

import os

public enum SpeakLog {
    // Reverse-DNS subsystem. Placeholder bundle prefix until the app target
    // fixes the real bundle id at Phase 0/1; categories below are stable.
    private static let subsystem = "com.speak.core"

    public static let engine      = Logger(subsystem: subsystem, category: "engine")
    public static let audio       = Logger(subsystem: subsystem, category: "audio")
    public static let stt         = Logger(subsystem: subsystem, category: "stt")
    public static let cleanup     = Logger(subsystem: subsystem, category: "cleanup")
    public static let hotkey      = Logger(subsystem: subsystem, category: "hotkey")
    public static let paste       = Logger(subsystem: subsystem, category: "paste")
    public static let permissions = Logger(subsystem: subsystem, category: "permissions")
    public static let storage     = Logger(subsystem: subsystem, category: "storage")
}
