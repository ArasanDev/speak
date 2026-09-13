// App/Dashboard/Panes/HomePaneView.swift
//
// The Home pane — the daily-open dashboard surface. Per the locked design spec
// (speak-ui-design-final-2026-06-28.md §Dashboard Home Pane), shows:
// 1. Permission status (top) — quiet "System Ready" when granted; the loud
//    error card with an animated `speakFlowError` border when anything is missing.
// 2. Dictate hero — `speakBone` fill / `speakInk` content; the on-air flow
//    border + tally dot appear only while the microphone is capturing (spec §2).
// 3. Activity Overview — today's words, sessions, AI cleanups.
// 4. Recent Dictations — the last 5 entries; click a row to copy its text.
//
// Card language: the shared `speakCard()` primitive (SpeakCard.swift) — the same
// surface Settings uses, so Home and Settings read as one system.
// [decision: retired the glassmorphism/gradient treatment — restrained Apple
//  chrome; color is reserved for semantics (permissions, on-air, delivered).]

import Foundation
import os
import SpeakCore
import SwiftUI

// MARK: - HomePaneView

struct HomePaneView: View {
    let context: DashboardContext

    @State private var entries: [HistoryEntry] = []
    @State private var loaded = false
    @State private var micPermissionStatus: PermissionState = .notDetermined
    @State private var accPermissionStatus: PermissionState = .notDetermined

    @State private var isCTAHovered = false
    /// Tracks whether dictation is actively recording — drives the on-air
    /// flow border and tally dot.
    @State private var isRecording = false
    /// True while a start/stop task is in flight — the heartbeat must not
    /// overwrite the hero state mid-transition.
    @State private var dictationTransitionInFlight = false
    /// Entry whose text was just copied — drives the transient checkmark.
    @State private var copiedEntryId: UUID?
    @State private var copyFeedbackTask: Task<Void, Never>?

    init(context: DashboardContext) {
        self.context = context
    }

