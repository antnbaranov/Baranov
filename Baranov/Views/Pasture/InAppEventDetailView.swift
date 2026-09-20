//
//  InAppEventDetailView.swift
//  Baranov
//
//  Sheet presented when an In-App Event deep link is opened (e.g. baranov://event/new-york).
//  Satisfies Apple App Store Guidelines requiring Event Deep Links to lead
//  directly to the specific event screen and content.
//

import SwiftUI

struct InAppEventDetailView: View {
    let event: InAppEvent
    var onParticipate: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header badge & icon
                VStack(spacing: 12) {
                    Image(systemName: event.symbolName)
                        .font(.system(size: 64))
                        .foregroundStyle(.tint)
                        .symbolRenderingMode(.hierarchical)
                        .padding(.top, 16)

                    Text(event.subtitle.uppercased())
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .tracking(1.2)

                    Text(event.title)
                        .font(.system(.title, design: .serif, weight: .bold))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.primary)

                    HStack(spacing: 6) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.subheadline)
                        Text(event.destinationCity)
                            .font(.subheadline.weight(.medium))
                    }
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal)

                // Event info card
                VStack(alignment: .leading, spacing: 14) {
                    Label {
                        Text("Expedition Dispatch")
                            .font(.headline)
                    } icon: {
                        Image(systemName: "figure.walk")
                            .foregroundStyle(.tint)
                    }

                    Text(event.eventDescription)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .lineSpacing(4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.horizontal)

                // Features / details strip
                VStack(spacing: 12) {
                    eventFeatureRow(
                        icon: "shoeprints.fill",
                        title: "Every Step Counts",
                        subtitle: "Your daily iPhone & Apple Watch steps advance the ram."
                    )
                    Divider()
                    eventFeatureRow(
                        icon: "seal.fill",
                        title: "Commemorative Stamp",
                        subtitle: "Arriving at the destination stamps your explorer passport."
                    )
                    Divider()
                    eventFeatureRow(
                        icon: "person.2.fill",
                        title: "Handoff Relay",
                        subtitle: "Hand off letters to fellow carriers via AirDrop or Shake."
                    )
                }
                .padding(16)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.horizontal)

                // Action buttons
                VStack(spacing: 12) {
                    Button {
                        dismiss()
                        onParticipate?()
                    } label: {
                        HStack {
                            Image(systemName: "paperplane.fill")
                            Text("Join Expedition")
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button("Close") {
                        dismiss()
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") {
                    dismiss()
                }
            }
        }
    }

    private func eventFeatureRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 28, alignment: .center)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }
}

#Preview {
    NavigationStack {
        InAppEventDetailView(event: .newYork)
    }
}
