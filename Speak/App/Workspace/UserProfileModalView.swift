// Speak/App/Workspace/UserProfileModalView.swift
//
// User Profile & Settings Modal for speak Workspace.
// Enforces consistent borders, smooth transitions, intuitive navigation, and full-screen minimalism.
// Styled with centralized design system tokens (`Color.speak*`, `Font.speakMono*`).

import SpeakCore
import SwiftUI

public struct UserProfileModalView: View {
    @Binding public var isPresented: Bool

    public init(isPresented: Binding<Bool>) {
        self._isPresented = isPresented
    }

    public var body: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isPresented = false
                    }
                }

            VStack(alignment: .leading, spacing: 16) {
                // Header Bar
                HStack {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color.speakHumanAmber)
                            .frame(width: 10, height: 10)

                        Text("USER PROFILE & PREFERENCES")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.speakBone)
                    }

                    Spacer()

                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isPresented = false
                        }
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12))
                            .foregroundColor(.speakMica)
                    }
                    .buttonStyle(.plain)
                }

                Divider()
                    .overlay(Color.speakCardBorder)

                // Identity Section
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.speakHumanAmber.opacity(0.2))
                            .frame(width: 48, height: 48)

                        Text("👤")
                            .font(.system(size: 24))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("@tamil")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.speakHumanAmber)

                        Text("Lead Human Architect & Workspace Operator")
                            .font(.system(size: 12))
                            .foregroundColor(.speakMica)
                    }
                }

                Divider()
                    .overlay(Color.speakCardBorder)

                // Privacy Moat & System Metrics
                VStack(alignment: .leading, spacing: 8) {
                    Text("LOCAL PRIVACY MOAT & ENGINE STATUS")
                        .font(.speakMonoCaption)
                        .foregroundColor(.speakMica)

                    HStack(spacing: 10) {
                        metricBadge(label: "Egress Status", value: "100% Offline", color: .speakDelivered)
                        metricBadge(label: "STT Engine", value: "SpeechAnalyzer", color: .speakAgentViolet)
                        metricBadge(label: "Neat-Writer", value: "Foundation Models", color: .speakHumanAmber)
                    }
                }

                Divider()
                    .overlay(Color.speakCardBorder)

                // Active Spoken Tag Roster
                VStack(alignment: .leading, spacing: 8) {
                    Text("ACTIVE AGENT TAGS")
                        .font(.speakMonoCaption)
                        .foregroundColor(.speakMica)

                    HStack(spacing: 8) {
                        tagChip(tag: "@Claude", label: "Claude Code CLI")
                        tagChip(tag: "@builder-qa", label: "Moat Audit Agent")
                        tagChip(tag: "@terminal", label: "Terminal Runner")
                    }
                }

                HStack {
                    Spacer()

                    Button("Close") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isPresented = false
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.speakAgentViolet)
                }
                .padding(.top, 4)
            }
            .padding(18)
            .frame(width: 420)
            .background(Color.speakInk)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.speakCardBorder, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.4), radius: 16, x: 0, y: 8)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }

    private func metricBadge(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(.speakMica)
            Text(value)
                .font(.speakMonoCaption)
                .foregroundColor(color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.speakInk2)
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.speakCardBorder, lineWidth: 1)
        )
    }

    private func tagChip(tag: String, label: String) -> some View {
        HStack(spacing: 4) {
            Text(tag)
                .font(.speakMonoCaption)
                .foregroundColor(.speakTagBadgeFg)
            Text("(\(label))")
                .font(.system(size: 9))
                .foregroundColor(.speakMica)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.speakTagBadgeBg)
        .cornerRadius(6)
    }
}
