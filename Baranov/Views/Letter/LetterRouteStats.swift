//
//  LetterRouteStats.swift
//  Baranov
//
//  The travel log under the envelope: one grouped card holding where the
//  letter is going (a one-line "Origin → Destination"), a slim route with
//  the ram on it, and how far it has come (three columns: walked, steps,
//  to go). System colours and semantic styles only.
//

import SwiftUI

extension String {
    /// A place name short enough for one line: geocoder results often
    /// arrive as "BCIT Burnaby, Burnaby, British Columbia, Canada".
    /// Keeps the part before the first comma; the caller still applies
    /// `lineLimit(1)` for names that are long on their own.
    var compactPlaceName: String {
        let head = split(separator: ",", maxSplits: 1, omittingEmptySubsequences: true)
            .first
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard let head, !head.isEmpty else { return trimmingCharacters(in: .whitespacesAndNewlines) }
        return head
    }
}

// MARK: - Route

struct LetterRouteIndicator: View {
    let originName: String
    let destinationName: String
    /// 0…1 along the whole route.
    let progress: Double
    var badgeSymbol: String = "pawprint.fill"

    private let badgeDiameter: CGFloat = 32
    private let trackHeight: CGFloat = 4

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Text(originName.compactPlaceName)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(1)
                Image(systemName: "arrow.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
                Text(destinationName.compactPlaceName)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(1)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
            .minimumScaleFactor(0.85)
            .frame(maxWidth: .infinity)

            GeometryReader { proxy in
                let inset = badgeDiameter / 2
                let travel = max(0, proxy.size.width - badgeDiameter)
                let x = inset + travel * CGFloat(min(max(progress, 0), 1))

                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                        .frame(height: trackHeight)
                    Capsule().fill(Color.accentColor)
                        .frame(width: x, height: trackHeight)

                    Circle()
                        .strokeBorder(.tertiary, lineWidth: 2)
                        .frame(width: 10, height: 10)
                        .position(x: inset, y: badgeDiameter / 2)
                    Image(systemName: "flag.checkered")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .position(x: proxy.size.width - inset, y: badgeDiameter / 2)

                    Image(systemName: badgeSymbol)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: badgeDiameter, height: badgeDiameter)
                        .background(Color.accentColor, in: Circle())
                        .position(x: x, y: badgeDiameter / 2)
                        .animation(.smooth(duration: 0.6), value: progress)
                }
            }
            .frame(height: badgeDiameter)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(Int((progress * 100).rounded())) percent of the way from \(originName.compactPlaceName) to \(destinationName.compactPlaceName)"))
    }
}

// MARK: - Stats

struct LetterStatsBar: View {
    struct Stat: Identifiable {
        let id: String
        let symbol: String
        let value: String
        let caption: LocalizedStringKey
    }

    let stats: [Stat]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(stats.enumerated()), id: \.element.id) { index, stat in
                if index > 0 {
                    Divider().frame(height: 36)
                }
                VStack(spacing: 4) {
                    Image(systemName: stat.symbol)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(stat.value)
                        .font(.title3.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .contentTransition(.numericText())
                    Text(stat.caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
            }
        }
    }
}

// MARK: - Travel log

/// Route, progress and stats as one grouped card: a white card on the
/// grouped background, like the rest of the app.
///
///     Burnaby → Vancity
///     ──────●────────⚑
///     8.7 km │ 8,742 │ 0 km
struct LetterTravelLog: View {
    let originName: String
    let destinationName: String
    /// 0…1 along the whole route.
    let progress: Double
    let stats: [LetterStatsBar.Stat]

    var body: some View {
        VStack(spacing: 16) {
            LetterRouteIndicator(
                originName: originName,
                destinationName: destinationName,
                progress: progress
            )

            Divider()

            LetterStatsBar(stats: stats)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}

#Preview("Travel log") {
    LetterTravelLog(
        originName: "BCIT Burnaby, Burnaby, British Columbia",
        destinationName: "Vancity",
        progress: 0.35,
        stats: [
            .init(id: "walked", symbol: "figure.walk", value: "0.6 km", caption: "walked"),
            .init(id: "steps", symbol: "shoeprints.fill", value: "812", caption: "steps"),
            .init(id: "togo", symbol: "flag.checkered", value: "1.1 km", caption: "to go"),
        ]
    )
    .padding()
    .background(Color(uiColor: .systemGroupedBackground))
}
