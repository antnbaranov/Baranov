//
//  LookAroundViewport.swift
//  Baranov
//
//  Hosts `MKLookAroundViewController` inside SwiftUI. SwiftUI's own
//  `LookAroundPreview` can't be used here for two reasons: it offers no
//  delegate (so the system full-screen presentation it triggers on tap
//  can't be observed or kept coherent with the split-screen layout), and
//  it gives no access to the touches inside the imagery, which is what
//  feeds the heading estimate for the map marker's radar cone.
//
//  Heading/FOV observation used to be done with a `UIPanGestureRecognizer`
//  / `UIPinchGestureRecognizer` pair added to the view controller's own
//  view, configured to recognize simultaneously with MapKit's internal
//  ones (`cancelsTouchesInView = false`, delegate opting in to
//  simultaneous recognition). In practice that still intermittently ate
//  the native pan — MapKit's own recognizers are private, so there is no
//  public way to confirm or force how they resolve simultaneity with a
//  foreign recognizer, and once ours was in the state machine at all it
//  could contend for it.
//
//  `PassiveTouchObserver` below sidesteps the state machine entirely: it
//  is a `UIGestureRecognizer` subclass that watches raw touches
//  (`touchesBegan/Moved/Ended/Cancelled`) but never transitions its own
//  `state` out of `.possible`. UIKit's gesture-exclusivity and
//  failure-requirement logic only ever considers a recognizer once it
//  begins recognizing, so one that never does can't block, delay, or be
//  raced against anything else attached to the same view — Look Around's
//  own panning is guaranteed untouched. Public API only, no private
//  introspection.
//
//  Navigation between scenes is disabled on purpose: the cone is drawn
//  under a specific marker, and `MKLookAroundScene` exposes no
//  coordinate, so letting the person walk down the street inside the
//  imagery would silently detach the cone from where it's drawn.
//

import MapKit
import SwiftUI
import UIKit

struct LookAroundViewport: UIViewControllerRepresentable {
    let scene: MKLookAroundScene?

    /// `false` in the preview card, where a tap must expand the panel
    /// instead of reaching the imagery.
    var isInteractive: Bool
    var showsRoadLabels: Bool

    /// Current estimated field of view, used to scale drag distance into
    /// degrees.
    var fieldOfViewDegrees: Double

    var onRotate: (Double) -> Void
    var onFieldOfViewChange: (Double) -> Void
    var onSystemFullScreen: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> MKLookAroundViewController {
        let controller = MKLookAroundViewController()
        controller.delegate = context.coordinator
        controller.isNavigationEnabled = false
        controller.showsRoadLabels = showsRoadLabels
        // The native binoculars badge — the "small icon badge" Apple Maps
        // shows on its own preview card — rather than a hand-drawn one.
        controller.badgePosition = .topLeading
        controller.scene = scene

        let observer = PassiveTouchObserver()
        observer.cancelsTouchesInView = false
        observer.delaysTouchesBegan = false
        observer.delaysTouchesEnded = false
        observer.onPan = { [weak coordinator = context.coordinator] deltaX, width in
            coordinator?.handlePan(deltaX: deltaX, viewWidth: width)
        }
        observer.onPinchScale = { [weak coordinator = context.coordinator] scale in
            coordinator?.handlePinch(scale: scale)
        }
        controller.view.addGestureRecognizer(observer)
        context.coordinator.observer = observer

        return controller
    }

    func updateUIViewController(_ controller: MKLookAroundViewController, context: Context) {
        context.coordinator.parent = self
        if controller.scene !== scene {
            controller.scene = scene
        }
        if controller.showsRoadLabels != showsRoadLabels {
            controller.showsRoadLabels = showsRoadLabels
        }
        controller.view.isUserInteractionEnabled = isInteractive
    }

    // MARK: - Passive touch observer

