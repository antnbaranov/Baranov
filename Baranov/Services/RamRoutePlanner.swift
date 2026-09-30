//
//  RamRoutePlanner.swift
//  Baranov
//
//  Turns "from here to that gate" into a ram ready to dispatch: the real road
//  if there is one, otherwise the road to the best port on the way (the
//  packet or a courier takes it across from there). The same rules Compose
//  uses for an address, for letters that only know a Shepherd ID or an ear
//  tag until the recipient's gate turns up (`LetterTracker`, Code mode).
//

import CoreLocation
import Foundation

enum RamRoutePlanner {
    enum PlanError: Error, Sendable {
        /// No road, and no port reachable by road on the way.
        case noRoute
        /// Offline or MapKit failed; worth trying again.
        case requestFailed
    }

    static func makeRam(
        name: String,
        letter: Letter,
        origin: CLLocationCoordinate2D,
        originCity: String,
        destination: CLLocationCoordinate2D,
        destinationCity: String
    ) async throws -> Ram {
        let originNode = RouteNode(
            cityName: originCity,
            latitude: origin.latitude,
            longitude: origin.longitude,
            carrierName: name,
            stepsContributed: 0
        )
        do {
            let leg = try await RouteService.drivingRoute(from: origin, to: destination)
            return Ram(
                name: name,
                totalStepsRequired: leg.distanceMeters,
                currentCity: originCity,
                targetCity: destinationCity,
                legDestinationCity: destinationCity,
                routeHistory: [originNode],
                routeCoordinates: leg.coordinates,
                requiresHandoffAtLegEnd: false,
                letter: letter,
                finalDestinationCoordinate: RamCoordinate(destination)
            )
        } catch RouteResolutionError.noDrivableRoute {
            guard let plan = await HandoffGatewayService.plan(from: origin, toward: destination) else {
                throw PlanError.noRoute
            }
            return Ram(
                name: name,
                totalStepsRequired: plan.leg.distanceMeters,
                currentCity: originCity,
                targetCity: destinationCity,
                legDestinationCity: plan.gateway.name,
                routeHistory: [originNode],
                routeCoordinates: plan.leg.coordinates,
                requiresHandoffAtLegEnd: true,
                letter: letter,
                finalDestinationCoordinate: RamCoordinate(destination)
            )
        } catch {
            throw PlanError.requestFailed
        }
    }
}
