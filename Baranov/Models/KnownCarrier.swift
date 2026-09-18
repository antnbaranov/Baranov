//
//  KnownCarrier.swift
//  Baranov
//
//  A person you know who's already headed somewhere — recorded manually
//  (there's no live peer-discovery protocol here; plain AirDrop/ShareLink
//  has no way to ask a nearby device "where is your ram going?"). Kept
//  around so a ram waiting for a handoff can be matched against carriers
//  already heading to, or near, the same place, rather than just AirDrop-
//  ing to whoever happens to be nearby with no idea if they're going the
//  right way.
//

import Foundation

struct KnownCarrier: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var name: String
    var destinationCity: String
    var destinationCoordinate: RamCoordinate

    init(
        id: UUID = UUID(),
        name: String,
        destinationCity: String,
        destinationCoordinate: RamCoordinate
    ) {
        self.id = id
        self.name = name
        self.destinationCity = destinationCity
        self.destinationCoordinate = destinationCoordinate
    }
}
