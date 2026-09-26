//
//  PassportNotesSection.swift
//  Baranov
//
//  "Notes from the Road": the journey told in the ram's own voice, one
//  postcard per stamp, in a horizontal carousel that opens on the newest
//  card. Each kind of stop has its own colour and stamp-sized symbol, the
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
}

extension JourneyStampKind {
    /// Each kind of stop gets its own postcard colour.
    var postcardColor: Color {
        let base: Color = switch self {
        case .setOut: .orange
        case .town: .indigo
        case .water: .teal
        case .landmark: .pink
        case .handoff: .green
        case .arrival: .purple
        }
        return base.calmed(0.15)
    }

    var postcardLabel: LocalizedStringKey {
        switch self {
        case .setOut: "SET OUT"
        case .town: "TOWN"
        case .water: "WATER"
        case .landmark: "LANDMARK"
        case .handoff: "HANDOFF"
        case .arrival: "ARRIVED"
        }
    }
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
                text: line(for: stamp.kind, place: stamp.shortPlaceName, variant: variant)
            )
        }
    }

    private static func line(for kind: JourneyStampKind, place: String, variant: Int) -> String {
        let format: String
        switch (kind, variant) {
        case (.setOut, 0): format = String(localized: "Set out from %@ with the letter tucked safely in my bag.")
        case (.setOut, 1): format = String(localized: "Left %@ at a steady trot. The road is long, and I am ready.")
        case (.setOut, _): format = String(localized: "Hooves on the road out of %@. Off we go.")

        case (.town, 0): format = String(localized: "Trotted through %@. Nobody asked about the letter, which is just how I like it.")
        case (.town, 1): format = String(localized: "Slowed down in %@ to take it all in. The letter is safe.")
        case (.town, _): format = String(localized: "Passed %@ and got another stamp. Chest out.")

        case (.water, 0): format = String(localized: "Crossed %@ with great care. The letter stayed dry.")
        case (.water, 1): format = String(localized: "%@ was wider than it looked, but we made it over.")
        case (.water, _): format = String(localized: "Splashed across %@ and shook off on the far side.")

        case (.landmark, 0): format = String(localized: "Went past %@. Lovely, but the letter comes first.")
        case (.landmark, 1): format = String(localized: "Paused at %@ for exactly one breath, then on again.")
        case (.landmark, _): format = String(localized: "%@ ticked off the list. Onward.")

        case (.handoff, 0): format = String(localized: "Reached %@ and waited for the next pair of hands.")
        case (.handoff, 1): format = String(localized: "Handed over at %@ after a good long walk.")
        case (.handoff, _): format = String(localized: "The road needs someone new from %@. Waiting politely.")

        case (.arrival, 0): format = String(localized: "Reached the gate at %@. Waiting for someone to break the seal.")
        case (.arrival, 1): format = String(localized: "Arrived at %@. The letter is home.")
        case (.arrival, _): format = String(localized: "Standing at the gate in %@, ears up. Delivered.")
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
            }
        }
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func postcard(_ note: TravelNote) -> some View {
        let color = note.kind.postcardColor
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(note.kind.postcardLabel)
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .tracking(1.5)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.white.opacity(0.28), in: Capsule())
                Spacer(minLength: 0)
                Text(note.time.formatted(.dateTime.day().month(.abbreviated).hour().minute()))
                    .font(.caption.weight(.semibold))
                    .opacity(0.85)
            }

            Text(note.text)
                .scaledFont(size: 19, weight: .semibold, design: .serif)
                .italic()
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            HStack {
                Label("\(DistanceFormatter.string(forMeters: note.metersIn)) in", systemImage: "figure.walk")
                    .font(.caption.weight(.bold))
                    .opacity(0.9)
                Spacer(minLength: 0)
                ShareLink(item: "“\(note.text)” — \(ramName), on the road with Baranov") {
                    Image(systemName: "square.and.arrow.up")
                        .font(.footnote.weight(.bold))
                        .frame(width: 32, height: 32)
                        .background(.white.opacity(0.28), in: Circle())
                }
                .accessibilityLabel("Share note")
            }
        }
        .foregroundStyle(.white)
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 200, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(color)
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: note.kind.symbolName)
                        .font(.system(size: 110, weight: .bold))
                        .foregroundStyle(.white.opacity(0.14))
                        .offset(x: 18, y: 18)
                }
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
