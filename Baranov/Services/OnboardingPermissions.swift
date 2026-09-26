//
//  OnboardingPermissions.swift
//  Baranov
//
//  The system permission prompts, asked one at a time on the onboarding
//  page where each one makes sense — not all together on the first map.
//  Every request is best-effort: a "Don't Allow" (or an already-decided
//  status) simply returns, and the feature that needed it degrades on its
//  own. Nothing here can block or fail the onboarding flow.
//
//    Ram page      → Motion & Fitness (iPhone step counting)
//    Ocean page    → Location (start city, map marker, nearby handoffs)
//    Seal page     → Notifications (arrivals and handoffs only)
//    Last page     → Health (Apple Watch steps), as the gate opens
//
//  The services that use these permissions later (`StepTrackerService`,
//  `LocationService`, `RamNotificationService`) still ask lazily on their
//  own, so anyone who swipes past a page instead of tapping its button is
//  asked at the point of use, exactly as before.
//

import CoreLocation
import CoreMotion
import HealthKit
import UserNotifications

enum OnboardingPermissions {

    /// Motion & Fitness. There is no explicit request API for CMPedometer —
    /// the system sheet appears on the first query — so ask for one minute
    /// of history and discard the answer.
    nonisolated static func requestMotion() async {
        guard CMPedometer.isStepCountingAvailable(),
              CMPedometer.authorizationStatus() == .notDetermined else { return }
        let pedometer = CMPedometer()
        let now = Date()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            pedometer.queryPedometerData(from: now.addingTimeInterval(-60), to: now) { _, _ in
                continuation.resume()
            }
        }
        pedometer.stopUpdates()
    }

    /// Health read access for step count only (merges Apple Watch steps).
    nonisolated static func requestHealthSteps() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let store = HKHealthStore()
        let stepType = HKQuantityType(.stepCount)
        _ = try? await store.requestAuthorization(toShare: [], read: [stepType])
    }

    /// Notifications. Mirrors the Pasture toggle: the person's own switch
    /// follows what they just chose.
    nonisolated static func requestNotifications() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        UserDefaults.standard.set(granted, forKey: "com.baranov.notificationsEnabled")
    }
}

/// Location needs a live manager and delegate for the prompt's outcome,
/// so it is a small main-actor object the onboarding view keeps alive
/// while the system sheet is up.
@MainActor
final class OnboardingLocationRequester: NSObject, CLLocationManagerDelegate {
    private var manager: CLLocationManager?
    private var continuation: CheckedContinuation<Void, Never>?

    func request() async {
        guard continuation == nil else { return }
        let manager = CLLocationManager()
        guard manager.authorizationStatus == .notDetermined else { return }
        self.manager = manager
        manager.delegate = self
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            self.continuation = continuation
            manager.requestWhenInUseAuthorization()
        }
        self.manager = nil
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            // The delegate also reports the initial, undecided status as
            // soon as it is set; only the person's answer finishes this.
            guard status != .notDetermined else { return }
            self.continuation?.resume()
            self.continuation = nil
        }
    }
}
