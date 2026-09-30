//
//  SavedRecipientCodeStore.swift
//  Baranov
//
//  Persists the sender's own saved Shepherd IDs (`UserDefaults`-backed
//  JSON, the same lightweight pattern as `KnownCarrierDirectory`/
//  `RamCompanionStore`). Compose reads this to offer saved codes as chips
//  in "Send by Code" instead of a blank field every time.
//

import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class SavedRecipientCodeStore {
    private(set) var saved: [SavedRecipientCode] = []

    private static let storageKey = "com.baranov.savedRecipientCodes"

    init() {
        load()
    }

    /// The saved entry for a given Shepherd ID, if one is on file — used
    /// so Compose can show "already saved" instead of offering to save it
    /// twice.
    func entry(forCode code: String) -> SavedRecipientCode? {
        let address = CourierCodeStore.address(from: code)
        return saved.first { CourierCodeStore.address(from: $0.code) == address }
    }

    func add(name: String, code: String, locationName: String?, locationCoordinate: RamCoordinate?, notes: String?) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let entry = SavedRecipientCode(
            name: trimmedName.isEmpty ? String(localized: "Someone", bundle: .appLanguage, locale: .appLanguage) : trimmedName,
            code: CourierCodeStore.formatted(code),
            locationName: locationName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            locationCoordinate: locationCoordinate,
            notes: notes?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        )
        saved.insert(entry, at: 0)
        save()
    }

    func update(_ entry: SavedRecipientCode) {
        guard let index = saved.firstIndex(where: { $0.id == entry.id }) else { return }
        saved[index] = entry
        save()
    }

    /// Keeps the profile key the relay gave for this entry.
    func cachePublicKey(_ key: String, for id: UUID) {
        guard let index = saved.firstIndex(where: { $0.id == id }), saved[index].publicKey != key else { return }
        saved[index].publicKey = key
        save()
    }

    func remove(_ entry: SavedRecipientCode) {
        saved.removeAll { $0.id == entry.id }
        save()
    }

    func remove(at offsets: IndexSet) {
        saved.remove(atOffsets: offsets)
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([SavedRecipientCode].self, from: data)
        else { return }
        saved = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(saved) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

#if DEBUG
extension SavedRecipientCodeStore {
    /// A couple of illustrative saved codes for SwiftUI canvas previews —
    /// never seeded into the real running app.
    static var preview: SavedRecipientCodeStore {
        let store = SavedRecipientCodeStore()
        store.saved = [
            SavedRecipientCode(name: "Mira", code: "ABCDE-FGHJK", locationName: "Met at the hostel in Ljubljana", notes: "Loves postcards with mountains."),
            SavedRecipientCode(name: "Theo", code: "MNPQR-STUVW", locationName: nil, notes: nil),
        ]
        return store
    }
}
#endif
