//
//  OnboardingPermissions.swift
//  Baranov
//
//  The system permission prompts, asked one at a time on the onboarding
//  page where each one makes sense — not all together on the first map.
//  Every request is best-effort: a "Don't Allow" (or an already-decided
//  status) simply returns, and the feature that needed it degrades on its
//  own. Nothing here can block or fail the onboarding flow — and now that
//  every request below is wrapped in `BestEffort.run`, that's actually
//  guaranteed rather than just hoped for: a stalled system prompt (a real
//  problem some people hit, most visibly on the "Turn on arrival alerts"
//  page, where the button stayed disabled forever because the completion
//  handler for the notification permission simply never fired) times out
//  and the flow moves on instead of freezing.
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
        #if DEBUG
        if CommandLine.arguments.contains("-demoMode") { return }
        #endif
        guard CMPedometer.isStepCountingAvailable(),
              CMPedometer.authorizationStatus() == .notDetermined else { return }
        let pedometer = CMPedometer()
        let now = Date()
        let box = UncheckedSendable(pedometer)
        await BestEffort.run {
            let pedometer = box.value
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                pedometer.queryPedometerData(from: now.addingTimeInterval(-60), to: now) { _, _ in
                    continuation.resume()
                }
            }
        }
        pedometer.stopUpdates()
    }

    /// Health read access for step count only (merges Apple Watch steps).
    nonisolated static func requestHealthSteps() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let store = HKHealthStore()
        let stepType = HKQuantityType(.stepCount)
        let box = UncheckedSendable((store: store, stepType: stepType))
        await BestEffort.run {
            _ = try? await box.value.store.requestAuthorization(toShare: [], read: [box.value.stepType])
        }
    }

    /// Notifications. Mirrors the Pasture toggle: the person's own switch
    /// follows what they just chose.
    nonisolated static func requestNotifications() async {
        let box = UncheckedSendable(UNUserNotificationCenter.current())
        await BestEffort.run {
            let center = box.value
            let settings = await center.notificationSettings()
            guard settings.authorizationStatus == .notDetermined else { return }
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            UserDefaults.standard.set(granted, forKey: "com.baranov.notificationsEnabled")
        }
        // Allowed: register for pushes straight away (the token reaches the
        // relay once the Shepherd ID is registered).
        await NotificationManager.shared.registerForRemoteIfAuthorized()
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
            // A stalled system prompt (the same kind of OS hang the
            // notification request above can hit) must never hold the
            // onboarding flow open forever.
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(8))
                self.finish()
            }
        }
        self.manager = nil
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            // The delegate also reports the initial, undecided status as
            // soon as it is set; only the person's answer finishes this.
            guard status != .notDetermined else { return }
            self.finish()
        }
    }

    /// Resumes the pending continuation exactly once, however it was
    /// reached — the person's real answer or the timeout above racing it.
    private func finish() {
        continuation?.resume()
        continuation = nil
    }
}
