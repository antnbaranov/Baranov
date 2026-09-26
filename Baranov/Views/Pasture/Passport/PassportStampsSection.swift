//
//  PassportStampsSection.swift
//  Baranov
//
//  "Journey stamps": the stamp collection. Tapping a stamp presses it
//  down with a soft haptic and opens a small slip below with when it was
//  earned, who carried the ram there and how far into the journey it was.
//  (Weather is deliberately absent: the app has no weather source, and a
//  made-up forecast would be a lie in a passport.)
//

import SwiftUI
import UIKit

struct PassportStampsSection: View {
    let stamps: [JourneyStamp]
    let ramName: String

    @State private var selectedId: UUID?

    private let columns = [GridItem(.adaptive(minimum: 104, maximum: 130), spacing: 12)]

    private var selected: JourneyStamp? { stamps.first { $0.id == selectedId } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            JournalHeading(title: "Stamps", symbol: "seal.fill")

            if stamps.isEmpty {
                emptyPage
            } else {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(stamps) { stamp in
                        Button {
                            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                            withAnimation(.spring(duration: 0.35, bounce: 0.3)) {
                                selectedId = selectedId == stamp.id ? nil : stamp.id
                            }
                        } label: {
                            InkStampView(stamp: stamp, isSelected: stamp.id == selectedId)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if let selected {
                    detailSlip(for: selected)
                        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
                } else {
                    Text("\(placeCount) \(placeCount == 1 ? "place" : "places") stamped. Tap a stamp to look closer.")
                        .font(.footnote)
                        .foregroundStyle(PassportInk.inkSoft)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .paperCard()
    }

    private var placeCount: Int {
        Set(stamps.map { $0.placeName.lowercased() }).count
    }

    private var emptyPage: some View {
        VStack(spacing: 6) {
            Image(systemName: "pawprint.fill")
                .font(.title2)
                .foregroundStyle(PassportInk.inkSoft)
            Text("An empty page")
                .font(.system(.subheadline).weight(.bold))
                .foregroundStyle(PassportInk.ink)
            Text("\(ramName) earns a stamp for every named place it walks past.")
                .font(.footnote)
                .foregroundStyle(PassportInk.inkSoft)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color(uiColor: .separator), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
        )
    }

    private func detailSlip(for stamp: JourneyStamp) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(Text(stamp.kind.journalVerb)) \(stamp.shortPlaceName)")
                .font(.system(.subheadline).weight(.bold))
                .foregroundStyle(PassportInk.ink)
            Label(stamp.timestamp.formatted(date: .long, time: .shortened), systemImage: "calendar")
            Label("\(DistanceFormatter.string(forMeters: stamp.stepsAtStamp)) into the journey", systemImage: "figure.walk")
            if let weather = stamp.weather {
                Label(
                    "\(weather.condition), \(Measurement(value: weather.temperatureCelsius, unit: UnitTemperature.celsius).formatted(.measurement(width: .abbreviated, usage: .weather, numberFormatStyle: .number.precision(.fractionLength(0)))))",
                    systemImage: weather.symbolName
                )
                WeatherAttributionView()
            }
            let carrier = stamp.carrierName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !carrier.isEmpty, carrier.caseInsensitiveCompare(ramName) != .orderedSame {
                Label("Carried by \(carrier)", systemImage: "person.fill")
            }
        }
        .font(.system(.footnote))
        .foregroundStyle(PassportInk.inkSoft)
        .labelStyle(.titleAndIcon)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
