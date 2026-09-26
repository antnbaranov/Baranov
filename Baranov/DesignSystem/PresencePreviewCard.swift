//
//  PresencePreviewCard.swift
//  Baranov
//
//  A truthful mock of what the *other* person sees when a Privacy toggle
//  is on — the same idea as `NotificationPreviewCard`, so the promise is
//  something you can look at instead of a paragraph to read. Sample names
//  and places only; nothing here is real data.
//

import SwiftUI

struct PresencePreviewCard: View {
    let symbol: String
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    var showsApproximateArea: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                if showsApproximateArea {
                    Circle()
                        .strokeBorder(.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                }
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(.tint)
                    .symbolRenderingMode(.hierarchical)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityHidden(true)
    }
}
