//
//  PassportPaper.swift
//  Baranov
//
//  The materials of the field passport: parchment, ink and a little paper
//  grain. Paper and ink are physical things, so — like the envelope in
//  `LetterStationery` — they are fixed colours that swap between a light
//  and a dark variant, not semantic styles. The only shadow is a plain
//  black, soft one: the paper rests on the table, nothing glows.
//

import SwiftUI
import UIKit

// MARK: - Palette

/// Semantic system colours only, so the passport sits in the same visual
/// language as the rest of the app and adapts to Light, Dark and increased
/// contrast on its own. The traditional "ink" tints are kept for the rubber
/// stamps alone.
extension Color {
    /// The card colours (milestones, badges, travel notes) eased toward grey so
    /// they stay friendly without shouting. One knob for every card.
    func calmed(_ amount: Double = 0.3) -> Color {
        mix(with: Color(uiColor: .systemGray), by: amount)
    }
}

enum PassportInk {
    /// Card surface.
    static let paper = Color(uiColor: .secondarySystemGroupedBackground)
    static let ink = Color.primary
    static let inkSoft = Color.secondary
    /// The app's own accent for highlights and progress.
    static let accent = Color.accentColor

    /// Customs-stamp inks.
    /// Arrival and hand-over stamps are pressed in the same wax burgundy as the seal.
    static let red = Color.wax
    static let blue = Color.blue
    static let green = Color.green
}

// MARK: - Deterministic randomness

/// A tiny seeded generator, so ink specks and stamp tilts are "random"
/// but identical on every redraw and every launch.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }

    mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

enum StableSeed {
    /// FNV-1a over the id's text. `hashValue` is re-randomised on every
    /// launch, which would reshuffle every stamp's tilt each time.
    static func value(for id: UUID) -> UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in id.uuidString.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return hash
    }
}

// MARK: - Card

/// A standard grouped-list card: system surface, continuous corners, no
/// borders or shadows.
struct PaperCard: ViewModifier {
    var cornerRadius: CGFloat = 24

    func body(content: Content) -> some View {
        // The Profile card: a regular material on the grouped background.
        content.background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
    }
}

extension View {
    func paperCard(cornerRadius: CGFloat = 24) -> some View {
        modifier(PaperCard(cornerRadius: cornerRadius))
    }
}

extension JourneyStamp {
    /// "British Columbia Institute of Technology, Burnaby" → the part
    /// before the first comma, which is what a person would say aloud.
    var shortPlaceName: String {
        let first = placeName.split(separator: ",").first.map(String.init) ?? placeName
        let trimmed = first.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? placeName : trimmed
    }
}

// MARK: - Section heading

struct JournalHeading: View {
    let title: LocalizedStringKey
    var symbol: String?

    /// Same label as the cards on the Profile screen: small, semibold,
    /// secondary, icon and title together.
    var body: some View {
        Group {
            if let symbol {
                Label(title, systemImage: symbol)
            } else {
                Text(title)
            }
        }
        .symbolVariant(.fill)
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityAddTraits(.isHeader)
    }
}