    /// A gesture recognizer that only watches — see the file header. It
    /// never calls `super`'s state machinery; it just measures raw touch
    /// movement and reports it through closures.
    final class PassiveTouchObserver: UIGestureRecognizer {
        /// Delta-x in points since the previous call, plus the view's
        /// current width (for converting to degrees).
        var onPan: ((_ deltaX: CGFloat, _ viewWidth: CGFloat) -> Void)?
        /// Cumulative distance ratio since the pinch started, matching
        /// `UIPinchGestureRecognizer.scale`'s semantics.
        var onPinchScale: ((_ scale: CGFloat) -> Void)?

        private var lastSingleTouchX: CGFloat?
        private var pinchStartDistance: CGFloat?

        private func liveTouches(from event: UIEvent) -> [UITouch] {
            guard let view else { return [] }
            return (event.allTouches ?? []).filter {
                $0.view === view && $0.phase != .ended && $0.phase != .cancelled
            }
        }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
            // Deliberately not calling super — this recognizer must never
            // enter `.began`/`.recognized`.
            resetTracking(for: liveTouches(from: event))
        }

        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
            guard let view else { return }
            let active = liveTouches(from: event)

            if active.count >= 2 {
                let points = active.prefix(2).map { $0.location(in: view) }
                let distance = max(1, hypot(points[0].x - points[1].x, points[0].y - points[1].y))
                if let start = pinchStartDistance {
                    onPinchScale?(distance / start)
                } else {
                    pinchStartDistance = distance
                }
                lastSingleTouchX = nil
            } else if let touch = active.first {
                let x = touch.location(in: view).x
                if let last = lastSingleTouchX {
                    onPan?(x - last, view.bounds.width)
                }
                lastSingleTouchX = x
                pinchStartDistance = nil
            }
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
            resetTracking(for: liveTouches(from: event))
        }

        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
            resetTracking(for: liveTouches(from: event))
        }

        private func resetTracking(for active: [UITouch]) {
            lastSingleTouchX = active.count == 1 ? active[0].location(in: view).x : nil
            pinchStartDistance = nil
        }
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, MKLookAroundViewControllerDelegate {
        var parent: LookAroundViewport
        weak var observer: PassiveTouchObserver?

        private var fieldOfViewAtPinchStart: Double = LookAroundSession.defaultFieldOfView
        private var isPinching = false

        init(parent: LookAroundViewport) {
            self.parent = parent
        }

        // MARK: Gesture observation

        func handlePan(deltaX: CGFloat, viewWidth: CGFloat) {
            guard viewWidth > 0 else { return }
            isPinching = false
            // Dragging the finger to the right pulls the scene right,
            // which turns the camera *left* — hence the sign flip.
            let degreesPerPoint = parent.fieldOfViewDegrees / viewWidth
            parent.onRotate(-Double(deltaX) * degreesPerPoint)
        }

        func handlePinch(scale: CGFloat) {
            guard scale > 0 else { return }
            if !isPinching {
                isPinching = true
                fieldOfViewAtPinchStart = parent.fieldOfViewDegrees
            }
            // Pinching out (scale > 1) zooms in, i.e. narrows the FOV.
            parent.onFieldOfViewChange(fieldOfViewAtPinchStart / Double(scale))
        }

        // MARK: MKLookAroundViewControllerDelegate

        // Declared `nonisolated` + hopped onto the main actor explicitly,
        // the same pattern `LocationService` uses for its delegate
        // callbacks, so this compiles identically whether or not the SDK
        // marks the protocol `@MainActor`.

        nonisolated func lookAroundViewControllerWillPresentFullScreen(_ viewController: MKLookAroundViewController) {
            MainActor.assumeIsolated {
                parent.onSystemFullScreen(true)
            }
        }

        nonisolated func lookAroundViewControllerDidDismissFullScreen(_ viewController: MKLookAroundViewController) {
            MainActor.assumeIsolated {
                parent.onSystemFullScreen(false)
            }
        }
    }
}
