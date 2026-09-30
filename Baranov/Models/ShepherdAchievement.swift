//
//  ShepherdAchievement.swift
//  Baranov
//
//  The handful of things worth a badge in a slow post. Each one is
//  decided *locally*, from the flock and the ledger — so the Pasture can
//  show them (earned or not) on any install, with or without Game Center
//  — and then reported to Game Center as an achievement with the same
//  identifier, best-effort, once the person is signed in.
//
//  Identifiers must match the achievements configured in App Store
//  Connect (Features → Game Center) for the reports to land; until then
//  the badges are still real on the phone, and reporting is a silent
//  no-op.
//

import Foundation
import SwiftUI

enum ShepherdAchievement: String, CaseIterable, Identifiable, Sendable {
    case firstLetter = "com.baranov.achievement.firstLetter"
    case sealBroken = "com.baranov.achievement.sealBroken"
    case tenKilometres = "com.baranov.achievement.tenKilometres"
    case hundredKilometres = "com.baranov.achievement.hundredKilometres"
    case oceanCrossing = "com.baranov.achievement.oceanCrossing"
    case fullPasture = "com.baranov.achievement.fullPasture"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .firstLetter: return String(localized: "First Letter", bundle: .appLanguage, locale: .appLanguage)
        case .sealBroken: return String(localized: "Seal Broken", bundle: .appLanguage, locale: .appLanguage)
        case .tenKilometres: return String(localized: "10 km on Hoof", bundle: .appLanguage, locale: .appLanguage)
        case .hundredKilometres: return String(localized: "100 km on Hoof", bundle: .appLanguage, locale: .appLanguage)
        case .oceanCrossing: return String(localized: "Ocean Crossing", bundle: .appLanguage, locale: .appLanguage)
        case .fullPasture: return String(localized: "Full Pasture", bundle: .appLanguage, locale: .appLanguage)
        }
    }

    var caption: String {
        switch self {
        case .firstLetter: return String(localized: "Send a ram on its way.", bundle: .appLanguage, locale: .appLanguage)
        case .sealBroken: return String(localized: "A letter reached its gate and was opened.", bundle: .appLanguage, locale: .appLanguage)
        case .tenKilometres: return String(localized: "Your rams have walked ten kilometres.", bundle: .appLanguage, locale: .appLanguage)
        case .hundredKilometres: return String(localized: "Your rams have walked a hundred kilometres.", bundle: .appLanguage, locale: .appLanguage)
        case .oceanCrossing: return String(localized: "Hand a ram to someone at a coast or border.", bundle: .appLanguage, locale: .appLanguage)
        case .fullPasture: return String(localized: "Every pen full — five rams out walking at once.", bundle: .appLanguage, locale: .appLanguage)
        }
    }

    var localizedTitle: LocalizedStringKey {
        LocalizedStringKey(title)
    }

    var localizedCaption: LocalizedStringKey {
        LocalizedStringKey(caption)
    }

    var symbolName: String {
        switch self {
        case .firstLetter: return "paperplane.fill"
        case .sealBroken: return "seal.fill"
        case .tenKilometres: return "figure.walk"
        case .hundredKilometres: return "figure.walk.motion"
        case .oceanCrossing: return "water.waves"
        case .fullPasture: return "pawprint.fill"
        }
    }

    /// What the badges are judged against — a plain snapshot so the rule
    /// for each one is a pure function and trivially testable.
    struct Progress: Sendable, Equatable {
        var ramsDispatched: Int
        var lettersDelivered: Int
        var metresWalked: Int
        var handoffsMade: Int
        var mostRamsAtOnce: Int
    }

    func isEarned(_ progress: Progress) -> Bool {
        switch self {
        case .firstLetter: return progress.ramsDispatched >= 1
        case .sealBroken: return progress.lettersDelivered >= 1
        case .tenKilometres: return progress.metresWalked >= 10_000
        case .hundredKilometres: return progress.metresWalked >= 100_000
        case .oceanCrossing: return progress.handoffsMade >= 1
        case .fullPasture: return progress.mostRamsAtOnce >= 5
        }
    }

    /// 0…1 toward the badge, for the ones that count something.
    func fraction(_ progress: Progress) -> Double {
        switch self {
        case .firstLetter: return min(1, Double(progress.ramsDispatched))
        case .sealBroken: return min(1, Double(progress.lettersDelivered))
        case .tenKilometres: return min(1, Double(progress.metresWalked) / 10_000)
        case .hundredKilometres: return min(1, Double(progress.metresWalked) / 100_000)
        case .oceanCrossing: return min(1, Double(progress.handoffsMade))
        case .fullPasture: return min(1, Double(progress.mostRamsAtOnce) / 5)
        }
    }

    static func earned(_ progress: Progress) -> [ShepherdAchievement] {
        allCases.filter { $0.isEarned(progress) }
    }
}
