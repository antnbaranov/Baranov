//
//  ShakeDetector.swift
//  Baranov
//
//  Detects a deliberate physical shake of the device via CoreMotion's raw
//  accelerometer, and reports the exact instant it happened.
//
//  Deliberately NOT `UIResponder.motionEnded(_:with:)`: that gesture gives
//  no usable timestamp, and the whole point of the hoofbeat handoff is that
//  two people who shook their phones at roughly the SAME MOMENT are the
//  ones who get paired. The shake instant is the shared secret, so it has
//  to be measured, not inferred.
//
//  Magnitude is computed inside the CoreMotion callback (pure arithmetic on
//  the sample, no isolated state touched) and only a threshold crossing is
//  hopped onto the main actor — so the 50 Hz stream costs nothing until an
//  actual shake happens.
//

import CoreMotion
import Foundation
import Observation

@Observable
@MainActor
final class ShakeDetector {
    /// Total acceleration, in g, that counts as a shake rather than
    /// ordinary pocket/walking motion. At rest the magnitude is ~1.0 g
    /// (gravity alone); a firm two-handed shake peaks well past 2.4.
    static let magnitudeThreshold: Double = 2.4

    /// Minimum gap between two reported shakes, so one physical shake —
    /// which crosses the threshold several times as the phone reverses
    /// direction — fires exactly once.
    static let rearmInterval: TimeInterval = 1.5

    private(set) var lastShakeAt: Date?
    private(set) var isRunning = false

    /// Called on the main actor with the instant the shake was registered.
    var onShake: ((Date) -> Void)?

    private let motionManager = CMMotionManager()

    var isAvailable: Bool {
        motionManager.isAccelerometerAvailable
    }

    func start() {
        guard !isRunning, motionManager.isAccelerometerAvailable else { return }
        isRunning = true

        motionManager.accelerometerUpdateInterval = 1.0 / 50.0
        motionManager.startAccelerometerUpdates(to: .main) { [weak self] data, _ in
            guard let acceleration = data?.acceleration else { return }

            let magnitude = (acceleration.x * acceleration.x
                             + acceleration.y * acceleration.y
                             + acceleration.z * acceleration.z).squareRoot()
            guard magnitude > ShakeDetector.magnitudeThreshold else { return }

            Task { @MainActor in
                self?.registerShake()
            }
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        motionManager.stopAccelerometerUpdates()
    }

    /// Debounces the threshold crossings of a single physical shake into
    /// one reported event.
    private func registerShake() {
        let now = Date()
        if let last = lastShakeAt, now.timeIntervalSince(last) < Self.rearmInterval {
            return
        }
        lastShakeAt = now
        onShake?(now)
    }

    /// The tap alternative to a physical shake: reports a shake at this
    /// instant, through the same debounce and `onShake` path a real one
    /// takes. Used by the on-screen "Hand over" buttons, and it makes the
    /// hoofbeat flow testable in the simulator, which has no accelerometer.
    func simulateShake() {
        registerShake()
    }
}
