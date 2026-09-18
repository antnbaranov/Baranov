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
//  Heading/FOV observation is done with two extra gesture recognizers
//  added to the view controller's *own* view (public API), configured
//  to recognize simultaneously with MapKit's internal ones and never to
//  cancel their touches — so Look Around still handles the pan/pinch
//  exactly as before, and this view merely listens. The conversion from
//  points to degrees assumes a full-width drag sweeps roughly one field
//  of view, which is how Look Around's own pan is tuned; it is an
//  estimate (see `LookAroundSession`), not a reading of MapKit's camera.
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

        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        pan.cancelsTouchesInView = false
        pan.delaysTouchesBegan = false
        pan.delaysTouchesEnded = false
        pan.delegate = context.coordinator
        controller.view.addGestureRecognizer(pan)

        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch(_:)))
        pinch.cancelsTouchesInView = false
        pinch.delaysTouchesBegan = false
        pinch.delaysTouchesEnded = false
        pinch.delegate = context.coordinator
        controller.view.addGestureRecognizer(pinch)

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

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, MKLookAroundViewControllerDelegate, UIGestureRecognizerDelegate {
        var parent: LookAroundViewport

        private var lastPanX: CGFloat = 0
        private var fieldOfViewAtPinchStart: Double = LookAroundSession.defaultFieldOfView

        init(parent: LookAroundViewport) {
            self.parent = parent
        }

        // MARK: Gesture observation

        @objc func handlePan(_ recognizer: UIPanGestureRecognizer) {
            guard let view = recognizer.view, view.bounds.width > 0 else { return }
            let x = recognizer.translation(in: view).x

            switch recognizer.state {
            case .began:
                lastPanX = x
            case .changed:
                let deltaPoints = x - lastPanX
                lastPanX = x
                // Dragging the finger to the right pulls the scene right,
                // which turns the camera *left* — hence the sign flip.
                let degreesPerPoint = parent.fieldOfViewDegrees / view.bounds.width
                parent.onRotate(-Double(deltaPoints) * degreesPerPoint)
            default:
                lastPanX = 0
            }
        }

        @objc func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
            switch recognizer.state {
            case .began:
                fieldOfViewAtPinchStart = parent.fieldOfViewDegrees
            case .changed:
                guard recognizer.scale > 0 else { return }
                // Pinching out (scale > 1) zooms in, i.e. narrows the FOV.
                parent.onFieldOfViewChange(fieldOfViewAtPinchStart / Double(recognizer.scale))
            default:
                break
            }
        }

        /// Observe alongside MapKit's own recognizers instead of competing
        /// with them — Look Around keeps handling the gesture itself.
        nonisolated func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
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
