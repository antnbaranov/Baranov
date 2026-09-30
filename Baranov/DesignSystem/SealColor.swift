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
        case .crimson: return String(localized: "Crimson", bundle: .appLanguage, locale: .appLanguage)
        case .gold: return String(localized: "Gold", bundle: .appLanguage, locale: .appLanguage)
        case .forest: return String(localized: "Forest", bundle: .appLanguage, locale: .appLanguage)
        case .navy: return String(localized: "Navy", bundle: .appLanguage, locale: .appLanguage)
        case .plum: return String(localized: "Plum", bundle: .appLanguage, locale: .appLanguage)
        case .ink: return String(localized: "Ink", bundle: .appLanguage, locale: .appLanguage)
        case .obsidian: return String(localized: "Obsidian Black", bundle: .appLanguage, locale: .appLanguage)
        case .oldGold: return String(localized: "Old Gold", bundle: .appLanguage, locale: .appLanguage)
        case .emerald: return String(localized: "Emerald", bundle: .appLanguage, locale: .appLanguage)
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

    /// Crimson is the only free wax. Every other colour comes with
    /// "Expand the Pasture". Sending is never blocked either way.
    var isIncludedFree: Bool { self == .crimson }

    /// Every paid wax catches the light on its own, so the difference
    /// between free and paid is visible at a glance. Plain crimson stays
    /// matte.
    var hasShimmer: Bool { self != .crimson }

    /// The three rare finishes — behind the same entitlement as every
    /// other paid colour, just called out as the top of the set.
    var isRare: Bool {
        switch self {
        case .obsidian, .oldGold, .emerald: return true
        case .crimson, .gold, .forest, .navy, .plum, .ink: return false
        }
    }
}
