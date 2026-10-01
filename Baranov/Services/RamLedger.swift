//
//  RamLedger.swift
//  Baranov
//
//  A ram's lifetime record, kept separately from the single-journey `Ram`
//  struct itself: composing a new letter always creates a brand-new `Ram`
//  (fresh id, one journey, one letter), so "how many letters has Klaus
//  delivered" can't live on `Ram` — it has to survive across however many
//  separate journeys have been walked under that name. Keyed by the ram's
//  chosen name, since that's the identity the person actually cares about
//  ("Klaus" the ram), not any particular journey's UUID.
//
//  `recordDeliveryIfNeeded(_:)` is idempotent per ram id — safe to call on
//  every observed state change without double-counting a delivery that's
//  already been logged.
//

import Foundation
import Observation

/// One named ram's lifetime stats.
struct RamLedgerEntry: Codable, Sendable {
    var name: String
    var lettersDelivered: Int = 0
    var totalStepsWalked: Int = 0
    var waypoints: [RouteNode] = []
    /// Every passport stamp this ram has ever earned, across every
    /// delivered journey — the lifetime collection `RamPassportView`
    /// shows. Journeys still in flight keep their stamps on the `Ram`
    /// itself; they're folded in here once the letter is delivered.
    var stamps: [JourneyStamp] = []
    /// Ram ids already folded into this entry, so re-observing the same
    /// delivered ram (e.g. after a view refresh) never double-counts it.
    var recordedRamIDs: Set<UUID> = []

    /// This ram's own lifetime score, across every journey ever walked
    /// under its current name — not tied to any GameCenter leaderboard
    /// (those are per-player, not per-ram), just a number `RamHistoryView`
    /// can show. Weighted heavily toward actual deliveries (100 points
    /// each) over raw distance (1 point per 10 steps), so a ram that
    /// finishes fewer, longer journeys isn't penalized against one that
    /// finishes lots of short ones.
    var experiencePoints: Int {
        lettersDelivered * 100 + totalStepsWalked / 10
    }

    /// How many distinct real places this ram has stamped in its passport,
    /// counted by name rather than by stamp — a ram that crossed the same
    /// river on three different journeys has been to one river.
    var distinctPlacesVisited: Int {
        Set(stamps.map { $0.placeName.lowercased() }).count
    }

    /// A hand-written decode so an entry persisted before passports
    /// existed still loads: `UserDefaults` already holds real ledger JSON
    /// on any install that has delivered a letter, and the synthesized
    /// decoder would reject all of it over one missing key.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        lettersDelivered = try container.decodeIfPresent(Int.self, forKey: .lettersDelivered) ?? 0
        totalStepsWalked = try container.decodeIfPresent(Int.self, forKey: .totalStepsWalked) ?? 0
        waypoints = try container.decodeIfPresent([RouteNode].self, forKey: .waypoints) ?? []
        stamps = try container.decodeIfPresent([JourneyStamp].self, forKey: .stamps) ?? []
        recordedRamIDs = try container.decodeIfPresent(Set<UUID>.self, forKey: .recordedRamIDs) ?? []
    }

    init(
        name: String,
        lettersDelivered: Int = 0,
        totalStepsWalked: Int = 0,
        waypoints: [RouteNode] = [],
        stamps: [JourneyStamp] = [],
        recordedRamIDs: Set<UUID> = []
    ) {
        self.name = name
        self.lettersDelivered = lettersDelivered
        self.totalStepsWalked = totalStepsWalked
        self.waypoints = waypoints
        self.stamps = stamps
        self.recordedRamIDs = recordedRamIDs
    }

    private enum CodingKeys: String, CodingKey {
        case name, lettersDelivered, totalStepsWalked, waypoints, stamps, recordedRamIDs
    }
}

@Observable
@MainActor
final class RamLedger {
    private(set) var entriesByName: [String: RamLedgerEntry] = [:]

    private static let storageKey = "com.baranov.ramLedger"

    init() {
        load()
    }

    /// Every letter ever delivered, across every named ram.
    var totalLettersDelivered: Int {
        entriesByName.values.reduce(0) { $0 + $1.lettersDelivered }
    }

    /// The player's own lifetime score — every named ram's
    /// `experiencePoints` added together. This, not the raw delivery
    /// count, is what gets submitted to GameCenter as the player's
    /// overall score, so "experience" means the same thing whether you're
    /// looking at one ram's history or the leaderboard.
    var totalExperiencePoints: Int {
        entriesByName.values.reduce(0) { $0 + $1.experiencePoints }
    }

    /// The stored entry for a name, or an empty one if this ram hasn't
    /// delivered anything yet — never `nil`, so callers can read it
    /// unconditionally.
    func entry(forName name: String) -> RamLedgerEntry {
        entriesByName[name] ?? RamLedgerEntry(name: name)
    }

    /// Folds a delivered ram's journey into its name's lifetime entry.
    /// No-ops (returning `false`) for a ram that isn't actually delivered,
    /// or one already recorded — callers can call this freely from an
    /// `onChange`/`.task` sweep over the whole flock without tracking
    /// which rams are new themselves.
    @discardableResult
    func recordDeliveryIfNeeded(_ ram: Ram) -> Bool {
        guard ram.status == .delivered else { return false }

        var entry = entriesByName[ram.name] ?? RamLedgerEntry(name: ram.name)
        guard !entry.recordedRamIDs.contains(ram.id) else { return false }

        entry.recordedRamIDs.insert(ram.id)
        entry.lettersDelivered += 1
        entry.totalStepsWalked += ram.routeHistory.reduce(0) { $0 + $1.stepsContributed }
        entry.waypoints.append(contentsOf: ram.routeHistory)

        // Stamps are folded in by id, not appended blindly: the same ram
        // can be re-imported (an idempotent AirDrop re-receive) carrying
        // stamps this entry has already absorbed.
        let knownStampIDs = Set(entry.stamps.map(\.id))
        entry.stamps.append(contentsOf: ram.stamps.filter { !knownStampIDs.contains($0.id) })

        entriesByName[ram.name] = entry
        save()
        return true
    }

    /// Carries a ram's lifetime history over to its new name after a
    /// rename, so renaming mid-journey doesn't orphan history already
    /// logged under the old one. A no-op if the old name has no entry yet.
    func rename(from oldName: String, to newName: String) {
        guard oldName != newName, var entry = entriesByName[oldName] else { return }
        entriesByName.removeValue(forKey: oldName)
        entry.name = newName

        if var existing = entriesByName[newName] {
            existing.lettersDelivered += entry.lettersDelivered
            existing.totalStepsWalked += entry.totalStepsWalked
            existing.waypoints.append(contentsOf: entry.waypoints)
            existing.recordedRamIDs.formUnion(entry.recordedRamIDs)
            entriesByName[newName] = existing
        } else {
            entriesByName[newName] = entry
        }

        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([String: RamLedgerEntry].self, from: data)
        else { return }
        entriesByName = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entriesByName) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }
}

// Preview fixtures: intentionally not #if DEBUG so #Preview blocks compile in Release/Archive builds.
extension RamLedger {
    /// An illustrative lifetime record for SwiftUI canvas previews.
    static var preview: RamLedger {
        let ledger = RamLedger()
        ledger.entriesByName = [
            "Klaus": RamLedgerEntry(
                name: "Klaus",
                lettersDelivered: 3,
                totalStepsWalked: 41_200,
                waypoints: []
            )
        ]
        return ledger
    }
}
