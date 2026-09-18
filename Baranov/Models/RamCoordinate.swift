//
//  RamCoordinate.swift
//  Baranov
//
//  A plain, `Codable` latitude/longitude pair. `CLLocationCoordinate2D`
//  itself isn't `Codable`, so this is what actually gets stored on a `Ram`
//  and carried across an AirDrop `RamTransitPackage`.
//

import CoreLocation
import Foundation

struct RamCoordinate: Codable, Hashable, Sendable {
    let latitude: Double
    let longitude: Double

    var clLocationCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    init(_ coordinate: CLLocationCoordinate2D) {
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
    }
}
