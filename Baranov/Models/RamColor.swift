//
//  RamColor.swift
//  Baranov
//
//  The wool colors a ram can wear. Every ram starts out white; from the
//  second pasture slot onward the person can paint a ram pink, brown or
//  green — once. The choice itself lives in `RamColorStore`; this file is
//  just the vocabulary.
//

import SwiftUI

enum RamColor: String, Codable, Sendable, CaseIterable, Hashable, Identifiable {
    case white
    case pink
    case brown
    case green

    var id: String { rawValue }

    /// The color a pasture slot's ram wears until the person picks one:
    /// the first slot is always white, then pink, brown and green, and
    /// the sequence starts over after that.
    static func defaultColor(forSlot slot: Int) -> RamColor {
        let order: [RamColor] = [.white, .pink, .brown, .green]
        guard slot > 0 else { return .white }
        return order[1 + (slot - 1) % (order.count - 1)]
    }

    /// The colors the person can pick from.
    static let choices: [RamColor] = [.white, .pink, .brown, .green]

    var displayName: String {
        switch self {
        case .white: String(localized: "White", bundle: .appLanguage, locale: .appLanguage)
        case .pink: String(localized: "Pink", bundle: .appLanguage, locale: .appLanguage)
        case .brown: String(localized: "Brown", bundle: .appLanguage, locale: .appLanguage)
        case .green: String(localized: "Green", bundle: .appLanguage, locale: .appLanguage)
        }
    }

    /// A system color for the picker's swatches.
    var swatch: Color {
        switch self {
        case .white: Color(red: 0.97, green: 0.93, blue: 0.84)
        case .pink: .pink
        case .brown: .brown
        case .green: .green
        }
    }
}
