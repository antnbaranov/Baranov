//
//  RamCompanionStore.swift
//  Baranov
//
//  Persists the person's `RamCompanion` (`UserDefaults`-backed JSON, same
//  lightweight pattern as `KnownCarrierDirectory`/`RamLedger`/
//  `MockEntitlementStore`). Every owner of this store reads/writes the
//  same underlying storage key, so `PastureView` and `ComposeLetterView`
//  can each hold their own instance without needing to share one via the
//  environment.
//

import Foundation
import Observation

@Observable
@MainActor
final class RamCompanionStore {
    private(set) var companion: RamCompanion?

    private static let storageKey = "com.baranov.ramCompanion"

    init() {
        load()
    }

    var hasCompanion: Bool { companion != nil }

    /// Names the person's default ram for the first time — a no-op that
    /// returns the existing companion if one is already there, since a
    /// companion keeps its original `bornAt` for the life of the app once
    /// created; onboarding only ever runs once.
    @discardableResult
    func createIfNeeded(name: String) -> RamCompanion {
        if let existing = companion { return existing }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let created = RamCompanion(name: trimmed.isEmpty ? "Klaus" : trimmed)
        companion = created
        save()
        return created
    }

    func rename(to newName: String) {
        guard var updated = companion else { return }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        updated.name = trimmed
        companion = updated
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode(RamCompanion.self, from: data)
        else { return }
        companion = decoded
    }

    private func save() {
        guard let companion, let data = try? JSONEncoder().encode(companion) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }
}

#if DEBUG
extension RamCompanionStore {
    /// An illustrative already-onboarded companion for SwiftUI canvas
    /// previews.
    static var preview: RamCompanionStore {
        let store = RamCompanionStore()
        store.companion = RamCompanion(name: "Klaus", bornAt: Date().addingTimeInterval(-86_400 * 12))
        return store
    }
}
#endif
