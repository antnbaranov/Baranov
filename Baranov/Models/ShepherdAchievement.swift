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
        case .firstLetter: return "First Letter"
        case .sealBroken: return "Seal Broken"
        case .tenKilometres: return "10 km on Hoof"
        case .hundredKilometres: return "100 km on Hoof"
        case .oceanCrossing: return "Ocean Crossing"
        case .fullPasture: return "Full Pasture"
        }
    }

    var caption: String {
        switch self {
        case .firstLetter: return "Send a ram on its way."
        case .sealBroken: return "A letter reached its gate and was opened."
        case .tenKilometres: return "Your rams have walked ten kilometres."
        case .hundredKilometres: return "Your rams have walked a hundred kilometres."
        case .oceanCrossing: return "Hand a ram to someone at a coast or border."
        case .fullPasture: return "Every pen full — five rams out walking at once."
        }
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
