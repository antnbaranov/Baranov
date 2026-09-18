//
//  SeaVoyage.swift
//  Baranov
//
//  A ram's booked passage aboard the packet.
//
//  A letter can walk anywhere a road goes, and a person can carry it over
//  water — but only if a person happens to be going. Before airmail that
//  was exactly the choice a letter faced at a port: leave with a traveller
//  you knew, or wait for the next scheduled packet boat. Baranov keeps
//  both. `SeaVoyage` is the second one: the sailing a ram is booked onto
//  while it stands at a port with an ocean in front of it, so a letter is
//  never stranded just because nobody happened to shake a phone.
//
//  The voyage is pure data — two ports, two instants. Nothing ticks it
//  forward; `FlockViewModel` compares it against the wall clock whenever
//  the app comes back to life, which means a crossing keeps happening
//  while the app is closed, exactly as a real ship would.
//

import CoreLocation
import Foundation

/// A scheduled crossing between two ports, carrying a ram over water it
/// cannot walk across.
struct SeaVoyage: Codable, Hashable, Sendable {
    /// The port the ram walked to and is sailing from.
    let departurePortName: String
    /// The port on the far side, chosen because a road runs from it to the
    /// letter's true destination.
    let arrivalPortName: String
    let departurePort: RamCoordinate
    let arrivalPort: RamCoordinate
    /// When the packet casts off. A ram booked before this is standing on
    /// the quay, not at sea — and can still be handed to a person instead.
    let departsAt: Date
    /// When it makes land and the ram resumes walking.
    let arrivesAt: Date

    /// Always positive, so `progress(at:)` can never divide by zero even
    /// if a package arrives with a corrupt or reversed pair of dates.
    var crossingDuration: TimeInterval {
        max(1, arrivesAt.timeIntervalSince(departsAt))
    }

    func hasDeparted(by date: Date = Date()) -> Bool { date >= departsAt }
    func hasLanded(by date: Date = Date()) -> Bool { date >= arrivesAt }

    /// How far across, 0...1. Zero until the packet actually sails.
    func progress(at date: Date = Date()) -> Double {
        guard hasDeparted(by: date) else { return 0 }
        return min(1, max(0, date.timeIntervalSince(departsAt) / crossingDuration))
    }

    /// Where the ram is right now, interpolated along the great circle
    /// between the two ports — the path a ship actually takes, not the
    /// straight line a flat map would draw.
    func coordinate(at date: Date = Date()) -> CLLocationCoordinate2D {
        Self.greatCirclePoint(
            from: departurePort.clLocationCoordinate,
            to: arrivalPort.clLocationCoordinate,
            fraction: progress(at: date)
        )
    }

    /// The whole crossing as a polyline, for drawing the sea leg on the
    /// map. Sampled rather than drawn as two points so it curves the way a
    /// real course does instead of cutting across the projection.
    var seaRoute: [RamCoordinate] {
        let start = departurePort.clLocationCoordinate
        let end = arrivalPort.clLocationCoordinate
        return stride(from: 0.0, through: 1.0, by: 1.0 / 48.0).map { fraction in
            RamCoordinate(Self.greatCirclePoint(from: start, to: end, fraction: fraction))
        }
    }

    /// The ship's heading at a given moment, so the marker points along the
    /// course. Taken from a short step ahead rather than straight at the
    /// destination, because a great circle's bearing changes as it runs.
    func bearingDegrees(at date: Date = Date()) -> Double {
        let fraction = progress(at: date)
        let start = departurePort.clLocationCoordinate
        let end = arrivalPort.clLocationCoordinate
        let here = Self.greatCirclePoint(from: start, to: end, fraction: fraction)
        let ahead = Self.greatCirclePoint(from: start, to: end, fraction: min(1, fraction + 0.01))
        return Self.bearing(from: here, to: ahead)
    }

    // MARK: - Spherical geometry

    /// Spherical linear interpolation between two coordinates. Degenerates
    /// gracefully when the two points coincide (the `sin` denominator goes
    /// to zero), in which case there is nothing to interpolate anyway.
    static func greatCirclePoint(
        from start: CLLocationCoordinate2D,
        to end: CLLocationCoordinate2D,
        fraction: Double
    ) -> CLLocationCoordinate2D {
        let lat1 = start.latitude * .pi / 180
        let lon1 = start.longitude * .pi / 180
        let lat2 = end.latitude * .pi / 180
        let lon2 = end.longitude * .pi / 180

        let deltaLat = lat2 - lat1
        let deltaLon = lon2 - lon1
        let haversine = sin(deltaLat / 2) * sin(deltaLat / 2)
            + cos(lat1) * cos(lat2) * sin(deltaLon / 2) * sin(deltaLon / 2)
        let angular = 2 * asin(min(1, sqrt(max(0, haversine))))

        guard angular > 1e-9 else { return start }

        let a = sin((1 - fraction) * angular) / sin(angular)
        let b = sin(fraction * angular) / sin(angular)

        let x = a * cos(lat1) * cos(lon1) + b * cos(lat2) * cos(lon2)
        let y = a * cos(lat1) * sin(lon1) + b * cos(lat2) * sin(lon2)
        let z = a * sin(lat1) + b * sin(lat2)

        let latitude = atan2(z, sqrt(x * x + y * y)) * 180 / .pi
        let longitude = atan2(y, x) * 180 / .pi
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    static func bearing(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        let lat1 = from.latitude * .pi / 180
        let lat2 = to.latitude * .pi / 180
        let deltaLon = (to.longitude - from.longitude) * .pi / 180

        let y = sin(deltaLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(deltaLon)
        let degrees = atan2(y, x) * 180 / .pi
        return (degrees + 360).truncatingRemainder(dividingBy: 360)
    }
}
