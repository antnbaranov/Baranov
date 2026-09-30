//
//  WalkingPaceService.swift
//  Baranov
//
//  "About 12 days at your pace": the person's own recent steps per day,
//  from the motion coprocessor's history (CMPedometer keeps the last seven
//  days on the phone). No server, no HealthKit read — the same Motion &
//  Fitness permission the pedometer already has.
//

import CoreMotion
import Foundation

enum WalkingPaceService {
    /// Below this many steps a day the estimate would read as "years";
    /// a gentle floor keeps it honest without being discouraging.
    static let minimumDailySteps = 1_500

    /// Average steps per day over the last `days` (at most 7), or `nil`
    /// when the pedometer isn't available or allowed.
    static func averageDailySteps(days: Int = 7) async -> Int? {
        guard CMPedometer.isStepCountingAvailable(),
              CMPedometer.authorizationStatus() == .authorized else { return nil }
        let span = max(1, min(days, 7))
        let now = Date()
        guard let start = Calendar.current.date(byAdding: .day, value: -span, to: now) else { return nil }

        // Held until the query answers: a pedometer released mid-query
        // never calls back, and the continuation would hang.
        let pedometer = CMPedometer()
        let steps: Int? = await withCheckedContinuation { continuation in
            pedometer.queryPedometerData(from: start, to: now) { data, error in
                _ = pedometer
                guard error == nil, let data else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: data.numberOfSteps.intValue)
            }
        }
        guard let steps, steps > 0 else { return nil }
        let average = max(minimumDailySteps, steps / span)
        UserDefaults.standard.set(average, forKey: cachedKey)
        return average
    }

    /// The last measured pace, for places that can't wait for the
    /// pedometer (a share message, say). Falls back to a modest default.
    static var cachedDailySteps: Int {
        let stored = UserDefaults.standard.integer(forKey: cachedKey)
        return stored > 0 ? stored : 5_000
    }

    private static let cachedKey = "com.baranov.cachedDailySteps"

    /// Whole days to walk `meters` at `dailySteps` (1 step = 1 metre).
    static func days(toWalk meters: Double, dailySteps: Int) -> Int {
        guard dailySteps > 0 else { return 0 }
        return max(1, Int((meters / Double(dailySteps)).rounded(.up)))
    }
}
