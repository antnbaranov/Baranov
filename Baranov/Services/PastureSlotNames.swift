//
//  PastureSlotNames.swift
//  Baranov
//
//  Names for the pasture slots that are unlocked but don't have a ram
//  walking yet. With "Expand the Pasture" the extra slots aren't empty
//  boxes: each one holds a ram of its own, already waiting under a
//  suggested name. The person can give that ram a name of their own
//  exactly once, before it sets out — after that the name is settled
//  (a running ram can still be renamed from its own card, as always).
//
//  Persisted in `UserDefaults`; every instance reads the same data, so
//  Pasture and Compose can each own one, like `RamLedger`.
//

import Foundation
import Observation

@Observable
@MainActor
final class PastureSlotNames {
    private static let storageKey = "com.baranov.pastureSlotNames.v1"

    private struct Stored: Codable {
        /// Names the person chose, by absolute slot index.
        var chosen: [Int: String] = [:]
    }

    private var stored = Stored()

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode(Stored.self, from: data) {
            stored = decoded
        }
    }

    /// Suggested names, in the same language/script as each other.
    private static var suggestions: [String] {
        [
            String(localized: "Juniper", bundle: .appLanguage, locale: .appLanguage),
            String(localized: "Basalt", bundle: .appLanguage, locale: .appLanguage),
            String(localized: "Thistle", bundle: .appLanguage, locale: .appLanguage),
            String(localized: "Clove", bundle: .appLanguage, locale: .appLanguage),
            String(localized: "Ember", bundle: .appLanguage, locale: .appLanguage),
        ]
    }

    /// Whether the person already named the ram in this slot.
    func isNamed(slot: Int) -> Bool {
        stored.chosen[slot] != nil
    }

    /// Names every open slot in `openSlots` (absolute indices, ascending):
    /// the person's own choice if there is one, otherwise the first
    /// suggestion that no other ram in the pasture already carries.
    func names(forOpenSlots openSlots: [Int], excluding usedNames: [String]) -> [Int: String] {
        var taken = Set(usedNames.map { $0.lowercased() })
        for slot in openSlots {
            if let name = stored.chosen[slot] { taken.insert(name.lowercased()) }
        }
        var result: [Int: String] = [:]
        var pool = Self.suggestions.filter { !taken.contains($0.lowercased()) }
        for slot in openSlots {
            if let name = stored.chosen[slot] {
                result[slot] = name
            } else if !pool.isEmpty {
                result[slot] = pool.removeFirst()
            } else {
                result[slot] = Self.suggestions[slot % Self.suggestions.count]
            }
        }
        return result
    }

    /// Saves the person's own name for this slot's ram. Only the first
    /// call per slot counts.
    @discardableResult
    func nameOnce(slot: Int, to newName: String) -> Bool {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, stored.chosen[slot] == nil else { return false }
        stored.chosen[slot] = trimmed
        if let data = try? JSONEncoder().encode(stored) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
        return true
    }
}
