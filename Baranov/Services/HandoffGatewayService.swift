//
//  HandoffGatewayService.swift
//  Baranov
//
//  Picks the handoff city for a letter whose destination no road reaches
//  (an ocean, or a border with no crossing) — so the sender never has to
//  guess a port themselves. Given the origin and the letter's true
//  destination, it ranks a fixed list of well-known ports and border
//  gateways by how little of a detour they add to the straight line
//  between the two, then asks `RouteService` for a real driving route
//  to each in turn; the first one a ram can actually walk to wins.
//
//  The list is deliberately static and offline — no network lookup is
//  needed to choose, only to confirm the road route — and every entry is
//  a real place with a real dock or crossing, so "walk to Halifax and
//  wait for a handoff" always reads as a sensible plan to the sender.
//

import CoreLocation
import Foundation

struct HandoffGateway: Sendable, Equatable {
    let name: String
    let coordinate: CLLocationCoordinate2D

    static func == (lhs: HandoffGateway, rhs: HandoffGateway) -> Bool {
        lhs.name == rhs.name
    }
}

/// A resolved plan: the port the ram will walk to, and the real road leg
/// that gets it there.
struct HandoffPlan: Sendable {
    let gateway: HandoffGateway
    let leg: ResolvedRoute
}

enum HandoffGatewayService {
    /// How many ranked candidates to actually try a route to before
    /// giving up and asking the sender to name a city. Each try is one
    /// `MKDirections` request.
    private static let maxAttempts = 6

    /// Finds the closest gateway on the way from `origin` toward
    /// `destination` that is reachable by road from `origin`. `nil` when
    /// none of the best candidates is — the caller should fall back to a
    /// manual choice. Never throws: a transient request failure on one
    /// candidate simply moves on to the next.
    static func plan(
        from origin: CLLocationCoordinate2D,
        toward destination: CLLocationCoordinate2D
    ) async -> HandoffPlan? {
        let originLocation = CLLocation(latitude: origin.latitude, longitude: origin.longitude)
        let destinationLocation = CLLocation(latitude: destination.latitude, longitude: destination.longitude)
        let directDistance = originLocation.distance(from: destinationLocation)

        // Detour cost: how much longer origin → gateway → destination is
        // than the straight line, weighted a little toward gateways that
        // are near the origin (a port the ram can actually reach on foot
        // in this lifetime beats one marginally more "on the way").
        let ranked = gateways
            .map { gateway -> (HandoffGateway, Double) in
                let gatewayLocation = CLLocation(latitude: gateway.coordinate.latitude, longitude: gateway.coordinate.longitude)
                let fromOrigin = originLocation.distance(from: gatewayLocation)
                let toDestination = gatewayLocation.distance(from: destinationLocation)
                let detour = fromOrigin + toDestination - directDistance
                return (gateway, detour + fromOrigin * 0.5)
            }
            .sorted { $0.1 < $1.1 }
            .map(\.0)

        for gateway in ranked.prefix(maxAttempts) {
            if Task.isCancelled { return nil }
            guard let leg = try? await RouteService.drivingRoute(from: origin, to: gateway.coordinate) else {
                continue
            }
            return HandoffPlan(gateway: gateway, leg: leg)
        }
        return nil
    }

    // MARK: - Gateways

