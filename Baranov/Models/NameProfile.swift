//
//  NameProfile.swift
//  Baranov
//
//  Who this phone answers to. A person keeps up to three active names (their
//  real name, a nickname, a pen name) and a letter addressed to ANY of them
//  is theirs. The first name is the shepherd name used everywhere else in
//  the app (`ShepherdIdentityKeys.name`); the other two live here.
//
//  Anti-spoofing, all on the phone:
//  - Names can be changed 3 times in total (filling an empty slot is free,
//    overwriting or removing a name costs one).
//  - The moment a letter reaches this phone's gate, every name field locks for
//    24 hours, so nobody can rename themselves to match a letter that is
//    already waiting.
//  - The ear tag code stays the real key: it opens a seal whatever the names
//    say (see `LetterDetailView`).
//

import Foundation
import Observation

@MainActor
@Observable
final class NameProfile {
    static let shared = NameProfile()

    static let maxNames = 3
    static let maxEdits = 3
    static let lockDuration: TimeInterval = 86_400

    enum Keys {
        static let aliases = "com.baranov.nameAliases"
        static let editCount = "com.baranov.nameEditCount"
        static let lockedUntil = "com.baranov.nameEditLockedUntil"
        static let seenArrivals = "com.baranov.nameLockSeenArrivals"
    }

    enum EditResult: Equatable {
        case saved
        case unchanged
        case locked(until: Date)
        case limitReached
        case duplicate
    }

    /// The two extra names (nickname, pen name); may contain empty slots.
    private(set) var aliases: [String]
    /// How many paid edits have been used, out of `maxEdits`.
    private(set) var editCount: Int
    /// While in the future, every name field is read-only.
    private(set) var nameEditLockedUntil: Date?

    private init() {
        let defaults = UserDefaults.standard
        let saved = defaults.stringArray(forKey: Keys.aliases) ?? []
        aliases = (saved + ["", ""]).prefix(Self.maxNames - 1).map { $0 }
        editCount = defaults.integer(forKey: Keys.editCount)
        let stamp = defaults.double(forKey: Keys.lockedUntil)
        nameEditLockedUntil = stamp > 0 ? Date(timeIntervalSince1970: stamp) : nil
    }

    // MARK: - Erase

    /// "Delete all data & reset": back to no extra names, a full set of
    /// edits and no lock. The saved copies go with `UserDefaults`
    /// (`AppDataEraser`).
    func eraseAll() {
        aliases = Array(repeating: "", count: Self.maxNames - 1)
        editCount = 0
        nameEditLockedUntil = nil
    }

    // MARK: - Reading

    /// The main name: the shepherd name.
    nonisolated static var primaryName: String {
        (UserDefaults.standard.string(forKey: ShepherdIdentityKeys.name) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Every non-empty active name, main name first.
    nonisolated static var activeNames: [String] {
        let extra = (UserDefaults.standard.stringArray(forKey: Keys.aliases) ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        return ([primaryName] + extra).filter { !$0.isEmpty }.prefix(maxNames).map { $0 }
    }

    /// Case-, diacritic- and whitespace-insensitive form used for every comparison.
    nonisolated static func normalized(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    /// Whether a letter's recipient name is any of this phone's active names.
    nonisolated static func matches(_ recipientName: String) -> Bool {
        let target = normalized(recipientName)
        guard !target.isEmpty else { return false }
        return activeNames.contains { normalized($0) == target }
    }

    var isLocked: Bool { lockRemaining != nil }

    /// Time left on the 24-hour lock, or `nil` when names can be edited.
    var lockRemaining: TimeInterval? {
        guard let until = nameEditLockedUntil, until > Date() else { return nil }
        return until.timeIntervalSinceNow
    }

    var editsLeft: Int { max(0, Self.maxEdits - editCount) }

    // MARK: - Editing

    /// Saves the whole set of names at once. `primary` is the shepherd name,
    /// `extras` the two other slots. Nothing is written unless everything fits.
    @discardableResult
    func apply(primary: String, extras: [String]) -> EditResult {
        if let until = nameEditLockedUntil, until > Date() { return .locked(until: until) }

        let newPrimary = primary.trimmingCharacters(in: .whitespacesAndNewlines)
        let newExtras = ((extras + ["", ""]).prefix(Self.maxNames - 1))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let oldPrimary = Self.primaryName
        let oldExtras = aliases

        // The main name can be replaced, never left empty.
        guard !newPrimary.isEmpty else { return .unchanged }

        let proposed = ([newPrimary] + newExtras).filter { !$0.isEmpty }.map(Self.normalized)
        guard Set(proposed).count == proposed.count else { return .duplicate }

        let old = [oldPrimary] + oldExtras
        let new = [newPrimary] + newExtras
        var cost = 0
        var changed = false
        for (before, after) in zip(old, new) where before != after {
            changed = true
            // Filling an empty slot is free; overwriting or removing a name costs an edit.
            if !before.isEmpty { cost += 1 }
        }
        guard changed else { return .unchanged }
        guard cost <= editsLeft else { return .limitReached }

        let defaults = UserDefaults.standard
        defaults.set(newPrimary, forKey: ShepherdIdentityKeys.name)
        defaults.set(newExtras, forKey: Keys.aliases)
        aliases = newExtras
        editCount += cost
        defaults.set(editCount, forKey: Keys.editCount)
        return .saved
    }

    // MARK: - The 24-hour delivery lock

    /// Locks every name field for 24 hours. Called when a letter arrives.
    func lockForArrival(now: Date = Date()) {
        let until = now.addingTimeInterval(Self.lockDuration)
        nameEditLockedUntil = until
        UserDefaults.standard.set(until.timeIntervalSince1970, forKey: Keys.lockedUntil)
    }

    /// Looks at the flock after every change and locks the names the first
    /// time a letter for this phone shows up at its gate. The first call after
    /// install only remembers what is already there, so updating the app
    /// never locks anyone.
    func noteArrivals(in rams: [Ram]) {
        let defaults = UserDefaults.standard
        let arrived = rams.filter { ram in
            ram.status == .arrivedAtGate && !ram.isGuest
                && (ram.addressedToThisPhone || !ram.isSentByThisPhone)
        }.map(\.id.uuidString)

        guard let seen = defaults.stringArray(forKey: Keys.seenArrivals) else {
            defaults.set(arrived, forKey: Keys.seenArrivals)
            return
        }
        let fresh = arrived.filter { !seen.contains($0) }
        guard !fresh.isEmpty else { return }
        lockForArrival()
        defaults.set(Array((seen + fresh).suffix(300)), forKey: Keys.seenArrivals)
    }
}
