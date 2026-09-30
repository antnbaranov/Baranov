//
//  DeliveredLettersCarousel.swift
//  Baranov
//
//  A horizontal, swipeable strip of completed journeys — one card per ram
//  whose letter has actually been opened (`.delivered`). Lets the flock's
//  history be glanced at without opening each ram individually.
//

import SwiftUI

struct DeliveredLettersCarousel: View {
    let rams: [Ram]

    var body: some View {
        if rams.isEmpty { return AnyView(EmptyView()) }
        return AnyView(
            VStack(alignment: .leading, spacing: 10) {
                Label("Delivered Letters", systemImage: "checkmark.seal.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(rams) { ram in
                            DeliveredLetterCard(ram: ram)
                        }
                    }
                    .padding(.vertical, 2)
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned)
                .contentMargins(.horizontal, 2, for: .scrollContent)
            }
        )
    }
}

private struct DeliveredLetterCard: View {
    let ram: Ram

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "pawprint.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(ram.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            }

            Text("\(ram.currentCity) → \(ram.targetCity)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if let letter = ram.letter {
                Divider()

                Text(letter.messageBody)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                Text("\(letter.senderName) → \(letter.recipientName)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(14)
        .frame(width: 220, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

#Preview {
    ScrollView {
        DeliveredLettersCarousel(rams: [FlockViewModel.preview.activeRams[0]])
            .padding()
    }
}
