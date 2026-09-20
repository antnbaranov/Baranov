//
//  KnownCarrierDirectory.swift
//  Baranov
//
//  A manually-maintained list of people you know are already headed
//  somewhere. There's no way to learn this over AirDrop itself — plain
//  ShareLink is a one-shot file transfer, not a live "what's your
//  destination" exchange — so this is deliberately a directory you build
//  yourself (typically from Contacts, via the same picker used for a
//  letter's recipient), not something the app discovers on its own.
//
//  `matches(for:)` is what makes the directory useful: given a ram
//  waiting for a handoff, it surfaces every known carrier whose declared
//  destination is the same city, or close enough — within
//  `matchRadiusMeters` — that handing the letter to them instead of
//  walking it the rest of the way yourself is a reasonable shortcut.
//

import CoreLocation
import Foundation
import Observation
import SwiftUI

@Observable
@MainActor
final class KnownCarrierDirectory {
    private(set) var carriers: [KnownCarrier] = []

    /// A known carrier heading anywhere within this radius of a ram's true
    /// final destination counts as "going the same way" for matching
    /// purposes — per the brief, 800 km.
    static let matchRadiusMeters: CLLocationDistance = 800_000
    static var matchRadiusKm: Int { Int(matchRadiusMeters / 1000) }

    private static let storageKey = "com.baranov.knownCarriers"

    init() {
        load()
    }

    func add(name: String, destinationCity: String, destinationCoordinate: RamCoordinate) {
        carriers.append(
            KnownCarrier(name: name, destinationCity: destinationCity, destinationCoordinate: destinationCoordinate)
        )
        save()
    }

    func remove(_ carrier: KnownCarrier) {
        carriers.removeAll { $0.id == carrier.id }
        save()
    }

    func remove(at offsets: IndexSet) {
        carriers.remove(atOffsets: offsets)
        save()
    }

    /// Known carriers worth AirDropping this ram to: heading to the exact
    /// same city as its true final destination (`targetCity`, not just
    /// this leg's intermediate handoff stop), or within `matchRadiusMeters`
    /// of it.
    func matches(for ram: Ram) -> [KnownCarrier] {
        let targetCity = ram.targetCity.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let targetLocation = CLLocation(
            latitude: ram.finalDestinationCoordinate.latitude,
            longitude: ram.finalDestinationCoordinate.longitude
        )

        return carriers.filter { carrier in
            let carrierCity = carrier.destinationCity.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !targetCity.isEmpty, carrierCity == targetCity {
                return true
            }

            let carrierLocation = CLLocation(
                latitude: carrier.destinationCoordinate.latitude,
                longitude: carrier.destinationCoordinate.longitude
            )
            return targetLocation.distance(from: carrierLocation) <= Self.matchRadiusMeters
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([KnownCarrier].self, from: data)
        else { return }
        carriers = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(carriers) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }
}

#if DEBUG
extension KnownCarrierDirectory {
    /// A couple of illustrative carriers for SwiftUI canvas previews —
    /// never seeded into the real running app.
    static var preview: KnownCarrierDirectory {
        let directory = KnownCarrierDirectory()
        directory.carriers = [
            KnownCarrier(name: "Mira", destinationCity: "Frankfurt", destinationCoordinate: RamCoordinate(latitude: 50.1109, longitude: 8.6821)),
            KnownCarrier(name: "Theo", destinationCity: "Gander", destinationCoordinate: RamCoordinate(latitude: 48.9564, longitude: -54.6089)),
        ]
        return directory
    }
}
#endif
