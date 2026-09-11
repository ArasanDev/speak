// App/Dashboard/Panes/HomePaneView.swift
//
// The Home pane — the daily-open dashboard surface. Per the locked design spec
// (speak-ui-design-final-2026-06-28.md §Dashboard Home Pane), shows:
// 1. Hotkey Status (top) — green/red indicator + quick link to grant permissions
// 2. [Start Dictation] button (prominent blue CTA)
// 3. Today's Quick Stats (words, sessions, engine badge)
// 4. Recent Dictations (last 5 entries with time, raw/cleaned preview, engine)
//
// Redesigned for a modern glassmorphism aesthetic.

import Foundation
import os
import SpeakCore
import SwiftUI

// MARK: - Glassmorphism Modifier

private struct GlassCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial)
            .background(Color.white.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(LinearGradient(
                        colors: [.white.opacity(0.4), .white.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.15), radius: 15, x: 0, y: 8)
    }
}

extension View {
    fileprivate func glassCard() -> some View {
        self.modifier(GlassCardModifier())
    }
}

// MARK: - HomePaneView

struct HomePaneView: View {
    let context: DashboardContext

    @State private var entries: [HistoryEntry] = []
    @State private var loaded = false
    @State private var micPermissionStatus: PermissionState = .notDetermined
    @State private var accPermissionStatus: PermissionState = .notDetermined
    
    @State private var isCTAHovered = false
    @State private var isPulseAnimating = false
    /// Tracks whether dictation is actively recording — drives the On-Air flow border.
    @State private var isRecording = false

    init(context: DashboardContext) {
        self.context = context
    }

