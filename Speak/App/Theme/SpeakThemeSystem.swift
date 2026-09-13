// App/Theme/SpeakThemeSystem.swift
//
// Runtime color themes — inspired by t3code's theme system
// (`apps/web/src/themePalette.ts`): a theme is a *named palette* of semantic
// color ROLES (not per-component colors), each role carrying a light + dark
// value. The active palette is painted app-wide at once; custom themes are
// user-editable at runtime and persist alongside built-ins.
//
// ARCHITECTURE [decision]:
//   - `ThemeColorRole` — the editable token set. Views never name literal
//     colors; they name roles (windowCanvas, humanAmber, …).
//   - `SpeakTheme` — Codable value: id + name + sparse `[role: hex pair]`
//     overrides merged over the default theme (lenient, like t3code's
//     `parseStoredThemeColors` — a partial theme still resolves every role).
//   - `SpeakThemeRuntime.active` — the one mutable registry the `Color.speak*`
//     statics resolve through. Static tokens can't read SwiftUI environment,
//     so this is the single sanctioned app-scope mutable: written ONLY by
//     `ThemeEngine` (main actor), read inside view bodies. Repaint is driven
//     by `ThemedRoot`, which injects `\.speakTheme` — an environment change
//     invalidates the whole subtree, re-evaluating every static token
//     WITHOUT remounting views (unlike `.id()`), so scroll/selection survive.
//   - `accent` is OPTIONAL: nil → `Color.accentColor` (system). Only custom
//     themes that set it override the macOS accent.
//
// Persistence lives in `SettingsStore` (`themeID`, `customThemesJSON`) — the
// store holds raw strings/Data; this file owns the schema.
//
// SECOND BUILT-IN: `ember` — a warm paper/ember palette pairing the amber
// human channel with a dark warm canvas (nods to t3code's `ember`).

import AppKit
import SwiftUI

// MARK: - ThemeColorRole

/// A semantic color role — the axis themes vary on. Raw values are the JSON
/// keys in stored themes; keep them stable forever (user data).
enum ThemeColorRole: String, CaseIterable, Codable, Sendable {
    // Surfaces
    case windowCanvas
    case cardCanvas
    case sidebarBg
    case surface
    case cardBorder
    case sidebarSelection
    case ink
    case ink2
    // Text
    case bone
    case mica
    // Channels ("who is acting?" — spec §2)
    case humanAmber
    case agentViolet
    case onAir
    case delivered
    // Status
    case error
    case warning
    case ok
    // Optional: nil in a theme resolves to `Color.accentColor`.
    case accent
    /// Text/glyph drawn ON the accent fill (rail pill, filled buttons).
    /// Bright accents (ember dark) need dark text — a fixed white fails.
    case onAccent

    /// Editor grouping (t3code's ThemeEditorPanel groups roles the same way).
    var editorGroup: String {
        switch self {
        case .windowCanvas, .cardCanvas, .sidebarBg, .surface,
             .cardBorder, .sidebarSelection, .ink, .ink2:
            return "Surfaces"
        case .bone, .mica:
            return "Text"
        case .humanAmber, .agentViolet, .onAir, .delivered:
            return "Channels"
        case .error, .warning, .ok:
            return "Status"
        case .accent, .onAccent:
            return "Accent"
        }
    }

    var displayName: String {
        switch self {
        case .windowCanvas:      return "Window Canvas"
        case .cardCanvas:        return "Card Canvas"
        case .sidebarBg:         return "Sidebar"
        case .surface:           return "Inset Surface"
        case .cardBorder:        return "Hairline Border"
        case .sidebarSelection:  return "Sidebar Selection"
        case .ink:               return "Deep Surface"
        case .ink2:              return "Raised Surface"
        case .bone:              return "Primary Text"
        case .mica:              return "Secondary Text"
        case .humanAmber:        return "Human (Mic)"
        case .agentViolet:       return "Agent"
        case .onAir:             return "On Air"
        case .delivered:         return "Delivered"
        case .error:             return "Error"
        case .warning:           return "Warning"
        case .ok:                return "Healthy"
        case .accent:            return "Accent"
        case .onAccent:          return "On-Accent Text"
        }
    }
}

// MARK: - ThemeHexPair

/// One role's light + dark hex values ("#RRGGBB" / "#RRGGBBAA"). Stored as
/// strings (like t3code's `ThemeColors` record) so themes are portable text.
struct ThemeHexPair: Codable, Equatable, Sendable {
    var light: String
    var dark: String

    /// Adaptive color resolved against the current NSAppearance — same
    /// mechanism the FE-1 tokens already use.
    var color: Color {
        let lightHex = light
        let darkHex = dark
        return Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            // Malformed hex resolves magenta — loud, not invisible.
            return NSColor(speakHex: isDark ? darkHex : lightHex) ?? .magenta
        })
    }
}

// MARK: - SpeakTheme

