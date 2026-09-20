//
//  NotificationPreviewCard.swift
//  Baranov
//
//  A truthful mock of a Baranov push notification on the lock screen — the
//  same shape as the real banner, filled with the copy that will actually
//  fire. Shown under the Notifications toggle so the promise is something
//  you can see, not just read.
//

import SwiftUI

struct NotificationPreviewCard: View {
    let title: String
    let message: String
    let time: String

    /// `.ultraThinMaterial` on a plain background; pass a system fill when
    /// nested inside another card.
    var fill: AnyShapeStyle = AnyShapeStyle(.regularMaterial)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "pawprint.fill")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                Text("Baranov")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.primary)

                Spacer()

                Text(time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(fill, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityHidden(true)
    }
}

#Preview {
    NotificationPreviewCard(
        title: "12 km to Lisbon",
        message: "Basalt walks when you do. Every step today counts.",
        time: "8:30 AM"
    )
    .padding()
}
