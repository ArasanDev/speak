// Speak/App/Workspace/QuickSwitcherModalView.swift
//
// Slack-Inspired Quick Switcher Modal (`Cmd+K`).
// Spotlight-style search modal for instant navigation across channels, agents, and SQLite threads.

import SpeakCore
import SwiftUI

public struct QuickSwitcherModalView: View {
    @Binding public var isPresented: Bool
    public let onSelectChannel: (String) -> Void

    @State private var searchQuery: String = ""
    @FocusState private var isFieldFocused: Bool

    private let availableChannels = [
        ("general", "Default workspace channel", "number"),
        ("core-engine", "Engine & Audio Core development", "number"),
        ("qa-regressions", "Test suites & moat privacy audits", "number")
    ]

    private let availableTags = [
        ("@Claude", "Claude Code CLI Agent", "person.badge.shield.checkmark.fill"),
        ("@builder-qa", "Moat & Quality Audit Agent", "shield.fill"),
        ("@terminal", "Local Shell Command Execution", "terminal.fill"),
        ("@github", "PRs, Issues & Commit Integration", "arrow.triangle.pull")
    ]

    public init(isPresented: Binding<Bool>, onSelectChannel: @escaping (String) -> Void) {
        self._isPresented = isPresented
        self.onSelectChannel = onSelectChannel
    }

    public var body: some View {
        ZStack {
            // Dark Backdrop
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture {
                    isPresented = false
                }

            // Modal Card
            VStack(spacing: 0) {
                // Search Input Header
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16))
                        .foregroundColor(.speakMica)

                    TextField("Search channels, agents, or type a command...", text: $searchQuery)
                        .textFieldStyle(.plain)
                        .font(.speakMonoBody)
                        .foregroundColor(.speakBone)
                        .focused($isFieldFocused)
                        .onSubmit {
                            selectFirstMatch()
                        }

                    Text("ESC")
                        .font(.speakMonoCaption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.speakInk2)
                        .foregroundColor(.speakMica)
                        .cornerRadius(4)
                }
                .padding(14)
                .background(Color.speakInk)

                Divider()
                    .overlay(Color.speakCardBorder)

                // Results List
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        // Channels Section
                        if !filteredChannels.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("CHANNELS")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.speakMica)

                                ForEach(filteredChannels, id: \.0) { item in
                                    resultRow(icon: item.2, title: "# " + item.0, subtitle: item.1) {
                                        onSelectChannel(item.0)
                                        isPresented = false
                                    }
                                }
                            }
                        }

                        // Tags & Agents Section
                        if !filteredTags.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("AGENTS & PLUGINS")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.speakMica)

                                ForEach(filteredTags, id: \.0) { item in
                                    resultRow(icon: item.2, title: item.0, subtitle: item.1) {
                                        onSelectChannel("general")
                                        isPresented = false
                                    }
                                }
                            }
                        }
                    }
                    .padding(12)
                }
                .frame(maxHeight: 280)
            }
            .frame(width: 520)
            .background(Color.speakInk)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.speakCardBorder, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.4), radius: 20, x: 0, y: 10)
        }
        .onAppear {
            isFieldFocused = true
        }
    }

    private var filteredChannels: [(String, String, String)] {
        if searchQuery.isEmpty { return availableChannels }
        return availableChannels.filter { $0.0.localizedCaseInsensitiveContains(searchQuery) || $0.1.localizedCaseInsensitiveContains(searchQuery) }
    }

    private var filteredTags: [(String, String, String)] {
        if searchQuery.isEmpty { return availableTags }
        return availableTags.filter { $0.0.localizedCaseInsensitiveContains(searchQuery) || $0.1.localizedCaseInsensitiveContains(searchQuery) }
    }

    private func resultRow(icon: String, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundColor(.speakAgentViolet)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.speakMonoBody)
                        .foregroundColor(.speakBone)

                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(.speakMica)
                }

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.speakInk2.opacity(0.6))
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }

    private func selectFirstMatch() {
        if let firstCh = filteredChannels.first {
            onSelectChannel(firstCh.0)
            isPresented = false
        }
    }
}
