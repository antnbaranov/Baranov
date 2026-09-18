//
//  CalendarTripSuggestionService.swift
//  Baranov
//
//  Suggests destinations from the person's own upcoming calendar events —
//  the fast alternative to typing a known carrier's destination by hand in
//  `CarrierDirectoryView`. Only events that are actually far from home make
//  the cut: a lunch across town isn't "heading somewhere" the way a trip
//  abroad is, so every candidate is geocoded up front and dropped unless
//  it's at least `minimumDistanceMeters` (300 km by default — comfortably
//  "another city/country," not just the other side of the metro area) from
//  wherever `refresh(near:)` was called with. Access is requested lazily,
//  only when Pasture actually asks for suggestions, and every failure path
//  (denied, no events, a geocode miss) just means an empty chip row rather
//  than any error the rest of the app has to handle.
//
//  `suggestions` is cached (`UserDefaults`-backed JSON, same lightweight
//  pattern as `RamCompanionStore`/`KnownCarrierDirectory`) and loaded back
//  on init, so a fresh `PastureView` — created new every time Pasture's
//  sheet is presented — shows last time's trips immediately instead of an
//  empty row while EventKit and the geocoder run all over again.
//  `refresh(near:)` itself still always does a real, un-cached query; it's
//  the caller's job to decide when that's actually worth doing (see
//  `PastureView`, which now only auto-refreshes once, before any cache
//  exists, and otherwise leaves refreshing to the pull-to-refresh control).
//

import CoreLocation
import EventKit
import Foundation
import Observation

/// One upcoming calendar event that names a place far enough from home to
/// be worth suggesting — a candidate for "I'm headed here soon."
struct TripSuggestion: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let title: String
    /// "City, Country" (or whatever subset `CLPlacemark` could resolve),
    /// never the raw free-text event location.
    let displayName: String
    let coordinate: RamCoordinate
    let date: Date

    init(
        id: UUID = UUID(),
        title: String,
        displayName: String,
        coordinate: RamCoordinate,
        date: Date
    ) {
        self.id = id
        self.title = title
        self.displayName = displayName
        self.coordinate = coordinate
        self.date = date
    }
}

@Observable
@MainActor
final class CalendarTripSuggestionService {
    private(set) var suggestions: [TripSuggestion] = []
    private(set) var isAuthorized = false

    /// When `suggestions` was last actually fetched from EventKit — `nil`
    /// means never (this install has no cache yet), which is the one case
    /// `PastureView` still auto-refreshes for.
    private(set) var lastRefreshedAt: Date?

    private let store = EKEventStore()
    private let geocoder = CLGeocoder()

    private static let cacheKey = "com.baranov.tripSuggestionsCache"
    private static let lastRefreshedKey = "com.baranov.tripSuggestionsLastRefreshedAt"

    /// Bounds how many raw event locations get geocoded per `refresh`,
    /// independent of how many actually pass the distance filter — a
    /// calendar with dozens of local events in the window shouldn't mean
    /// dozens of geocode requests.
    private let maxCandidatesToGeocode = 20

    init() {
        loadCache()
    }

    /// Refreshes `suggestions` from calendar events with a location, in the
    /// next `withinDays` days, keeping only ones at least
    /// `minimumDistanceMeters` from `referenceCoordinate` — i.e. an actual
    /// trip away from home, not somewhere already nearby. Never throws
    /// outward: a denied or not-yet-decided permission, or no events
    /// clearing the distance bar, simply leaves `suggestions` empty, which
    /// callers use to hide the chip row entirely rather than showing an
    /// error state.
    func refresh(
        near referenceCoordinate: CLLocationCoordinate2D,
        withinDays: Int = 30,
        minimumDistanceMeters: CLLocationDistance = 300_000
    ) async {
        do {
            let granted = try await store.requestFullAccessToEvents()
            isAuthorized = granted
            guard granted else {
                suggestions = []
                return
            }
        } catch {
            isAuthorized = false
            suggestions = []
            return
        }

        let now = Date()
        guard let end = Calendar.current.date(byAdding: .day, value: withinDays, to: now) else { return }

        let predicate = store.predicateForEvents(withStart: now, end: end, calendars: nil)
        let events = store.events(matching: predicate)
        let referenceLocation = CLLocation(latitude: referenceCoordinate.latitude, longitude: referenceCoordinate.longitude)

        var seenLocations = Set<String>()
        var candidatesGeocoded = 0
        var results: [TripSuggestion] = []

        for event in events.sorted(by: { $0.startDate < $1.startDate }) {
            guard results.count < 8, candidatesGeocoded < maxCandidatesToGeocode else { break }
            guard let rawLocation = event.location else { continue }
            let location = rawLocation.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !location.isEmpty, !seenLocations.contains(location.lowercased()) else { continue }
            seenLocations.insert(location.lowercased())

            candidatesGeocoded += 1
            guard let placemark = try? await geocoder.geocodeAddressString(location).first,
                  let eventCoordinate = placemark.location?.coordinate else { continue }

            let distanceMeters = CLLocation(latitude: eventCoordinate.latitude, longitude: eventCoordinate.longitude)
                .distance(from: referenceLocation)
            guard distanceMeters >= minimumDistanceMeters else { continue }

            results.append(
                TripSuggestion(
                    title: event.title ?? "Trip",
                    displayName: Self.displayName(for: placemark, fallback: location),
                    coordinate: RamCoordinate(eventCoordinate),
                    date: event.startDate
                )
            )
        }

        suggestions = results
        lastRefreshedAt = Date()
        saveCache()
    }

    private func loadCache() {
        if let data = UserDefaults.standard.data(forKey: Self.cacheKey),
           let decoded = try? JSONDecoder().decode([TripSuggestion].self, from: data) {
            suggestions = decoded
        }
        lastRefreshedAt = UserDefaults.standard.object(forKey: Self.lastRefreshedKey) as? Date
    }

    private func saveCache() {
        if let data = try? JSONEncoder().encode(suggestions) {
            UserDefaults.standard.set(data, forKey: Self.cacheKey)
        }
        UserDefaults.standard.set(lastRefreshedAt, forKey: Self.lastRefreshedKey)
    }

    /// "City, Country" from a resolved placemark, falling back gracefully
    /// (city only, country only, or the original free-text location) when
    /// a geocode result is missing one part.
    private static func displayName(for placemark: CLPlacemark, fallback: String) -> String {
        let city = placemark.locality ?? placemark.subAdministrativeArea ?? placemark.administrativeArea
        let country = placemark.country

        switch (city, country) {
        case let (city?, country?): return "\(city), \(country)"
        case let (city?, nil): return city
        case let (nil, country?): return country
        default: return fallback
        }
    }
}

#if DEBUG
extension CalendarTripSuggestionService {
    /// Illustrative suggestions for SwiftUI canvas previews — never backed
    /// by a real `EKEventStore` query.
    static var preview: CalendarTripSuggestionService {
        let service = CalendarTripSuggestionService()
        service.isAuthorized = true
        service.suggestions = [
            TripSuggestion(
                title: "Conference",
                displayName: "Berlin, Germany",
                coordinate: RamCoordinate(latitude: 52.5200, longitude: 13.4050),
                date: Date().addingTimeInterval(86_400 * 5)
            ),
            TripSuggestion(
                title: "Family visit",
                displayName: "Gander, Canada",
                coordinate: RamCoordinate(latitude: 48.9564, longitude: -54.6089),
                date: Date().addingTimeInterval(86_400 * 12)
            ),
        ]
        return service
    }
}
#endif
