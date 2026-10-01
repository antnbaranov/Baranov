//
//  PassportNotesSection.swift
//  Baranov
//
//  "Notes from the Road": the journey told in the ram's own voice, one
//  postcard per stamp, in a horizontal carousel that opens on the newest
//  card. Each kind of stop has its own symbol on a plain white card, the
//  cards sit at a slight tilt like a pile of real postcards, and any note
//  can be shared as text.
//
//  The lines are written from the real stamps (place, kind, time,
//  distance) — nothing is invented beyond the phrasing — with a few
//  wordings per kind, picked by the stamp's stable seed so a note never
//  rewrites itself.
//

import SwiftUI
import UIKit

struct TravelNote: Identifiable, Hashable {
    let id: UUID
    let time: Date
    let kind: JourneyStampKind
    let place: String
    let metersIn: Int
    let text: String
    let weather: StampWeather?
}

enum TravelNoteWriter {
    /// Oldest first, so the carousel reads left to right like a diary.
    static func notes(from stamps: [JourneyStamp]) -> [TravelNote] {
        stamps.sorted { $0.timestamp < $1.timestamp }.map { stamp in
            let variant = Int(StableSeed.value(for: stamp.id) % 3)
            return TravelNote(
                id: stamp.id,
                time: stamp.timestamp,
                kind: stamp.kind,
                place: stamp.shortPlaceName,
                metersIn: stamp.stepsAtStamp,
                text: line(for: stamp.kind, place: stamp.shortPlaceName, variant: variant),
                weather: stamp.weather
            )
        }
    }

    private static func line(for kind: JourneyStampKind, place: String, variant: Int) -> String {
        let format: String
        switch (kind, variant) {
        case (.setOut, 0): format = String(localized: "Set out from %@ with the letter tucked safely in my bag.", bundle: .appLanguage, locale: .appLanguage)
        case (.setOut, 1): format = String(localized: "Left %@ at a steady trot. The road is long, and I am ready.", bundle: .appLanguage, locale: .appLanguage)
        case (.setOut, _): format = String(localized: "Hooves on the road out of %@. Off we go.", bundle: .appLanguage, locale: .appLanguage)

        case (.town, 0): format = String(localized: "Trotted through %@. Nobody asked about the letter, which is just how I like it.", bundle: .appLanguage, locale: .appLanguage)
        case (.town, 1): format = String(localized: "Slowed down in %@ to take it all in. The letter is safe.", bundle: .appLanguage, locale: .appLanguage)
        case (.town, _): format = String(localized: "Passed %@ and got another stamp. Chest out.", bundle: .appLanguage, locale: .appLanguage)

        case (.water, 0): format = String(localized: "Crossed %@ with great care. The letter stayed dry.", bundle: .appLanguage, locale: .appLanguage)
        case (.water, 1): format = String(localized: "%@ was wider than it looked, but we made it over.", bundle: .appLanguage, locale: .appLanguage)
        case (.water, _): format = String(localized: "Splashed across %@ and shook off on the far side.", bundle: .appLanguage, locale: .appLanguage)

        case (.landmark, 0): format = String(localized: "Went past %@. Lovely, but the letter comes first.", bundle: .appLanguage, locale: .appLanguage)
        case (.landmark, 1): format = String(localized: "Paused at %@ for exactly one breath, then on again.", bundle: .appLanguage, locale: .appLanguage)
        case (.landmark, _): format = String(localized: "%@ ticked off the list. Onward.", bundle: .appLanguage, locale: .appLanguage)

        case (.handoff, 0): format = String(localized: "Reached %@ and waited for the next pair of hands.", bundle: .appLanguage, locale: .appLanguage)
        case (.handoff, 1): format = String(localized: "Handed over at %@ after a good long walk.", bundle: .appLanguage, locale: .appLanguage)
        case (.handoff, _): format = String(localized: "The road needs someone new from %@. Waiting politely.", bundle: .appLanguage, locale: .appLanguage)

        case (.arrival, 0): format = String(localized: "Reached the gate at %@. Waiting for someone to break the seal.", bundle: .appLanguage, locale: .appLanguage)
        case (.arrival, 1): format = String(localized: "Arrived at %@. The letter is home.", bundle: .appLanguage, locale: .appLanguage)
        case (.arrival, _): format = String(localized: "Standing at the gate in %@, ears up. Delivered.", bundle: .appLanguage, locale: .appLanguage)
        }
        return String(format: format, place)
    }
}

struct PassportNotesSection: View {
    let ramName: String
    let stamps: [JourneyStamp]

    @State private var focusedId: UUID?

    private var notes: [TravelNote] { TravelNoteWriter.notes(from: stamps) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            JournalHeading(title: "Notes", symbol: "pencil.and.scribble")
                .padding(.horizontal, 34)

            if notes.isEmpty {
                Text("The first note is written when the first stamp lands.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 34)
            } else {
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(Array(notes.enumerated()), id: \.element.id) { index, note in
                            postcard(note)
                                .rotationEffect(.degrees([-1.5, 1.0, -0.8, 1.6, -1.2, 0.8][index % 6]))
                                .containerRelativeFrame(.horizontal) { width, _ in
                                    min(300, width * 0.8)
                                }
                                .id(note.id)
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.vertical, 10)
                }
                .contentMargins(.horizontal, 16, for: .scrollContent)
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: $focusedId, anchor: .center)
                .scrollIndicators(.hidden)
                .onAppear {
                    // Opens on the newest note, the way a diary falls open at the last entry.
                    if focusedId == nil { focusedId = notes.last?.id }
                }
                .onChange(of: focusedId) { _, newValue in
                    guard newValue != nil else { return }
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                }

                if notes.contains(where: { $0.weather != nil }) {
                    WeatherAttributionView()
                        .padding(.horizontal, 34)
                }
            }
        }
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A plain white card on the grouped gray page, like every other card
    /// in the app: the stop's symbol and place in secondary, the ram's own
    /// line in primary. No per-kind colour, no eyebrow label.
    private func postcard(_ note: TravelNote) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: note.kind.symbolName)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
                    .background(Color(uiColor: .systemGray6), in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    if !note.place.isEmpty {
                        Text(verbatim: note.place)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }
                    Text(note.time.formatted(.dateTime.day().month(.abbreviated).hour().minute().locale(.appLanguage)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            Text(note.text)
                .scaledFont(size: 19, weight: .semibold, design: .serif)
                .italic()
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            if let weather = note.weather {
                Label(weather.summaryLine, systemImage: weather.symbolName)
                    .symbolRenderingMode(.multicolor)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            HStack {
                Label("\(DistanceFormatter.string(forMeters: note.metersIn)) in", systemImage: "figure.walk")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                ShareLink(item: String(localized: "\u{201C}\(note.text)\u{201D} \u{2014} \(ramName), on the road with Baranov", bundle: .appLanguage, locale: .appLanguage)) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.black)
                        .frame(width: 32, height: 32)
                        .background(Color(uiColor: .systemGray6), in: Circle())
                }
                .accessibilityLabel("Share note")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 200, alignment: .topLeading)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 26, style: .continuous)
        )
        .fixedSize(horizontal: false, vertical: true)
    }
}
