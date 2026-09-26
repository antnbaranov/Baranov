//
//  SavedCourierStore.swift
//  Baranov
//
//  Couriers you've met nearby and chosen to keep. Nearby discovery
//  (`NearbyCourierService`) only ever shows who is in range right now, and
//  peer ids change every launch, so a saved courier is remembered by name —
//  the same lightweight UserDefaults-backed JSON pattern as
//  `KnownCarrierDirectory` and `SavedRecipientCodeStore`.
//
//  Saving also records, automatically, when and where you first met them
//  (the place is reverse-geocoded in the background and simply stays blank
//  offline), plus a free-form note you can edit later.
//

import CoreLocation
import Foundation
import Observation

struct SavedCourier: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var name: String
    var tripCity: String
    /// When you first met — set once, automatically, when the courier is saved.
    var savedAt = Date()
    var note = ""
    /// A readable place ("Granville Island, Vancouver"), filled in after saving when the geocoder answers.
    var metPlace: String?
    var metLatitude: Double?
    var metLongitude: Double?

    init(name: String, tripCity: String, metLatitude: Double? = nil, metLongitude: Double? = nil) {
        self.name = name
        self.tripCity = tripCity
        self.metLatitude = metLatitude
        self.metLongitude = metLongitude
    }

    // Tolerant decode: records saved before notes existed still load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decode(String.self, forKey: .name)
        tripCity = try c.decodeIfPresent(String.self, forKey: .tripCity) ?? ""
        savedAt = try c.decodeIfPresent(Date.self, forKey: .savedAt) ?? Date()
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        metPlace = try c.decodeIfPresent(String.self, forKey: .metPlace)
        metLatitude = try c.decodeIfPresent(Double.self, forKey: .metLatitude)
        metLongitude = try c.decodeIfPresent(Double.self, forKey: .metLongitude)
    }
}

@MainActor
@Observable
final class SavedCourierStore {
    private(set) var couriers: [SavedCourier] = []

    private static let storageKey = "com.baranov.savedCouriers"

    init() {
        load()
    }

    func isSaved(name: String) -> Bool {
        index(of: name) != nil
    }

    /// Saves a courier seen nearby. Saving the same name again only refreshes their trip; the first-met
    /// date and place are never overwritten.
    func save(_ courier: NearbyCourier, at coordinate: CLLocationCoordinate2D? = nil) {
        if let i = index(of: courier.name) {
            couriers[i].tripCity = courier.tripCity
            persist()
            return
        }
        let saved = SavedCourier(name: courier.name, tripCity: courier.tripCity,
                                 metLatitude: coordinate?.latitude, metLongitude: coordinate?.longitude)
        couriers.insert(saved, at: 0)
        persist()
        if let coordinate {
            let id = saved.id
            Task { await resolvePlace(for: id, coordinate: coordinate) }
        }
    }

    func remove(name: String) {
        guard let i = index(of: name) else { return }
        couriers.remove(at: i)
        persist()
    }

    func toggle(_ courier: NearbyCourier, at coordinate: CLLocationCoordinate2D? = nil) {
        if isSaved(name: courier.name) { remove(name: courier.name) } else { save(courier, at: coordinate) }
    }

    func setNote(_ note: String, for id: UUID) {
        guard let i = couriers.firstIndex(where: { $0.id == id }), couriers[i].note != note else { return }
        couriers[i].note = note
        persist()
    }

    private func resolvePlace(for id: UUID, coordinate: CLLocationCoordinate2D) async {
        guard let name = await Self.placeName(at: coordinate),
              let i = couriers.firstIndex(where: { $0.id == id }) else { return }
        couriers[i].metPlace = name
        persist()
    }

    /// Off the main actor so the non-`Sendable` placemark never crosses an isolation boundary.
    private nonisolated static func placeName(at coordinate: CLLocationCoordinate2D) async -> String? {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first else { return nil }
        var seen = Set<String>()
        let parts = [placemark.name ?? placemark.thoroughfare, placemark.locality]
            .compactMap { $0 }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    private func index(of name: String) -> Int? {
        let key = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return couriers.firstIndex { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(key) == .orderedSame }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([SavedCourier].self, from: data)
        else { return }
        couriers = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(couriers) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }
}
