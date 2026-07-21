// Speak/App/Workspace/ApprovalCardView.swift
//
// Interactive Approval Card View for high-risk or mutating agent actions.

import SpeakCore
import SwiftUI

public struct ApprovalCardView: View {
    public let prompt: String
    public let consequence: String?
    public let onApprove: () -> Void
    public let onDecline: () -> Void

    @State private var isApproved: Bool = false
    @State private var isDeclined: Bool = false

    public init(
        prompt: String,
        consequence: String? = nil,
        onApprove: @escaping () -> Void,
        onDecline: @escaping () -> Void
    ) {
        self.prompt = prompt
        self.consequence = consequence
        self.onApprove = onApprove
        self.onDecline = onDecline
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.speakHumanAmber)

                Text("ACTION APPROVAL REQUESTED")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.speakHumanAmber)

                Spacer()
            }

            Text(prompt)
                .font(.speakMonoBody)
                .foregroundColor(.speakBone)

            if let consequence {
                Text("Consequence: \(consequence)")
                    .font(.speakMonoCaption)
                    .foregroundColor(.speakMica)
            }

            HStack(spacing: 10) {
                if isApproved {
                    Label("Approved & Executing", systemImage: "checkmark.circle.fill")
                        .font(.speakMonoCaption)
                        .foregroundColor(.speakDelivered)
                } else if isDeclined {
                    Label("Action Declined", systemImage: "xmark.circle.fill")
                        .font(.speakMonoCaption)
                        .foregroundColor(.speakOnAir)
                } else {
                    Button(action: {
                        isApproved = true
                        onApprove()
                    }) {
                        Label("Approve Action", systemImage: "checkmark")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.speakHumanAmber)

                    Button(action: {
                        isDeclined = true
                        onDecline()
                    }) {
                        Label("Decline", systemImage: "xmark")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.bordered)
                    .tint(.speakOnAir)
                }
            }
            .padding(.top, 4)
        }
        .padding(12)
        .background(Color.speakInk2)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.speakHumanAmber.opacity(0.4), lineWidth: 1)
        )
    }
}