    var body: some View {
        let contentView = ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Hotkey status
                hotkeyStatusSection
                
                // Hero CTA
                startDictationHero
                
                // Today's Stats
                todayStatsSection
                
                // Recent Dictations
                recentDictationsSection
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task { await loadInitialData() }
        .onAppear {
            updatePermissionStatus()
            if let isDictating = context.isDictating {
                isRecording = isDictating()
            }
        }

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

    // MARK: - Hotkey Status (top)

    private var hotkeyStatusSection: some View {
        let ready = micPermissionStatus == .granted && accPermissionStatus == .granted

        return HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(ready ? Color.green.opacity(0.2) : Color.red.opacity(0.2))
                    .frame(width: 32, height: 32)
                
                Image(systemName: ready ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                    .foregroundStyle(ready ? Color.green : Color.red)
                    .font(.system(size: 16, weight: .semibold))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(ready ? "System Ready" : "Missing Permissions")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.primary)
                Text(ready
                    ? "Microphone & Accessibility granted"
                    : "Action required to enable dictation")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            if !ready {
                Button(action: { context.showOnboarding?() }) {
                    Text("Resolve Permissions →")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.red)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .glassCard()
    }

    // MARK: - Hero Dictation CTA

    private var startDictationHero: some View {
        Button(action: { startDictation() }) {
            ZStack {
                // Background Gradient
                LinearGradient(
                    colors: [Color.blue.opacity(0.8), Color.purple.opacity(0.8)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                
                // Glow effect when hovered
                if isCTAHovered {
                    LinearGradient(
                        colors: [Color.blue, Color.purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .blur(radius: 20)
                    .opacity(0.6)
                }

                HStack(spacing: 16) {
                    Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.white)
                        .scaleEffect(isPulseAnimating ? 1.05 : 1.0)
                        .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: isPulseAnimating)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(isRecording ? "Stop Dictation" : "Start Dictation")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white)
                        Text(isRecording ? "Recording..." : "Powered by AI")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    
                    Spacer()
                    
                    // Hotkey Pill
                    HStack(spacing: 4) {
                        ForEach(context.hotkeyCombo, id: \.self) { key in
                            Text(key)
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.black.opacity(0.3))
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
                .background(
                    LinearGradient(
                        colors: [Color.blue, Color.purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(0.4), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
        }
        .buttonStyle(.plain)
        .flowBorder(
            colors: Color.speakFlowOnAir,
            cornerRadius: 20,
            isActive: isRecording
        )
        .onHover { hovering in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isCTAHovered = hovering
            }
        }
        .scaleEffect(isCTAHovered ? 1.02 : 1.0)
        .onAppear {
            isPulseAnimating = true
        }
    }

    private func startDictation() {
        if isRecording {
            Task {
                if let onStop = context.onStopDictation {
                    await onStop()
                } else if let engine = context.speakEngine {
                    _ = try? await engine.endDictation()
                }
                isRecording = false
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
            }
        }
    }

    // MARK: - Today's Quick Stats

    private var todayStatsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Activity Overview")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.primary)

            let stats = InsightsStats(entries: todayEntries, now: Date(), calendar: .current)

            HStack(spacing: 16) {
                statCard(
                    title: "Words Dictated",
                    value: "\(stats.totalWords)",
                    icon: "text.word.spacing",
                    color: .blue,
                    trend: "+12%"
                )
                
                statCard(
                    title: "Sessions Today",
                    value: "\(todayEntries.count)",
                    icon: "waveform",
                    color: .purple,
                    trend: "+2"
                )
                
                if context.settingsStore.cleanupEnabled {
                    statCard(
                        title: "AI Cleanups",
                        value: "\(todayEntries.compactMap { $0.cleanedText }.count)",
                        icon: "wand.and.stars",
                        color: .orange,
                        trend: "Active"
                    )
                }
            }
        }
    }

    private func statCard(title: String, value: String, icon: String, color: Color, trend: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.2))
                        .frame(width: 28, height: 28)
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(color)
                }
                Spacer()
                Text(trend)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.green)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.green.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(value)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
        .flowBorder(
            colors: Color.speakFlowGlass,
            lineWidth: 1,
            cornerRadius: 16,
            speed: 0.5,
            isActive: true
        )
    }

    // MARK: - Recent Dictations (last 5)

    private var recentDictationsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Recent Dictations")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
                Button(action: { /* View all */ }) {
                    Text("View All")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            if todayEntries.isEmpty {
                emptyState
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(todayEntries.prefix(5)), id: \.id) { entry in
                        RecentEntryRow(entry: entry)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .center, spacing: 12) {
            Image(systemName: "mic.slash")
                .font(.system(size: 32))
                .foregroundStyle(.secondary.opacity(0.5))
            Text("No dictations today")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
            Text("Use your hotkey to start recording your thoughts.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .glassCard()
    }

    // MARK: - Data loading

    private func loadInitialData() async {
        do {
            let all = try await context.historyStore.recent(limit: 100)
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: Date())
            entries = all.filter { calendar.startOfDay(for: $0.createdAt) == today }
                .sorted { $0.createdAt > $1.createdAt }
        } catch {
            entries = []
        }
        loaded = true
    }

    private func updatePermissionStatus() {
        guard let pm = context.permissionManager else { return }
        micPermissionStatus = pm.status(.microphone)
        accPermissionStatus = pm.status(.accessibility)
    }

    private var todayEntries: [HistoryEntry] {
        entries
    }
}

// MARK: - RecentEntryRow

private struct RecentEntryRow: View {
    let entry: HistoryEntry
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 16) {
            // Timestamp Pill
            Text(entry.createdAt, format: .dateTime.hour().minute())
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.primary.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            
            VStack(alignment: .leading, spacing: 4) {
                Text(truncatePreview(entry.rawText, maxChars: 60))
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                
                if let cleaned = entry.cleanedText {
                    HStack(spacing: 4) {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 10))
                            .foregroundStyle(.purple)
                        Text(truncatePreview(cleaned, maxChars: 50))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            
            Spacer(minLength: 0)
            
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.secondary.opacity(isHovered ? 1.0 : 0.0))
        }
        .padding(12)
        .background(isHovered ? Color.primary.opacity(0.05) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
    }

    private func truncatePreview(_ text: String, maxChars: Int) -> String {
        if text.count > maxChars {
            return String(text.prefix(maxChars - 1)) + "…"
        }
        return text
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
