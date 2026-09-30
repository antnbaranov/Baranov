//
//  PacketShipService.swift
//  Baranov
//
//  Books a ram onto the next scheduled crossing when it reaches a port
//  with water in front of it and no person has volunteered to carry it.
//
//  This is the guarantee underneath the whole handoff idea. A peer-to-peer
//  handoff is wonderful when it happens and impossible to rely on: the
//  chance that someone standing next to you is about to cross the exact
//  ocean your letter needs is, in practice, zero. Without a fallback a
//  letter simply dies at the coast. With one, the human handoff becomes
//  what it should have been all along — the shortcut that skips the wait,
//  not the only door.
//
//  The schedule is deliberately unglamorous: packets leave on the clock at
//  a fixed interval, and a crossing takes as long as the distance divided
//  by a steady cruising speed. Nothing is random, so the departure time
//  shown to the sender is the departure time that happens, and a ram's
//  position at sea can be recomputed from the two timestamps alone after
//  any amount of time with the app closed.
//

import CoreLocation
import Foundation

enum PacketShipService {
    // MARK: - Schedule

    /// How fast a packet crosses, in meters per second. Not a real ship's
    /// speed: a genuine 20-knot Atlantic crossing is the better part of a
    /// week, which is honest to the theme and unusable for anyone trying
    /// the app for the first time. ~130 km/h puts the Atlantic at roughly
    /// a day and a half — still unmistakably slow, still worth skipping by
    /// finding a carrier, but not a week of nothing.
    static let cruisingMetersPerSecond: Double = 36

    /// No crossing is ever instant, however short the hop. A ferry-width
    /// strait should still feel like waiting for a boat.
    static let minimumCrossingSeconds: TimeInterval = 3 * 3600

    /// How many ports on the far side to try a road route from before
    /// giving up. Each attempt is one `MKDirections` request.
    private static let maxArrivalCandidates = 6

    /// A port must be this far from where the ram is standing to count as
    /// "the other side" — otherwise the nearest candidate is often the
    /// same dock the ram is already on, and the ram would book a voyage
    /// from a port to itself.
    private static let minimumCrossingMeters: Double = 80_000

    /// Wall-clock spacing between sailings, and the divisor applied to a
    /// crossing's duration. In a debug build both are compressed hard so
    /// the whole mechanic — book, wait, sail, land, walk on — can be seen
    /// end to end in a sitting instead of over two days.
#if DEBUG
    static let departureInterval: TimeInterval = 2 * 60
    static let durationCompression: Double = 240
#else
    static let departureInterval: TimeInterval = 6 * 3600
    static let durationCompression: Double = 1
#endif

    /// The next time a packet leaves any port, rounded up to the schedule.
    /// Anchored to the epoch rather than to "now + interval" so every
    /// device in the world agrees on when the boats go, and a ram handed
    /// between two phones keeps the same departure.
    static func nextDeparture(after date: Date = Date()) -> Date {
        let epoch = date.timeIntervalSince1970
        let slots = (epoch / departureInterval).rounded(.down) + 1
        return Date(timeIntervalSince1970: slots * departureInterval)
    }

    /// How long a packet takes over `meters` of open water.
    static func crossingDuration(meters: CLLocationDistance) -> TimeInterval {
        max(minimumCrossingSeconds, meters / cruisingMetersPerSecond) / durationCompression
    }

    /// A quick, offline guess at the crossing a ram will need, for showing
    /// the whole trip before it is sent: the port nearest the destination
    /// that is far enough to be the other side. The real booking at the
    /// quay still checks that a road leads on from it, so the arrival port
    /// can differ — this is a preview, never a promise.
    static func estimatedCrossing(
        from port: CLLocationCoordinate2D,
        toward destination: CLLocationCoordinate2D
    ) -> (arrivalPortName: String, duration: TimeInterval)? {
        let portLocation = CLLocation(latitude: port.latitude, longitude: port.longitude)
        let destinationLocation = CLLocation(latitude: destination.latitude, longitude: destination.longitude)

        let arrival = HandoffGatewayService.gateways
            .map { gateway in
                (gateway, CLLocation(latitude: gateway.coordinate.latitude, longitude: gateway.coordinate.longitude))
            }
            .filter { $0.1.distance(from: portLocation) >= minimumCrossingMeters }
            .min { $0.1.distance(from: destinationLocation) < $1.1.distance(from: destinationLocation) }

        guard let arrival else { return nil }
        return (arrival.0.name, crossingDuration(meters: arrival.1.distance(from: portLocation)))
    }

    // MARK: - Booking

    /// Books the ram standing at `port` onto a crossing toward
    /// `destination`.
    ///
    /// Picks the arrival port by asking, of the gateways nearest the
    /// letter's destination, which one a road actually connects to it —
    /// the same "let MapKit answer it" approach `RouteService` uses for
    /// land, rather than maintaining a table of which ports face which.
    /// Returns `nil` when no far-side port is reachable by road, in which
    /// case the ram keeps waiting for a person, exactly as before.
    static func bookPassage(
        from port: CLLocationCoordinate2D,
        portName: String,
        toward destination: CLLocationCoordinate2D,
        departingAfter now: Date = Date()
    ) async -> SeaVoyage? {
        let portLocation = CLLocation(latitude: port.latitude, longitude: port.longitude)
        let destinationLocation = CLLocation(latitude: destination.latitude, longitude: destination.longitude)

        let candidates = HandoffGatewayService.gateways
            .filter { gateway in
                let location = CLLocation(latitude: gateway.coordinate.latitude, longitude: gateway.coordinate.longitude)
                return location.distance(from: portLocation) >= minimumCrossingMeters
            }
            .sorted { lhs, rhs in
                let left = CLLocation(latitude: lhs.coordinate.latitude, longitude: lhs.coordinate.longitude)
                let right = CLLocation(latitude: rhs.coordinate.latitude, longitude: rhs.coordinate.longitude)
                return left.distance(from: destinationLocation) < right.distance(from: destinationLocation)
            }

        for gateway in candidates.prefix(maxArrivalCandidates) {
            if Task.isCancelled { return nil }
            // The test is not "is this port near the destination" but "can
            // a ram walk from this port to the destination" — a port on
            // the wrong landmass can be geographically close and still be
            // useless, which is the entire problem being solved here.
            guard (try? await RouteService.drivingRoute(from: gateway.coordinate, to: destination)) != nil else {
                continue
            }

            let arrivalLocation = CLLocation(
                latitude: gateway.coordinate.latitude,
                longitude: gateway.coordinate.longitude
            )
            let seaDistance = portLocation.distance(from: arrivalLocation)
            let departsAt = nextDeparture(after: now)
            let crossing = crossingDuration(meters: seaDistance)

            return SeaVoyage(
                departurePortName: portName,
                arrivalPortName: gateway.name,
                departurePort: RamCoordinate(port),
                arrivalPort: RamCoordinate(gateway.coordinate),
                departsAt: departsAt,
                arrivesAt: departsAt.addingTimeInterval(crossing)
            )
        }
        return nil
    }
}
