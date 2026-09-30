//
//  DroppedDestination.swift
//  Baranov
//
//  A destination the sender marked by pressing and holding on the map
//  (instead of typing a place name). `JourneyView` creates it and hands it
//  to `ComposeLetterView`, which treats it exactly like a destination picked
//  from search results.
//

import CoreLocation
import Foundation

struct DroppedDestination: Equatable, Sendable {
    let latitude: Double
    let longitude: Double
    let name: String

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// A readable name for a spot on the map ("Water St, Vancouver"), or a
    /// plain "Dropped Pin" when the geocoder has nothing — offline included.
    static func resolve(_ coordinate: CLLocationCoordinate2D) async -> DroppedDestination {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let placemark = try? await CLGeocoder().reverseGeocodeLocation(location, preferredLocale: .appLanguage).first
        let parts = [placemark?.name ?? placemark?.thoroughfare, placemark?.locality]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        var seen = Set<String>()
        let unique = parts.filter { seen.insert($0).inserted }
        let name = unique.isEmpty ? String(localized: "Dropped Pin", bundle: .appLanguage, locale: .appLanguage) : unique.joined(separator: ", ")
        return DroppedDestination(latitude: coordinate.latitude, longitude: coordinate.longitude, name: name)
    }
}
