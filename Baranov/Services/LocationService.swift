//
//  LocationService.swift
//  Baranov
//
//  Two jobs, one `CLLocationManager`:
//
//  1. Resolve the sender's current city on request (`resolveCurrentLocation`)
//     so a letter's starting point defaults to wherever they actually are —
//     the way Apple Maps' directions sheet defaults to "My Location". This
//     is the one-shot, city-level path: coarse accuracy, stops the radio
//     the moment a usable fix lands, and every failure (denied, no fix,
//     reverse geocoding failing) is surfaced through
//     `authorizationDenied`/`isResolving` so the compose form can explain
//     why sending is blocked instead of just staying disabled.
//
//  2. Keep the map's own marker alive (`startLiveTracking` /
//     `stopLiveTracking`): continuous, best-accuracy location updates plus
//     compass heading for as long as the Journey map is on screen. This
//     is what moves the marker as the person walks, turns the heading
//     indicator toward where they're facing/going, and reports whether
//     they are moving *right now* (`isMovingByLocation`) so the sprite can
//     switch between its running and standing frames even before the
//     pedometer's first (often seconds-late) step callback.
//
//  Location is strictly while-in-use. There is no background location:
//  steps come from CMPedometer / HealthKit, which keep counting while the
//  app is suspended and are caught up when it returns, so the radio has no
//  reason to run behind a locked screen. (`location` is deliberately not in
//  `UIBackgroundModes`.)
//
//  The one-shot resolver and live tracking coexist: while live tracking
//  is on, a resolve just reads the freshest fix instead of stopping the
//  radio out from under the map, and `stopLiveTracking` returns the
//  manager to its coarse, battery-friendly settings.
//
//  Why the resolver is "keep trying until something lands" rather than a
//  single `requestLocation()`: that call is one shot — the first
//  `kCLErrorLocationUnknown` (routine indoors, on a cold start, or on a
//  Simulator with no simulated location) ends it with no fix and nothing
//  would ever retry, leaving Send disabled for the whole session. The
//  coordinate is also published the instant CoreLocation delivers it,
//  *before* reverse geocoding (a network round trip with no timeout of its
//  own) — Send only ever needed the coordinate; the city name fills in
//  afterwards.
//

import CoreLocation
import Foundation
import Observation

@Observable
@MainActor
final class LocationService: NSObject {
    // MARK: - Published state

    private(set) var currentCoordinate: CLLocationCoordinate2D?
    private(set) var currentCityName: String?
    private(set) var isResolving = false
    private(set) var authorizationDenied = false

    /// The most recent full fix (timestamp, speed, course, accuracy) —
    /// what the live map marker and the movement detector read.
    private(set) var currentLocation: CLLocation?

    /// Compass heading in degrees (0 = north), true heading when the
    /// device can provide one, magnetic otherwise. `nil` until the first
    /// valid reading, or on hardware without a magnetometer.
    private(set) var currentHeadingDegrees: Double?

    /// Direction of travel in degrees from the GPS fix (`CLLocation.course`),
    /// only while it's valid — CoreLocation reports a negative course when
    /// it can't determine one (standing still, poor fix).
    private(set) var currentCourseDegrees: Double?

    /// Ground speed in metres per second from the latest fix, never
    /// negative (CoreLocation uses negative to mean "unknown").
    private(set) var currentSpeedMetersPerSecond: Double = 0

    /// Whether the person is moving right now according to the GPS
    /// stream: `true` once a fix reports speed above
    /// `movingSpeedThreshold` (or consecutive fixes are far enough apart
    /// to imply it), and back to `false` after `movementGracePeriod`
    /// without such a fix. This is the location-side counterpart to
    /// `StepTrackerService.isSenderMoving`; the map ORs the two.
    private(set) var isMovingByLocation = false

    /// When `isMovingByLocation` last saw movement.
    private(set) var lastMovementAt: Date?

    /// Whether continuous updates (and heading) are currently running.
    private(set) var isLiveTracking = false

