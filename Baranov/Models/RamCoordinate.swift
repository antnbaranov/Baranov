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

    private enum CodingKeys: String, CodingKey {
        case latitude, longitude
    }

    /// Coordinates arrive from AirDrop packages and the relay, not only from
    /// this device. MapKit raises an exception on an out-of-range
    /// coordinate in an `Annotation` or camera, so anything outside
    /// ±90 / ±180 is pulled back into range at the door.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawLatitude = try container.decode(Double.self, forKey: .latitude)
        let rawLongitude = try container.decode(Double.self, forKey: .longitude)
        self.latitude = rawLatitude.isFinite ? min(max(rawLatitude, -90), 90) : 0
        if rawLongitude.isFinite {
            let wrapped = (rawLongitude + 180).truncatingRemainder(dividingBy: 360)
            self.longitude = (wrapped < 0 ? wrapped + 360 : wrapped) - 180
        } else {
            self.longitude = 0
        }
    }
}
