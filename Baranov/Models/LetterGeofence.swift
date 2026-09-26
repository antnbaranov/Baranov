//
//  LetterGeofence.swift
//  Baranov
//
//  Geo-Lock (paid): a letter can carry one of these, binding it to a
//  real point on the ground rather than just the ram's destination
//  city. The ram's own arrival gate is still city-level (see
//  `LetterArrivalView.cityMatches`); a geofence is a second, tighter
//  lock on top of that — the recipient has to actually walk to the
//  spot, not just the city, before the seal will break.
//
//  Deliberately plain data, exactly like `RamCoordinate` elsewhere in
//  the project — Sendable, Codable, no CoreLocation types stored
//  directly so it survives a `.ram` AirDrop package and a UserDefaults
//  round-trip without fuss.
//

import CoreLocation
import Foundation

struct LetterGeofence: Codable, Hashable, Sendable {
    var latitude: Double
    var longitude: Double
    /// How close the recipient's device has to be before the letter will
    /// decrypt. 50 m is the shipped default — about a city block, close
    /// enough to feel like "you have to actually be here" without
    /// demanding GPS accuracy the phone can't reliably hit indoors.
    var radiusMeters: Double

    static let defaultRadiusMeters: Double = 50

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    init(coordinate: CLLocationCoordinate2D, radiusMeters: Double = LetterGeofence.defaultRadiusMeters) {
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
        self.radiusMeters = radiusMeters
    }

    /// Straight-line distance from `coordinate` to the drop point, in
    /// meters. Straight-line on purpose — this is "stand here", not a
    /// route to walk, so it doesn't need `RouteService`.
    func distance(from coordinate: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: latitude, longitude: longitude)
            .distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
    }

    func contains(_ coordinate: CLLocationCoordinate2D) -> Bool {
        distance(from: coordinate) <= radiusMeters
    }
}
