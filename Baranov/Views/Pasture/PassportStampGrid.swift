//
//  PassportStampGrid.swift
//  Baranov
//
//  How a ram's passport actually looks: a page of stamps, each one a real
//  place it walked past, tilted a few degrees the way a hand-pressed stamp
//  never lands quite square.
//
//  The tilt is deterministic — derived from the stamp's own id — so a page
//  looks hand-stamped but never reshuffles itself between redraws, which
//  is what would make it read as decoration rather than a record.
//
//  Drawn entirely from semantic styles and a dashed `strokeBorder`: no
//  gradient rings, no colored glow, nothing that would look like a web
//  badge pretending to be a passport. In dark mode it inverts on its own
//  because every color here is `.primary`/`.secondary`/`.tertiary` against
//  a material, not a hardcoded ink color.
//

import SwiftUI

/// A single pressed stamp.
struct PassportStampView: View {
    let stamp: JourneyStamp
    /// The ram this passport belongs to. Used only to decide whether the
    /// carrier's name is worth printing: on a relay, the stretch that
    /// earned a stamp was often walked by somebody else entirely, and
    /// saying so is the whole point of handing a ram over.
    var ramName: String?

    private var carrierCredit: String? {
        let carrier = stamp.carrierName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !carrier.isEmpty else { return nil }
        if let ramName, carrier.caseInsensitiveCompare(ramName) == .orderedSame { return nil }
        return carrier
    }

    /// -6…6 degrees, stable for a given stamp — see the file header.
    private var tiltDegrees: Double {
        let bucket = abs(stamp.id.hashValue % 13)
        return Double(bucket) - 6
    }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .strokeBorder(
                        .secondary,
                        style: StrokeStyle(lineWidth: 1.5, dash: [3, 3])
                    )

                Circle()
                    .strokeBorder(.tertiary, lineWidth: 1)
                    .padding(5)

                VStack(spacing: 2) {
                    Image(systemName: stamp.kind.symbolName)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.primary)

                    Text(stamp.timestamp.formatted(.dateTime.day().month(.abbreviated).locale(.appLanguage)))
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 76, height: 76)
            .rotationEffect(.degrees(tiltDegrees))

            Text(stamp.displayPlaceName)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 88)

            Text(carrierCredit.map { "\(stamp.kind.caption) • \($0)" } ?? stamp.kind.caption)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    private var accessibilityDescription: String {
        var description = "\(stamp.kind.caption) \(stamp.displayPlaceName), \(stamp.timestamp.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, locale: .appLanguage)))"
        if let carrierCredit {
            description += String(localized: ", carried by \(carrierCredit)", bundle: .appLanguage, locale: .appLanguage)
        }
        description += String(localized: ", \(stamp.stepsAtStamp) steps into the journey", bundle: .appLanguage, locale: .appLanguage)
        return description
    }
}

/// A page of stamps. Shows its own empty state rather than collapsing to
/// nothing, because "no stamps yet" is the honest, motivating answer for a
/// ram that hasn't set out — an invisible section would just read as a
/// missing feature.
struct PassportStampGrid: View {
    let stamps: [JourneyStamp]
    let ramName: String

    private let columns = [GridItem(.adaptive(minimum: 88, maximum: 120), spacing: 16)]

    var body: some View {
        if stamps.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("No stamps yet")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Text("\(ramName) earns a stamp for every named place walked past — a river crossed, a town passed through, a gate reached.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        } else {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                ForEach(Array(stamps.enumerated()), id: \.element.id) { index, stamp in
                    PassportStampView(stamp: stamp, ramName: ramName)
                        .modifier(StampEntranceModifier(index: index))
                }
            }
            .padding(.vertical, 8)
        }
    }
}

/// Staggers each stamp's appearance: fades + scales in from 0.82,
/// with a 50 ms delay per index so a full page of stamps fans in
/// rather than popping in all at once.
private struct StampEntranceModifier: ViewModifier {
    let index: Int
    @State private var appeared = false

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .scaleEffect(appeared ? 1 : 0.82)
            .onAppear {
                withAnimation(
                    .spring(response: 0.45, dampingFraction: 0.72)
                    .delay(Double(index) * 0.05)
                ) {
                    appeared = true
                }
            }
    }
}

#Preview {
    List {
        Section("Passport") {
            PassportStampGrid(
                stamps: [
                    JourneyStamp(
                        placeName: "Burnaby",
                        kind: .setOut,
                        latitude: 49.2488,
                        longitude: -122.9805,
                        stepsAtStamp: 0,
                        carrierName: "Anton"
                    ),
                    JourneyStamp(
                        placeName: "Fraser River",
                        kind: .water,
                        latitude: 49.2,
                        longitude: -122.9,
                        stepsAtStamp: 3_200,
                        carrierName: "Anton"
                    ),
                    JourneyStamp(
                        placeName: "Calgary",
                        kind: .town,
                        latitude: 51.0447,
                        longitude: -114.0719,
                        stepsAtStamp: 41_000,
                        carrierName: "Anton"
                    )
                ],
                ramName: "Klaus"
            )
        }
    }
}
