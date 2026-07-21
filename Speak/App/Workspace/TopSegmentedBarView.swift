// Speak/App/Workspace/TopSegmentedBarView.swift
//
// Top Segmented Navigation bar for switching between Dictation Engine and Agent Workspace.

import SwiftUI

public struct TopSegmentedBarView: View {
    @Binding public var currentMode: AppMode

    public init(currentMode: Binding<AppMode>) {
        self._currentMode = currentMode
    }

    public var body: some View {
        HStack {
            Spacer()

            Picker("App Mode", selection: $currentMode) {
                ForEach(AppMode.allCases) { mode in
                    Label(mode.rawValue, systemImage: mode.iconName)
                        .tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 320)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.speakInk)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(.speakCardBorder),
            alignment: .bottom
        )
    }
}