    /// The direction the marker should face: the direction of travel
    /// while actually moving (it's what the person is walking toward and
    /// is far steadier than the compass mid-stride), the compass heading
    /// otherwise (so a person turning on the spot sees the indicator
    /// turn with them), and `nil` if neither is known yet.
    var travelBearingDegrees: Double? {
        if isMovingByLocation, let course = currentCourseDegrees {
            return course
        }
        return currentHeadingDegrees ?? currentCourseDegrees
    }

    // MARK: - Tuning

    /// Speed below this reads as "standing still" — GPS jitter on a
    /// stationary phone typically shows 0–0.3 m/s; a slow walk is ~1 m/s.
    static let movingSpeedThreshold: Double = 0.35

    /// How long after the last moving fix the marker keeps running.
    /// Bridges the ~1 s gaps between fixes and the occasional dropped
    /// one without the sprite flickering between running and standing.
    static let movementGracePeriod: TimeInterval = 5

    /// Stops a one-shot fix attempt that never produces a usable location
    /// (Location Services off, or a Simulator with no simulated location)
    /// so the UI isn't stuck on "Finding your starting location…" forever.
    private static let fixTimeout: Duration = .seconds(20)

    /// A cached fix older than this is still used to seed the coordinate
    /// right away, but a fresh fix is always requested behind it.
    private static let staleFixInterval: TimeInterval = 5 * 60

    /// Headings from the magnetometer that are worse than this (degrees
    /// of uncertainty) are ignored; negative means invalid.
    private static let maximumHeadingUncertainty: CLLocationDirection = 45

    // MARK: - Internals

    private let manager: CLLocationManager
    private let geocoder = CLGeocoder()

    @ObservationIgnored private var timeoutTask: Task<Void, Never>?
    @ObservationIgnored private var geocodeTask: Task<Void, Never>?
    @ObservationIgnored private var movementIdleTask: Task<Void, Never>?
    @ObservationIgnored private var wantsLiveTracking = false
    @ObservationIgnored private var lastGeocodedLocation: CLLocation?

    override init() {
        manager = CLLocationManager()
        super.init()
        manager.delegate = self
        manager.activityType = .fitness
        manager.pausesLocationUpdatesAutomatically = false
        applyCoarseSettings()
    }

    // MARK: - One-shot city resolution

    /// Kicks off (or re-triggers) resolving the sender's current city.
    /// Safe to call repeatedly — a request already in flight is a no-op,
    /// and a prior denial is remembered rather than re-prompting forever.
    func resolveCurrentLocation() {
        guard !isResolving else { return }

        switch manager.authorizationStatus {
        case .notDetermined:
            isResolving = true
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            authorizationDenied = false
            beginFix()
        case .denied, .restricted:
            authorizationDenied = true
        @unknown default:
            break
        }
    }

    // MARK: - Live tracking (map marker + heading)

