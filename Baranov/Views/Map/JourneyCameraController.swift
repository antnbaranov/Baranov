//
//  JourneyCameraController.swift
//  Baranov
//
//  Owns the Journey map's camera: the one `MapCameraPosition` the `Map`
//  binds to, whether it is currently following the tracked ram, and the
//  distinction between a camera move this app made and one the person
//  made with their fingers — the latter is the only thing that switches
//  following off.
//
//  Three motions live here:
//
//  1. `flyover(...)` — the moment a letter is dispatched. The camera lifts
//     off wherever it was (usually the person's own blue-dot spot, which
//     may be a different city from where the ram sets out), frames the
//     whole leg so its shape registers, then dives onto the departure
//     vertex — `routeCoordinates[0]` exactly — into the tilted follow
//     camera. Two eased steps, one after the other, rather than a single
//     jump cut from the person to a ram somewhere else.
//  2. `follow(...)` — every step delta while following: a short eased
//     re-center on the ram's interpolated position. The ram sits above
//     the docked slider because the view reserves the sheet's height as
//     bottom safe area (`reservedBottomInset` in `JourneyView`) and
//     MapKit centers the camera inside the safe area, not the full frame
//     — so no manual screen-space offset is needed, and the padding
//     tracks the sheet's live detent for free.
//  3. `showUser(...)` / the return pill — a deliberate look back at where
//     the person actually is when that isn't where the ram is, without
//     losing the ram: "Find Ram" (or the pill again) resumes following.
//
//  Reads of `position.camera` are what `JourneyView` uses for the
//  distance-driven map style and region-overview switches.
//

import CoreLocation
import MapKit
import Observation
import SwiftUI

@Observable
@MainActor
final class JourneyCameraController {
    /// What the camera is looking at on purpose.
    enum Focus: Equatable {
        /// Tracking the ram as steps land.
        case ram
        /// The person's own location, while a ram is being tracked
        /// elsewhere (see the return pill).
        case user
        /// The person has taken the camera themselves.
        case free
    }

    /// Bound by the `Map`. Written here for every programmatic move;
    /// written by MapKit as the person pans and zooms.
    var position: MapCameraPosition = .automatic

    private(set) var focus: Focus = .ram

    /// Whether step updates should keep re-centering on the ram — the
    /// `isFollowingRam` the rest of `JourneyView` reads. Off the moment
    /// the person moves the camera themselves; back on via "Find Ram".
    var isFollowingRam: Bool { focus == .ram }

    /// True during the dispatch flyover; step deltas that land mid-flight
    /// don't fight it, and camera-change callbacks it produces aren't
    /// mistaken for the person panning.
    private(set) var isFlyingOver = false

    /// Tilted, close follow camera — the same "right up close, 3D" default
    /// Apple Maps settles into once it's centered on something.
    var followDistanceMeters: CLLocationDistance = 350
    var followPitchDegrees: Double = 65

    /// Set right before every assignment to `position` made here, and
    /// consumed by `noteCameraChangeEnded()`, so only the person's own
    /// gestures break following. A flag, not a counter: MapKit reports
    /// one `.onEnd` for a move that interrupts an earlier animated one,
    /// so counting would leave a stale expectation that swallowed the
    /// next real pan.
    @ObservationIgnored private var expectsProgrammaticChange = false
    @ObservationIgnored private var flyoverTask: Task<Void, Never>?

    var currentDistance: CLLocationDistance {
        position.camera?.distance ?? followDistanceMeters
    }

    var currentHeadingDegrees: Double {
        position.camera?.heading ?? 0
    }

    // MARK: - Map callbacks

    /// Call from `onMapCameraChange(frequency: .onEnd)`. A move this
    /// controller initiated is expected and ignored; anything else is the
    /// person browsing, which ends following (and the flyover, if they
    /// grab the map mid-flight).
    func noteCameraChangeEnded() {
        if expectsProgrammaticChange {
            expectsProgrammaticChange = false
            return
        }
        // Mid-flyover, every change is ours (two chained animations);
        // nothing here should read as the person taking over.
        guard !isFlyingOver else { return }
        focus = .free
    }

    // MARK: - Following the ram

    /// Turns following back on and re-centers — "Find Ram".
    func resumeFollowing(ramCoordinate: CLLocationCoordinate2D?, animated: Bool) {
        cancelFlyover()
        focus = .ram
        if let ramCoordinate {
            follow(ramCoordinate, animated: animated)
        }
    }

    /// One eased re-center on the ram's live position. No-op while not
    /// following or while the flyover is still in the air.
    func followIfNeeded(_ coordinate: CLLocationCoordinate2D?) {
        guard focus == .ram, !isFlyingOver, let coordinate else { return }
        follow(coordinate, animated: true)
    }

    private func follow(_ coordinate: CLLocationCoordinate2D, animated: Bool) {
        move(to: followCamera(centeredOn: coordinate), animation: animated ? .easeInOut(duration: 0.4) : nil)
    }

    /// A re-center that leaves `focus` alone — used when the map's own
    /// safe area changes shape under the camera (Look Around opening or
    /// closing), so whatever is being looked at stays in the visible
    /// half without silently switching following back on.
    func recenter(on coordinate: CLLocationCoordinate2D?, animated: Bool) {
        guard let coordinate, !isFlyingOver else { return }
        move(to: followCamera(centeredOn: coordinate), animation: animated ? .easeInOut(duration: 0.4) : nil)
    }

    // MARK: - The person's own spot (no ram, or looking back)