    static let gateways: [HandoffGateway] = [
        // North America
        .init(name: "Vancouver", coordinate: .init(latitude: 49.2827, longitude: -123.1207)),
        .init(name: "Seattle", coordinate: .init(latitude: 47.6062, longitude: -122.3321)),
        .init(name: "San Francisco", coordinate: .init(latitude: 37.7749, longitude: -122.4194)),
        .init(name: "Los Angeles", coordinate: .init(latitude: 34.0522, longitude: -118.2437)),
        .init(name: "Anchorage", coordinate: .init(latitude: 61.2181, longitude: -149.9003)),
        .init(name: "Honolulu", coordinate: .init(latitude: 21.3069, longitude: -157.8583)),
        .init(name: "Houston", coordinate: .init(latitude: 29.7604, longitude: -95.3698)),
        .init(name: "Miami", coordinate: .init(latitude: 25.7617, longitude: -80.1918)),
        .init(name: "New York", coordinate: .init(latitude: 40.7128, longitude: -74.0060)),
        .init(name: "Boston", coordinate: .init(latitude: 42.3601, longitude: -71.0589)),
        .init(name: "Montreal", coordinate: .init(latitude: 45.5017, longitude: -73.5673)),
        .init(name: "Halifax", coordinate: .init(latitude: 44.6488, longitude: -63.5752)),
        .init(name: "St. John's", coordinate: .init(latitude: 47.5615, longitude: -52.7126)),
        .init(name: "Veracruz", coordinate: .init(latitude: 19.1738, longitude: -96.1342)),
        .init(name: "Panama City", coordinate: .init(latitude: 8.9824, longitude: -79.5199)),
        // South America
        .init(name: "Cartagena", coordinate: .init(latitude: 10.3910, longitude: -75.4794)),
        .init(name: "Lima", coordinate: .init(latitude: -12.0464, longitude: -77.0428)),
        .init(name: "Valparaíso", coordinate: .init(latitude: -33.0472, longitude: -71.6127)),
        .init(name: "Buenos Aires", coordinate: .init(latitude: -34.6037, longitude: -58.3816)),
        .init(name: "Santos", coordinate: .init(latitude: -23.9608, longitude: -46.3336)),
        .init(name: "Rio de Janeiro", coordinate: .init(latitude: -22.9068, longitude: -43.1729)),
        // Europe
        .init(name: "Reykjavík", coordinate: .init(latitude: 64.1466, longitude: -21.9426)),
        .init(name: "Dublin", coordinate: .init(latitude: 53.3498, longitude: -6.2603)),
        .init(name: "Glasgow", coordinate: .init(latitude: 55.8642, longitude: -4.2518)),
        .init(name: "Southampton", coordinate: .init(latitude: 50.9097, longitude: -1.4044)),
        .init(name: "London", coordinate: .init(latitude: 51.5074, longitude: -0.1278)),
        .init(name: "Porto", coordinate: .init(latitude: 41.1579, longitude: -8.6291)),
        .init(name: "Lisbon", coordinate: .init(latitude: 38.7223, longitude: -9.1393)),
        .init(name: "Valencia", coordinate: .init(latitude: 39.4699, longitude: -0.3763)),
        .init(name: "Barcelona", coordinate: .init(latitude: 41.3874, longitude: 2.1686)),
        .init(name: "Marseille", coordinate: .init(latitude: 43.2965, longitude: 5.3698)),
        .init(name: "Genoa", coordinate: .init(latitude: 44.4056, longitude: 8.9463)),
        .init(name: "Naples", coordinate: .init(latitude: 40.8518, longitude: 14.2681)),
        .init(name: "Piraeus", coordinate: .init(latitude: 37.9475, longitude: 23.6372)),
        .init(name: "Istanbul", coordinate: .init(latitude: 41.0082, longitude: 28.9784)),
        .init(name: "Antwerp", coordinate: .init(latitude: 51.2194, longitude: 4.4025)),
        .init(name: "Rotterdam", coordinate: .init(latitude: 51.9244, longitude: 4.4777)),
        .init(name: "Hamburg", coordinate: .init(latitude: 53.5511, longitude: 9.9937)),
        .init(name: "Copenhagen", coordinate: .init(latitude: 55.6761, longitude: 12.5683)),
        .init(name: "Gdańsk", coordinate: .init(latitude: 54.3520, longitude: 18.6466)),
        .init(name: "Oslo", coordinate: .init(latitude: 59.9139, longitude: 10.7522)),
        .init(name: "Bergen", coordinate: .init(latitude: 60.3913, longitude: 5.3221)),
        .init(name: "Stockholm", coordinate: .init(latitude: 59.3293, longitude: 18.0686)),
        .init(name: "Helsinki", coordinate: .init(latitude: 60.1699, longitude: 24.9384)),
        .init(name: "Saint Petersburg", coordinate: .init(latitude: 59.9311, longitude: 30.3609)),
        // Africa & Middle East
        .init(name: "Casablanca", coordinate: .init(latitude: 33.5731, longitude: -7.5898)),
        .init(name: "Alexandria", coordinate: .init(latitude: 31.2001, longitude: 29.9187)),
        .init(name: "Lagos", coordinate: .init(latitude: 6.5244, longitude: 3.3792)),
        .init(name: "Mombasa", coordinate: .init(latitude: -4.0435, longitude: 39.6682)),
        .init(name: "Durban", coordinate: .init(latitude: -29.8587, longitude: 31.0218)),
        .init(name: "Cape Town", coordinate: .init(latitude: -33.9249, longitude: 18.4241)),
        .init(name: "Haifa", coordinate: .init(latitude: 32.7940, longitude: 34.9896)),
        .init(name: "Dubai", coordinate: .init(latitude: 25.2048, longitude: 55.2708)),
        // Asia & Oceania
        .init(name: "Karachi", coordinate: .init(latitude: 24.8607, longitude: 67.0011)),
        .init(name: "Mumbai", coordinate: .init(latitude: 19.0760, longitude: 72.8777)),
        .init(name: "Chennai", coordinate: .init(latitude: 13.0827, longitude: 80.2707)),
        .init(name: "Colombo", coordinate: .init(latitude: 6.9271, longitude: 79.8612)),
        .init(name: "Bangkok", coordinate: .init(latitude: 13.7563, longitude: 100.5018)),
        .init(name: "Singapore", coordinate: .init(latitude: 1.3521, longitude: 103.8198)),
        .init(name: "Jakarta", coordinate: .init(latitude: -6.2088, longitude: 106.8456)),
        .init(name: "Ho Chi Minh City", coordinate: .init(latitude: 10.8231, longitude: 106.6297)),
        .init(name: "Manila", coordinate: .init(latitude: 14.5995, longitude: 120.9842)),
        .init(name: "Hong Kong", coordinate: .init(latitude: 22.3193, longitude: 114.1694)),
        .init(name: "Keelung", coordinate: .init(latitude: 25.1276, longitude: 121.7392)),
        .init(name: "Shanghai", coordinate: .init(latitude: 31.2304, longitude: 121.4737)),
        .init(name: "Busan", coordinate: .init(latitude: 35.1796, longitude: 129.0756)),
        .init(name: "Osaka", coordinate: .init(latitude: 34.6937, longitude: 135.5023)),
        .init(name: "Tokyo", coordinate: .init(latitude: 35.6762, longitude: 139.6503)),
        .init(name: "Vladivostok", coordinate: .init(latitude: 43.1155, longitude: 131.8855)),
        .init(name: "Perth", coordinate: .init(latitude: -31.9505, longitude: 115.8605)),
        .init(name: "Melbourne", coordinate: .init(latitude: -37.8136, longitude: 144.9631)),
        .init(name: "Sydney", coordinate: .init(latitude: -33.8688, longitude: 151.2093)),
        .init(name: "Brisbane", coordinate: .init(latitude: -27.4698, longitude: 153.0251)),
        .init(name: "Auckland", coordinate: .init(latitude: -36.8485, longitude: 174.7633)),
        .init(name: "Wellington", coordinate: .init(latitude: -41.2865, longitude: 174.7762)),
    ]
}