    var body: some View {
        let contentView = ScrollView {
            VStack(alignment: .leading, spacing: SpeakSpacing.lg) {
                permissionStatusCard
                startDictationHero
                todayStatsSection
                recentDictationsSection
            }
            .padding(SpeakSpacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task { await loadInitialData() }
        .task { await monitorLiveState() }
        .onAppear { refreshLiveState() }

        if let publisher = context.dictationCompletedPublisher {
            contentView
                .onReceive(publisher) { _ in
                    isRecording = false
                    Task { await loadInitialData() }
                }
        } else {
            contentView
        }
    }

    // MARK: - Permission status (top)

    /// The three honest states of the permission rail. `unknown` covers the
    /// `permissionManager == nil` window (previews, pre-injection) so the pane
    /// never cries wolf with a red card before status is known.
    private enum PermissionHealth {
        case unknown
        case ready
        case missing([String])
    }

    private var permissionHealth: PermissionHealth {
        guard context.permissionManager != nil else { return .unknown }
        var missing: [String] = []
        if micPermissionStatus != .granted { missing.append("Microphone") }
        if accPermissionStatus != .granted { missing.append("Accessibility") }
        return missing.isEmpty ? .ready : .missing(missing)
    }

    /// Quiet when healthy — the loudest card on the desk when permissions are
    /// missing (error palette + animated error border + the only filled CTA).
    private var permissionStatusCard: some View {
        let health = permissionHealth
        let isMissing: Bool = {
            if case .missing = health { return true }
            return false
        }()

        return HStack(spacing: SpeakSpacing.md) {
            permissionStatusIcon(health)

            VStack(alignment: .leading, spacing: SpeakSpacing.xs) {
                Text(permissionTitle(health))
                    .font(.speakBody(.base, semibold: true))
                    .foregroundStyle(Color.speakBone)
                Text(permissionSubtitle(health))
                    .font(.speakBody(.caption))
                    .foregroundStyle(Color.speakMica)
            }

            Spacer(minLength: 0)

            if isMissing, context.showOnboarding != nil {
                Button(
                    action: { context.showOnboarding?() },
                    label: {
                        Text("Resolve Permissions")
                            .font(.speakBody(.caption, semibold: true))
                            .foregroundStyle(Color.speakOnAccent)
                            .padding(.horizontal, SpeakSpacing.sm + SpeakSpacing.xs)
                            .padding(.vertical, SpeakSpacing.sm)
                            .background(Color.speakError)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                )
                .buttonStyle(.plain)
            }
        }
        .padding(SpeakSpacing.md)
        .speakCard()
        .flowBorder(
            colors: Color.speakFlowError,
            cornerRadius: 16,
            isActive: isMissing
        )
    }

    private func permissionStatusIcon(_ health: PermissionHealth) -> some View {
        let tint: Color
        let symbol: String
        switch health {
        case .ready:
            tint = .speakOK
            symbol = "checkmark.shield.fill"

        case .missing:
            tint = .speakError
            symbol = "exclamationmark.shield.fill"

        case .unknown:
            tint = .speakMica
            symbol = "shield"
        }
        return ZStack {
            Circle()
                .fill(tint.opacity(0.18))
                .frame(width: 32, height: 32)
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .font(.system(size: 16, weight: .semibold))
        }
        .accessibilityHidden(true)
    }

    private func permissionTitle(_ health: PermissionHealth) -> String {
        switch health {
        case .ready: return "System Ready"

        case .missing: return "Permissions Needed"

        case .unknown: return "Checking Permissions"
        }
    }

    private func permissionSubtitle(_ health: PermissionHealth) -> String {
        switch health {
        case .ready:
            return "Microphone and Accessibility are granted."

        case .missing(let names):
            return "\(names.joined(separator: " and ")) access required to dictate."

        case .unknown:
            return "Status appears once the engine attaches."
        }
    }

    // MARK: - Hero Dictation CTA

    /// High-contrast monochrome CTA — `speakBone` fill / `speakInk` content
    /// inverts with the mode, so it reads as the primary action in both light
    /// and dark. The only color is the on-air flow border + tally dot while
    /// recording (spec §2: `speakOnAir` may only appear while the mic is capturing).
    private var startDictationHero: some View {
        Button(action: { toggleDictation() }, label: { heroLabel })
        .buttonStyle(.plain)
        .flowBorder(
            colors: Color.speakFlowOnAir,
            cornerRadius: 16,
            isActive: isRecording
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: SpeakMotion.microDuration)) {
                isCTAHovered = hovering
            }
        }
        .opacity(isCTAHovered ? 0.92 : 1.0)
        .accessibilityLabel(isRecording ? "Stop dictation" : "Start dictation")
    }

    private var heroLabel: some View {
        HStack(spacing: SpeakSpacing.md) {
            Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Color.speakInk)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 28)

            VStack(alignment: .leading, spacing: SpeakSpacing.xs) {
                Text(isRecording ? "Stop Dictation" : "Start Dictation")
                    .font(.speakDisplay(.title))
                    .foregroundStyle(Color.speakInk)
                HStack(spacing: SpeakSpacing.sm) {
                    if isRecording {
                        // The live tally — `onAir` exists ONLY here while
                        // the mic captures (spec §2 hard rule).
                        Circle()
                            .fill(Color.speakOnAir)
                            .frame(width: SpeakSpacing.sm, height: SpeakSpacing.sm)
                    }
                    Text(isRecording ? "Listening — tap to finish and paste" : "Double-tap your hotkey, or click here")
                        .font(.speakBody(.caption))
                        .foregroundStyle(Color.speakInk.opacity(0.7))
                }
            }

            Spacer(minLength: 0)

            // Hotkey keycaps — ink-on-ink so they read on the bone fill.
            HStack(spacing: SpeakSpacing.xs) {
                ForEach(Array(context.hotkeyCombo.enumerated()), id: \.offset) { _, key in
                    Text(key)
                        .font(.speakMonoKeycap)
                        .foregroundStyle(Color.speakInk)
                        .padding(.horizontal, SpeakSpacing.sm)
                        .padding(.vertical, SpeakSpacing.xs)
                        .background(Color.speakInk.opacity(0.10))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
            }
        }
        .padding(SpeakSpacing.lg)
        .background(Color.speakBone)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func toggleDictation() {
        dictationTransitionInFlight = true
        if isRecording {
            Task {
                if let onStop = context.onStopDictation {
                    await onStop()
                } else if let engine = context.speakEngine {
                    _ = try? await engine.endDictation()
                }
                isRecording = false
                dictationTransitionInFlight = false
            }
        } else {
            Task {
                if let onStart = context.onStartDictation {
                    await onStart()
                    isRecording = context.isDictating?() ?? true
                } else if let engine = context.speakEngine {
                    do {
                        _ = try await engine.beginDictation()
                        isRecording = true
                    } catch {
                        SpeakLog.engine.error("Start dictation failed: \(error.localizedDescription)")
                        isRecording = false
                    }
                }
                dictationTransitionInFlight = false
            }
        }
    }

    // MARK: - Activity Overview

    private var todayStatsSection: some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.md) {
            sectionHeader("Activity Overview")

            let stats = InsightsStats(entries: todayEntries, now: Date(), calendar: .current)

            HStack(spacing: SpeakSpacing.md) {
                statCard(
                    title: "Words Dictated",
                    value: "\(stats.totalWords)",
                    icon: "text.word.spacing"
                )

                statCard(
                    title: "Sessions Today",
                    value: "\(todayEntries.count)",
                    icon: "waveform"
                )

                if context.settingsStore.cleanupEnabled {
                    statCard(
                        title: "AI Cleanups",
                        value: "\(todayEntries.compactMap { $0.cleanedText }.count)",
                        icon: "wand.and.stars"
                    )
                }
            }
        }
    }

    private func statCard(title: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.sm + SpeakSpacing.xs) {
            Image(systemName: icon)
                .font(.speakBody(.base, semibold: true))
                .foregroundStyle(Color.speakMica)

            VStack(alignment: .leading, spacing: SpeakSpacing.xs) {
                Text(value)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.speakBone)
                Text(title)
                    .font(.speakBody(.caption))
                    .foregroundStyle(Color.speakMica)
            }
        }
        .padding(SpeakSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .speakCard()
    }

    // MARK: - Recent Dictations (last 5)

    private var recentDictationsSection: some View {
        VStack(alignment: .leading, spacing: SpeakSpacing.md) {
            sectionHeader("Recent Dictations")

            if !loaded {
                loadingCard
            } else if entries.isEmpty {
                emptyState
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(entries.prefix(5).enumerated()), id: \.element.id) { index, entry in
                        if index > 0 {
                            rowSeparator
                        }
                        RecentEntryRow(
                            entry: entry,
                            isCopied: copiedEntryId == entry.id,
                            onCopy: { copyEntry(entry) }
                        )
                    }
                }
                .speakCard()
            }
        }
    }

    /// Hairline between rows, inset to the card's padding rhythm.
    private var rowSeparator: some View {
        Rectangle()
            .fill(Color.speakCardBorder)
            .frame(height: 1)
            .padding(.horizontal, SpeakSpacing.md)
    }

    private var loadingCard: some View {
        HStack(spacing: SpeakSpacing.sm) {
            ProgressView()
                .controlSize(.small)
            Text("Loading history…")
                .font(.speakBody(.caption))
                .foregroundStyle(Color.speakMica)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, SpeakSpacing.xl)
        .speakCard()
    }

    /// True empty state (nothing dictated yet) — icon + line + a real hint
    /// bound to the user's actual hotkey combo.
    private var emptyState: some View {
        VStack(spacing: SpeakSpacing.sm + SpeakSpacing.xs) {
            Image(systemName: "waveform")
                .font(.system(size: 28))
                .foregroundStyle(Color.speakMica.opacity(0.6))
            Text("No dictations yet")
                .font(.speakBody(.base, semibold: true))
                .foregroundStyle(Color.speakBone)
            HStack(spacing: SpeakSpacing.xs) {
                Text("Press")
                    .font(.speakBody(.caption))
                    .foregroundStyle(Color.speakMica)
                ForEach(Array(context.hotkeyCombo.enumerated()), id: \.offset) { _, key in
                    KeyCapView(label: key)
                }
                Text("to dictate your first note")
                    .font(.speakBody(.caption))
                    .foregroundStyle(Color.speakMica)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, SpeakSpacing.xl)
        .speakCard()
    }

    // MARK: - Section header chrome

    /// Dashboard chrome per the design contract: 16pt semibold bone on canvas.
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Color.speakBone)
    }

    // MARK: - Actions

    /// Copies the entry's pasted text (cleaned preferred, raw fallback) to the
    /// pasteboard. Write-only — the app never reads the pasteboard (§2).
    private func copyEntry(_ entry: HistoryEntry) {
        let text = entry.cleanedText ?? entry.rawText
        guard !text.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        copiedEntryId = entry.id
        copyFeedbackTask?.cancel()
        copyFeedbackTask = Task {
            // [decision: 1.5s confirmation dwell — standard transient-toast timing]
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            copiedEntryId = nil
        }
    }

    // MARK: - Data loading & live state

    private func loadInitialData() async {
        do {
            let all = try await context.historyStore.recent(limit: 100)
            entries = all.sorted { $0.createdAt > $1.createdAt }
        } catch {
            entries = []
        }
        loaded = true
    }

    /// 1s heartbeat [decision]: reflects dictations started via the hotkey and
    /// permissions granted in System Settings while the desk is open.
    /// `DashboardContext` exposes no event seam for either, and both checks are
    /// cheap reads on already-injected objects. Cancelled with the view's task.
    private func monitorLiveState() async {
        while !Task.isCancelled {
            refreshLiveState()
            try? await Task.sleep(for: .seconds(1))
        }
    }

    private func refreshLiveState() {
        updatePermissionStatus()
        guard !dictationTransitionInFlight else { return }
        if let isDictating = context.isDictating {
            isRecording = isDictating()
        }
    }

    private func updatePermissionStatus() {
        guard let pm = context.permissionManager else { return }
        micPermissionStatus = pm.status(.microphone)
        accPermissionStatus = pm.status(.accessibility)
    }

    /// Entries captured today — drives the Activity Overview numbers.
    private var todayEntries: [HistoryEntry] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return entries.filter { calendar.startOfDay(for: $0.createdAt) == today }
    }
}