/// A named palette. `colors` is SPARSE — roles missing here resolve from
/// `SpeakTheme.default`. `accent` may be nil (system accent).
struct SpeakTheme: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var name: String
    /// Keyed by `ThemeColorRole.rawValue` (not the enum) so unknown roles in
    /// a stored theme decode leniently instead of failing the whole file.
    var colors: [String: ThemeHexPair]

    var isBuiltIn: Bool {
        Self.builtInIDs.contains(id)
    }

    static let builtInIDs: Set<String> = ["speak", "ember"]

    /// Resolve a role: this theme's override, else the default theme's value.
    /// `accent` falls back to the system accent color when unset anywhere.
    func color(_ role: ThemeColorRole) -> Color {
        guard let pair = pair(for: role) else { return .accentColor }
        return pair.color
    }

    func pair(for role: ThemeColorRole) -> ThemeHexPair? {
        colors[role.rawValue] ?? Self.speak.colors[role.rawValue]
    }

    // MARK: Built-in themes

    /// `speak` — the FE-1 default palette. Every role defined (the merge base);
    /// `accent` intentionally absent → system accent.
    static let speak = SpeakTheme(
        id: "speak",
        name: "Speak",
        colors: [
            "windowCanvas":     ThemeHexPair(light: "#F5F3EF", dark: "#16181D"),
            "cardCanvas":       ThemeHexPair(light: "#FFFFFF", dark: "#1C1F26"),
            "sidebarBg":        ThemeHexPair(light: "#F3F2EE", dark: "#121418"),
            // Recessed inset tone — sits between canvas and border so mica
            // text stays ≥ ~3.9:1 on it in light (was #969696 → 1.1:1, an
            // unreadable solid-gray card). [decision: WCAG audit]
            "surface":          ThemeHexPair(light: "#EAE8E2", dark: "#2C303A"),
            "cardBorder":       ThemeHexPair(light: "#D6D2C7", dark: "#3A3F4D"),
            "sidebarSelection": ThemeHexPair(light: "#DAD6CC", dark: "#262A34"),
            "ink":              ThemeHexPair(light: "#E9E6E0", dark: "#16181D"),
            "ink2":             ThemeHexPair(light: "#FFFFFF", dark: "#1F232B"),
            "bone":             ThemeHexPair(light: "#16181D", dark: "#E9E6E0"),
            // mica darkened in light — #8A8F98 failed 4.5:1 body text on every
            // light surface (2.9-3.25). [decision: WCAG audit]
            "mica":             ThemeHexPair(light: "#656C78", dark: "#8A8F98"),
            // Channel/status hues get text-legible light values (≥3:1 UI /
            // ≥4.5:1 where they carry body text); dark values stay vivid on
            // the dark canvas + dark-glass HUD.
            "humanAmber":       ThemeHexPair(light: "#B87514", dark: "#FFB25A"),
            "agentViolet":      ThemeHexPair(light: "#6B5BD6", dark: "#9D8CFF"),
            "onAir":            ThemeHexPair(light: "#E0342C", dark: "#FF5C49"),
            "delivered":        ThemeHexPair(light: "#23804B", dark: "#5FBF8F"),
            "error":            ThemeHexPair(light: "#B02318", dark: "#FF6B61"),
            "warning":          ThemeHexPair(light: "#B54708", dark: "#FFB224"),
            "ok":               ThemeHexPair(light: "#2E7D4F", dark: "#5FBF8F"),
            "onAccent":         ThemeHexPair(light: "#FFFFFF", dark: "#FFFFFF"),
        ]
    )

    /// `ember` — warm paper/ember. Dark canvas warms toward brown-black; the
    /// amber human channel keeps its hue (it IS the ember), accent goes
    /// ember-orange. [decision: the one extra built-in the user asked for.]
    static let ember = SpeakTheme(
        id: "ember",
        name: "Ember",
        colors: [
            "windowCanvas":     ThemeHexPair(light: "#F6F0E6", dark: "#1C1611"),
            "cardCanvas":       ThemeHexPair(light: "#FFFBF4", dark: "#251F18"),
            "sidebarBg":        ThemeHexPair(light: "#EFE7DA", dark: "#15110C"),
            "surface":          ThemeHexPair(light: "#EDE4D4", dark: "#3A2F24"),
            "cardBorder":       ThemeHexPair(light: "#CDBBA0", dark: "#4A3E30"),
            "sidebarSelection": ThemeHexPair(light: "#D9C8AC", dark: "#3A2F22"),
            "ink":              ThemeHexPair(light: "#EFE7D8", dark: "#1C1611"),
            "ink2":             ThemeHexPair(light: "#FFFBF4", dark: "#282118"),
            "bone":             ThemeHexPair(light: "#2A1E10", dark: "#F2E8D8"),
            "mica":             ThemeHexPair(light: "#71624F", dark: "#9C8A74"),
            "humanAmber":       ThemeHexPair(light: "#B87514", dark: "#FFB25A"),
            "agentViolet":      ThemeHexPair(light: "#7058D6", dark: "#B09CFF"),
            "onAir":            ThemeHexPair(light: "#E0342C", dark: "#FF5C49"),
            "delivered":        ThemeHexPair(light: "#3F7A4D", dark: "#62B98B"),
            "error":            ThemeHexPair(light: "#C23B22", dark: "#FF7A66"),
            "warning":          ThemeHexPair(light: "#B45309", dark: "#FFB224"),
            "ok":               ThemeHexPair(light: "#4E7A3A", dark: "#8FBC7A"),
            "accent":           ThemeHexPair(light: "#D4571E", dark: "#FF9E57"),
            // Ember's dark accent is bright — dark text required on it.
            "onAccent":         ThemeHexPair(light: "#FFFFFF", dark: "#2A1E10"),
        ]
    )

    static let builtInThemes: [SpeakTheme] = [.speak, .ember]
    static let `default` = SpeakTheme.speak
}

