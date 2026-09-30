//
//  LetterGate.swift
//  Baranov
//
//  Where letters to a person walk: their gate. A town and a point rounded to
//  about 1 km — enough for a ram to aim at, never a street address.
//

import CoreLocation
import Foundation

struct LetterGate: Codable, Hashable, Sendable {
    let city: String
    let latitude: Double
    let longitude: Double

    init(city: String, latitude: Double, longitude: Double) {
        self.city = String(city.prefix(120))
        // About 1 km: the same rounding the relay applies.
        self.latitude = (latitude * 100).rounded() / 100
        self.longitude = (longitude * 100).rounded() / 100
    }

    init(city: String, coordinate: CLLocationCoordinate2D) {
        self.init(city: city, latitude: coordinate.latitude, longitude: coordinate.longitude)
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
