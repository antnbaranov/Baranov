//
//  RamCompanion.swift
//  Baranov
//
//  The person's own default ram: named once at onboarding and never
//  re-created after that — separate from `Ram`, which models one
//  in-progress journey/letter rather than a standing identity. A
//  companion persists for the life of the app and ages for real as time
//  passes, independent of whether any letter has ever actually been sent.
//

import Foundation

/// How a companion's age reads to the person, and what it currently
/// affects. Deliberately never touches the core "1 step = 1 meter"
/// walking rule — age instead affects how many *passenger* letters (see
/// `Ram.passengerLetters`) it can carry alongside its own, not how fast
/// or far it walks.
enum RamAgeStage: String, Codable, Sendable {
    case lamb
    case yearling
    case adult

    var displayName: String {
        switch self {
        case .lamb: return "Lamb"
        case .yearling: return "Yearling"
        case .adult: return "Adult"
        }
    }

    /// How many passenger letters — picked up from others along the way,
    /// on top of its own — a ram at this age can carry at once.
    var maxPassengerLetters: Int {
        switch self {
        case .lamb: return 0
        case .yearling: return 1
        case .adult: return 3
        }
    }
}

/// The person's own default ram. Composing a letter defaults to riding on
/// this one; it's the guaranteed-non-empty first entry `ComposeLetterView`
/// offers, and the one always shown in the Pasture even before any letter
/// has ever been sent.
struct RamCompanion: Codable, Sendable {
    var name: String
    let bornAt: Date

    init(name: String, bornAt: Date = Date()) {
        self.name = name
        self.bornAt = bornAt
    }

    var ageInDays: Int {
        max(0, Calendar.current.dateComponents([.day], from: bornAt, to: Date()).day ?? 0)
    }

    var ageStage: RamAgeStage {
        switch ageInDays {
        case ..<7: return .lamb
        case 7..<30: return .yearling
        default: return .adult
        }
    }

    /// "2 days old", "5 weeks old" — always in whichever unit reads most
    /// naturally at the companion's current age, rather than a raw day
    /// count once it's been around a while.
    var ageDescription: String {
        let days = ageInDays
        if days < 14 {
            return days == 1 ? "1 day old" : "\(days) days old"
        }
        let weeks = days / 7
        if weeks < 12 {
            return weeks == 1 ? "1 week old" : "\(weeks) weeks old"
        }
        let months = days / 30
        return months <= 1 ? "1 month old" : "\(months) months old"
    }
}