// MARK: - SpeakThemeRuntime

/// The resolved active palette that `Color.speak*` statics read through.
///
/// [decision: the ONE app-scope mutable — see file header. `Color.speakX`
/// statics cannot take SwiftUI environment, so the palette lives here and is
/// written only by `ThemeEngine` on the main actor. `nonisolated(unsafe)`
/// because view bodies are not guaranteed main-actor-isolated at compile
/// time; actual writes are main-actor-only and reads are snapshot-cheap.]
enum SpeakThemeRuntime {
    nonisolated(unsafe) static var active: SpeakTheme = .speak

    static func color(_ role: ThemeColorRole) -> Color {
        active.color(role)
    }
}

// MARK: - Environment

private struct SpeakThemeEnvironmentKey: EnvironmentKey {
    static let defaultValue: SpeakTheme = .speak
}

extension EnvironmentValues {
    /// The active theme. Injected by `ThemedRoot`; changing it invalidates the
    /// entire subtree, which is what repaints the `Color.speak*` statics.
    /// New code may also read it directly via `@Environment(\.speakTheme)`.
    var speakTheme: SpeakTheme {
        get { self[SpeakThemeEnvironmentKey.self] }
        set { self[SpeakThemeEnvironmentKey.self] = newValue }
    }
}

// MARK: - ThemedRoot

/// Root wrapper for every hosted surface (dashboard window, settings scene,
/// sheets). Observes the engine and injects the active theme: an environment
/// change re-evaluates every descendant body — so `Color.speak*` statics and
/// `.tint` repaint live, without remounting (scroll position and @State
/// survive, which `.id()` would destroy on every editor drag tick).
struct ThemedRoot<Content: View>: View {
    let engine: ThemeEngine
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .environment(\.speakTheme, engine.activeTheme)
            .tint(engine.activeTheme.color(.accent))
    }
}

extension View {
    /// Wrap in `ThemedRoot` when the context carries an engine (it is nil in
    /// previews/tests, where the default palette applies anyway).
    @ViewBuilder
    func speakThemed(with engine: ThemeEngine?) -> some View {
        if let engine {
            ThemedRoot(engine: engine) { self }
        } else {
            self
        }
    }
}

// MARK: - Hex parsing

extension NSColor {
    /// "#RGB" / "#RRGGBB" / "#RRGGBBAA" → NSColor (sRGB). Invalid input falls
    /// back to magenta so a malformed stored theme is loud, not invisible.
    convenience init?(speakHex raw: String) {
        var hex = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") { hex.removeFirst() }
        if hex.count == 3 {
            hex = hex.map { "\($0)\($0)" }.joined()
        }
        guard hex.count == 6 || hex.count == 8,
              let value = UInt64(hex, radix: 16) else { return nil }
        let hasAlpha = hex.count == 8
        let divisor: CGFloat = 255
        let r = CGFloat((value >> (hasAlpha ? 24 : 16)) & 0xFF) / divisor
        let g = CGFloat((value >> (hasAlpha ? 16 : 8)) & 0xFF) / divisor
        let b = CGFloat((value >> (hasAlpha ? 8 : 0)) & 0xFF) / divisor
        let a = hasAlpha ? CGFloat(value & 0xFF) / divisor : 1
        self.init(srgbRed: r, green: g, blue: b, alpha: a)
    }
}

extension Color {
    /// Color → "#RRGGBB" (sRGB, alpha dropped — theme tokens are opaque).
    /// Nil when the color can't resolve in the current appearance.
    func speakHexString() -> String? {
        guard let srgb = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        return String(
            format: "#%02X%02X%02X",
            Int((srgb.redComponent * 255).rounded()),
            Int((srgb.greenComponent * 255).rounded()),
            Int((srgb.blueComponent * 255).rounded())
        )
    }
}
