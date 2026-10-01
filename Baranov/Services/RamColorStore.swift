//
//  RamColorStore.swift
//  Baranov
//
//  Which color each ram wears. Rams are identified by name everywhere a
//  portrait is drawn (the same way `RamLedger` keys its history), so the
//  color is keyed by name too and travels with a rename.
//
//  A ram's color can be changed once every 24 hours: `choose` records the
//  time of the change and refuses another until `cooldown` has passed.
//  `rename` moves the entry across instead of resetting it, so renaming
//  is never a way around the wait.
//
//  One shared, observable instance — every portrait, the map marker and
//  the picker read the same data, so a choice shows up everywhere the
//  moment it is made. Persisted in `UserDefaults`.
//

import Foundation
import Observation

@Observable
@MainActor
final class RamColorStore {
    static let shared = RamColorStore()

    /// How long a ram keeps a color before it can be changed again.
    static let cooldown: TimeInterval = 24 * 60 * 60

    private static let storageKey = "com.baranov.ramColors.v2"
    private static let legacyStorageKey = "com.baranov.ramColors.v1"

    private struct Entry: Codable {
        var color: RamColor
        var changedAt: Date
    }

    /// Lowercased ram name → the color the person chose and when.
    private var entriesByName: [String: Entry] = [:]

    private init() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode([String: Entry].self, from: data) {
            entriesByName = decoded
        } else if let data = defaults.data(forKey: Self.legacyStorageKey),
                  let legacy = try? JSONDecoder().decode([String: RamColor].self, from: data) {
            // Choices made when a color could only be set once: they have
            // had their wait already, so they may be changed right away.
            entriesByName = legacy.mapValues { Entry(color: $0, changedAt: .distantPast) }
        }
    }

    private static func key(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// The ram's wool color; white until the person picks one.
    func color(for name: String) -> RamColor {
        entriesByName[Self.key(name)]?.color ?? .white
    }

    /// Whether the person has picked a color for this ram at all (as
    /// opposed to it still wearing its slot's default).
    func hasChosen(for name: String) -> Bool {
        entriesByName[Self.key(name)] != nil
    }

    /// When this ram's color can next be changed; `nil` if it can be
    /// changed now.
    func nextChangeDate(for name: String, now: Date = Date()) -> Date? {
        guard let entry = entriesByName[Self.key(name)] else { return nil }
        let next = entry.changedAt.addingTimeInterval(Self.cooldown)
        return next > now ? next : nil
    }

    func canChange(for name: String, now: Date = Date()) -> Bool {
        nextChangeDate(for: name, now: now) == nil
    }

    /// Saves the person's color for this ram and starts the 24-hour wait.
    /// Refused while the wait from the last change is still running.
    @discardableResult
    func choose(_ color: RamColor, for name: String, now: Date = Date()) -> Bool {
        let key = Self.key(name)
        guard !key.isEmpty, canChange(for: name, now: now) else { return false }
        entriesByName[key] = Entry(color: color, changedAt: now)
        save()
        return true
    }

    /// Carries a ram's color, and its wait, to its new name. A ram that
    /// never chose has nothing to move; a new name that already has an
    /// entry keeps its own.
    func rename(from oldName: String, to newName: String) {
        let oldKey = Self.key(oldName)
        let newKey = Self.key(newName)
        guard oldKey != newKey, let entry = entriesByName.removeValue(forKey: oldKey) else { return }
        if entriesByName[newKey] == nil {
            entriesByName[newKey] = entry
        }
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entriesByName) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }
}
