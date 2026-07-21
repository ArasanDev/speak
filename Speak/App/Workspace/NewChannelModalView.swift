// Speak/App/Workspace/NewChannelModalView.swift
//
// Modal dialog for creating new workspace channels in SQLite.

import SpeakCore
import SwiftUI

public struct NewChannelModalView: View {
    @Binding public var isPresented: Bool
    public let onCreateChannel: (String, String) -> Void

    @State private var channelName: String = ""
    @State private var channelTopic: String = ""

    public init(isPresented: Binding<Bool>, onCreateChannel: @escaping (String, String) -> Void) {
        self._isPresented = isPresented
        self.onCreateChannel = onCreateChannel
    }

    public var body: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture {
                    isPresented = false
                }

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Create Channel")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.speakBone)

                    Spacer()

                    Button(action: { isPresented = false }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12))
                            .foregroundColor(.speakMica)
                    }
                    .buttonStyle(.plain)
                }

                Divider()
                    .overlay(Color.speakCardBorder)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Channel Name")
                        .font(.speakMonoCaption)
                        .foregroundColor(.speakMica)

                    TextField("e.g. release-v1", text: $channelName)
                        .textFieldStyle(.plain)
                        .padding(8)
                        .background(Color.speakInk2)
                        .cornerRadius(6)
                        .foregroundColor(.speakBone)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Topic / Description")
                        .font(.speakMonoCaption)
                        .foregroundColor(.speakMica)

                    TextField("e.g. v1 ship checklist & release build", text: $channelTopic)
                        .textFieldStyle(.plain)
                        .padding(8)
                        .background(Color.speakInk2)
                        .cornerRadius(6)
                        .foregroundColor(.speakBone)
                }

                HStack {
                    Spacer()

                    Button("Cancel") {
                        isPresented = false
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.speakMica)

                    Button("Create Channel") {
                        let name = channelName.trimmingCharacters(in: .whitespacesAndNewlines)
                            .lowercased()
                            .replacingOccurrences(of: " ", with: "-")
                        guard !name.isEmpty else { return }
                        onCreateChannel(name, channelTopic)
                        isPresented = false
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.speakAgentViolet)
                }
                .padding(.top, 8)
            }
            .padding(16)
            .frame(width: 380)
            .background(Color.speakInk)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.speakCardBorder, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.4), radius: 16, x: 0, y: 8)
        }
    }
}
