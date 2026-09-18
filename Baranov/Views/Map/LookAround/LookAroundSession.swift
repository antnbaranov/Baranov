//
//  LookAroundSession.swift
//  Baranov
//
//  The single source of truth for the Apple-Maps-style Look Around
//  presentation on the Journey map: which of the three stages it is in
//  (floating preview card → split screen → full screen), the resolved
//  `MKLookAroundScene`, the coordinate that scene was resolved for, and
//  the *estimated* camera heading / field of view that the map marker's
//  radar cone mirrors while the person pans inside the imagery.
//
//  Why "estimated": `MKLookAroundScene` is opaque — MapKit exposes no
//  public camera heading, pitch, or field of view for Look Around, and
//  panning inside the viewport does not fire any delegate callback
//  (`lookAroundViewControllerDidUpdateScene` only fires when the person
//  *navigates* to a different scene, which `LookAroundViewport` disables
//  so the cone always belongs to the marker it sits under). The heading
//  is therefore seeded from the ram's own travel bearing when the panel
//  expands and then integrated from the pan gesture the viewport observes
//  alongside MapKit's own — public API only, no private introspection.
//  It is kept as a continuous (unnormalized) value so the cone never
//  spins the long way round when a rotation crosses 0°/360°.
//

import CoreLocation
import MapKit
import Observation

/// The three visible stages of Look Around, plus hidden. Mirrors Apple
/// Maps: a small thumbnail card at the top-trailing corner, a split view
/// filling the upper part of the screen with the map still live below,
/// and an edge-to-edge full-screen view.
enum LookAroundLayout: Equatable, Sendable {
    case hidden
    case preview
    case split
    case fullscreen

    var isVisible: Bool { self != .hidden }
    var isExpanded: Bool { self == .split || self == .fullscreen }
}

@Observable
@MainActor
final class LookAroundSession {
    // MARK: - Published state

    private(set) var scene: MKLookAroundScene?
    private(set) var layout: LookAroundLayout = .hidden

    /// Where `scene` was resolved — the marker coordinate the heading cone
    /// is drawn under. Refreshing is skipped for tiny moves (see
    /// `needsRefresh(for:)`) so a live GPS stream doesn't reload the
    /// imagery every fix.
    private(set) var anchorCoordinate: CLLocationCoordinate2D?

    /// Estimated camera heading in degrees, 0 = north, clockwise,
    /// deliberately *not* wrapped to 0…360 (see the header doc).
    private(set) var headingDegrees: Double = 0

    /// Estimated horizontal field of view in degrees, driven by pinch.
    private(set) var fieldOfViewDegrees: Double = LookAroundSession.defaultFieldOfView

    /// `true` while `MKLookAroundViewController` has presented its own
    /// system full-screen modal (from a badge tap). Pan estimates are
    /// paused for its duration because the gestures then happen inside a
    /// view controller this session can't observe.
    private(set) var isSystemFullScreenActive = false

    // MARK: - Tuning

    static let defaultFieldOfView: Double = 80
    static let minimumFieldOfView: Double = 30
    static let maximumFieldOfView: Double = 110

    /// Below this, an anchor move isn't worth re-resolving the scene for
    /// — Look Around imagery is captured every few metres along a road
    /// anyway, and a scene reload while the panel is open reads as a
    /// flicker, not an update.
    static let refreshDistanceMeters: CLLocationDistance = 20

    /// Heading in 0…360 for display / accessibility.
    var normalizedHeadingDegrees: Double {
        Self.normalize(headingDegrees)
    }

    // MARK: - Scene lifecycle

    /// Whether resolving a new scene for `coordinate` is worthwhile.
    /// Never while expanded (the person is looking at it) and never for
    /// a move shorter than `refreshDistanceMeters`.
    func needsRefresh(for coordinate: CLLocationCoordinate2D) -> Bool {
        if layout.isExpanded { return false }
        guard scene != nil, let anchor = anchorCoordinate else { return true }
        let from = CLLocation(latitude: anchor.latitude, longitude: anchor.longitude)
        let to = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return from.distance(from: to) >= Self.refreshDistanceMeters
    }

    /// Installs a freshly resolved scene (or `nil` when there's no
    /// imagery). A first scene surfaces the preview card; losing the scene
    /// hides everything; a replacement while previewing just swaps the
    /// imagery in place.
    func update(scene newScene: MKLookAroundScene?, at coordinate: CLLocationCoordinate2D?) {
        scene = newScene
        anchorCoordinate = newScene == nil ? nil : coordinate
        if newScene == nil {
            layout = .hidden
        } else if layout == .hidden {
            layout = .preview
        }
    }

    // MARK: - Layout transitions

    /// Preview card → split screen. `initialHeading` seeds the cone (the
    /// ram's travel bearing, typically); the field of view resets to the
    /// default so a previous pinch doesn't leak into a new session.
    func expand(initialHeading: Double?) {
        guard scene != nil else { return }
        if let initialHeading {
            headingDegrees = Self.normalize(initialHeading)
        }
        fieldOfViewDegrees = Self.defaultFieldOfView
        layout = .split
    }

    /// Back to the floating preview card (or hidden if the scene is gone).
    func collapse() {
        guard layout.isVisible else { return }
        layout = scene == nil ? .hidden : .preview
    }

    func toggleFullscreen() {
        switch layout {
        case .split, .preview:
            layout = .fullscreen
        case .fullscreen:
            layout = .split
        case .hidden:
            break
        }
    }

    func noteSystemFullScreen(_ isActive: Bool) {
        isSystemFullScreenActive = isActive
    }

    // MARK: - Camera estimate

    /// Integrates a pan delta from the viewport. Positive `delta` turns
    /// the camera clockwise (to the right).
    func rotate(byDegrees delta: Double) {
        guard !isSystemFullScreenActive else { return }
        headingDegrees += delta
    }

    func setFieldOfView(_ degrees: Double) {
        guard !isSystemFullScreenActive else { return }
        fieldOfViewDegrees = min(max(degrees, Self.minimumFieldOfView), Self.maximumFieldOfView)
    }

    static func normalize(_ degrees: Double) -> Double {
        let wrapped = degrees.truncatingRemainder(dividingBy: 360)
        return wrapped < 0 ? wrapped + 360 : wrapped
    }
}