    /// Idle map: keep the camera on the person as fixes land. Only while
    /// they haven't taken the map themselves.
    func followUserIfNeeded(_ coordinate: CLLocationCoordinate2D?, animated: Bool) {
        guard focus != .free, !isFlyingOver, let coordinate else { return }
        move(to: followCamera(centeredOn: coordinate), animation: animated ? .easeInOut(duration: 0.4) : nil)
    }

    /// "My Location" with no ram tracked: re-enable following the person.
    func centerOnUser(_ coordinate: CLLocationCoordinate2D?, animated: Bool) {
        cancelFlyover()
        focus = .ram
        guard let coordinate else { return }
        move(to: followCamera(centeredOn: coordinate), animation: animated ? .easeInOut(duration: 0.4) : nil)
    }

    /// The return pill / "My Location" while a ram is being tracked
    /// somewhere else: look at the person without losing the ram. The
    /// pill then offers the way back.
    func showUser(_ coordinate: CLLocationCoordinate2D?, animated: Bool) {
        cancelFlyover()
        focus = .user
        guard let coordinate else { return }
        move(to: followCamera(centeredOn: coordinate), animation: animated ? .easeInOut(duration: 0.6) : nil)
    }

    // MARK: - Dispatch flyover

    /// Departure: lift off the current view, frame the leg, then settle
    /// onto its first vertex in the follow camera. `origin` must be the
    /// polyline's own `[0]` — not an interpolated point — so the camera
    /// and the marker land on the same spot.
    ///
    /// If the person is already looking at the origin at follow distance
    /// (they dispatched from where they stand and the idle camera was on
    /// them), the establishing shot is skipped and it just eases in —
    /// a lift-and-dive over a spot already on screen reads as theatre.
    func flyover(
        route: [CLLocationCoordinate2D],
        origin: CLLocationCoordinate2D,
        reduceMotion: Bool
    ) {
        guard CLLocationCoordinate2DIsValid(origin) else { return }
        cancelFlyover()
        focus = .ram

        let currentCenter = position.camera?.centerCoordinate
        let alreadyThere: Bool = {
            guard let currentCenter, position.camera != nil else { return false }
            let offset = CLLocation(latitude: currentCenter.latitude, longitude: currentCenter.longitude)
                .distance(from: CLLocation(latitude: origin.latitude, longitude: origin.longitude))
            return offset < 150 && currentDistance < followDistanceMeters * 3
        }()

        if reduceMotion || alreadyThere || route.count < 2 {
            move(to: followCamera(centeredOn: origin), animation: reduceMotion ? nil : .easeInOut(duration: 0.8))
            return
        }

        isFlyingOver = true
        let establishing = establishingCamera(framing: route)
        let arrival = followCamera(centeredOn: origin)

        flyoverTask = Task { [weak self] in
            guard let self else { return }
            // Up and out: the whole leg, flat, so its shape registers.
            self.move(to: establishing, animation: .easeInOut(duration: 1.1))
            try? await Task.sleep(for: .milliseconds(1_300))
            guard !Task.isCancelled else { return }

            // Down onto the departure vertex, into the tilted follow view.
            self.move(to: arrival, animation: .easeInOut(duration: 1.2))
            try? await Task.sleep(for: .milliseconds(1_250))
            guard !Task.isCancelled else { return }

            self.isFlyingOver = false
        }
    }

    private func cancelFlyover() {
        flyoverTask?.cancel()
        flyoverTask = nil
        isFlyingOver = false
    }

    // MARK: - Cameras

    private func followCamera(centeredOn coordinate: CLLocationCoordinate2D) -> MapCamera {
        MapCamera(
            centerCoordinate: coordinate,
            distance: followDistanceMeters,
            heading: 0,
            pitch: followPitchDegrees
        )
    }

    /// A flat camera high enough to take in every vertex of the leg, with
    /// some air around it. Distance is derived from the leg's bounding
    /// box (with a floor so a walk across town still reads as a lift-off,
    /// not a twitch).
    private func establishingCamera(framing route: [CLLocationCoordinate2D]) -> MapCamera {
        var minLat = route[0].latitude, maxLat = route[0].latitude
        var minLon = route[0].longitude, maxLon = route[0].longitude
        for point in route {
            minLat = min(minLat, point.latitude); maxLat = max(maxLat, point.latitude)
            minLon = min(minLon, point.longitude); maxLon = max(maxLon, point.longitude)
        }
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
        let corner1 = CLLocation(latitude: minLat, longitude: minLon)
        let corner2 = CLLocation(latitude: maxLat, longitude: maxLon)
        let diagonal = corner1.distance(from: corner2)

        // ~1.6× the diagonal keeps the polyline clear of the sheet and the
        // top chrome; floor at 2.5 km so short legs still get a real shot.
        let distance = max(2_500, diagonal * 1.6)
        return MapCamera(centerCoordinate: center, distance: distance, heading: 0, pitch: 0)
    }

    private func move(to camera: MapCamera, animation: Animation?) {
        guard CLLocationCoordinate2DIsValid(camera.centerCoordinate) else { return }
        expectsProgrammaticChange = true
        if let animation {
            withAnimation(animation) {
                position = .camera(camera)
            }
        } else {
            position = .camera(camera)
        }
    }

    // MARK: - Offset between person and mission

    /// How far the person is from where the ram currently stands — what
    /// the return pill shows, and whether it shows at all.
    static func offsetMeters(
        from user: CLLocationCoordinate2D?,
        to ram: CLLocationCoordinate2D?
    ) -> CLLocationDistance? {
        guard let user, let ram,
              CLLocationCoordinate2DIsValid(user), CLLocationCoordinate2DIsValid(ram)
        else { return nil }
        return CLLocation(latitude: user.latitude, longitude: user.longitude)
            .distance(from: CLLocation(latitude: ram.latitude, longitude: ram.longitude))
    }
}
