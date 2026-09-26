//
//  SealColor.swift
//  Baranov
//
//  The wax a letter is sealed with. Crimson is every shepherd's; the rest
//  come with "Expand the Pasture" — the one purely aesthetic perk in the
//  subscription, chosen because it's visible on both ends of a journey
//  (the sender picks it in Compose, the recipient breaks it at the gate)
//  without ever gating the letter itself.
//
//  Colors are system colors, so they adapt to light/dark and increased
//  contrast on their own.
//

import SwiftUI

extension Color {
    /// The app's crimson wax. Reserved for sealing, breaking and delivering
    /// a letter (the seal, dispatch, arrival, stamps); everything else
    /// keeps the accent colour.
    static var wax: Color { SealColor.crimson.color }
}

enum SealColor: String, Codable, CaseIterable, Identifiable, Sendable {
    case crimson
    case gold
    case forest
    case navy
    case plum
    case ink
    /// Premium Materials (paid): the three "rare" finishes — same
    /// entitlement as the standard colours above, just styled with a
    /// tilt-reactive shimmer (`isRare`, `WaxSealView`) and a small badge
    /// wherever the wax picker lists them.
    case obsidian
    case oldGold
    case emerald

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .crimson: return "Crimson"
        case .gold: return "Gold"
        case .forest: return "Forest"
        case .navy: return "Navy"
        case .plum: return "Plum"
        case .ink: return "Ink"
        case .obsidian: return "Obsidian Black"
        case .oldGold: return "Old Gold"
        case .emerald: return "Emerald"
        }
    }

    var color: Color {
        switch self {
        case .crimson: return .adaptive(light: (0.66, 0.11, 0.13), dark: (0.80, 0.25, 0.27))
        case .gold: return .orange
        case .forest: return .green
        case .navy: return .blue
        case .plum: return .purple
        case .ink: return Color(uiColor: .label)
        case .obsidian: return .adaptive(light: (0.09, 0.09, 0.10), dark: (0.16, 0.16, 0.18))
        case .oldGold: return .adaptive(light: (0.60, 0.47, 0.20), dark: (0.78, 0.64, 0.33))
        case .emerald: return .adaptive(light: (0.02, 0.40, 0.28), dark: (0.16, 0.52, 0.38))
        }
    }

    /// Whether this wax comes free with the app or with the pasture
    /// expansion: crimson is free, every other colour is a subscription perk.
    var isIncludedFree: Bool { self == .crimson }

    /// The three rare finishes — behind the same entitlement as every
    /// other paid colour, just called out as the top of the set.
    var isRare: Bool {
        switch self {
        case .obsidian, .oldGold, .emerald: return true
        case .crimson, .gold, .forest, .navy, .plum, .ink: return false
        }
    }
}
