//
//  NextLandmarkService.swift
//  Baranov
//
//  "1,800 km to Vancouver" is not a goal, it's a sentence. This service
//  answers a much smaller question instead: what is the next real, named
//  place this ram will reach, and how many steps away is it?
//
//  It works by walking forward along the current leg's polyline — the
//  same road-following path the ram itself is interpolated along — and
//  reverse-geocoding a handful of points ahead until one comes back with
//  a usable name (a river, a park or pass, a town). The nearest such
//  place becomes the ram's near-term target, and passing it is what earns
//  a passport stamp (`JourneyStamp`).
//
//  Deliberately conservative with `CLGeocoder`, which is rate-limited
//  per-app: a resolved landmark is held until the ram actually walks past
//  it, so a normal day's walking costs a couple of lookups, not one per
//  step callback. Every failure mode — no network, a throttled geocoder,
//  a stretch of road with nothing named on it — resolves to `nil`, which
//  the UI reads as "just don't show the line," never as an error.
//

import CoreLocation
import Foundation
import Observation

@Observable
@MainActor
final class NextLandmarkService {

    /// The next named place ahead on the current leg.
    struct Landmark: Equatable, Sendable {
        let name: String
        let kind: JourneyStampKind
        let coordinate: RamCoordinate
        /// How far along the leg's polyline this place sits, in meters —
        /// directly comparable with `Ram.stepsWalked`, since one step is
        /// one meter in this app.
        let metersAlongRoute: Double
    }

    private(set) var landmark: Landmark?
    private(set) var isResolving = false

    /// Which ram/leg the current `landmark` was resolved for, so a
    /// different ram — or the same ram starting a fresh leg after a
    /// handoff — re-resolves instead of pointing at the old leg's place.
    private var resolvedRamId: UUID?
    private var resolvedLegDestination: String?

    private let geocoder = CLGeocoder()

    /// How far ahead to look, in meters. Starts close enough that a city
    /// walk finds its next landmark within a block or two, and reaches far
    /// enough that an empty stretch of highway still finds the next town
    /// rather than giving up.
    private static let lookaheadOffsets: [Double] = [
        300, 800, 1_600, 3_200, 6_500, 13_000, 26_000, 55_000, 110_000
    ]

    /// Resolves the next landmark for this ram if the one already held is
    /// stale — the ram has walked past it, or it belongs to another ram or
    /// a previous leg. Safe to call from any step callback: it no-ops in
    /// the overwhelmingly common case where nothing has changed.
    func refreshIfNeeded(for ram: Ram) async {
        guard !isResolving else { return }
        guard ram.routeCoordinates.count > 1 else {
            clear()
            return
        }

        let isForThisLeg = resolvedRamId == ram.id && resolvedLegDestination == ram.legDestinationCity
        if isForThisLeg,
           let current = landmark,
           current.metersAlongRoute > Double(ram.stepsWalked) {
            return
        }

        await resolve(for: ram)
    }

    /// Drops any held landmark — used when no ram is being tracked, so a
    /// stale target never lingers on screen after a journey ends.
    func clear() {
        landmark = nil
        resolvedRamId = nil
        resolvedLegDestination = nil
    }

    // MARK: - Resolution

    private func resolve(for ram: Ram) async {
        isResolving = true
        defer { isResolving = false }

        resolvedRamId = ram.id
        resolvedLegDestination = ram.legDestinationCity
        landmark = nil

        let walked = Double(ram.stepsWalked)
        let legLength = Double(ram.totalStepsRequired)

        for offset in Self.lookaheadOffsets {
            let distanceAlongRoute = walked + offset

            // Never look past the end of the leg: the leg's own endpoint
            // is already shown as its own destination, and stamping it is
            // `FlockViewModel`'s job when the leg actually completes.
            guard distanceAlongRoute < legLength else { break }

            guard let coordinate = ram.coordinate(atMetersAlongRoute: distanceAlongRoute) else { break }

            guard let candidate = await namedPlace(at: coordinate) else { continue }

            // Skip anything the ram is effectively already "at": the leg's
            // own endpoints, and anywhere already stamped on this journey.
            guard !isRedundant(candidate.name, for: ram) else { continue }

            landmark = Landmark(
                name: candidate.name,
                kind: candidate.kind,
                coordinate: RamCoordinate(coordinate),
                metersAlongRoute: distanceAlongRoute
            )
            return
        }
    }

    /// Whether a resolved name is worth showing as a *next* target, or is
    /// just a restatement of where the ram already is / has been.
    private func isRedundant(_ name: String, for ram: Ram) -> Bool {
        let matches: (String) -> Bool = { name.caseInsensitiveCompare($0) == .orderedSame }
        if matches(ram.currentCity) { return true }
        if matches(ram.legDestinationCity) { return true }
        if ram.hasStamp(named: name) { return true }
        return false
    }

    /// One reverse-geocode, reduced to "is there something here worth
    /// naming?" A thrown error (offline, throttled, cancelled) is not
    /// propagated — it just means this particular point ahead contributes
    /// nothing, and the caller moves on to the next one.
    private func namedPlace(at coordinate: CLLocationCoordinate2D) async -> (name: String, kind: JourneyStampKind)? {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)

        guard let placemark = try? await geocoder.reverseGeocodeLocation(location, preferredLocale: .appLanguage).first else { return nil }

        if let water = placemark.inlandWater, !water.isEmpty {
            return (water, .water)
        }
        if let ocean = placemark.ocean, !ocean.isEmpty {
            return (ocean, .water)
        }
        if let areaOfInterest = placemark.areasOfInterest?.first, !areaOfInterest.isEmpty {
            return (areaOfInterest, .landmark)
        }
        if let subLocality = placemark.subLocality, !subLocality.isEmpty {
            return (subLocality, .town)
        }
        if let locality = placemark.locality, !locality.isEmpty {
            return (locality, .town)
        }
        if let administrativeArea = placemark.administrativeArea, !administrativeArea.isEmpty {
            return (administrativeArea, .landmark)
        }
        return nil
    }
}
