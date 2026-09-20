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

enum SealColor: String, Codable, CaseIterable, Identifiable, Sendable {
    case crimson
    case gold
    case forest
    case navy
    case plum
    case ink

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .crimson: return "Crimson"
        case .gold: return "Gold"
        case .forest: return "Forest"
        case .navy: return "Navy"
        case .plum: return "Plum"
        case .ink: return "Ink"
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
        }
    }

    /// Whether this wax comes free with the app or with the pasture
    /// expansion.
    var isIncludedFree: Bool { true }
}
