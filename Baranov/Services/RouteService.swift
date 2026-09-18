//
//  RouteService.swift
//  Baranov
//
//  Resolves a real, road-following route between two coordinates using
//  MapKit — this is what makes a ram travel like a car on real streets
//  instead of cutting a diagonal line, and what tells the rest of the app
//  when a leg simply isn't walkable (an ocean in the way), so a handoff to
//  someone else is required instead of pretending the ram can swim.
//

import CoreLocation
import Foundation
import MapKit

/// A resolved, drivable leg between two points: the real road polyline and
/// its real distance in meters, used directly as a ram's step quota since
/// 1 step = 1 meter.
struct ResolvedRoute: Sendable {
    let coordinates: [RamCoordinate]
    let distanceMeters: Int
}

enum RouteResolutionError: Error, Sendable {
    /// No drivable road connects the two points — most commonly because
    /// they're on different landmasses. Treated as a real geographic fact,
    /// not a transient failure: the caller should offer a handoff rather
    /// than retry the same request.
    case noDrivableRoute
    /// The request itself failed (offline, server error, etc.) — worth
    /// retrying, unlike `.noDrivableRoute`.
    case requestFailed
}

enum RouteService {
    /// Calculates a real driving route between `origin` and `destination`.
    static func drivingRoute(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D
    ) async throws -> ResolvedRoute {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: origin))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination))
        request.transportType = .automobile

        let response: MKDirections.Response
        do {
            response = try await MKDirections(request: request).calculate()
        } catch {
            let nsError = error as NSError
            if nsError.domain == MKError.errorDomain {
                // MapKit's own signal that it found no way to connect the
                // two points by road — the expected outcome for an
                // intercontinental/overseas pair, not a bug to fix.
                throw RouteResolutionError.noDrivableRoute
            }
            throw RouteResolutionError.requestFailed
        }

        guard let route = response.routes.first else {
            throw RouteResolutionError.noDrivableRoute
        }

        return ResolvedRoute(
            coordinates: route.polyline.ramCoordinates,
            distanceMeters: max(Int(route.distance), 1)
        )
    }
}

private extension MKPolyline {
    /// Extracts this polyline's points as plain, `Codable` coordinates.
    var ramCoordinates: [RamCoordinate] {
        var coordinates = [CLLocationCoordinate2D](
            repeating: kCLLocationCoordinate2DInvalid,
            count: pointCount
        )
        getCoordinates(&coordinates, range: NSRange(location: 0, length: pointCount))
        return coordinates.map(RamCoordinate.init)
    }
}
