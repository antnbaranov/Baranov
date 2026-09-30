//
//  RoutePreview.swift
//  Baranov
//
//  What a letter's trip will look like, before it is sent. Compose
//  publishes one of these as soon as there is a start, a destination and
//  a ram; `JourneyView` draws it on the whole map (the path traces
//  itself, the ram runs along it) and the ticket in the compose sheet
//  shows the same journey as a slim strip.
//
//  The path is a great-circle arc, not the road: it is a preview of the
//  shape of the trip, and it works the same over water, where there is no
//  road to ask for. The real road leg is resolved when the letter is
//  dispatched.
//
//  Both drawings read `RoutePreviewClock`, a pure function of the wall
//  clock, so the map and the ticket move in step without sharing state.
//

import CoreLocation
import SwiftUI

// MARK: - Clock

enum RoutePreviewClock {
    /// Seconds the ram takes to run the whole path.
    static let travel: Double = 3.6
    /// Seconds the finished route rests before it draws again.
    static let hold: Double = 1.6

    static var period: Double { travel + hold }

    /// 0…1 along the path at `date`: eased in and out while travelling,
    /// then held at 1.
    static func progress(at date: Date) -> Double {
        let t = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period)
        guard t < travel else { return 1 }
        let x = t / travel
        return x * x * (3 - 2 * x)
    }
}

// MARK: - Model

struct RoutePreview: Equatable {
    let ramName: String
    let originName: String
    let destinationName: String
    let viaName: String?
    let origin: CLLocationCoordinate2D
    let destination: CLLocationCoordinate2D
    let via: CLLocationCoordinate2D?

    /// Dense points along the whole trip, start to finish.
    let path: [CLLocationCoordinate2D]
    /// Meters from the start at each point of `path`.
    private let cumulative: [Double]

    /// Identity for change detection — coordinates are not `Equatable`.
    let key: String

    init(
        ramName: String,
        originName: String,
        origin: CLLocationCoordinate2D,
        destinationName: String,
        destination: CLLocationCoordinate2D,
        viaName: String? = nil,
        via: CLLocationCoordinate2D? = nil
    ) {
        self.ramName = ramName
        self.originName = originName
        self.destinationName = destinationName
        self.viaName = viaName
        self.origin = origin
        self.destination = destination
        self.via = via

        var stops = [origin]
        if let via { stops.append(via) }
        stops.append(destination)

        var points: [CLLocationCoordinate2D] = []
        for index in 0..<(stops.count - 1) {
            let leg = Self.greatCircle(from: stops[index], to: stops[index + 1], steps: 64)
            points.append(contentsOf: index == 0 ? leg : Array(leg.dropFirst()))
        }
        self.path = points

        var running = 0.0
        var distances: [Double] = [0]
        for index in 1..<max(points.count, 1) {
            let a = CLLocation(latitude: points[index - 1].latitude, longitude: points[index - 1].longitude)
            let b = CLLocation(latitude: points[index].latitude, longitude: points[index].longitude)
            running += a.distance(from: b)
            distances.append(running)
        }
        self.cumulative = distances

        self.key = [
            ramName,
            String(format: "%.4f,%.4f", origin.latitude, origin.longitude),
            String(format: "%.4f,%.4f", destination.latitude, destination.longitude),
            via.map { String(format: "%.4f,%.4f", $0.latitude, $0.longitude) } ?? "-"
        ].joined(separator: "|")
    }

    static func == (lhs: RoutePreview, rhs: RoutePreview) -> Bool { lhs.key == rhs.key }

    var totalMeters: Double { cumulative.last ?? 0 }

    // MARK: Sampling

    /// The point `fraction` (0…1) of the way along the trip, by distance.
    func point(at fraction: Double) -> CLLocationCoordinate2D {
        guard path.count > 1, totalMeters > 0 else { return origin }
        let clamped = min(max(fraction, 0), 1)
        let target = totalMeters * clamped
        let upper = index(atOrAfter: target)
        let lower = max(upper - 1, 0)
        let span = cumulative[upper] - cumulative[lower]
        let t = span > 0 ? (target - cumulative[lower]) / span : 0
        return CLLocationCoordinate2D(
            latitude: path[lower].latitude + (path[upper].latitude - path[lower].latitude) * t,
            longitude: path[lower].longitude + (path[upper].longitude - path[lower].longitude) * t
        )
    }

    /// The path from the start to `fraction`, ending exactly on the ram.
    func trail(upTo fraction: Double) -> [CLLocationCoordinate2D] {
        guard path.count > 1, totalMeters > 0 else { return [] }
        let clamped = min(max(fraction, 0), 1)
        if clamped >= 1 { return path }
        let target = totalMeters * clamped
        let upper = index(atOrAfter: target)
        var points = Array(path[0..<upper])
        points.append(point(at: clamped))
        return points
    }

    /// Compass bearing of travel at `fraction`, for the ram's facing.
    func bearing(at fraction: Double) -> Double {
        let from = point(at: max(fraction - 0.02, 0))
        let to = point(at: min(fraction + 0.02, 1))
        let lat1 = from.latitude * .pi / 180
        let lat2 = to.latitude * .pi / 180
        let dLon = (to.longitude - from.longitude) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let degrees = atan2(y, x) * 180 / .pi
        return (degrees + 360).truncatingRemainder(dividingBy: 360)
    }

    /// The first index whose cumulative distance reaches `meters`.
    private func index(atOrAfter meters: Double) -> Int {
        var low = 0
        var high = cumulative.count - 1
        while low < high {
            let mid = (low + high) / 2
            if cumulative[mid] < meters { low = mid + 1 } else { high = mid }
        }
        return max(low, 1)
    }

    // MARK: Geometry

    private static func greatCircle(
        from a: CLLocationCoordinate2D,
        to b: CLLocationCoordinate2D,
        steps: Int
    ) -> [CLLocationCoordinate2D] {
        let lat1 = a.latitude * .pi / 180
        let lon1 = a.longitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let lon2 = b.longitude * .pi / 180

        let haversine = pow(sin((lat2 - lat1) / 2), 2) + cos(lat1) * cos(lat2) * pow(sin((lon2 - lon1) / 2), 2)
        let angle = 2 * asin(min(1, sqrt(haversine)))
        guard angle > 1e-9, abs(sin(angle)) > 1e-9 else { return [a, b] }

        return (0...steps).map { step in
            let f = Double(step) / Double(steps)
            let weightA = sin((1 - f) * angle) / sin(angle)
            let weightB = sin(f * angle) / sin(angle)
            let x = weightA * cos(lat1) * cos(lon1) + weightB * cos(lat2) * cos(lon2)
            let y = weightA * cos(lat1) * sin(lon1) + weightB * cos(lat2) * sin(lon2)
            let z = weightA * sin(lat1) + weightB * sin(lat2)
            return CLLocationCoordinate2D(
                latitude: atan2(z, sqrt(x * x + y * y)) * 180 / .pi,
                longitude: atan2(y, x) * 180 / .pi
            )
        }
    }
}
