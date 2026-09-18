//
//  RouteWaypointService.swift
//  Baranov
//
//  Names the three points the in-transit progress strip shows for a leg:
//  where it starts, where it ends, and the halfway vertex between them.
//
//  The halfway label used to be the bug: reverse-geocoding the midpoint
//  of a leg that stays inside one metro area returns the same `locality`
//  as the destination, so the strip read "Burnaby → Burnaby → Burnaby".
//  Here the midpoint is taken as `routeCoordinates[count / 2]` — the
//  polyline's own middle vertex, exactly as `MKPolyline.points()[count/2]`
//  would give it — and when its city matches the destination's (or the
//  origin's), the label steps down to something finer that is actually
//  different: a neighbourhood (`subLocality`), a landmark
//  (`areasOfInterest`), or the street (`thoroughfare`).
//
//  Resolved once per leg (keyed on ram id + leg destination) and cached:
//  `CLGeocoder` is per-app rate limited and these three names don't
//  change while the ram walks.
//

import CoreLocation
import Foundation
import Observation

@Observable
@MainActor
final class RouteWaypointService {
    struct Waypoints: Equatable, Sendable {
        var origin: String
        var midpoint: String
        var destination: String
        var midpointCoordinate: RamCoordinate?
    }

    private(set) var waypoints: Waypoints?
    private(set) var isResolving = false

    @ObservationIgnored private var resolvedRamId: UUID?
    @ObservationIgnored private var resolvedLegDestination: String?
    @ObservationIgnored private let geocoder = CLGeocoder()

    /// Resolves labels for this ram's current leg if they aren't already
    /// held. The ram's own city strings are used as the immediate
    /// fallback for the two ends, so the strip is never blank while the
    /// geocoder is out.
    func refreshIfNeeded(for ram: Ram) async {
        let isForThisLeg = resolvedRamId == ram.id && resolvedLegDestination == ram.legDestinationCity
        if isForThisLeg, waypoints != nil { return }
        guard !isResolving else { return }

        resolvedRamId = ram.id
        resolvedLegDestination = ram.legDestinationCity

        let points = ram.routeCoordinates
        let provisional = Waypoints(
            origin: ram.currentCity,
            midpoint: "",
            destination: ram.legDestinationCity,
            midpointCoordinate: points.isEmpty ? nil : points[points.count / 2]
        )
        waypoints = provisional

        guard points.count > 1 else { return }
        isResolving = true
        defer { isResolving = false }

        let originPlacemark = await placemark(at: points[0])
        let destinationPlacemark = await placemark(at: points[points.count - 1])
        let midpointPlacemark = await placemark(at: points[points.count / 2])

        // The task could have been superseded by a newer leg while the
        // geocoder was out — never write stale names over it.
        guard resolvedRamId == ram.id, resolvedLegDestination == ram.legDestinationCity else { return }

        let originName = Self.cityName(from: originPlacemark) ?? ram.currentCity
        let destinationName = Self.cityName(from: destinationPlacemark) ?? ram.legDestinationCity

        waypoints = Waypoints(
            origin: originName,
            midpoint: Self.midpointName(
                from: midpointPlacemark,
                avoiding: [originName, destinationName, ram.currentCity, ram.legDestinationCity]
            ) ?? "",
            destination: destinationName,
            midpointCoordinate: points[points.count / 2]
        )
    }

    func clear() {
        waypoints = nil
        resolvedRamId = nil
        resolvedLegDestination = nil
    }

    // MARK: - Naming

    private func placemark(at coordinate: RamCoordinate) async -> CLPlacemark? {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return try? await geocoder.reverseGeocodeLocation(location).first
    }

    /// The city-level name for an endpoint — what a person would call
    /// the place a letter is going to.
    static func cityName(from placemark: CLPlacemark?) -> String? {
        guard let placemark else { return nil }
        for candidate in [placemark.locality, placemark.subAdministrativeArea, placemark.administrativeArea] {
            if let candidate, !candidate.isEmpty { return candidate }
        }
        return nil
    }

    /// The label for the halfway vertex. Starts with the city, but if
    /// that city is one of the endpoints' names — the leg never leaves
    /// town — falls through to the neighbourhood, a named landmark, then
    /// the street, and finally the county/region, so the middle of the
    /// strip is a *different* place from its ends. `nil` only when
    /// nothing distinct exists, in which case the strip shows no midpoint
    /// label at all rather than a duplicate.
    static func midpointName(from placemark: CLPlacemark?, avoiding taken: [String]) -> String? {
        guard let placemark else { return nil }

        let isTaken: (String) -> Bool = { name in
            taken.contains { $0.caseInsensitiveCompare(name) == .orderedSame }
        }

        let candidates: [String?] = [
            placemark.locality,
            placemark.subLocality,
            placemark.areasOfInterest?.first,
            placemark.thoroughfare,
            placemark.inlandWater,
            placemark.subAdministrativeArea,
            placemark.administrativeArea,
        ]

        for candidate in candidates {
            guard let candidate, !candidate.isEmpty, !isTaken(candidate) else { continue }
            return candidate
        }
        return nil
    }
}