// MARK: - RecentEntryRow

/// One recent dictation. Click copies the pasted text (cleaned ?? raw); hover
/// reveals the copy affordance, and a brief `delivered` checkmark confirms.
private struct RecentEntryRow: View {
    let entry: HistoryEntry
    let isCopied: Bool
    let onCopy: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onCopy) {
            HStack(spacing: SpeakSpacing.md) {
                // Timestamp pill — recessed well, mono data face.
                Text(entry.createdAt, format: .dateTime.hour().minute())
                    .font(.speakMonoFace(.caption, semibold: true))
                    .foregroundStyle(Color.speakMica)
                    .padding(.horizontal, SpeakSpacing.sm)
                    .padding(.vertical, SpeakSpacing.xs)
                    .speakInset(cornerRadius: 6)

                VStack(alignment: .leading, spacing: SpeakSpacing.xs) {
                    Text(primaryText)
                        .font(.speakBody(.base))
                        .foregroundStyle(primaryIsPlaceholder ? Color.speakMica : Color.speakBone)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if let cleaned = entry.cleanedText, cleaned != entry.rawText, !cleaned.isEmpty {
                        HStack(spacing: SpeakSpacing.xs) {
                            Image(systemName: "wand.and.stars")
                                .font(.speakBody(.caption))
                            Text(cleaned)
                                .font(.speakBody(.caption))
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        .foregroundStyle(Color.speakMica)
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                    .font(.speakBody(.base, semibold: true))
                    .foregroundStyle(isCopied ? Color.speakDelivered : Color.speakMica)
                    .opacity(isCopied || isHovered ? 1.0 : 0.0)
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(.horizontal, SpeakSpacing.md)
            .padding(.vertical, SpeakSpacing.sm + SpeakSpacing.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Color.speakMica.opacity(isHovered ? 0.08 : 0.0))
        .onHover { hovering in
            withAnimation(.easeInOut(duration: SpeakMotion.microDuration)) {
                isHovered = hovering
            }
        }
        .help(isCopied ? "Copied" : "Click to copy")
        .accessibilityLabel("Dictation from \(entry.createdAt.formatted(date: .omitted, time: .shortened))")
    }

    /// The row's headline: raw transcript, falling back to cleaned text, then
    /// an honest placeholder when a row somehow has neither.
    private var primaryText: String {
        if !entry.rawText.isEmpty { return entry.rawText }
        if let cleaned = entry.cleanedText, !cleaned.isEmpty { return cleaned }
        return "Empty transcription"
    }

    private var primaryIsPlaceholder: Bool {
        entry.rawText.isEmpty && (entry.cleanedText?.isEmpty ?? true)
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Home — empty history") {
    HomePaneView(context: DashboardContext(
        settingsStore: SettingsStore(),
        historyStore: PreviewNullHistoryStore(),
        hotkeyCombo: ["Fn", "Fn"]
    ))
    .frame(width: 820, height: 560)
}

#Preview("Home — with dictations") {
    HomePaneView(context: DashboardContext(
        settingsStore: SettingsStore(),
        historyStore: PreviewNullHistoryStore(),
        hotkeyCombo: ["Fn", "Fn"]
    ))
    .frame(width: 820, height: 560)
}
#endif