    /// Starts continuous location + heading updates. Requests permission
    /// first if it hasn't been decided; updates begin automatically once
    /// it's granted. Idempotent.
    func startLiveTracking() {
        wantsLiveTracking = true

        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            authorizationDenied = false
            beginLiveUpdates()
        case .denied, .restricted:
            authorizationDenied = true
        @unknown default:
            break
        }
    }

    /// Stops continuous updates and heading, returning the manager to its
    /// coarse settings. A one-shot city resolve still works afterwards.
    func stopLiveTracking() {
        wantsLiveTracking = false
        guard isLiveTracking else { return }
        isLiveTracking = false
        manager.stopUpdatingHeading()
        // Only stop location updates if no one-shot resolve is mid-flight;
        // `endFix` will stop them itself when that finishes.
        if !isResolving {
            manager.stopUpdatingLocation()
        }
        applyCoarseSettings()
        movementIdleTask?.cancel()
        movementIdleTask = nil
        isMovingByLocation = false
        currentCourseDegrees = nil
        currentSpeedMetersPerSecond = 0
    }

    private func beginLiveUpdates() {
        guard !isLiveTracking else { return }
        isLiveTracking = true

        // Ten-metre accuracy with a 5 m filter is plenty for a map marker and
        // draws far less power than best accuracy with no filter.
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = 5
        manager.headingFilter = 5
        manager.pausesLocationUpdatesAutomatically = false

        if let cached = manager.location {
            publish(cached)
        }
        manager.startUpdatingLocation()
        if CLLocationManager.headingAvailable() {
            manager.startUpdatingHeading()
        }
    }

    private func applyCoarseSettings() {
        // City-level accuracy is all a letter's starting point needs, and
        // a coarser target lets CoreLocation answer from Wi-Fi/cell far
        // sooner than a "best" fix that waits on GPS.
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 50
    }

    // MARK: - One-shot fix lifecycle

    private func beginFix() {
        // Seed from whatever the system already knows so dependent UI
        // (the Send button, the idle ram on the map) unblocks at once;
        // a fresh fix still follows and replaces it.
        if let cached = manager.location, currentCoordinate == nil {
            publish(cached)
            if Date().timeIntervalSince(cached.timestamp) < Self.staleFixInterval {
                return
            }
        }

        // Live tracking already has the radio running at full accuracy —
        // the next fix it delivers satisfies this resolve too.
        if isLiveTracking {
            if currentCoordinate != nil { return }
            isResolving = true
            armFixTimeout()
            return
        }

        isResolving = true
        manager.startUpdatingLocation()
        armFixTimeout()
    }

    private func armFixTimeout() {
        timeoutTask?.cancel()
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: Self.fixTimeout)
            guard !Task.isCancelled, let self else { return }
            // If nothing better arrived, fall back to any fix at all so
            // the sender isn't blocked by a slow GPS lock.
            if self.currentCoordinate == nil, let cached = self.manager.location {
                self.publish(cached)
            }
            self.endFix()
        }
    }

    private func endFix() {
        timeoutTask?.cancel()
        timeoutTask = nil
        if !isLiveTracking {
            manager.stopUpdatingLocation()
        }
        isResolving = false
    }

    // MARK: - Publishing

    /// Publishes the coordinate immediately (that alone is what gates
    /// sending and routing), then fills in a human city name behind it.
    /// Called for every fix while live tracking, so it must stay cheap:
    /// reverse geocoding only re-runs when there's no name yet or the fix
    /// moved a long way from the last geocoded one.
    private func publish(_ location: CLLocation) {
        let previous = currentLocation
        currentLocation = location
        currentCoordinate = location.coordinate

        if currentCityName == nil {
            currentCityName = String(localized: "Current Location", bundle: .appLanguage, locale: .appLanguage)
        }
        if shouldReverseGeocode(location) {
            reverseGeocode(location)
        }

        updateMovement(from: previous, to: location)
    }

    private func shouldReverseGeocode(_ location: CLLocation) -> Bool {
        guard let last = lastGeocodedLocation else { return true }
        // A city name doesn't change every metre; 500 m is well inside
        // any locality and avoids a geocode per GPS tick.
        return location.distance(from: last) > 500
    }

    private func updateMovement(from previous: CLLocation?, to location: CLLocation) {
        let speed = max(0, location.speed)
        currentSpeedMetersPerSecond = speed

        // Negative means CoreLocation couldn't determine one this fix;
        // keep the last known course rather than blanking it.
        if location.course >= 0 {
            currentCourseDegrees = location.course
        }

        var moving = speed > Self.movingSpeedThreshold

        // Some fixes (Wi-Fi/cell, or a Simulator location) carry no
        // speed at all. Fall back to displacement between consecutive
        // fixes so movement is still detected, but only when both fixes
        // are precise enough that the displacement isn't just jitter.
        if !moving, location.speed < 0, let previous {
            let interval = location.timestamp.timeIntervalSince(previous.timestamp)
            if interval > 0.5,
               location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 30,
               previous.horizontalAccuracy >= 0, previous.horizontalAccuracy <= 30 {
                let distance = location.distance(from: previous)
                let impliedSpeed = distance / interval
                if distance > max(3, location.horizontalAccuracy * 0.5),
                   impliedSpeed > Self.movingSpeedThreshold {
                    moving = true
                    currentSpeedMetersPerSecond = impliedSpeed
                    if currentCourseDegrees == nil || location.course < 0 {
                        currentCourseDegrees = Self.bearing(from: previous.coordinate, to: location.coordinate)
                    }
                }
            }
        }

        if moving {
            noteMovement()
        }
    }

    /// Marks the person as moving and (re)arms the idle timer that clears
    /// it after a quiet stretch — each moving fix restarts the countdown,
    /// so the running animation holds steadily through fix-to-fix gaps.
    private func noteMovement() {
        lastMovementAt = Date()
        if !isMovingByLocation {
            isMovingByLocation = true
        }
        movementIdleTask?.cancel()
        movementIdleTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.movementGracePeriod))
            guard !Task.isCancelled, let self else { return }
            self.isMovingByLocation = false
            self.currentSpeedMetersPerSecond = 0
        }
    }

    private static func bearing(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        let lat1 = from.latitude * .pi / 180
        let lat2 = to.latitude * .pi / 180
        let deltaLon = (to.longitude - from.longitude) * .pi / 180
        let y = sin(deltaLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(deltaLon)
        let degrees = atan2(y, x) * 180 / .pi
        return (degrees + 360).truncatingRemainder(dividingBy: 360)
    }

    private func reverseGeocode(_ location: CLLocation) {
        geocodeTask?.cancel()
        geocoder.cancelGeocode()
        lastGeocodedLocation = location
        geocodeTask = Task { [weak self] in
            guard let self else { return }
            do {
                let placemarks = try await self.geocoder.reverseGeocodeLocation(location, preferredLocale: .appLanguage)
                guard !Task.isCancelled else { return }
                if let name = placemarks.first?.locality ?? placemarks.first?.name {
                    self.currentCityName = name
                }
            } catch {
                // Offline-first: the coordinate itself is still good for
                // routing even when reverse geocoding fails — only the
                // display label stays on its generic fallback. Allow a
                // retry on the next fix rather than waiting for 500 m.
                self.lastGeocodedLocation = nil
            }
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            switch self.manager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways:
                // A prior denial (or a stale flag from before the person
                // flipped permission on in Settings) should never keep
                // showing "access is off" once it's actually back on.
                self.authorizationDenied = false
                if self.wantsLiveTracking {
                    self.beginLiveUpdates()
                }
                // `isResolving` may already be `true` from the permission
                // prompt that led here — clear it so `beginFix` runs.
                if self.isResolving {
                    self.isResolving = false
                    self.beginFix()
                }
            case .denied, .restricted:
                self.endFix()
                if self.isLiveTracking {
                    self.isLiveTracking = false
                    self.manager.stopUpdatingHeading()
                    self.manager.stopUpdatingLocation()
                }
                self.authorizationDenied = true
            default:
                break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // Deliver every fix in order so displacement-based movement
        // detection sees consecutive samples, not just the newest.
        let fixes = locations
        Task { @MainActor [weak self] in
            guard let self else { return }
            for location in fixes {
                // Reject fixes CoreLocation itself marks as unusable.
                guard location.horizontalAccuracy >= 0 else { continue }
                self.publish(location)
            }
            if self.isResolving, self.currentCoordinate != nil {
                self.endFix()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        guard newHeading.headingAccuracy >= 0,
              newHeading.headingAccuracy <= Self.maximumHeadingUncertainty
        else { return }
        let degrees = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        Task { @MainActor [weak self] in
            self?.currentHeadingDegrees = degrees
        }
    }

    nonisolated func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool {
        // The system's figure-eight calibration prompt would cover the
        // map; a slightly less accurate heading is fine for a marker.
        false
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let code = (error as? CLError)?.code
        Task { @MainActor [weak self] in
            guard let self else { return }
            switch code {
            case .locationUnknown:
                // Transient — CoreLocation keeps trying on its own while
                // updates are running; the timeout bounds the wait.
                break
            case .headingFailure:
                // Magnetic interference or no magnetometer — the marker
                // falls back to the GPS course; nothing to surface.
                break
            case .denied:
                self.endFix()
                self.authorizationDenied = true
            default:
                if self.currentCoordinate == nil, let cached = self.manager.location {
                    self.publish(cached)
                }
                if self.isResolving {
                    self.endFix()
                }
            }
        }
    }
}
